# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Performs one lifecycle transition on a contract record
      # (civora-org/civora-platform#59).
      #
      # Authorization is re-derived here at execution time, fail-closed, from
      # the same config-time seams the permission layer used: the engine role
      # resolver and the lifecycle transition table. Each transition edge
      # carries exactly one role, so the first intersection is deterministic;
      # a request whose roles intersect no edge (wrong role or no edge at
      # all) broadcasts :invalid without touching the record. The permission
      # layer remains the request-admission authority — this re-check covers
      # stale permission decisions and keeps the command safe to call from
      # other contexts.
      #
      # The state change and the audit row commit atomically: both happen
      # inside contract.with_lock (row lock + single transaction), so a
      # failure at either step rolls the record back — a transition either
      # fully happened (with its audit row) or did not happen at all. The
      # audit payload shape is fixed by the #57 migration (D4): action
      # "contract.<event>", polymorphic target, explicit organization/actor,
      # timestamps — no JSON payload, no from/to.
      class TransitionContract < Decidim::Command
        def initialize(contract, event:, user:)
          super()
          @contract = contract
          @event = event
          @user = user
        end

        def call
          return broadcast(:invalid) unless role

          contract.with_lock do
            contract.transition_state!(event: event, role: role)
            record_audit!
          end

          broadcast(:ok, contract)
        rescue ContractLifecycle::InvalidTransitionError, ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :contract, :event, :user

        # The D4-payload audit row: written inside the caller's transaction,
        # so its failure rolls the state change back with it.
        def record_audit!
          AuditEvent.create!(action: "contract.#{event}", target: contract,
                             organization: contract.organization, actor: user)
        end

        # The single engine role that may fire this event from the record's
        # current state, or nil when the user's roles intersect no edge.
        # Rails enum getters return Strings while ContractLifecycle is keyed
        # on Symbols — normalize at this boundary (same as the Permissions
        # class).
        def role
          state = contract.state&.to_sym
          roles = Array(Decidim::ContractsSk.role_resolver.call(user, {})) & ContractLifecycle::ROLES

          (ContractLifecycle.allowed_roles(from: state, event: event) & roles).first
        end
      end
    end
  end
end
