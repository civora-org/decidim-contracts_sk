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
    # Cop note: one shared vocabulary of small PORO-safe formatters and
    # predicates (the PDF includes this module too); splitting it would
    # scatter that single vocabulary rather than simplify it.
    # rubocop:disable Metrics/ModuleLength
    module ApplicationHelper
      include ActionView::Helpers::NumberHelper

      # True when the record is a CRZ metadata mirror created by the import
      # ETL (ADR-008) rather than an editorial record. Drives every
      # provenance-labelled render in the catalogue; editorial records are
      # never labelled.
      def imported_contract?(contract)
        contract.source == "crz"
      end

      # The date shown as the record's publication date (civora-org/
      # civora-platform#159): the real CRZ date (crz_published_on, a Date)
      # when the record carries one, else published_at (a Time, the moment it
      # entered the catalogue) — the rule Contract.publication_date_arel
      # sorts and filters by. Blank when neither exists; format_date takes
      # both types. Reads the columns only, so any contract-like object works.
      def publication_date(contract)
        contract.crz_published_on || contract.published_at
      end

      # True when publication_date is the CRZ one.
      def publication_date_from_crz?(contract)
        contract.crz_published_on.present?
      end

      # "Published in CRZ on" when the date shown is the real CRZ one,
      # otherwise the original "Published on" (the catalogue entry date).
      def publication_date_label(contract)
        key = publication_date_from_crz?(contract) ? "published_on_crz" : "published_on"
        I18n.t("decidim.contracts_sk.contract.#{key}")
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

      # Same contract as format_date, with the time of day: the audit trail
      # records several events per contract per day, and a date alone
      # cannot order them for the reader. Rendered in the application time
      # zone (Time.zone), never the server's.
      def format_datetime(time)
        return "" if time.blank?

        I18n.l(time.in_time_zone, format: I18n.t("decidim.contracts_sk.date_formats.datetime"))
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

      # Remix Icon outlines (Apache-2.0, the set Decidim's own `icon` helper
      # draws from) for the public pages. Inline, so the engine needs neither
      # Decidim's icon registry nor the host's sprite build to render them.
      CONTRACTS_ICON_PATHS = {
        search: [
          "M18.031 16.617l4.283 4.282-1.415 1.415-4.282-4.283A8.96 8.96 0 0 1 11 20c-4.968 ",
          "0-9-4.032-9-9s4.032-9 9-9 9 4.032 9 9a8.96 8.96 0 0 1-1.969 5.617zm-2.006-.742A6.977 ",
          "6.977 0 0 0 18 11c0-3.868-3.133-7-7-7-3.868 0-7 3.132-7 7 0 3.867 3.132 7 7 7a6.977 ",
          "6.977 0 0 0 4.875-1.975l.15-.15z"
        ].join,
        information: [
          "M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm0-2a8 8 0 ",
          "1 0 0-16 8 8 0 0 0 0 16zM11 7h2v2h-2V7zm0 4h2v6h-2v-6z"
        ].join,
        document: [
          "M21 8v12.993A1 1 0 0 1 20.007 22H3.993A.993.993 0 0 1 3 21.008V2.992C3 2.455 3.449 2 ",
          "4.002 2h10.995L21 8zm-2 1h-5V4H5v16h14V9zM8 7h3v2H8V7zm0 4h8v2H8v-2zm0 4h8v2H8v-2z"
        ].join
      }.freeze

      # A decorative icon: hidden from assistive technology (the adjacent
      # text carries the meaning), sized and coloured by the caller's CSS.
      def contracts_icon(name)
        tag.svg(tag.path(d: CONTRACTS_ICON_PATHS.fetch(name)),
                viewBox: "0 0 24 24", width: "1em", height: "1em", fill: "currentColor",
                "aria-hidden": "true", focusable: "false")
      end

      # Decidim `label` modifiers per tracked deadline status (civora-org/
      # civora-platform#124). Decidim classes only — never Tailwind
      # utilities: the host stylesheet is compiled at image build and
      # silently drops any utility the host itself does not use
      # (docs/public-ui.md; the rule holds for admin views too).
      CRZ_DEADLINE_BADGE_CLASSES = {
        overdue: "label alert",
        due_soon: "label warning",
        ok: "label"
      }.freeze

      # The admin index's per-row CRZ deadline badge (civora-org/
      # civora-platform#124, § 47a OZ): nil for untracked rows (filed,
      # mirror, terminal — an empty cell), a muted dash with an explanatory
      # title for a tracked row whose signing date is unknown, otherwise a
      # `label` badge: alert "po termíne" when overdue, warning (0..14 days
      # left, "dnes" on the day) or plain with the days left. Reads the
      # status from the record (single-sourced with the Contract scopes).
      def crz_deadline_badge(contract, today: Date.current)
        status = contract.crz_deadline_status(today: today)
        return nil if status == :untracked
        return crz_deadline_unknown_badge if status == :unknown

        text = status == :overdue ? crz_t("badge.overdue") : crz_days_text(contract.crz_days_left(today: today))
        tag.span(text, class: CRZ_DEADLINE_BADGE_CLASSES.fetch(status))
      end

      # The edit page's deadline line (civora-org/civora-platform#124): nil
      # for untracked records, the "deadline unknown — add signing date"
      # prompt when signed_on is missing, otherwise the deadline date with
      # the days left, due-today or overdue wording. Callers pass the
      # PERSISTED record, never form values.
      def crz_deadline_line(contract, today: Date.current)
        status = contract.crz_deadline_status(today: today)
        return nil if status == :untracked
        return crz_t("header.unknown") if status == :unknown

        crz_deadline_wording(contract, status, today)
      end

      private

      # The dated wording of the edit page's deadline line.
      def crz_deadline_wording(contract, status, today)
        date = format_date(contract.crz_deadline)
        left = contract.crz_days_left(today: today)
        return crz_t("header.overdue", date: date, days: crz_days_text(-left)) if status == :overdue
        return crz_t("header.today", date: date) if left.zero?

        crz_t("header.upcoming", date: date, left: crz_days_text(left))
      end

      def crz_deadline_unknown_badge
        title = crz_t("badge.unknown")
        tag.span(tag.span("\u2014", "aria-hidden": "true") + tag.span(title, class: "sr-only"), title: title)
      end

      # "1 deň" / "3 dni" / "7 dní" (plural keys; the host's rails-i18n
      # supplies the sk rule, otherwise one/other applies).
      def crz_days_text(count)
        return crz_t("badge.today") if count.zero?

        I18n.t("decidim.contracts_sk.admin.contracts.deadline.days", count: count)
      end

      def crz_t(key, **options)
        I18n.t("decidim.contracts_sk.admin.contracts.deadline.#{key}", **options)
      end

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
    # rubocop:enable Metrics/ModuleLength
  end
end
