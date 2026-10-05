# frozen_string_literal: true

module Decidim
  module ContractsSk
    module OpenData
      # The single whitelist behind the open-data export
      # (civora-org/civora-platform#119): one published contract rendered as
      # a CSV row or a JSON object. Every field a reader can ever download is
      # named in FIELDS — nothing is serialized by reflection, so an internal
      # column (review reason, redaction stamp, author, submitter, CRZ filing
      # data, import provenance, party addresses) can never leak by being
      # added to the table. docs/open-data.md pins its field table to this
      # constant.
      #
      # The serializer runs while the response body streams, i.e. AFTER the
      # controller action (and Decidim's switch_locale / time-zone
      # around_actions) has returned. It therefore uses no I18n and no
      # Time.zone: dates are Date#iso8601 and published_at is rendered in UTC.
      class ContractRecord
        # CSV columns, in order. The names are a stability promise.
        FIELDS = %w[
          reference title subject_matter amount currency signed_on effective_from
          published_at source crz_url party_roles party_icos party_names url
        ].freeze

        # The parallel party columns and the party attribute each one lists.
        PARTY_ATTRIBUTES = { "party_roles" => :role, "party_icos" => :ico, "party_names" => :name }.freeze
        PARTY_FIELDS = PARTY_ATTRIBUTES.keys.freeze

        # JSON keys: FIELDS with the three parallel party columns folded into
        # one `parties` array of { role, ico, name } at the first one's place.
        JSON_KEYS = FIELDS.each_with_object([]) do |field, keys|
          next if PARTY_FIELDS.include?(field) && field != PARTY_FIELDS.first

          keys << (field == PARTY_FIELDS.first ? "parties" : field)
        end.freeze

        # Free-text CSV cells that a spreadsheet would evaluate as a formula
        # when they start with one of these (OWASP "CSV injection").
        # A leading tab, CR or LF, or a trigger character (ASCII or fullwidth)
        # after any run of whitespace, NBSP or ideographic space.
        FORMULA_START = /\A(?:[\t\r\n]|[\s\u00a0\u3000]*[=+\-@\uff1d\uff0b\uff0d\uff20])/
        TEXT_FIELDS = %w[reference title subject_matter crz_url party_names].freeze

        PARTY_SEPARATOR = " | "
        ICO_FORMAT = /\A\d{8}\z/

        # A party appears only with a well-formed IČO; IČO-less parties
        # (natural persons, typically) are dropped entirely, name included.
        def self.publishable_party?(party)
          party.ico.to_s.match?(ICO_FORMAT)
        end

        # +url+ is the absolute detail URL, resolved by the caller while the
        # request context is still alive.
        def initialize(contract, url:)
          @contract = contract
          @url = url
        end

        # Array of cell strings in FIELDS order. +decimal_comma+ switches the
        # amount to the decimal comma of the Excel profile.
        def csv_row(decimal_comma: false)
          FIELDS.map do |field|
            cell = csv_value(field, decimal_comma)
            TEXT_FIELDS.include?(field) ? neutralize_formula(cell) : cell
          end
        end

        # Hash in JSON_KEYS order; nulls are kept.
        def as_json_hash
          JSON_KEYS.index_with { |key| json_value(key) }
        end

        # "1250.50": two decimals, never scientific notation.
        def self.decimal_string(amount)
          whole, fraction = amount.to_d.round(2).to_s("F").split(".")
          "#{whole}.#{fraction.to_s.ljust(2, "0")}"
        end

        private

        attr_reader :contract, :url

        def csv_value(field, decimal_comma)
          case field
          when "amount" then csv_amount(decimal_comma)
          when *PARTY_FIELDS then party_cell(field)
          else scalar(field)
          end
        end

        def json_value(key)
          case key
          when "parties" then parties.map { |party| { "role" => party.role, "ico" => party.ico, "name" => party.name } }
          when "amount" then contract.amount&.to_d&.round(2)&.to_f
          else scalar(key)
          end
        end

        # The nil-preserving scalar view of one field (CSV maps nil to an
        # empty cell, JSON keeps null).
        def scalar(field)
          case field
          when "signed_on", "effective_from" then contract.public_send(field)&.iso8601
          when "published_at" then contract.published_at&.utc&.iso8601
          when "url" then url
          else contract.public_send(field)
          end
        end

        # nil (an empty cell, not a quoted "") when there is no party to list.
        def party_cell(field)
          return nil if parties.empty?

          parties.map(&PARTY_ATTRIBUTES.fetch(field)).join(PARTY_SEPARATOR)
        end

        def csv_amount(decimal_comma)
          return nil if contract.amount.nil?

          text = self.class.decimal_string(contract.amount)
          decimal_comma ? text.tr(".", ",") : text
        end

        # Prefix an apostrophe so a spreadsheet treats the cell as text.
        def neutralize_formula(cell)
          return cell if cell.nil? || cell.empty?

          cell.match?(FORMULA_START) ? "'#{cell}" : cell
        end

        # Parties with an IČO, ordered by role then id (the association is
        # preloaded by the caller; sorted in Ruby so no query is issued).
        def parties
          @parties ||= contract.parties.select { |party| self.class.publishable_party?(party) }
                               .sort_by { |party| [party.role, party.id] }
        end
      end
    end
  end
end
