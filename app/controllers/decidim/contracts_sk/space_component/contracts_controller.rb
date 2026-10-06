# frozen_string_literal: true

module Decidim
  module ContractsSk
    module SpaceComponent
      # The in-space contracts list and detail page (civora-org/civora-platform
      # #89). Read-only and a pure presentation lens: it shows the
      # organization's published contracts, the SAME records the standalone
      # catalogue shows. A contract carries no component or space reference
      # (ADR-009), so "relevant to the space" means "published, of the
      # space's organization" and nothing narrower.
      #
      # Both actions read exclusively through PublicCatalogue#
      # published_contracts (published-only + organization scoped), so an
      # unpublished record, another organization's record and a nonexistent
      # id are indistinguishable (ActiveRecord::RecordNotFound, rendered as
      # 404 by the host), exactly like the standalone catalogue.
      #
      # Deliberately smaller than the standalone catalogue: no search,
      # filters or sorting (the list reads only the page parameter) and no
      # open-data, feed or supplier surface; the full register lives at the
      # standalone mount.
      class ContractsController < Decidim::ContractsSk::SpaceComponent::ApplicationController
        include Decidim::ContractsSk::PublicCatalogue

        # The shared detail view links a contractor to its supplier page
        # when the route exists, which it does not inside a space.
        helper Decidim::ContractsSk::SuppliersHelper

        def index
          @contracts = catalogue_query.results.includes(:parties).page(public_page)
                                      .per(Decidim::ContractsSk::CONTRACTS_PER_PAGE)
        end

        def show
          @contract = published_contracts.find(params[:id])

          # The manifest's permissions class decides the public read: the
          # wiring (permissions_class_name) is live, not decorative. The
          # published scope above already hides everything else, so this is
          # defence in depth: a state the permission table does not admit
          # for the public (fail closed) raises Decidim::ActionForbidden.
          enforce_permission_to :read, :contract, contract: @contract

          # Published amendments only, newest version first (the standalone
          # detail page's rule, ADR-006).
          @amendments = @contract.amendments.published.order(version: :desc)
        end

        private

        # The list ignores every catalogue filter/sort parameter: the
        # in-space list is the plain default-ordered published list, so a
        # crafted ?q=/?sort= can neither narrow nor reorder it.
        def build_catalogue_query(scope)
          CatalogueQuery.new(scope: scope, params: {}, time_zone: Time.zone)
        end
      end
    end
  end
end
