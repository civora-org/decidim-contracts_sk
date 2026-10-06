# frozen_string_literal: true

module Decidim
  module ContractsSk
    # The public catalogue's filter and sort object (civora-org/civora-platform
    # #116) — one query object reused by the supplier pages (#117),
    # statistics (#118), exports (#119) and feeds (#120).
    #
    # It takes the caller's already-scoped relation (the published,
    # organization-scoped records) and request-style params, normalizes every
    # value defensively (an invalid value is ignored, never an error) and
    # applies the filters ON TOP of that scope, so the published-only and
    # tenant scoping survives every combination.
    #
    #   query = CatalogueQuery.new(scope: published, params: request_params)
    #   query.filters   # normalized, frozen
    #   query.relation  # filtered, UNORDERED (counts, aggregates, exports)
    #   query.results   # relation + the chosen deterministic sort
    #   query.with(party: "36396567").relation   # a derived query
    #
    # Semantics worth knowing:
    # * Amounts compare the stored amount regardless of currency; only EUR
    #   exists (Contract::SUPPORTED_CURRENCIES). Records without an amount are
    #   excluded only while an amount filter is active.
    # * Publication dates (civora-org/civora-platform#159) filter and sort the
    #   real CRZ publication date (crz_published_on) when the record carries
    #   one — CRZ mirrors and editorial records confirmed as filed — and
    #   otherwise published_at (the moment the record entered the catalogue),
    #   as calendar days in the given time zone (Contract.publication_date_arel).
    #   A mirror imported before #159 has no CRZ date until the backfill
    #   task has run, and meanwhile falls back to its import time. Signing
    #   dates filter signed_on.
    # * A reversed range (from after to) is swapped, not rejected.
    # * party matches a contract's party by exact IČO (8 digits) or by
    #   case-insensitive name substring, via an IN-subquery (no N+1, no
    #   DISTINCT). A name is matched only against parties that have an IČO:
    #   a party without one (possibly a natural person) is never findable by
    #   name. q searches title and reference only, never party names.
    class CatalogueQuery
      PARAM_KEYS = %i[q amount_min amount_max published_from published_to
                      signed_from signed_to party source sort].freeze

      SOURCES = %w[editorial crz].freeze
      SORTS = %w[published_desc published_asc amount_desc amount_asc].freeze
      DEFAULT_SORT = "published_desc"

      # A party filter: kind is :ico (exact) or :name (substring).
      PartyFilter = Data.define(:kind, :value)

      # The results toolbar's figures (see #summary).
      Summary = Data.define(:count, :eur_total, :eur_count, :other_currency, :without_amount)

      # The one currency that is summed; amounts in any other currency are
      # counted, never added in (PRODUCT: no sums across currencies).
      SUMMARY_CURRENCY = "EUR"

      Filters = Data.define(:q, :amount_min, :amount_max, :published_from, :published_to,
                            :signed_from, :signed_to, :party, :source, :sort)

      attr_reader :scope, :time_zone, :filters

      def initialize(scope:, params: {}, time_zone: Time.zone)
        @scope = scope
        @time_zone = time_zone
        @filters = Normalizer.call(params)
      end

      # The filtered relation, unordered.
      def relation
        @relation ||= conditions.filter(scope)
      end

      # The filtered relation with the deterministic sort applied.
      def results
        conditions.sort(relation)
      end

      # What the filtered set holds, in at most two queries: the record count,
      # the EUR sum over records that have an EUR amount (the sum is skipped
      # when there is none), and the records the sum leaves out: those in
      # another currency and those without an amount. Memoized.
      def summary
        @summary ||= build_summary
      end

      # Filter keys (never :sort) carrying a value.
      def active_filter_keys
        (PARAM_KEYS - [:sort]).reject { |key| filters.public_send(key).nil? }
      end

      def active?
        active_filter_keys.any?
      end

      def non_default_sort?
        filters.sort != DEFAULT_SORT
      end

      # Normalized string params (only what is set; sort only when not the
      # default) — round-trips through .new.
      def to_params
        active_filter_keys.to_h { |key| [key.to_s, param_value(key)] }.tap do |hash|
          hash["sort"] = filters.sort if non_default_sort?
        end
      end

      # A new query over the same scope and zone with param overrides applied
      # on top of this one's normalized params; a nil override removes the key.
      # Strict by design: an unknown key, or a non-nil value that does not
      # normalize (e.g. a malformed IČO), raises ArgumentError instead of
      # silently widening the result to the whole catalogue.
      def with(**overrides)
        unknown = overrides.keys.map(&:to_sym) - PARAM_KEYS
        raise ArgumentError, "unknown catalogue param(s): #{unknown.join(", ")}" if unknown.any?

        derived = self.class.new(scope: scope, params: merged_params(overrides), time_zone: time_zone)
        reject_invalid_overrides!(overrides, derived)
        derived
      end

      private

      # One grouped query: [currency, records, records with an amount] per
      # currency; the EUR sum is a second query, only when it can be non-zero.
      def build_summary
        rows = relation.group(:currency).pluck(:currency, Arel.star.count, Contract.arel_table[:amount].count)
        count = rows.sum { |_, total, _| total }
        with_amount = rows.sum { |_, _, counted| counted }
        eur_count = eur_amount_count(rows)
        Summary.new(count: count, eur_total: eur_total(eur_count), eur_count: eur_count,
                    other_currency: with_amount - eur_count, without_amount: count - with_amount)
      end

      def eur_amount_count(rows)
        rows.sum { |currency, _, counted| currency == SUMMARY_CURRENCY ? counted : 0 }
      end

      def eur_total(eur_count)
        relation.group(:currency).sum(:amount)[SUMMARY_CURRENCY] if eur_count.positive?
      end

      def merged_params(overrides)
        given = overrides.to_h { |key, value| [key.to_s, value.nil? ? nil : stringify(value)] }
        to_params.merge(given).compact
      end

      def reject_invalid_overrides!(overrides, derived)
        invalid = overrides.compact.keys.map(&:to_sym).reject { |key| override_applied?(key, overrides[key], derived) }
        raise ArgumentError, "invalid catalogue value for: #{invalid.join(", ")}" if invalid.any?
      end

      # A non-nil override took effect when it normalized to something (sort
      # always normalizes, so it is checked against the whitelist).
      def override_applied?(key, value, derived)
        return SORTS.include?(value.to_s.strip.downcase) if key == :sort

        !derived.filters.public_send(key).nil?
      end

      # Override values may be typed (Date, Integer, BigDecimal); the params
      # vocabulary is strings.
      def stringify(value)
        value.is_a?(BigDecimal) ? value.to_s("F") : value.to_s
      end

      def conditions
        @conditions ||= Conditions.new(filters, time_zone)
      end

      def param_value(key)
        value = filters.public_send(key)
        case value
        when BigDecimal then value.frac.zero? ? value.to_i.to_s : value.to_s("F")
        when Date then value.iso8601
        when PartyFilter then value.value
        else value
        end
      end
    end
  end
end
