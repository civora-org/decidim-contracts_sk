# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Public statistics page (civora-org/civora-platform#118): totals, the last
    # twelve months, per-year counts, top suppliers and the own-versus-CRZ
    # split over the organization's published records (CRZ mirrors included,
    # split out in their own block). Read-only and authentication-free; reads
    # no request parameter at all (no filters in V1).
    #
    # The figures are cached as DATA (never HTML) for an hour. The key is
    # derived from the data itself (record count and newest updated_at of the
    # published scope, plus organization, schema version, time zone and the
    # current month), so a publish, an edit or an unpublish changes the key
    # and nothing needs invalidating; the TTL only bounds how long a change
    # that does not touch the contract row (a party rename) can stay unseen.
    # Unlike the supplier pages the page is indexable, and that is a
    # trade-off, not a claim that it holds no individual: the top-10 tables
    # do rank individual suppliers, some of whom may be sole traders. The
    # owner accepted indexing because only the top ten appear, every name is
    # already on the public contract detail pages, and parties without an
    # IČO never appear (docs/contracts-domain-notes.md, "Statistics page").
    class StatisticsController < Decidim::ContractsSk::ApplicationController
      include Decidim::ContractsSk::PublicCatalogue

      CACHE_TTL = 1.hour

      helper Decidim::ContractsSk::StatisticsHelper
      helper_method :statistics

      def show; end

      private

      def statistics
        @statistics ||= Rails.cache.fetch(statistics_cache_key, expires_in: CACHE_TTL) do
          CatalogueStatistics.new(scope: published_contracts, time_zone: Time.zone).call
        end
      end

      # One aggregate query on a cache hit.
      def statistics_cache_key
        ["decidim-contracts_sk/statistics", CatalogueStatistics::SCHEMA_VERSION, current_organization.id,
         Time.zone.tzinfo.name, Time.zone.today.beginning_of_month.iso8601, *published_signature]
      end

      # [record count, newest updated_at]. MAX() comes back as a String on
      # SQLite and a Time on PostgreSQL, so it is normalized for the key.
      def published_signature
        count, newest = published_contracts.pick(Arel.sql("COUNT(*)"),
                                                 Arel.sql("MAX(#{Contract.table_name}.updated_at)"))
        [count, newest.respond_to?(:utc) ? newest.utc.iso8601(6) : newest.to_s]
      end
    end
  end
end
