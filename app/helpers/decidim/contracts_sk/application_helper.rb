# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Base view helper for the Decidim ContractsSk module.
    #
    # Carries the public catalogue's CRZ-mirror provenance predicates
    # (civora-org/civora-platform#88): ADR-002 rule 1 makes the engine's
    # imported records "externally confirmed" data — never a legal
    # publication — and ADR-008 decisions 4/6 require a freshness signal
    # that never implies real-time accuracy.
    #
    # Also carries the engine's locale-aware money/date/timestamp rendering
    # (civora-org/civora-platform#81). The three formatters are deliberately
    # PORO-safe — no view-context dependencies, I18n only — so the CRZ
    # handoff PDF (a plain object) can include this module and share one
    # formatting vocabulary with the views, never a second one.
    module ApplicationHelper
      include ActionView::Helpers::NumberHelper

      # True when the record is a CRZ metadata mirror created by the import
      # ETL (ADR-008) rather than an editorial record. Drives every
      # provenance-labelled render in the catalogue; editorial records are
      # never labelled.
      def imported_contract?(contract)
        contract.source == "crz"
      end

      # Locale-aware amount rendering (civora-org/civora-platform#81).
      # Under :sk the value is grouped and comma-decimalized — "1 250,50" —
      # through number_with_precision with EXPLICIT separators: regular
      # spaces (not non-breaking ones) were chosen on purpose, so the
      # engine ships no glyph-dependent markup and the same string renders
      # identically in HTML and in the PDF. Under every other locale the
      # historical fixed-point form is kept verbatim (BigDecimal#to_s("F"),
      # which also guards huge amounts against scientific notation). A
      # blank amount renders empty; a blank currency renders the bare
      # number — the PDF's drop-the-row semantics rely on both.
      def format_amount(amount, currency = nil)
        return "" if amount.blank?

        formatted = localized_amount(amount)
        return formatted if currency.blank?

        "#{formatted} #{currency}"
      end

      # Locale-aware date rendering (civora-org/civora-platform#81): the
      # format STRING is resolved from the engine's own
      # decidim.contracts_sk.date_formats vocabulary and handed to I18n.l
      # explicitly — never a named format, so no host-app or rails-i18n
      # locale data can ever be required for the render to resolve. Blank
      # renders empty, so guarded views may call it unconditionally.
      def format_date(date)
        return "" if date.blank?

        I18n.l(date, format: I18n.t("decidim.contracts_sk.date_formats.default"))
      end

      # The PDF footer's generation stamp (civora-org/civora-platform#81):
      # the timestamp is converted to UTC BEFORE formatting, so the naive
      # to_fs(:db) digits can never silently carry the server's local zone
      # — the label is explicit and true.
      def format_timestamp(time)
        return "" if time.blank?

        "#{time.utc.to_fs(:db)} UTC"
      end

      # True when a mirrored record must carry the stale notice (ADR-008
      # decision 4): the last import was stamped "failed" (the engine-side
      # stale-fallback signal — the record kept its last-good mirror data
      # but a re-import could not prove it current, docs/crz-import.md), or
      # the mirror's imported_at is blank (a crz-sourced row without a
      # timestamp cannot prove freshness — fail closed), or the timestamp
      # is older than the configurable Decidim::ContractsSk.stale_after
      # threshold (default 48 h — twice the recommended nightly sync
      # cadence). The comparison normalizes the setting through #to_i, so
      # hosts may configure Integer seconds or an ActiveSupport::Duration.
      #
      # Time.current (not Time.now) keeps the comparison in the Decidim
      # application time zone.
      def mirror_stale?(contract)
        return false unless imported_contract?(contract)
        return true if contract.import_status == "failed"
        return true if contract.imported_at.blank?

        contract.imported_at < Decidim::ContractsSk.stale_after.to_i.seconds.ago
      end

      private

      # The locale branch of format_amount. Under :sk the value is grouped
      # and comma-decimalized through number_with_precision; under every
      # other locale the historical fixed-point form is kept verbatim —
      # "F" on BigDecimal keeps extreme magnitudes out of scientific
      # notation (plain BigDecimal#to_s goes scientific), while the frozen
      # content snapshots' plain Strings render as stored.
      def localized_amount(amount)
        if I18n.locale == :sk
          number_with_precision(amount, precision: 2, delimiter: " ", separator: ",")
        elsif amount.is_a?(BigDecimal)
          amount.to_s("F")
        else
          amount.to_s
        end
      end
    end
  end
end
