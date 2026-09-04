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
      # publication stamp (published_at, #75) rides the same transaction: it
      # is assigned inside the lock BEFORE the state write, so the state's
      # update! persists it in the same UPDATE, and an audit failure rolls
      # the stamp back together with the state. It is a system field — the
      # admin form never writes it; the archive event leaves the original
      # stamp untouched, and there is no un-publish edge, so a stamp is
      # never cleared. The audit payload shape is fixed by the #57 migration
      # (D4): action "contract.<event>", polymorphic target, explicit
      # organization/actor, timestamps — no JSON payload, no from/to.
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
            stamp_published_at!
            contract.transition_state!(event: event, role: role)
            record_audit!
          end

          broadcast(:ok, contract)
        rescue ContractLifecycle::InvalidTransitionError, ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :contract, :event, :user

        # The publish stamp: assigned before transition_state! so the
        # state's update! persists both attributes atomically (this runs
        # inside the caller's with_lock transaction, so an audit failure
        # rolls the stamp back with the state). The event is normalized
        # with #to_s at this boundary — this file's doctrine wherever input
        # meets the lifecycle (cf. the #to_sym normalization in
        # transition_state! and #role): a caller passing "publish" as a
        # String must stamp exactly like the symbol, otherwise the edge
        # would resolve and only the stamp would silently be skipped.
        def stamp_published_at!
          contract.published_at = Time.current if event.to_s == "publish"
        end

        # The D4-payload audit row: written inside the caller's transaction,
        # so its failure rolls the state change back with it.
        def record_audit!
          AuditEvent.create!(action: "contract.#{event}", target: contract,
                             organization: contract.organization, actor: user)
        end

        # The single engine role that may fire this event from the record's
        # current state, or nil when the user's roles intersect no edge.
        # Rails enum getters return Strings while ContractLifecycle is keyed
        # on Symbols — normalize both the state and the event at this
        # boundary (same as the Permissions class), so a String event
        # resolves its edge instead of silently missing it and leaving the
        # stamp behind.
        def role
          state = contract.state&.to_sym
          roles = Array(Decidim::ContractsSk.role_resolver.call(user, {})) & ContractLifecycle::ROLES

          (ContractLifecycle.allowed_roles(from: state, event: event&.to_sym) & roles).first
        end
      end
    end
  end
end
