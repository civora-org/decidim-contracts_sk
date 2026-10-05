# frozen_string_literal: true

module Decidim
  module ContractsSk
    # View helpers of the Atom feed (civora-org/civora-platform#120) and of the
    # catalogue's feed auto-discovery link. Needs ApplicationHelper's
    # format_amount / format_date and CatalogueHelper's catalogue_active_filters
    # (all mixed into the public controllers), plus the view's request and
    # current_organization.
    #
    # Deliberately written without Decidim's translated_attribute helper: the
    # organization name is a translatable hash, resolved here per locale with
    # fallbacks, so the helper works in the engine's own test harness too.
    module FeedHelper
      # Tag-URI schema date of every id the feed mints (RFC 4151: the date the
      # naming authority held the name). Fixed forever: ids must never change.
      FEED_TAG_DATE = "2026"

      # The organization's name in the current locale, then its default
      # locale, then any non-blank translation; with no name at all, its host.
      def feed_organization_name
        feed_name_candidates.map { |name| name.to_s.strip }.find(&:present?) || feed_host
      end

      def feed_title
        t("decidim.contracts_sk.feeds.show.title", organization: feed_organization_name)
      end

      # "Newly published contracts", plus the active filters when there are any.
      def feed_subtitle(query)
        filters = catalogue_active_filters(query).map { |label, value| "#{label}: #{value}" }.join("; ")
        return t("decidim.contracts_sk.feeds.show.subtitle") if filters.empty?

        t("decidim.contracts_sk.feeds.show.subtitle_filtered", filters: filters)
      end

      # Stable per query: the same normalized, key-sorted filters always give
      # the same id, whatever order or spelling the reader used.
      def feed_id(query)
        params = query.to_params
        base = "tag:#{feed_host},#{FEED_TAG_DATE}:contracts_sk/feed"
        params.empty? ? base : "#{base}?#{params.sort.to_h.to_query}"
      end

      # Stable per record, and independent of the filters.
      def feed_entry_id(contract)
        "tag:#{feed_host},#{FEED_TAG_DATE}:contracts_sk/contract/#{contract.id}"
      end

      # Plain text: reference, amount and signing date, whichever are known.
      def feed_entry_summary(contract)
        signed = contract.signed_on &&
                 t("decidim.contracts_sk.feeds.show.summary_signed", date: format_date(contract.signed_on))
        [contract.reference, format_amount(contract.amount, contract.currency), signed].compact_blank.join(", ")
      end

      # The feed's time: the moment a record entered the catalogue.
      def feed_entry_time(contract)
        (contract.published_at || contract.created_at).utc
      end

      # The feed's own updated stamp: its newest entry, or — for an empty feed
      # — the organization's creation, so the value is stable rather than "now".
      def feed_updated_at(contracts)
        contracts.map { |contract| feed_entry_time(contract) }.max ||
          (current_organization.created_at || Time.zone.at(0)).utc
      end

      # Query params of the feed's own URLs: the filters only (never sort),
      # with Decidim's locale param kept out.
      def feed_url_params(query)
        query.to_params.except("sort").symbolize_keys.merge(locale: nil)
      end

      # The ONE parameter set of every link to the feed itself — the page's
      # button, the head's alternate link and the feed's rel=self: the
      # filters (never sort), the visitor's locale (always explicit, so a
      # reader subscribing from the English page gets the English feed and
      # the self link matches the document location) and the format. The
      # tag-URI ids deliberately ignore the locale.
      def feed_link_params(query)
        query.to_params.except("sort").symbolize_keys.merge(locale: I18n.locale.to_s, format: :atom)
      end

      # <link rel="alternate" type="application/atom+xml"> for the page head.
      def feed_discovery_link(query)
        auto_discovery_link_tag(:atom, feed_url(feed_link_params(query)),
                                type: "application/atom+xml", title: feed_title)
      end

      private

      # Locale, default locale, then every String translation (a Decidim name
      # hash may also hold a nested machine_translations hash, never a name).
      def feed_name_candidates
        names = current_organization.name
        return [] unless names.is_a?(Hash)

        [names[I18n.locale.to_s], names[current_organization.default_locale.to_s], *names.values.grep(String)]
      end

      def feed_host
        current_organization.host.presence || request.host
      end
    end
  end
end
