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
    # Admin scope, subject :amendment (M02-05-B, civora-org/civora-platform
    # #65): amendments are the contract's version history, which exists only
    # from publication onwards (ADR-006), so the rules read BOTH the parent
    # contract's state (context[:contract], as above) and the amendment's
    # own amendment state (context[:amendment], with context[:amendment_state]
    # as the duck-typed fallback — the same two-sources doctrine as the
    # contract's state):
    # - :create is allowed when the user's engine roles include :editor AND
    #   the parent contract's state is published — drafts are seeded onto
    #   published records only.
    # - :update and :destroy are allowed when the user's engine roles
    #   include :editor AND the amendment is a draft — published amendments
    #   are immutable forever (ADR-006), regardless of the contract's own
    #   state.
    # - :publish is allowed when the user's engine roles include :editor AND
    #   the parent contract's state is published AND the amendment is a
    #   draft — one explicit POST per publish event, gated like the
    #   lifecycle transitions are.
    # - :read is allowed when the user holds any engine role, same rule as
    #   :party/:document (the admin index shows drafts and published alike).
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
    # is the natural state source; the :amendment subject reads the
    # amendment's own state from context[:amendment]&.state or
    # context[:amendment_state] the same way.
    # Load-time note: TRANSITION_EVENTS below evaluates ContractLifecycle
    # at class-body load; this file is only ever loaded through the gem's
    # lib require chain (which defines ContractLifecycle first), never
    # standalone.
    class Permissions < Decidim::DefaultPermissions
      TRANSITION_EVENTS = ContractLifecycle::TRANSITIONS.values
                                                        .flat_map(&:keys)
                                                        .uniq.sort.freeze

      def permissions
        return permission_action unless %i[contract party document amendment].include? subject

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
        when :amendment
          amendment_action
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

      # The amendment rule (M02-05-B, civora-org/civora-platform#65): the
      # version history exists only from publication onwards (ADR-006), so
      # every gate combines the parent contract's published state with the
      # amendment's own draft state. Update/destroy deliberately consult
      # only the amendment's draft state — published amendments are
      # immutable regardless of what the contract does next. The case stays
      # flat on purpose; the role/state combinators live in the named
      # predicates below it.
      def amendment_action
        case action
        when :create
          toggle_allow(amendment_create_allowed?)
        when :update, :destroy
          toggle_allow(amendment_edit_allowed?)
        when :publish
          toggle_allow(amendment_publish_allowed?)
        when :read
          toggle_allow(roles_for_user.any?)
        end
      end

      def amendment_create_allowed?
        editor? && contract_published?
      end

      def amendment_edit_allowed?
        editor? && amendment_draft?
      end

      def amendment_publish_allowed?
        editor? && contract_published? && amendment_draft?
      end

      def editor?
        roles_for_user.include?(:editor)
      end

      # The parent contract's lifecycle state, as the amendment gates see it.
      def contract_published?
        state == :published
      end

      def amendment_draft?
        amendment_state == :draft
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

      # The amendment's own state, normalized at the same boundary (see the
      # class comment): the amendment object or a bare state fallback.
      def amendment_state
        (context[:amendment]&.state || context[:amendment_state])&.to_sym
      end

      def roles_for_user
        Array(Decidim::ContractsSk.role_resolver.call(user, context)) & ContractLifecycle::ROLES
      end
    end
  end
end
