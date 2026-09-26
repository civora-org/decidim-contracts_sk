# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Pure-Ruby definition of the contract lifecycle: states, transitions and
    # the engine-logical roles allowed to trigger each transition.
    #
    # This module is the single source of truth for the lifecycle. The
    # human-facing rendering of the transition table (with rationale) lives in
    # docs/contract-lifecycle.md and is the contract consumed by the
    # permission-mapping milestone (civora-org/civora-platform#54).
    #
    # Roles are engine-logical symbols only (:editor, :reviewer). Mapping them
    # onto Decidim users/permissions is intentionally out of scope here.
    #
    # The Contract model (civora-org/civora-platform#55) wraps this API: a
    # `state` column validated against STATES and model-level transition
    # methods that persist via transition!.
    module ContractLifecycle
      class InvalidTransitionError < Decidim::ContractsSk::Error; end

      STATES = %i[draft in_review returned approved rejected published archived].freeze
      INITIAL_STATE = :draft
      TERMINAL_STATES = %i[rejected archived].freeze
      EDITABLE_STATES = %i[draft returned].freeze
      # States on which the ADR-007 privacy-redaction confirmation (ADR-007,
      # civora-org/civora-platform#91) may still be stamped: the editable
      # states plus :approved — a record can reach its reviewer sign-off
      # unstamped, and the confirmation must be admittable right up to the
      # publish edge. Deliberately NOT folded into EDITABLE_STATES: approval
      # still locks the content fields, so `editable?` keeps its exact
      # meaning; only the confirmation window widens.
      CONFIRMABLE_STATES = (EDITABLE_STATES + %i[approved]).freeze
      # States whose entry edge (in_review -> return/reject) demands a
      # reviewer decision reason (civora-org/civora-platform#90): a record
      # sitting in one of them carries the reviewer's judgment text, which
      # the admin edit page renders as a decision banner. The judgment
      # vocabulary is reviewer-only — TransitionContract fails any other
      # event closed when a reason is passed, and `submit` from :returned
      # clears the stale decision on resubmit.
      DECISION_STATES = %i[returned rejected].freeze
      PUBLIC_STATES = %i[published archived].freeze
      ROLES = %i[editor reviewer].freeze

      TRANSITIONS = {
        draft: { submit: { to: :in_review, roles: %i[editor] } },
        in_review: {
          return: { to: :returned, roles: %i[reviewer] },
          approve: { to: :approved, roles: %i[reviewer] },
          reject: { to: :rejected, roles: %i[reviewer] }
        },
        returned: { submit: { to: :in_review, roles: %i[editor] } },
        approved: { publish: { to: :published, roles: %i[editor] } },
        published: { archive: { to: :archived, roles: %i[editor] } },
        rejected: {},
        archived: {}
      }.tap do |table|
        table.each_value do |edges|
          edges.each_value do |edge|
            edge[:roles].freeze
            edge.freeze
          end
          edges.freeze
        end
      end.freeze

      module_function

      def state?(value)
        STATES.include?(value)
      end

      def initial_state
        INITIAL_STATE
      end

      def terminal?(state)
        TERMINAL_STATES.include?(state)
      end

      def editable?(state)
        EDITABLE_STATES.include?(state)
      end

      # True while the ADR-007 privacy-redaction confirmation may still be
      # stamped (CONFIRMABLE_STATES: draft, returned, approved — the
      # confirmation window, deliberately wider than editability).
      def confirmable?(state)
        CONFIRMABLE_STATES.include?(state)
      end

      def publicly_visible?(state)
        PUBLIC_STATES.include?(state)
      end

      def events_from(state)
        (TRANSITIONS[state] || {}).keys.sort.freeze
      end

      def transition_allowed?(from:, event:, role:)
        edge = edge_for(from, event)
        return false unless edge

        edge[:roles].include?(role)
      end

      def allowed_roles(from:, event:)
        edge = edge_for(from, event)
        return [].freeze unless edge

        edge[:roles].freeze
      end

      def next_state(from:, event:)
        edge = edge_for(from, event)
        return nil unless edge

        edge[:to]
      end

      def transition!(from:, event:, role:)
        to = next_state(from: from, event: event)
        unless to && transition_allowed?(from: from, event: event, role: role)
          raise InvalidTransitionError,
                "Invalid transition: #{event.inspect} from #{from.inspect} by #{role.inspect}"
        end

        to
      end

      # Internal edge lookup; deliberately not part of the public lifecycle API.
      def edge_for(from, event)
        (TRANSITIONS[from] || {})[event]
      end
      private_class_method :edge_for
    end
  end
end
