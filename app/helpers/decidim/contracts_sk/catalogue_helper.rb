# frozen_string_literal: true

module Decidim
  module ContractsSk
    # View helpers of the public catalogue's filter form
    # (civora-org/civora-platform#116). Needs ApplicationHelper's
    # format_amount / format_date (both helpers are mixed into the public
    # controller).
    module CatalogueHelper
      AMOUNT_KEYS = %i[amount_min amount_max].freeze
      DATE_KEYS = %i[published_from published_to signed_from signed_to].freeze

      # The active filters as [label, value] pairs for the "active filters"
      # summary, built from the NORMALIZED query: what the reader sees is
      # what was applied (a swapped range shows swapped).
      def catalogue_active_filters(query)
        keys = query.active_filter_keys
        keys += [:sort] if query.non_default_sort?
        keys.map do |key|
          [t("decidim.contracts_sk.contracts.index.filters.active.#{key}"),
           catalogue_filter_text(key, query.filters.public_send(key))]
        end
      end

      private

      def catalogue_filter_text(key, value)
        return format_amount(value, "EUR") if AMOUNT_KEYS.include?(key)
        return format_date(value) if DATE_KEYS.include?(key)
        return value.value if key == :party

        catalogue_choice_text(key, value)
      end

      # source / sort are labelled choices; q is the plain term.
      def catalogue_choice_text(key, value)
        return value if key == :q

        t("decidim.contracts_sk.contracts.index.filters.#{key}s.#{value}")
      end
    end
  end
end
