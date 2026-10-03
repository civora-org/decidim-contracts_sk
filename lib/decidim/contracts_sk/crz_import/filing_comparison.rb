# frozen_string_literal: true

require "bigdecimal"
require "active_support/core_ext/object/blank"

module Decidim
  module ContractsSk
    module CrzImport
      # Pure comparison of an editorial contract against the official CRZ
      # record it is claimed to be filed as (civora-org/civora-platform#125).
      # It backs the admin filing preview and the Admin::ConfirmCrzFiling
      # command, which re-runs it inside the row lock — one rule, two
      # callers. No I/O, no Rails model access beyond reading the contract's
      # attributes and parties; +record+ is the Mapper.map output.
      #
      # Three rows, each :match / :mismatch / :unverifiable:
      # - reference — both sides stripped of ALL whitespace and Unicode
      #   case-folded, then compared (CRZ writes "ZP 2026/001" where the
      #   editor typed "zp2026/001");
      # - supplier IČO — a match when ANY of the editorial record's
      #   contractor parties carries the IČO of the CRZ contractor party
      #   (the mapper already normalized the CRZ side, including the
      #   integer-CIN leading-zero repair of #145);
      # - amount — BigDecimal equality to the cent (both sides rounded to
      #   two places, never Float).
      # A side that is blank (no reference, no contractor IČO, no amount)
      # makes the row :unverifiable — it cannot confirm the filing, so the
      # command treats it like a mismatch (a reason is required to proceed).
      #
      # Hard refusals are NOT rows: the CRZ record's status 4 (zrušená,
      # cancelled) and 5 (stiahnutá, withdrawn) can never be confirmed as a
      # filing, with or without a reason (.withdrawn?). A blank or other
      # status is not refused — the status is advisory for those.
      class FilingComparison
        Row = Struct.new(:field, :editorial, :crz, :status, keyword_init: true)

        FIELDS = %i[reference supplier_ico amount].freeze

        # CRZ status codes that can never be a confirmed filing.
        WITHDRAWN_STATUS_IDS = [4, 5].freeze

        # True when the mapped CRZ record carries a status that can never
        # be confirmed as a filing (see the class comment).
        def self.withdrawn?(record)
          WITHDRAWN_STATUS_IDS.include?(record[:status_id])
        end

        def initialize(contract:, record:)
          @contract = contract
          @record = record
        end

        def rows
          @rows ||= [reference_row, supplier_row, amount_row]
        end

        def all_match?
          rows.all? { |row| row.status == :match }
        end

        # Any row that is not a :match (a :mismatch OR :unverifiable): the
        # filing then needs the editor's override reason.
        def needs_reason?
          !all_match?
        end

        private

        attr_reader :contract, :record

        def reference_row
          editorial = contract.reference.to_s.strip
          crz = record[:attributes][:reference].to_s.strip

          Row.new(field: :reference, editorial: editorial.presence, crz: crz.presence,
                  status: compare(normalize_reference(editorial), normalize_reference(crz)))
        end

        def supplier_row
          editorial = editorial_contractor_icos
          crz = record[:parties].find { |party| party[:role] == "contractor" }&.dig(:ico)

          Row.new(field: :supplier_ico, editorial: editorial.presence, crz: crz.presence,
                  status: supplier_status(editorial, crz))
        end

        def editorial_contractor_icos
          contract.parties.select { |party| party.role.to_s == "contractor" }
                  .filter_map { |party| party.ico.presence }
        end

        def supplier_status(editorial, crz)
          return :unverifiable if editorial.empty? || crz.blank?

          editorial.include?(crz) ? :match : :mismatch
        end

        def amount_row
          editorial = contract.amount
          crz = record[:attributes][:amount]

          Row.new(field: :amount, editorial: editorial, crz: crz,
                  status: compare(cents(editorial), cents(crz)))
        end

        # Whitespace-free, case-folded. Unicode case folding (not plain
        # downcase) so "STRAŠE" and "straše" agree on every script.
        def normalize_reference(value)
          value.gsub(/\s+/, "").downcase(:fold)
        end

        def cents(value)
          value.nil? ? nil : BigDecimal(value.to_s).round(2)
        end

        def compare(left, right)
          return :unverifiable if left.blank? || right.blank?

          left == right ? :match : :mismatch
        end
      end
    end
  end
end
