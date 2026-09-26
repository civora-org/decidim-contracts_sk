# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Removes a project/result link from a contract record (M01-87,
      # civora-org/civora-platform#87).
      #
      # Like DestroyParty, the link is contract-scoped by construction (the
      # controller loads it from the parent contract's links association)
      # and editability is re-checked at execution time, fail-closed, INSIDE
      # the parent contract's row lock — the TOCTOU doctrine of
      # TransitionContract (the repo-wide lock discipline since #69): the
      # lock is the same row the lifecycle commands lock, so a concurrent
      # state change serializes against this write, and with_lock reloads
      # the contract first, so the guard reads the in-database state: no
      # link may be removed once the record has left the editable states.
      # There is no audit row for link removal — the audit trail tracks
      # contract lifecycle transitions only.
      class DestroyLink < Decidim::Command
        def initialize(link)
          super()
          @link = link
        end

        def call
          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            link.destroy!
          end

          broadcast(:ok)
        rescue ActiveRecord::RecordNotDestroyed
          broadcast(:invalid)
        end

        private

        attr_reader :link

        # The locked parent, loaded through the link's association (see the
        # class comment): with_lock's reload reads the in-database row under
        # the lock, so the guard decides on live state.
        def contract
          link.contract
        end
      end
    end
  end
end
