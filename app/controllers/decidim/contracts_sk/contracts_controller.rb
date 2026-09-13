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
    # Only :id is ever read from the request on the detail page. The show
    # view renders the record's parties, documents (the latter as download
    # links through the host's ActiveStorage route, M02-05-A0
    # civora-org/civora-platform#73) and its public version history
    # (M02-05-B, civora-org/civora-platform#65 — published amendments
    # only). The index is paginated at the engine-wide fixed page size
    # (CONTRACTS_PER_PAGE, civora-org/civora-platform#86b) and carries a
    # single free-text search (:q over title/reference, mirroring the admin
    # index's filter): the search is applied strictly ON TOP of
    # #published_contracts, so the published-only + organization scoping
    # survives every query.
    class ContractsController < Decidim::ContractsSk::ApplicationController
      # Case-insensitive free-text match for the catalogue's :q search over
      # the two editorial identity fields — the SAME condition the admin
      # index applies (one vocabulary, never a second one); :pattern is
      # always pre-escaped with sanitize_sql_like, so user-supplied % and _
      # stay literal.
      SEARCH_CONDITION = "LOWER(title) LIKE :pattern OR LOWER(reference) LIKE :pattern"

      # Deterministic catalogue order (civora-org/civora-platform#86b):
      # newest publication first, the id as the tiebreaker — a total order,
      # so pagination stays stable when two records share a publication
      # timestamp (PostgreSQL leaves unordered row order undefined).
      CATALOGUE_ORDER = { published_at: :desc, id: :desc }.freeze

      # The stripped search term backs the view's field prefill.
      helper_method :search_term

      def index
        # The page param reaches Kaminari only as a string: an array
        # (page[]=2) would raise inside Kaminari's Integer coercion.
        @contracts = filtered_published_contracts.page(params[:page].to_s)
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

      # The catalogue's read surface with the free-text search applied ON
      # TOP (never around it), so the published-only + organization
      # scoping survives every query. A blank or absent :q contributes no
      # WHERE clause — an empty search box degrades to the plain catalogue.
      def filtered_published_contracts
        pattern = index_search_pattern
        pattern ? published_contracts.where(SEARCH_CONDITION, pattern: pattern) : published_contracts
      end

      # The escaped LIKE pattern for the :q search; nil when the term is
      # blank. Mirrors the admin index's index_search_pattern.
      def index_search_pattern
        term = search_term
        "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" if term.present?
      end

      # The stripped search term (also the view's field prefill).
      def search_term
        params[:q].to_s.strip
      end

      # The catalogue's entire public read surface: the current
      # organization's lifecycle-published records only, newest publication
      # first. The Gate-1 scope for #62/#63 pins `state == "published"`
      # (archived visibility is a separate, later decision), so the plain
      # enum scope is used instead of the broader
      # ContractState#publicly_visible?; the organization filter is the
      # tenant boundary, same rule as the admin side.
      def published_contracts
        Contract.where(organization: current_organization)
                .published.order(CATALOGUE_ORDER)
      end
    end
  end
end
