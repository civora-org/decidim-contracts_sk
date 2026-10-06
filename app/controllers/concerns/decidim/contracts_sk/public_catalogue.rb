# frozen_string_literal: true

module Decidim
  module ContractsSk
    # The public catalogue's read surface, shared by the public controllers
    # (the catalogue itself and, since civora-org/civora-platform#119, the
    # open-data export, the Atom feed and the supplier pages). One place
    # decides what the public may read, so no controller can widen it by
    # accident.
    #
    # * #published_contracts: the current organization's lifecycle-published
    #   records, UNORDERED (the CatalogueQuery owns the sort). The Gate-1
    #   scope for #62/#63 pins `state == "published"` (archived visibility is
    #   a separate, later decision), so the plain enum scope is used instead
    #   of the broader ContractState#publicly_visible?; the organization
    #   filter is the tenant boundary, same rule as the admin side.
    # * #open_data_scope: the machine-readable surfaces' narrower scope —
    #   the organization's OWN records only (civora-org/civora-platform#119,
    #   ADR-008 decision 6): CRZ-mirrored rows are link-only mirrors of
    #   someone else's register and CRZ declares no reuse licence (#83), so
    #   they are never re-published as data.
    # * #catalogue_query / #build_catalogue_query(scope): the filter/sort
    #   object over the published scope, or over a given (narrower) one. Only
    #   the catalogue's own keys are ever read from the request.
    module PublicCatalogue
      extend ActiveSupport::Concern

      included do
        helper_method :catalogue_query, :current_organization
        # Titles, descriptions and Open Graph tags of the HTML pages (#122).
        helper Decidim::ContractsSk::DiscoverabilityHelper
      end

      # Upper bound of the page number: an absurd value would overflow the
      # database's integer OFFSET (PostgreSQL raises, SQLite mismatches).
      MAX_PAGE = 100_000

      private

      # The page param, read as a String (page[]=2 would raise inside
      # Kaminari's Integer coercion) and clamped into 1..MAX_PAGE, so no
      # hostile value can reach the OFFSET.
      def public_page
        params[:page].to_s.to_i.clamp(1, MAX_PAGE)
      end

      def catalogue_query
        @catalogue_query ||= build_catalogue_query(published_contracts)
      end

      def build_catalogue_query(scope)
        CatalogueQuery.new(
          scope: scope,
          params: request.query_parameters.slice(*CatalogueQuery::PARAM_KEYS),
          time_zone: Time.zone
        )
      end

      def published_contracts
        Contract.where(organization: current_organization)
                .published
      end

      def open_data_scope
        Contract.open_data(current_organization)
      end
    end
  end
end
