# frozen_string_literal: true

module Decidim
  module ContractsSk
    # The public catalogue's read surface, shared by the public controllers
    # (the catalogue itself and, since civora-org/civora-platform#119, the
    # open-data export; the Atom feed and the supplier pages build on it
    # next). One place decides what the public may read, so no controller can
    # widen it by accident.
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
      end

      private

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
        published_contracts.where.not(source: CrzImport::Mapper::SOURCE)
      end
    end
  end
end
