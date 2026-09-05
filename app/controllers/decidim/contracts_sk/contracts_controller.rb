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
    # Tenancy: the catalogue is scoped to the current organization (Gate-1
    # fold-in, mirroring the admin side's contracts_scope). A published
    # record of ANOTHER organization is as invisible as an unpublished one:
    # the tenant-scoped find raises the same ActiveRecord::RecordNotFound,
    # indistinguishable from a nonexistent id. current_organization comes
    # from the host's Decidim::ApplicationController
    # (Decidim::NeedsOrganization) — the same seam the admin base relies on.
    #
    # Only :id is ever read from the request. The show view renders the
    # record's parties and documents (the latter as download links through
    # the host's ActiveStorage route, M02-05-A0
    # civora-org/civora-platform#73); amendments are deliberately not
    # rendered yet (M02-05-B), and the index is not paginated (no new
    # dependencies by design; the catalogue is small at this stage).
    class ContractsController < Decidim::ContractsSk::ApplicationController
      def index
        @contracts = published_contracts
      end

      def show
        @contract = published_contracts.find(params[:id])
      end

      private

      # The catalogue's entire public read surface: the current
      # organization's lifecycle-published records only, newest publication
      # first. The Gate-1 scope for #62/#63 pins `state == "published"`
      # (archived visibility is a separate, later decision), so the plain
      # enum scope is used instead of the broader
      # ContractState#publicly_visible?; the organization filter is the
      # tenant boundary, same rule as the admin side.
      def published_contracts
        Contract.where(organization: current_organization)
                .published.order(published_at: :desc)
      end
    end
  end
end
