# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Permission checks for the engine's contract records and their child
    # records, following Decidim's DefaultPermissions contract: it may set
    # the permission action's state only for the subjects it owns (:contract,
    # :party, :document, :amendment, :link, :note, :audit_event) and leaves every
    # other action untouched, so the rest of the host's permission_class_chain
    # decides those.
    #
    # Admin scope, subject :contract:
    # - :create is allowed when the user's engine roles include :editor
    #   (the transition-table row 1 analog).
    # - :update is allowed when the user's engine roles include :editor AND
    #   the record's state is editable (ContractLifecycle::EDITABLE_STATES) —
    #   the editorial twin of the lifecycle's editability rule; reviewers can
    #   never edit, and non-editable states deny even editors.
    # - :confirm_redaction (ADR-007, civora-org/civora-platform#91) shares
    #   :update's role rule but is admittable on the wider confirmable
    #   window (ContractLifecycle::CONFIRMABLE_STATES = editable states +
    #   :approved — a reviewer-approved record may still be stamped right
    #   before publish; `editable?` itself is NOT widened). The command
    #   re-checks both conditions inside the row lock.
    # - :import_crz (ADR-008, civora-org/civora-platform#86) is allowed when
    #   the user's engine roles include :editor, with NO lifecycle condition
    #   — importing one CRZ record by id is a record-management act on the
    #   catalogue, not an edit of an existing record (the created/updated
    #   record's own lifecycle guards live in the upsert command's lock).
    # - :import_file (civora-org/civora-platform#129, spreadsheet bulk
    #   import) is allowed when the user's engine roles include :editor,
    #   role-only like :import_crz: the rows land as DRAFTS and still pass
    #   the normal workflow (four-eyes review included).
    # - :download_crz_handoff (M02-05-C, civora-org/civora-platform#74) is
    #   allowed when the user's engine roles include :editor, with NO
    #   editability condition — fetching the generated handoff aid is
    #   role-gated only, so an editor can retrieve it on any lifecycle
    #   state (unlike :update, which stays editable-state-gated for the
    #   generating twin action).
    # - :confirm_crz_filing (civora-org/civora-platform#125) is allowed when
    #   the user's engine roles include :editor AND the record
    #   (context[:contract] — required, a bare :state context is denied
    #   fail-closed) is editorial (source != the CRZ mirror's), published and
    #   not yet confirmed as filed (crz_filed_at blank): only a published
    #   editorial record that has been handed off to the CRZ can be linked to
    #   its official record, and once. Reviewers are denied. The command
    #   re-checks all of it inside the row lock.
    # - Transition events (:submit, :return, :approve, :reject, :publish,
    #   :archive) are allowed when ContractLifecycle.allowed_roles for the
    #   record's state intersect the user's engine roles. The event list is
    #   derived from ContractLifecycle::TRANSITIONS, never hand-enumerated.
    #   Four-eyes rule (civora-org/civora-platform#123): the judgment
    #   events (:return, :approve, :reject) are additionally DENIED to the
    #   person recorded as the record's submitter
    #   (context[:contract].decidim_submitted_by_id), unless the host
    #   enabled Decidim::ContractsSk.allow_self_review. A context with only
    #   :state carries no submitter and is unaffected.
    # - :read is allowed when the user holds any engine role (admin index).
    #
    # Admin scope, subject :party (civora-org/civora-platform#76), subject
    # :document (M02-05-A0, civora-org/civora-platform#73) and subject :link
    # (civora-org/civora-platform#87): all are contract-scoped child
    # records, so their decisions hang off the parent contract passed in
    # context[:contract] and follow the same editorial rule (the replace
    # route maps onto the :update action):
    # - :create, :update and :destroy are allowed exactly when the user's
    #   engine roles include :editor AND the parent contract's state is
    #   editable — party composition, document files and project/result
    #   links are part of editing the record (links expose only :create and
    #   :destroy through their routes — links have no editable content —
    #   but the shared rule covers the whole action set for symmetry).
    # - :read is allowed when the user holds any engine role, same rule as
    #   the contract's :read (the admin surfaces never grew a document or
    #   link index, but the rule is declared for symmetry with :party).
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
    # Admin scope, subject :note (civora-org/civora-platform#128): internal
    # review notes are a private thread on a contract. :read and :create are
    # allowed when the user holds ANY engine role (editor OR reviewer — the
    # editor asks, the reviewer explains), in ANY lifecycle state: the
    # thread is never public and survives publication. The gate is
    # role-only; the parent contract (context[:contract]) is passed for
    # the tenant-scoped lookup but not consulted. Notes are append-only, so
    # :update and :destroy are deliberately left unset (fail-closed) for
    # every role.
    #
    # Admin scope, subject :audit_event (civora-org/civora-platform#92):
    # the append-only audit trail is read-only and organization-scoped, so
    # its single action mirrors the contracts index read:
    # - :read is allowed when the user holds any engine role (editor OR
    #   reviewer) — every role holder may consult the org's trail. The gate
    #   is role-only: no record is needed (the viewer is org-level) and no
    #   lifecycle state is consulted.
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
    # Cop note: the class stays deliberately cohesive — one rule table per
    # subject, every gate readable in one file; splitting it would scatter
    # the permission contract rather than simplify it.
    # rubocop:disable Metrics/ClassLength
    class Permissions < Decidim::DefaultPermissions
      TRANSITION_EVENTS = ContractLifecycle::TRANSITIONS.values
                                                        .flat_map(&:keys)
                                                        .uniq.sort.freeze

      def permissions
        return permission_action unless %i[contract party document amendment link note audit_event].include? subject

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
        when :contract then contract_action
        when :party, :document, :link then child_record_action
        when :amendment then amendment_action
        when :note then note_action
        when :audit_event then audit_event_action
        end
      end

      # The internal-notes rule (civora-org/civora-platform#128): any engine
      # role may read and add, no lifecycle condition. Only :read and
      # :create are answered; update/destroy stay unset (append-only).
      def note_action
        toggle_allow(roles_for_user.any?) if %i[read create].include?(action)
      end

      # The audit-trail read rule (civora-org/civora-platform#92): any
      # engine role, no record, no lifecycle condition — identical to the
      # contracts index's :read. Only :read is answered; every other
      # action on the subject stays unset (fail-closed), and the trail has
      # no write surface anywhere.
      def audit_event_action
        toggle_allow(roles_for_user.any?) if action == :read
      end

      def contract_action
        case action
        # :create, :download_crz_handoff (M02-05-C,
        # civora-org/civora-platform#74) and :import_crz (ADR-008,
        # civora-org/civora-platform#86) share the role-only rule: editor
        # membership decides, no lifecycle state is consulted.
        when :create, :download_crz_handoff, :import_crz, :import_file
          toggle_allow(roles_for_user.include?(:editor))
        # :update and :confirm_redaction (ADR-007,
        # civora-org/civora-platform#91) share the editor-role rule but
        # consult different lifecycle windows (see #action_state_window):
        # the stamp may still land on an approved record right before
        # publish, while editability itself is never widened.
        when :update, :confirm_redaction, :confirm_crz_filing
          toggle_allow(contract_write_allowed?)
        when :read
          toggle_allow(roles_for_user.any?)
        when *TRANSITION_EVENTS
          toggle_allow(transition_roles.any? && !self_review_blocked?)
        end
      end

      # The four-eyes rule at request admission (civora-org/civora-platform
      # #123): the judgment events (return, approve, reject) are denied to
      # the person recorded as the contract's submitter, unless the host
      # enabled allow_self_review. Needs the record (context[:contract]);
      # a context carrying only :state has no submitter to compare, so it
      # is unaffected. The predicate is single-sourced in
      # Decidim::ContractsSk.self_review_blocked?; TransitionContract
      # re-checks it inside the row lock.
      def self_review_blocked?
        Decidim::ContractsSk.self_review_blocked?(context[:contract], user, action)
      end

      # The shared rule for the contract-scoped child-record subjects
      # (:party, civora-org/civora-platform#76; :document, M02-05-A0,
      # civora-org/civora-platform#73; :link, civora-org/civora-platform
      # #87): writing is editorial work, so the editor-role-plus-editable-
      # state rule is identical for all of them.
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
        when :create then toggle_allow(amendment_create_allowed?)
        when :update, :destroy then toggle_allow(amendment_edit_allowed?)
        when :publish then toggle_allow(amendment_publish_allowed?)
        when :read then toggle_allow(roles_for_user.any?)
        end
      end

      def amendment_create_allowed?
        editor? && contract_published?
      end

      # The shared gate behind :update and :confirm_redaction: the editor
      # role plus the action's lifecycle window (see #action_state_window).
      def contract_write_allowed?
        return editor? && crz_filing_allowed? if action == :confirm_crz_filing

        editor? && action_state_window.include?(state)
      end

      # The lifecycle window behind the two write-ish contract actions:
      # :update keeps the strict editable set; :confirm_redaction (ADR-007,
      # civora-org/civora-platform#91) is admittable on the wider
      # confirmable window — the editable states plus :approved, so a
      # reviewer-approved record can still be stamped right before publish.
      # Editability itself is never widened.
      def action_state_window
        if action == :update
          ContractLifecycle::EDITABLE_STATES
        else
          ContractLifecycle::CONFIRMABLE_STATES
        end
      end

      # The CRZ filing confirmation window (civora-org/civora-platform#125):
      # an editorial, published, not-yet-filed record. Needs the record
      # itself — the filed flag and the source are not derivable from a bare
      # state, so a context without :contract denies.
      def crz_filing_allowed?
        record = context[:contract]
        return false unless record

        record.source.to_s != CrzImport::Mapper::SOURCE && state == :published && record.crz_filed_at.blank?
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
    # rubocop:enable Metrics/ClassLength
  end
end
