# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Removes a party from a contract record
      # (civora-org/civora-platform#76).
      #
      # Like UpdateParty, the party is contract-scoped by construction (the
      # controller loads it from the parent contract's parties association)
      # and editability is re-checked at execution time, fail-closed, INSIDE
      # the parent contract's row lock — the TOCTOU doctrine of
      # TransitionContract: the lock is the same row the lifecycle commands
      # lock, so a concurrent state change serializes against this write, and
      # with_lock reloads the contract first, so the guard reads the
      # in-database state: no party may be removed once the record has left
      # the editable states. There is no audit row for party removal — the
      # audit trail tracks contract lifecycle transitions only.
      class DestroyParty < Decidim::Command
        def initialize(party)
          super()
          @party = party
        end

        def call
          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            party.destroy!
          end

          broadcast(:ok)
        rescue ActiveRecord::RecordNotDestroyed
          broadcast(:invalid)
        end

        private

        attr_reader :party

        # The locked parent, loaded through the party's association (see the
        # class comment): with_lock's reload reads the in-database row under
        # the lock, so the guard decides on live state.
        def contract
          party.contract
        end
      end
    end
  end
end
