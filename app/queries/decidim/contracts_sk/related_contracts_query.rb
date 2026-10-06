# frozen_string_literal: true

module Decidim
  module ContractsSk
    # The reverse lookup of the engine-owned contract link join (ADR-009,
    # civora-org/civora-platform#131): which PUBLISHED contracts of the
    # resource's organization are linked to a given Decidim resource (an
    # accountability result, a budgets project), so the host can show them on
    # the participation side.
    #
    #   Decidim::ContractsSk::RelatedContractsQuery.call(result)  # a relation
    #   Decidim::ContractsSk::RelatedContractsQuery.items(result) # display items
    #
    # Guards, all fail-closed (an unknown situation yields an empty relation,
    # never an error and never another tenant's rows):
    #
    # * the resource must be persisted and answer +organization+ with a
    #   persisted organization (Result and Project both do, through their
    #   component) — contracts of any OTHER organization never match, even
    #   when the host's link resolver let a cross-tenant link through;
    # * the resource's class (its polymorphic name, as the join stores it)
    #   must be on Decidim::ContractsSk.supported_link_target_types — the
    #   same whitelist that gates creating and rendering links;
    # * only the +published+ state matches: draft, in-review, approved,
    #   returned, rejected and archived records are invisible.
    #
    # One relation, one IN-subquery on the join (no duplicates) and one
    # preload of the parties, so rendering N contracts costs two queries,
    # not 1 + N. The default limit is the catalogue page size; a resource
    # linked to more contracts than that shows the newest ones.
    class RelatedContractsQuery
      def self.call(resource, limit: CONTRACTS_PER_PAGE)
        new(resource, limit: limit).relation
      end

      # The display items the shipped partial renders.
      def self.items(resource, limit: CONTRACTS_PER_PAGE)
        call(resource, limit: limit).map { |contract| Item.new(contract) }
      end

      def initialize(resource, limit: CONTRACTS_PER_PAGE)
        @resource = resource
        @limit = limit.is_a?(Integer) && limit.positive? ? limit : CONTRACTS_PER_PAGE
      end

      def relation
        return Contract.none unless eligible?

        Contract.published
                .where(decidim_organization_id: organization_id)
                .where(id: linked_contract_ids)
                .preload(:parties)
                .order(published_at: :desc, id: :desc)
                .limit(@limit)
      end

      private

      def linked_contract_ids
        ContractLink.where(target_type: target_type, target_id: @resource.id).select(:contract_id)
      end

      def eligible?
        @resource.try(:id).present? && organization_id.present? &&
          Decidim::ContractsSk.supported_link_target_types.include?(target_type)
      end

      def organization_id
        @organization_id ||= @resource.try(:organization)&.id
      end

      # The name the polymorphic join stores (the base class for STI models).
      def target_type
        @target_type ||= (@resource.class.try(:polymorphic_name) || @resource.class.name).to_s
      end
    end
  end
end
