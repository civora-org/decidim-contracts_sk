# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Permission checks for the engine's contract records and their parties,
    # following Decidim's DefaultPermissions contract: it may set the
    # permission action's state only for the subjects it owns (:contract and
    # :party) and leaves every other action untouched, so the rest of the
    # host's permission_class_chain decides those.
    #
    # Admin scope, subject :contract:
    # - :create is allowed when the user's engine roles include :editor
    #   (the transition-table row 1 analog).
    # - :update is allowed when the user's engine roles include :editor AND
    #   the record's state is editable (ContractLifecycle::EDITABLE_STATES) —
    #   the editorial twin of the lifecycle's editability rule; reviewers can
    #   never edit, and non-editable states deny even editors.
    # - :download_crz_handoff (M02-05-C, civora-org/civora-platform#74) is
    #   allowed when the user's engine roles include :editor, with NO
    #   editability condition — fetching the generated handoff aid is
    #   role-gated only, so an editor can retrieve it on any lifecycle
    #   state (unlike :update, which stays editable-state-gated for the
    #   generating twin action).
    # - Transition events (:submit, :return, :approve, :reject, :publish,
    #   :archive) are allowed when ContractLifecycle.allowed_roles for the
    #   record's state intersect the user's engine roles. The event list is
    #   derived from ContractLifecycle::TRANSITIONS, never hand-enumerated.
    # - :read is allowed when the user holds any engine role (admin index).
    #
    # Admin scope, subject :party (civora-org/civora-platform#76) and
    # subject :document (M02-05-A0, civora-org/civora-platform#73): both are
    # contract-scoped child records, so their decisions hang off the parent
    # contract passed in context[:contract] and follow the same editorial
    # rule (the replace route maps onto the :update action):
    # - :create, :update and :destroy are allowed exactly when the user's
    #   engine roles include :editor AND the parent contract's state is
    #   editable — party composition and document files are part of editing
    #   the record.
    # - :read is allowed when the user holds any engine role, same rule as
    #   the contract's :read (the admin surfaces never grew a document index,
    #   but the rule is declared for symmetry with :party).
    #
    # Public scope, subject :contract:
    # - :read is allowed exactly when the record's state is publicly visible
    #   (ContractLifecycle::PUBLIC_STATES). No authentication required.
    #
    # Every other scope/subject/action combination is left unset, which
    # Decidim's permission machinery treats as denied (PermissionNotSetError
    # rescued to false — fail-closed). Public-scope party/document actions
    # are unset on purpose: the catalogue renders a published contract's
    # parties and documents as part of the record's own public :read (the
    # published-only scope IS the gate), never through per-record permission
    # decisions of its own.
    #
    # The record's state is read duck-typed from context[:contract]&.state
    # or context[:state]; callers pass at least one. For the child-record
    # subjects (:party, :document) the parent contract (context[:contract])
    # is the natural state source.
    # Load-time note: TRANSITION_EVENTS below evaluates ContractLifecycle
    # at class-body load; this file is only ever loaded through the gem's
    # lib require chain (which defines ContractLifecycle first), never
    # standalone.
    class Permissions < Decidim::DefaultPermissions
      TRANSITION_EVENTS = ContractLifecycle::TRANSITIONS.values
                                                        .flat_map(&:keys)
                                                        .uniq.sort.freeze

      def permissions
        return permission_action unless %i[contract party document].include? subject

        case permission_action.scope
        when :admin
          admin_action
        when :public
          public_action
        end

        permission_action
      end

      private

      def admin_action
        case subject
        when :contract
          contract_action
        when :party, :document
          child_record_action
        end
      end

      def contract_action
        case action
        # :create and :download_crz_handoff (M02-05-C,
        # civora-org/civora-platform#74) share the role-only rule: editor
        # membership decides, no lifecycle state is consulted.
        when :create, :download_crz_handoff
          toggle_allow(roles_for_user.include?(:editor))
        when :update
          toggle_allow(roles_for_user.include?(:editor) && ContractLifecycle.editable?(state))
        when :read
          toggle_allow(roles_for_user.any?)
        when *TRANSITION_EVENTS
          toggle_allow(transition_roles.any?)
        end
      end

      # The shared rule for the contract-scoped child-record subjects
      # (:party, civora-org/civora-platform#76; :document,
      # civora-org/civora-platform#73): writing is editorial work, so the
      # editor-role-plus-editable-state rule is identical for both.
      def child_record_action
        case action
        when :create, :update, :destroy
          toggle_allow(roles_for_user.include?(:editor) && ContractLifecycle.editable?(state))
        when :read
          toggle_allow(roles_for_user.any?)
        end
      end

      def public_action
        return unless subject == :contract

        toggle_allow(ContractLifecycle.publicly_visible?(state)) if action == :read
      end

      def transition_roles
        ContractLifecycle.allowed_roles(from: state, event: action) & roles_for_user
      end

      # Rails enum getters return Strings while ContractLifecycle is keyed
      # on Symbols; normalize (nil-safely) at this single boundary so both
      # state sources behave identically.
      def state
        (context[:contract]&.state || context[:state])&.to_sym
      end

      def roles_for_user
        Array(Decidim::ContractsSk.role_resolver.call(user, context)) & ContractLifecycle::ROLES
      end
    end
  end
end
