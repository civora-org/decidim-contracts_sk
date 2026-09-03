# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A public contract record moving through the engine's lifecycle.
    #
    # Identity is per organization: (organization, reference) is unique.
    # The state column is validated against ContractLifecycle::STATES and
    # transitions run through ContractState, backed by ContractLifecycle —
    # the single source of truth for the lifecycle.
    #
    # The source/source_id/imported_at/import_status columns are manual
    # CRZ-handoff provenance metadata (docs/contracts-domain-notes.md); no
    # behaviour attaches to them until the V0.2 import arc.
    class Contract < ApplicationRecord
      include Decidim::ContractsSk::ContractState

      # Symbol => stored String mapping for the Rails enum, derived from the
      # lifecycle's single source of truth.
      STATE_VALUES = ContractLifecycle::STATES.to_h { |state| [state, state.to_s] }.freeze

      # Stored-string state vocabulary for the inclusion validator — frozen
      # so a captured validator reference cannot mutate the vocabulary.
      STATE_STRINGS = ContractLifecycle::STATES.map(&:to_s).freeze

      belongs_to :organization,
                 foreign_key: "decidim_organization_id",
                 class_name: "Decidim::Organization"

      belongs_to :author,
                 foreign_key: "decidim_author_id",
                 class_name: "Decidim::User"

      validates :title, presence: true, length: { maximum: 255 }
      validates :reference, presence: true,
                            length: { maximum: 255 },
                            uniqueness: { scope: :decidim_organization_id }
      validates :state, presence: true,
                        inclusion: { in: STATE_STRINGS }

      # Positional arguments: the Rails 7.2 enum API (the keyword form is
      # deprecated and removed in Rails 8). The getter returns Strings, which
      # ContractState and the permissions layer normalize via #to_sym.
      enum :state, STATE_VALUES, default: "draft"
    end
  end
end
