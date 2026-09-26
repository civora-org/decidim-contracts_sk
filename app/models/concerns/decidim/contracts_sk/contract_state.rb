# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Lifecycle behaviour for records carrying a ContractLifecycle state.
    #
    # Mixes the pure-Ruby state machine (ContractLifecycle — the single
    # source of truth) into any object that exposes a #state reader and
    # persists through #update! — the Contract model today, test doubles and
    # future state-bearing records as needed. Nothing here touches the
    # database directly, so the concern stays testable offline.
    #
    # All query methods fail closed (false / [] on unknown or missing
    # state); only the transition methods raise InvalidTransitionError, and
    # they do so before any mutation: ContractLifecycle.transition! validates
    # the edge first, #update! runs only afterwards.
    module ContractState
      extend ActiveSupport::Concern

      # Sorted, unique event vocabulary derived from the transition table —
      # never hand-enumerated, so table additions are picked up verbatim.
      # Permissions::TRANSITION_EVENTS repeats this derivation on purpose
      # (the layers stay decoupled); the duplicate is spec-pinned in both
      # permissions_spec.rb and contract_state_spec.rb.
      TRANSITION_EVENTS = ContractLifecycle::TRANSITIONS.values
                                                        .flat_map(&:keys)
                                                        .uniq.sort.freeze

      # Moves the record through a lifecycle event and persists the new
      # state. Returns self; raises InvalidTransitionError (before any
      # mutation) when the edge does not exist for the record's current
      # state and role. State/event/role input is coerced with #to_sym, so
      # Rails enum getters (Strings) work as-is.
      def transition_state!(event:, role:)
        target = ContractLifecycle.transition!(
          from: state&.to_sym,
          event: event&.to_sym,
          role: role&.to_sym
        )

        update!(state: target)
        self
      end

      # One convenience wrapper per transition event, derived from the table
      # (submit!/return!/approve!/reject!/publish!/archive!), each delegating
      # to #transition_state! with its event.
      TRANSITION_EVENTS.each do |event|
        define_method(:"#{event}!") do |by_role:|
          transition_state!(event: event, role: by_role)
        end
      end

      # True exactly when the lifecycle table allows the edge from the
      # record's current state; false (never raises) otherwise.
      def can_transition?(event:, role:)
        ContractLifecycle.transition_allowed?(
          from: state&.to_sym,
          event: event&.to_sym,
          role: role&.to_sym
        )
      end

      # Frozen list of events the role may trigger right now; [] when none.
      # Fails closed for unknown states, unknown roles, terminal states and
      # a missing state.
      def allowed_events_for(role:)
        from = state&.to_sym
        ContractLifecycle.events_from(from).select do |event|
          ContractLifecycle.transition_allowed?(from: from, event: event, role: role&.to_sym)
        end.freeze
      end

      # True in terminal states (rejected, archived) only.
      def terminal?
        ContractLifecycle.terminal?(state&.to_sym)
      end

      # True while editors may still edit the record (draft, returned).
      def editable?
        ContractLifecycle.editable?(state&.to_sym)
      end

      # True while the ADR-007 privacy-redaction confirmation may still be
      # stamped (draft, returned, approved — CONFIRMABLE_STATES). Deliberately
      # wider than #editable?: approval locks the content, but the
      # confirmation must stay admittable right up to the publish edge.
      def confirmable?
        ContractLifecycle.confirmable?(state&.to_sym)
      end

      # True when the lifecycle marks the record publicly visible
      # (published, archived — lifecycle decision D4). Broader than the
      # catalogue itself: the public catalogue renders lifecycle-published
      # records only (Gate-1 decision), so this predicate is a visibility
      # signal, not the catalogue's query.
      def publicly_visible?
        ContractLifecycle.publicly_visible?(state&.to_sym)
      end
    end
  end
end
