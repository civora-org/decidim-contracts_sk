# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Removes a party from a contract record
      # (civora-org/civora-platform#76).
      #
      # Like UpdateParty, the party is contract-scoped by construction (the
      # controller loads it from the parent contract's parties association)
      # and editability is re-checked at execution time, fail-closed through
      # the party's contract: no party may be removed once the record has
      # left the editable states. There is no audit row for party removal —
      # the audit trail tracks contract lifecycle transitions only.
      class DestroyParty < Decidim::Command
        def initialize(party)
          super()
          @party = party
        end

        def call
          return broadcast(:invalid) unless party.contract.editable?

          party.destroy!

          broadcast(:ok)
        rescue ActiveRecord::RecordNotDestroyed
          broadcast(:invalid)
        end

        private

        attr_reader :party
      end
    end
  end
end
