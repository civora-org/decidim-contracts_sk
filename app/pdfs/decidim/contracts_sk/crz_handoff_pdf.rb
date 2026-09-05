# frozen_string_literal: true

require "prawn"

module Decidim
  module ContractsSk
    # Renders the manual CRZ-handoff PDF for one contract record
    # (M02-05-C, civora-org/civora-platform#74; ADR-002).
    #
    # This is a HANDOFF AID for the clerical CRZ record, never a legal
    # publication — the disclaimer is printed on every generated document.
    #
    # The content locale is Slovak only, regardless of the acting admin's
    # UI locale: the artifact travels to the Slovak CRZ registry, so every
    # string is resolved through I18n.with_locale(:sk). Field labels reuse
    # the public catalogue vocabulary (contract.*, contracts.show.parties)
    # and the contract_states.* table — one terminology, never a second one.
    #
    # Content follows the data dictionary's shipped content fields
    # (civora-org/civora-platform#75): title, reference, lifecycle state,
    # subject matter, amount with currency, signature/effectivity dates and
    # the CRZ link — each rendered only when present — plus the contract's
    # parties (role + name).
    #
    # Font: prawn's built-in core fonts are WinAnsi-encoded and RAISE
    # Prawn::Errors::IncompatibleStringEncoding on Slovak text (ľ š č ť ž
    # ... are outside CP1252), so the renderer uses the gem-vendored DejaVu
    # Sans (data/fonts, Bitstream-Vera-licensed, redistribution permitted).
    # Pure Ruby end to end — generation is deterministic and offline.
    #
    # The contract is duck-typed (title, reference, state, subject_matter,
    # amount, currency, signed_on, effective_from, crz_url, parties), so the
    # renderer is testable without ActiveRecord.
    class CrzHandoffPdf
      def initialize(contract)
        super()
        @contract = contract
      end

      # The rendered PDF as a binary String. No disk temp files: the caller
      # hands the string to ActiveStorage as an IO attachable.
      def render
        I18n.with_locale(:sk) do
          document.render
        end
      end

      private

      attr_reader :contract

      def document
        Prawn::Document.new do |pdf|
          pdf.font font_path
          render_header(pdf)
          render_field_rows(pdf)
          render_parties(pdf)
          render_footer(pdf)
        end
      end

      def render_header(pdf)
        pdf.text t("decidim.contracts_sk.crz_handoff_pdf.heading"), size: 14
        pdf.text t("decidim.contracts_sk.crz_handoff_pdf.disclaimer"), size: 9
        pdf.move_down 12
      end

      def render_field_rows(pdf)
        field_rows.each do |label, value|
          pdf.text "#{label}: #{value}"
        end
      end

      def render_parties(pdf)
        pdf.move_down 12
        pdf.text t("decidim.contracts_sk.contracts.show.parties"), size: 12
        contract.parties.each do |party|
          pdf.text "#{t("decidim.contracts_sk.contract.party.#{party.role}")}: #{party.name}"
        end
        pdf.text t("decidim.contracts_sk.contracts.show.parties_empty"), size: 9 if contract.parties.blank?
      end

      def render_footer(pdf)
        pdf.move_down 12
        pdf.text "#{t("decidim.contracts_sk.crz_handoff_pdf.generated_on")} #{Time.current.to_fs(:db)}", size: 9
      end

      # The identity + content field rows, in the data dictionary's order,
      # data-driven: each optional row carries its pre-formatted value and
      # is dropped when that value is blank — a handoff aid shows what the
      # record actually carries, never blank placeholders.
      #
      # Cop note: the method IS the pinned row table — its ABC size grows
      # with the data dictionary's field count (one t() call per label),
      # not with logic, so the budget is disabled rather than splitting
      # the table apart (same doctrine as the controller's ClassLength
      # disable).
      # rubocop:disable Metrics/AbcSize
      def field_rows
        [
          [t("decidim.contracts_sk.contract.title"), contract.title],
          [t("decidim.contracts_sk.contract.reference_number"), contract.reference],
          [t("decidim.contracts_sk.contract.status"), state_label],
          [t("decidim.contracts_sk.contract.subject_matter"), contract.subject_matter],
          [t("decidim.contracts_sk.contract.amount"), amount_value],
          [t("decidim.contracts_sk.contract.signed_on"), contract.signed_on&.to_fs(:db)],
          [t("decidim.contracts_sk.contract.effective_from"), contract.effective_from&.to_fs(:db)],
          [t("decidim.contracts_sk.contract.crz_url"), contract.crz_url]
        ].select { |_, value| value.present? }
      end
      # rubocop:enable Metrics/AbcSize

      # Slovak state label from the contract_states.* table (the namespace
      # reserved for state labels in docs/contract-lifecycle.md), falling
      # back to the raw stored token for an unknown value.
      def state_label
        return "" if contract.state.blank?

        I18n.t("decidim.contracts_sk.contract_states.#{contract.state}", default: contract.state.to_s)
      end

      # Fixed-point rendering on purpose: BigDecimal#to_s alone is
      # scientific ("0.125e4"); the public catalogue's ERB interpolation
      # hides that, a plain text draw would not. Nil when the amount is
      # blank, so the row drops out of the field list.
      def amount_value
        return nil if contract.amount.blank?
        return contract.amount.to_s("F") if contract.currency.blank?

        "#{contract.amount.to_s("F")} #{contract.currency}"
      end

      def t(key)
        I18n.t(key)
      end

      # The gem-vendored Unicode font (see the class comment): resolved off
      # the engine root, never the host app's filesystem.
      def font_path
        Decidim::ContractsSk::Engine.root.join("data", "fonts", "DejaVuSans.ttf").to_s
      end
    end
  end
end
