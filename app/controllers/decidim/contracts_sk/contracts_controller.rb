# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Public contracts catalogue (civora-org/civora-platform#62, #63).
    #
    # Read-only and authentication-free: the public base carries no sign-in
    # floor and neither action consults the permission layer. Both actions
    # read exclusively through #published_contracts, so a record in any other
    # lifecycle state and a nonexistent id are indistinguishable — the scoped
    # find raises ActiveRecord::RecordNotFound for both (the host app's
    # standard handling renders it as 404; nothing about the response may
    # hint at hidden records).
    #
    # The read scope (#published_contracts) and the filter object live in
    # the PublicCatalogue concern, shared with the open-data export.
    #
    # Tenancy: the catalogue is scoped to the current organization (Gate-1
    # fold-in, mirroring the admin side's contracts_scope). A published
    # record of ANOTHER organization is as invisible as an unpublished one:
    # the tenant-scoped find raises the same ActiveRecord::RecordNotFound,
    # indistinguishable from a nonexistent id. current_organization comes
    # from the host's Decidim::ApplicationController
    # (Decidim::NeedsOrganization) — the same seam the admin base relies on.
    #
    # Only :id is ever read from the request on the detail page. The show
    # view renders the record's parties, documents (the latter as download
    # links through the host's ActiveStorage route, M02-05-A0
    # civora-org/civora-platform#73) and its public version history
    # (M02-05-B, civora-org/civora-platform#65 — published amendments
    # only). The index is paginated at the engine-wide fixed page size
    # (CONTRACTS_PER_PAGE, civora-org/civora-platform#86b) and carries the
    # free-text search plus amount/date/party/source filters and a sort
    # (civora-org/civora-platform#116, see CatalogueQuery): all applied
    # strictly ON TOP of #published_contracts, so the published-only +
    # organization scoping survives every query.
    class ContractsController < Decidim::ContractsSk::ApplicationController
      include Decidim::ContractsSk::PublicCatalogue

      # The filter/sort object behind the index (civora-org/civora-platform
      # #116); the view prefills its form from the NORMALIZED values.
      helper Decidim::ContractsSk::CatalogueHelper
      helper_method :search_term

      def index
        # The page param reaches Kaminari only as a string: an array
        # (page[]=2) would raise inside Kaminari's Integer coercion.
        @contracts = catalogue_query.results.page(params[:page].to_s)
                                    .per(Decidim::ContractsSk::CONTRACTS_PER_PAGE)
      end

      def show
        @contract = published_contracts.find(params[:id])

        # Public version history (M02-05-B, civora-org/civora-platform#65,
        # ADR-006): published amendments only, newest version first. Draft
        # amendments are NEVER publicly visible — the published scope IS
        # the gate, mirroring the record's own published-only read; an
        # unpublished version and an absent one are indistinguishable.
        @amendments = @contract.amendments.published.order(version: :desc)
      end

      private

      # The normalized free-text term (the search field's prefill).
      def search_term
        catalogue_query.filters.q.to_s
      end
    end
  end
end
