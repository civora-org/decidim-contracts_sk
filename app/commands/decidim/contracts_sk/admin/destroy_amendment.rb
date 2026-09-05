# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Removes a draft amendment from a contract record (M02-05-B,
      # civora-org/civora-platform#65).
      #
      # Like UpdateAmendment, the amendment is contract-scoped by
      # construction (the controller loads it from the parent contract's
      # amendments association) and draft-only is re-checked at execution
      # time, fail-closed, INSIDE the row lock — the TOCTOU doctrine of
      # TransitionContract: published amendments are immutable forever
      # (ADR-006) and can never be removed through this surface. with_lock
      # reloads the row first, so the guard reads the in-database state
      # rather than a possibly stale in-memory copy; the model raises
      # ReadOnlyRecord should a stale path even reach it. There is no audit
      # row for amendment removal — the audit trail tracks lifecycle
      # transitions and publications only.
      class DestroyAmendment < Decidim::Command
        def initialize(amendment)
          super()
          @amendment = amendment
        end

        def call
          amendment.with_lock do
            return broadcast(:invalid) unless amendment.draft?

            amendment.destroy!
          end

          broadcast(:ok)
        rescue ActiveRecord::RecordNotDestroyed
          broadcast(:invalid)
        end

        private

        attr_reader :amendment
      end
    end
  end
end
