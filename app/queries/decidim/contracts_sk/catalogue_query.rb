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
    # * Publication dates filter published_at (the moment the record entered
    #   the catalogue; for CRZ mirrors that is their import time), as calendar
    #   days in the given time zone. Signing dates filter signed_on.
    # * A reversed range (from after to) is swapped, not rejected.
    # * party matches a contract's party by exact IČO (8 digits) or by
    #   case-insensitive name substring, via an IN-subquery (no N+1, no
    #   DISTINCT).
    class CatalogueQuery
      PARAM_KEYS = %i[q amount_min amount_max published_from published_to
                      signed_from signed_to party source sort].freeze

      SOURCES = %w[editorial crz].freeze
      SORTS = %w[published_desc published_asc amount_desc amount_asc].freeze
      DEFAULT_SORT = "published_desc"

      # A party filter: kind is :ico (exact) or :name (substring).
      PartyFilter = Data.define(:kind, :value)

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
