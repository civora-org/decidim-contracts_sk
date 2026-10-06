# frozen_string_literal: true

module Decidim
  # Engine for Slovak public contracts workflow and catalogue.
  module ContractsSk
    # Public host API (civora-org/civora-platform#131): the published
    # contracts of the resource's organization linked to a Decidim resource,
    # newest first, as an ActiveRecord relation with the parties preloaded.
    # Empty (never raising) for an unsupported target type, an unpersisted
    # resource or one without an organization. See RelatedContractsQuery for
    # the guards and docs/related-contracts.md for how a host embeds it.
    def self.related_contracts_for(resource, limit: CONTRACTS_PER_PAGE)
      RelatedContractsQuery.call(resource, limit: limit)
    end
  end
end
