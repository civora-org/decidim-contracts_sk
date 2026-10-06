# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, class-level specs for the engine's permissions
# class (M02-01-B, civora-org/civora-platform#54).
#
# Classes come from the Stage-1 dummy harness (spec/dummy): the engine's
# Permissions class is provided by the dummy's autoloader, and the pinned
# gem's Decidim::PermissionAction / Decidim::DefaultPermissions are required
# by the dummy boot.
#
# Fail-closed semantics asserted here follow the REAL pinned-gem classes:
# a permission action left UNSET raises PermissionNotSetError on #allowed?
# (Decidim's NeedsPermission#allowed_to? rescues it to false), while an
# action explicitly disallowed answers #allowed? with false.
#
# The exhaustive matrix example walks the full state x event x role grid on
# both state sources, so it intentionally holds many expectations and
# exceeds the default example-length budget.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

# Minimal stand-in for a Decidim user, carrying only what resolvers consult:
# the default resolver reads admin?/admin_terms_accepted?, host-style custom
# resolvers may read engine_roles.
SpecUser = Struct.new(:admin, :admin_terms_accepted, :engine_roles, keyword_init: true) do
  def admin?
    admin
  end

  def admin_terms_accepted?
    admin_terms_accepted
  end
end

# Minimal stand-in for the Contract model (#55): a duck-typed state
# holder exercised via context[:contract].
SpecContract = Struct.new(:state)

# Filing-confirmation stand-in (civora-org/civora-platform#125): the
# :confirm_crz_filing rule reads the record's state, source and filed flag.
FilingContract = Struct.new(:state, :source, :crz_filed_at)

# Four-eyes stand-ins (civora-org/civora-platform#123): a user carrying an id
# (the rule compares it with the record's submitter stamp) and a contract
# carrying that stamp. Both stay duck-typed, DB-free.
FourEyesUser = Struct.new(:id, :admin, :admin_terms_accepted, keyword_init: true) do
  def admin?
    admin
  end

  def admin_terms_accepted?
    admin_terms_accepted
  end
end
FourEyesContract = Struct.new(:state, :decidim_submitted_by_id)

# Minimal stand-in for the Amendment model (#65): a duck-typed state
# holder exercised via context[:amendment].
SpecAmendment = Struct.new(:state)

RSpec.describe Decidim::ContractsSk::Permissions do
  let(:lifecycle) { Decidim::ContractsSk::ContractLifecycle }
  let(:org_admin) { SpecUser.new(admin: true, admin_terms_accepted: true) }
  let(:org_admin_unaccepted) { SpecUser.new(admin: true, admin_terms_accepted: false) }
  let(:plain_user) { SpecUser.new(admin: false, admin_terms_accepted: true) }

  # Runs the engine's permissions class the way Decidim's chain does and
  # returns the (mutated) permission action for #allowed? / raise assertions.
  # The named parameters mirror Decidim's vocabulary (user, scope, action,
  # subject, state sources — the amendment's own state sources included,
  # #65) and keep every call site self-describing.
  # rubocop:disable Metrics/ParameterLists
  def action_for(user, scope:, action:, state: nil, contract: nil, amendment: nil, amendment_state: nil,
                 action_subject: :contract)
    context = {}
    context[:state] = state if state
    context[:contract] = contract if contract
    context[:amendment] = amendment if amendment
    context[:amendment_state] = amendment_state if amendment_state
    permission_action = Decidim::PermissionAction.new(scope: scope, action: action, subject: action_subject)
    described_class.new(user, permission_action, context).permissions
  end
  # rubocop:enable Metrics/ParameterLists

  # True when the class leaves the action UNSET: #allowed? then raises
  # PermissionNotSetError (which Decidim's allowed_to? rescues to false).
  def unset?(user, **checks)
    action_for(user, **checks).allowed?
    false
  rescue Decidim::PermissionAction::PermissionNotSetError
    true
  end

  def resolver_of(roles)
    ->(_user, _context) { roles }
  end

  # Swaps the config seam for the duration of the block, restoring the
  # ambient resolver afterwards (config-time-only seam: tests restore it).
  def swap_resolver(resolver)
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = resolver.respond_to?(:call) ? resolver : resolver_of(resolver)
    yield
  ensure
    Decidim::ContractsSk.role_resolver = original
  end

  describe "transition event vocabulary" do
    it "derives TRANSITION_EVENTS from the lifecycle table, never hand-enumerated" do
      table_events = lifecycle::TRANSITIONS.values.flat_map(&:keys).uniq.sort

      expect(described_class::TRANSITION_EVENTS).to eq(table_events)
      expect(described_class::TRANSITION_EVENTS)
        .to eq(%i[approve archive publish reject return submit])
    end
  end

  describe "default role_resolver" do
    it "grants every engine role to org admins with accepted admin terms" do
      expect(Decidim::ContractsSk.role_resolver.call(org_admin, {})).to eq(%i[editor reviewer])
    end

    it "grants nothing to org admins who have not accepted the admin terms" do
      expect(Decidim::ContractsSk.role_resolver.call(org_admin_unaccepted, {})).to eq([])
    end

    it "grants nothing to plain users or anonymous visitors" do
      expect(Decidim::ContractsSk.role_resolver.call(plain_user, {})).to eq([])
      expect(Decidim::ContractsSk.role_resolver.call(nil, {})).to eq([])
    end
  end

  describe "admin scope — exhaustive state x event x role matrix" do
    let(:role_sets) { [[], %i[editor], %i[reviewer], %i[editor reviewer], %i[admin]] }

    # Swap in an engine_roles-driven resolver for the matrix; restored after
    # each example so the ambient default resolver is never leaked.
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "allows exactly where the lifecycle table allows, on both state sources" do
      events = lifecycle::TRANSITIONS.values.flat_map(&:keys).uniq.sort

      lifecycle::STATES.product(events, role_sets).each do |state, event, roles|
        expected = (lifecycle.allowed_roles(from: state, event: event) & roles).any?
        user = SpecUser.new(engine_roles: roles)

        via_state = action_for(user, scope: :admin, action: event, state: state)
        via_contract = action_for(user, scope: :admin, action: event, contract: SpecContract.new(state))

        expect(via_state.allowed?).to eq(expected), "#{state} --#{event}--> #{roles.inspect} via context[:state]"
        expect(via_contract.allowed?).to eq(expected), "#{state} --#{event}--> #{roles.inspect} via context[:contract]"
      end
    end
  end

  describe "admin scope — create (transition-table row 1 analog)" do
    it "is allowed for org admins, who hold :editor by default" do
      expect(action_for(org_admin, scope: :admin, action: :create).allowed?).to be(true)
    end

    it "is denied when the resolver yields no :editor" do
      swap_resolver(%i[reviewer]) do
        expect(action_for(plain_user, scope: :admin, action: :create).allowed?).to be(false)
      end
    end
  end

  describe "admin scope — update (editorial twin of the lifecycle editability rule)" do
    # Plain-method helper (not a let) so the group stays within the
    # memoized-helpers budget while every example names its user explicitly.
    def user_with_roles(*roles)
      SpecUser.new(engine_roles: roles)
    end

    # The group's users carry engine_roles, so swap in the engine_roles-driven
    # resolver for the duration of each example (restored afterwards).
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "is allowed for an editor exactly on the editable states, on both state sources" do
      lifecycle::EDITABLE_STATES.each do |state|
        via_state = action_for(user_with_roles(:editor), scope: :admin, action: :update, state: state)
        via_contract = action_for(user_with_roles(:editor), scope: :admin, action: :update,
                                                            contract: SpecContract.new(state))

        expect(via_state.allowed?).to be(true), "editor must update #{state}"
        expect(via_contract.allowed?).to be(true), "editor must update #{state} via context[:contract]"
      end
    end

    it "is denied for an editor on every non-editable state" do
      (lifecycle::STATES - lifecycle::EDITABLE_STATES).each do |state|
        via_state = action_for(user_with_roles(:editor), scope: :admin, action: :update, state: state)
        via_contract = action_for(user_with_roles(:editor), scope: :admin, action: :update,
                                                            contract: SpecContract.new(state))

        expect(via_state.allowed?).to be(false), "editor must not update #{state}"
        expect(via_contract.allowed?).to be(false), "editor must not update #{state} via context[:contract]"
      end
    end

    it "is denied for a reviewer even on editable states" do
      lifecycle::EDITABLE_STATES.each do |state|
        via_state = action_for(user_with_roles(:reviewer), scope: :admin, action: :update, state: state)
        via_contract = action_for(user_with_roles(:reviewer), scope: :admin, action: :update,
                                                              contract: SpecContract.new(state))

        expect(via_state.allowed?).to be(false), "reviewer must not update #{state}"
        expect(via_contract.allowed?).to be(false), "reviewer must not update #{state} via context[:contract]"
      end
    end

    it "is disallowed (not unset) when no state is reachable — fail-closed" do
      expect(action_for(user_with_roles(:editor), scope: :admin, action: :update).allowed?).to be(false)
      expect(unset?(user_with_roles(:editor), scope: :admin, action: :update)).to be(false)
    end

    it "is denied for org admins without accepted terms on editable states" do
      swap_resolver([]) do
        lifecycle::EDITABLE_STATES.each do |state|
          expect(action_for(org_admin_unaccepted, scope: :admin, action: :update, state: state).allowed?)
            .to be(false), "unaccepted admin must not update #{state}"
        end
      end
    end

    it "treats String states (Rails enum getters) identically to Symbols" do
      lifecycle::STATES.each do |state|
        expected = lifecycle::EDITABLE_STATES.include?(state)

        via_state = action_for(user_with_roles(:editor), scope: :admin, action: :update, state: state.to_s)
        via_contract = action_for(user_with_roles(:editor), scope: :admin, action: :update,
                                                            contract: SpecContract.new(state.to_s))

        expect(via_state.allowed?).to eq(expected), "String state diverged for :update on #{state}"
        expect(via_contract.allowed?).to eq(expected), "String state diverged for :update on #{state} (contract)"
      end
    end
  end

  describe "admin scope — confirm_crz_filing (civora-org/civora-platform#125)" do
    def filing_user_with_roles(*roles)
      SpecUser.new(engine_roles: roles)
    end

    def filing_action(user, contract)
      action_for(user, scope: :admin, action: :confirm_crz_filing, contract: contract)
    end

    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "is allowed for an editor on a published, unfiled editorial record (String or Symbol state)" do
      [:published, "published"].each do |state|
        expect(filing_action(filing_user_with_roles(:editor), FilingContract.new(state, "editorial", nil)).allowed?)
          .to be(true)
      end
    end

    it "is denied on every other lifecycle state" do
      (lifecycle::STATES - [:published]).each do |state|
        outcome = filing_action(filing_user_with_roles(:editor), FilingContract.new(state, "editorial", nil))

        expect(outcome.allowed?).to be(false), "must not allow filing on #{state}"
      end
    end

    it "is denied for a record already confirmed as filed and for a CRZ mirror" do
      editor = filing_user_with_roles(:editor)

      expect(filing_action(editor, FilingContract.new(:published, "editorial", Time.current)).allowed?).to be(false)
      expect(filing_action(editor, FilingContract.new(:published, "crz", nil)).allowed?).to be(false)
    end

    it "is denied for a reviewer and for a roleless user" do
      record = FilingContract.new(:published, "editorial", nil)

      expect(filing_action(filing_user_with_roles(:reviewer), record).allowed?).to be(false)
      expect(filing_action(filing_user_with_roles, record).allowed?).to be(false)
    end

    it "is disallowed (not unset) without a record — a bare state cannot prove source or filed flag" do
      outcome = action_for(filing_user_with_roles(:editor), scope: :admin, action: :confirm_crz_filing,
                                                            state: :published)

      expect(outcome.allowed?).to be(false)
    end

    it "leaves the public-scope action unset (fail-closed)" do
      expect(unset?(filing_user_with_roles(:editor), scope: :public, action: :confirm_crz_filing,
                                                     contract: FilingContract.new(:published, "editorial", nil)))
        .to be(true)
    end
  end

  describe "admin scope — confirm_redaction (ADR-007, civora-org/civora-platform#91: :update's twin)" do
    # Plain-method helper (not a let) so the group stays within the
    # memoized-helpers budget while every example names its user explicitly.
    def redaction_user_with_roles(*roles)
      SpecUser.new(engine_roles: roles)
    end

    # The group's users carry engine_roles, so swap in the engine_roles-driven
    # resolver for the duration of each example (restored afterwards).
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "is allowed for an editor exactly on the confirmable states, on both state sources" do
      # ADR-007 review round (#91 H-1): the window is CONFIRMABLE_STATES —
      # the editable states plus approved — not editability itself.
      lifecycle::CONFIRMABLE_STATES.each do |state|
        via_state = action_for(redaction_user_with_roles(:editor), scope: :admin, action: :confirm_redaction,
                                                                   state: state)
        via_contract = action_for(redaction_user_with_roles(:editor), scope: :admin, action: :confirm_redaction,
                                                                      contract: SpecContract.new(state))

        expect(via_state.allowed?).to be(true), "editor must confirm redaction on #{state}"
        expect(via_contract.allowed?).to be(true), "editor must confirm redaction on #{state} via context[:contract]"
      end
    end

    it "is denied for an editor on every non-confirmable state" do
      (lifecycle::STATES - lifecycle::CONFIRMABLE_STATES).each do |state|
        via_state = action_for(redaction_user_with_roles(:editor), scope: :admin, action: :confirm_redaction,
                                                                   state: state)
        via_contract = action_for(redaction_user_with_roles(:editor), scope: :admin, action: :confirm_redaction,
                                                                      contract: SpecContract.new(state))

        expect(via_state.allowed?).to be(false), "editor must not confirm redaction on #{state}"
        expect(via_contract.allowed?).to be(false),
                                         "editor must not confirm redaction on #{state} via context[:contract]"
      end
    end

    it "keeps :update narrower than :confirm_redaction on approved (the window, not editability, widened)" do
      outcome = action_for(redaction_user_with_roles(:editor), scope: :admin, action: :update,
                                                               contract: SpecContract.new(:approved))

      expect(outcome.allowed?).to be(false), "approved must stay non-editable while remaining confirmable"
    end

    it "is denied for a reviewer even on confirmable states" do
      lifecycle::CONFIRMABLE_STATES.each do |state|
        outcome = action_for(redaction_user_with_roles(:reviewer), scope: :admin, action: :confirm_redaction,
                                                                   contract: SpecContract.new(state))

        expect(outcome.allowed?).to be(false), "reviewer must not confirm redaction on #{state}"
      end
    end

    it "is disallowed (not unset) when no state is reachable — fail-closed" do
      expect(action_for(redaction_user_with_roles(:editor), scope: :admin, action: :confirm_redaction).allowed?)
        .to be(false)
      expect(unset?(redaction_user_with_roles(:editor), scope: :admin, action: :confirm_redaction)).to be(false)
    end

    it "leaves the public-scope action unset (fail-closed; the catalogue has no redaction surface)" do
      expect(unset?(redaction_user_with_roles(:editor), scope: :public, action: :confirm_redaction,
                                                        state: :draft)).to be(true)
      expect(unset?(nil, scope: :public, action: :confirm_redaction, state: :published)).to be(true)
    end

    it "treats String states (Rails enum getters) identically to Symbols" do
      lifecycle::STATES.each do |state|
        expected = lifecycle::CONFIRMABLE_STATES.include?(state)

        outcome = action_for(redaction_user_with_roles(:editor), scope: :admin, action: :confirm_redaction,
                                                                 contract: SpecContract.new(state.to_s))

        expect(outcome.allowed?).to eq(expected), "String state diverged for :confirm_redaction on #{state}"
      end
    end
  end

  describe "admin scope — download_crz_handoff (M02-05-C split: editor-only, any state)" do
    # Plain-method helper (not a let) so the group stays within the
    # memoized-helpers budget while every example names its user explicitly.
    def user_with_roles(*roles)
      SpecUser.new(engine_roles: roles)
    end

    # The group's users carry engine_roles, so swap in the engine_roles-driven
    # resolver for the duration of each example (restored afterwards).
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "is allowed for an editor on every lifecycle state (no editability condition)" do
      lifecycle::STATES.each do |state|
        via_state = action_for(user_with_roles(:editor), scope: :admin, action: :download_crz_handoff,
                                                         state: state)
        via_contract = action_for(user_with_roles(:editor), scope: :admin, action: :download_crz_handoff,
                                                            contract: SpecContract.new(state))

        expect(via_state.allowed?).to be(true), "editor must download the handoff on #{state}"
        expect(via_contract.allowed?).to be(true), "editor must download the handoff on #{state} via context[:contract]"
      end
    end

    it "is allowed for an editor even with no state reachable (the gate is role-only)" do
      expect(action_for(user_with_roles(:editor), scope: :admin, action: :download_crz_handoff).allowed?).to be(true)
    end

    it "is denied for a reviewer on every state (non-editors never hold the gate)" do
      lifecycle::STATES.each do |state|
        outcome = action_for(user_with_roles(:reviewer), scope: :admin, action: :download_crz_handoff,
                                                         contract: SpecContract.new(state))

        expect(outcome.allowed?).to be(false), "reviewer must not download the handoff on #{state}"
      end
    end

    it "is denied for a roleless user and disallowed (not unset) — fail-closed" do
      outcome = action_for(user_with_roles, scope: :admin, action: :download_crz_handoff, state: :draft)

      expect(outcome.allowed?).to be(false)
      expect(unset?(user_with_roles, scope: :admin, action: :download_crz_handoff, state: :draft)).to be(false)
    end
  end

  describe "admin scope — import_crz (ADR-008, civora-org/civora-platform#86: editor-only, any state)" do
    # Plain-method helper (not a let) so the group stays within the
    # memoized-helpers budget while every example names its user explicitly.
    def import_user_with_roles(*roles)
      SpecUser.new(engine_roles: roles)
    end

    # The group's users carry engine_roles, so swap in the engine_roles-driven
    # resolver for the duration of each example (restored afterwards).
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "is allowed for an editor on every lifecycle state (the gate is role-only)" do
      lifecycle::STATES.each do |state|
        via_state = action_for(import_user_with_roles(:editor), scope: :admin, action: :import_crz,
                                                                state: state)
        via_contract = action_for(import_user_with_roles(:editor), scope: :admin, action: :import_crz,
                                                                   contract: SpecContract.new(state))

        expect(via_state.allowed?).to be(true), "editor must import on #{state}"
        expect(via_contract.allowed?).to be(true), "editor must import on #{state} via context[:contract]"
      end
    end

    it "is allowed for an editor even with no state reachable (the gate is role-only)" do
      expect(action_for(import_user_with_roles(:editor), scope: :admin, action: :import_crz).allowed?).to be(true)
    end

    it "is denied for a reviewer on every state (non-editors never hold the gate)" do
      lifecycle::STATES.each do |state|
        outcome = action_for(import_user_with_roles(:reviewer), scope: :admin, action: :import_crz,
                                                                contract: SpecContract.new(state))

        expect(outcome.allowed?).to be(false), "reviewer must not import on #{state}"
      end
    end

    it "is denied for a roleless user and disallowed (not unset) — fail-closed" do
      outcome = action_for(import_user_with_roles, scope: :admin, action: :import_crz, state: :draft)

      expect(outcome.allowed?).to be(false)
      expect(unset?(import_user_with_roles, scope: :admin, action: :import_crz, state: :draft)).to be(false)
    end
  end

  describe "admin scope — read (admin index)" do
    it "is allowed when the user holds any engine role" do
      swap_resolver(%i[reviewer]) do
        expect(action_for(plain_user, scope: :admin, action: :read, state: :draft).allowed?).to be(true)
      end
    end

    it "is denied when the user holds no engine role" do
      expect(action_for(org_admin_unaccepted, scope: :admin, action: :read, state: :draft).allowed?).to be(false)
    end
  end

  describe "admin scope — party (contract-scoped child records, civora-org/civora-platform#76)" do
    # The party actions the writing gate covers (see the Permissions class
    # comment). A plain method, not a block-level constant — the constants
    # this file owns live at the top level.
    def party_actions
      %i[create update destroy]
    end

    # Party decisions hang off the PARENT contract passed in
    # context[:contract]; the same engine_roles-driven resolver swap as the
    # sibling groups applies (restored after each example).
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "allows an editor exactly on the editable parent states, for every writing action" do
      lifecycle::EDITABLE_STATES.each do |state|
        party_actions.each do |party_action|
          outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                       action: party_action,
                                                                       contract: SpecContract.new(state),
                                                                       action_subject: :party)

          expect(outcome.allowed?).to be(true), "editor must #{party_action} a party on #{state}"
        end
      end
    end

    it "denies an editor on every non-editable parent state" do
      (lifecycle::STATES - lifecycle::EDITABLE_STATES).each do |state|
        party_actions.each do |party_action|
          outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                       action: party_action,
                                                                       contract: SpecContract.new(state),
                                                                       action_subject: :party)

          expect(outcome.allowed?).to be(false), "editor must not #{party_action} a party on #{state}"
        end
      end
    end

    it "denies a reviewer even on editable parent states (reviewers never draft)" do
      lifecycle::EDITABLE_STATES.each do |state|
        party_actions.each do |party_action|
          outcome = action_for(SpecUser.new(engine_roles: %i[reviewer]), scope: :admin,
                                                                         action: party_action,
                                                                         contract: SpecContract.new(state),
                                                                         action_subject: :party)

          expect(outcome.allowed?).to be(false), "reviewer must not #{party_action} a party on #{state}"
        end
      end
    end

    it "answers party :read like the contract's :read: any engine role, any parent state" do
      %i[draft published].each do |state|
        editor = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: :read,
                                                                    contract: SpecContract.new(state),
                                                                    action_subject: :party)
        reviewer = action_for(SpecUser.new(engine_roles: %i[reviewer]), scope: :admin, action: :read,
                                                                        contract: SpecContract.new(state),
                                                                        action_subject: :party)

        expect(editor.allowed?).to be(true), "editor must read parties on #{state}"
        expect(reviewer.allowed?).to be(true), "reviewer must read parties on #{state}"
      end
    end

    it "denies party :read for a roleless user" do
      outcome = action_for(SpecUser.new(engine_roles: []), scope: :admin, action: :read,
                                                           contract: SpecContract.new(:draft),
                                                           action_subject: :party)

      expect(outcome.allowed?).to be(false)
    end

    it "disallows (not unset) party writes when no contract state is reachable — fail-closed" do
      party_actions.each do |party_action|
        outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                     action: party_action,
                                                                     action_subject: :party)

        expect(outcome.allowed?).to be(false)
        expect(unset?(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: party_action,
                                                              action_subject: :party)).to be(false)
      end
    end

    it "treats String states (Rails enum getters) identically to Symbols" do
      lifecycle::STATES.each do |state|
        expected = lifecycle::EDITABLE_STATES.include?(state)

        outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: :update,
                                                                     contract: SpecContract.new(state.to_s),
                                                                     action_subject: :party)

        expect(outcome.allowed?).to eq(expected), "String state diverged for party :update on #{state}"
      end
    end
  end

  describe "admin scope — document (contract-scoped child records, civora-org/civora-platform#73)" do
    # The document actions the writing gate covers: create (attach), update
    # (replace — the PATCH/PUT route maps onto :update) and destroy. A plain
    # method, not a block-level constant — the constants this file owns live
    # at the top level.
    def document_actions
      %i[create update destroy]
    end

    # Document decisions hang off the PARENT contract passed in
    # context[:contract]; the same engine_roles-driven resolver swap as the
    # sibling groups applies (restored after each example).
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "allows an editor exactly on the editable parent states, for every writing action" do
      lifecycle::EDITABLE_STATES.each do |state|
        document_actions.each do |document_action|
          outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                       action: document_action,
                                                                       contract: SpecContract.new(state),
                                                                       action_subject: :document)

          expect(outcome.allowed?).to be(true), "editor must #{document_action} a document on #{state}"
        end
      end
    end

    it "denies an editor on every non-editable parent state" do
      (lifecycle::STATES - lifecycle::EDITABLE_STATES).each do |state|
        document_actions.each do |document_action|
          outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                       action: document_action,
                                                                       contract: SpecContract.new(state),
                                                                       action_subject: :document)

          expect(outcome.allowed?).to be(false), "editor must not #{document_action} a document on #{state}"
        end
      end
    end

    it "denies a reviewer even on editable parent states (reviewers never draft)" do
      lifecycle::EDITABLE_STATES.each do |state|
        document_actions.each do |document_action|
          outcome = action_for(SpecUser.new(engine_roles: %i[reviewer]), scope: :admin,
                                                                         action: document_action,
                                                                         contract: SpecContract.new(state),
                                                                         action_subject: :document)

          expect(outcome.allowed?).to be(false), "reviewer must not #{document_action} a document on #{state}"
        end
      end
    end

    it "answers document :read like the contract's :read: any engine role, any parent state" do
      %i[draft published].each do |state|
        editor = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: :read,
                                                                    contract: SpecContract.new(state),
                                                                    action_subject: :document)
        reviewer = action_for(SpecUser.new(engine_roles: %i[reviewer]), scope: :admin, action: :read,
                                                                        contract: SpecContract.new(state),
                                                                        action_subject: :document)

        expect(editor.allowed?).to be(true), "editor must read documents on #{state}"
        expect(reviewer.allowed?).to be(true), "reviewer must read documents on #{state}"
      end
    end

    it "denies document :read for a roleless user" do
      outcome = action_for(SpecUser.new(engine_roles: []), scope: :admin, action: :read,
                                                           contract: SpecContract.new(:draft),
                                                           action_subject: :document)

      expect(outcome.allowed?).to be(false)
    end

    it "disallows (not unset) document writes when no contract state is reachable — fail-closed" do
      document_actions.each do |document_action|
        outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                     action: document_action,
                                                                     action_subject: :document)

        expect(outcome.allowed?).to be(false)
        expect(unset?(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: document_action,
                                                              action_subject: :document)).to be(false)
      end
    end

    it "treats String states (Rails enum getters) identically to Symbols" do
      lifecycle::STATES.each do |state|
        expected = lifecycle::EDITABLE_STATES.include?(state)

        outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: :update,
                                                                     contract: SpecContract.new(state.to_s),
                                                                     action_subject: :document)

        expect(outcome.allowed?).to eq(expected), "String state diverged for document :update on #{state}"
      end
    end
  end

  describe "admin scope — link (contract-scoped child records, civora-org/civora-platform#87)" do
    # The link actions the writing gate covers: create and destroy — links
    # have no editable content, so the routes expose no update. :read stays
    # declared on the shared rule for symmetry. A plain method, not a
    # block-level constant — the constants this file owns live at the top
    # level.
    def link_actions
      %i[create destroy]
    end

    # Link decisions hang off the PARENT contract passed in
    # context[:contract]; the same engine_roles-driven resolver swap as the
    # sibling groups applies (restored after each example).
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "allows an editor exactly on the editable parent states, for every writing action" do
      lifecycle::EDITABLE_STATES.each do |state|
        link_actions.each do |link_action|
          outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                       action: link_action,
                                                                       contract: SpecContract.new(state),
                                                                       action_subject: :link)

          expect(outcome.allowed?).to be(true), "editor must #{link_action} a link on #{state}"
        end
      end
    end

    it "denies an editor on every non-editable parent state" do
      (lifecycle::STATES - lifecycle::EDITABLE_STATES).each do |state|
        link_actions.each do |link_action|
          outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                       action: link_action,
                                                                       contract: SpecContract.new(state),
                                                                       action_subject: :link)

          expect(outcome.allowed?).to be(false), "editor must not #{link_action} a link on #{state}"
        end
      end
    end

    it "denies a reviewer even on editable parent states (reviewers never draft)" do
      lifecycle::EDITABLE_STATES.each do |state|
        link_actions.each do |link_action|
          outcome = action_for(SpecUser.new(engine_roles: %i[reviewer]), scope: :admin,
                                                                         action: link_action,
                                                                         contract: SpecContract.new(state),
                                                                         action_subject: :link)

          expect(outcome.allowed?).to be(false), "reviewer must not #{link_action} a link on #{state}"
        end
      end
    end

    it "answers link :read like the contract's :read: any engine role, any parent state" do
      %i[draft published].each do |state|
        editor = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: :read,
                                                                    contract: SpecContract.new(state),
                                                                    action_subject: :link)
        reviewer = action_for(SpecUser.new(engine_roles: %i[reviewer]), scope: :admin, action: :read,
                                                                        contract: SpecContract.new(state),
                                                                        action_subject: :link)

        expect(editor.allowed?).to be(true), "editor must read links on #{state}"
        expect(reviewer.allowed?).to be(true), "reviewer must read links on #{state}"
      end
    end

    it "denies link :read for a roleless user" do
      outcome = action_for(SpecUser.new(engine_roles: []), scope: :admin, action: :read,
                                                           contract: SpecContract.new(:draft),
                                                           action_subject: :link)

      expect(outcome.allowed?).to be(false)
    end

    it "disallows (not unset) link writes when no contract state is reachable — fail-closed" do
      link_actions.each do |link_action|
        outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                     action: link_action,
                                                                     action_subject: :link)

        expect(outcome.allowed?).to be(false)
        expect(unset?(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: link_action,
                                                              action_subject: :link)).to be(false)
      end
    end

    it "treats String states (Rails enum getters) identically to Symbols" do
      lifecycle::STATES.each do |state|
        expected = lifecycle::EDITABLE_STATES.include?(state)

        outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: :create,
                                                                     contract: SpecContract.new(state.to_s),
                                                                     action_subject: :link)

        expect(outcome.allowed?).to eq(expected), "String state diverged for link :create on #{state}"
      end
    end

    it "leaves public-scope link actions unset (the catalogue has no per-link permission)" do
      expect(unset?(nil, scope: :public, action: :read, state: :published, action_subject: :link)).to be(true)
      expect(unset?(org_admin, scope: :public, action: :destroy, state: :draft, action_subject: :link)).to be(true)
    end
  end

  describe "admin scope — note (internal review notes, civora-org/civora-platform#128)" do
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    def note_outcome(roles, action, state)
      action_for(SpecUser.new(engine_roles: roles), scope: :admin, action: action,
                                                    contract: SpecContract.new(state), action_subject: :note)
    end

    it "allows :read and :create for any engine role on every lifecycle state" do
      lifecycle::STATES.each do |state|
        %i[read create].each do |action|
          %i[editor reviewer].each do |role|
            expect(note_outcome([role], action, state).allowed?).to be(true), "#{role} must #{action} notes on #{state}"
          end
        end
      end
    end

    it "denies :read and :create for a roleless user" do
      %i[read create].each do |action|
        expect(note_outcome([], action, :draft).allowed?).to be(false), "roleless must not #{action} notes"
      end
    end

    it "never answers :update or :destroy (append-only): left unset, so denied fail-closed for every role" do
      %i[update destroy].each do |action|
        %i[editor reviewer].each do |role|
          outcome = note_outcome([role], action, :draft)

          expect { outcome.allowed? }.to raise_error(Decidim::PermissionAction::PermissionNotSetError),
                                         "#{role} #{action} on a note must stay unset"
        end
      end
    end

    it "is not answered in the public scope (notes are never public)" do
      outcome = action_for(SpecUser.new(engine_roles: %i[editor reviewer]), scope: :public, action: :read,
                                                                            contract: SpecContract.new(:published),
                                                                            action_subject: :note)

      expect { outcome.allowed? }.to raise_error(Decidim::PermissionAction::PermissionNotSetError)
    end
  end

  describe "admin scope — amendment (M02-05-B, civora-org/civora-platform#65)" do
    # Amendment decisions read BOTH state sources: the parent contract's
    # lifecycle state (context[:contract]) and the amendment's own draft
    # state (context[:amendment]); the same engine_roles-driven resolver
    # swap as the sibling groups applies (restored after each example).
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "allows an editor to create exactly on a published parent contract" do
      lifecycle::STATES.each do |state|
        outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: :create,
                                                                     contract: SpecContract.new(state),
                                                                     amendment_state: :draft,
                                                                     action_subject: :amendment)

        expect(outcome.allowed?).to eq(state == :published), "editor create on #{state} must be #{state == :published}"
      end
    end

    it "allows an editor to update and destroy exactly while the amendment is a draft" do
      %i[update destroy].each do |amendment_action|
        lifecycle::STATES.each do |state|
          draft = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: amendment_action,
                                                                     contract: SpecContract.new(state),
                                                                     amendment_state: :draft,
                                                                     action_subject: :amendment)

          # Draft-only, regardless of the contract's own state (ADR-006):
          # a published amendment stays immutable whatever the record does.
          expect(draft.allowed?).to be(true), "editor must #{amendment_action} a draft on #{state}"
        end

        published = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin,
                                                                       action: amendment_action,
                                                                       contract: SpecContract.new(:published),
                                                                       amendment_state: :published,
                                                                       action_subject: :amendment)

        expect(published.allowed?).to be(false), "editor must not #{amendment_action} a published amendment"
      end
    end

    it "allows an editor to publish exactly a draft on a published contract" do
      lifecycle::STATES.each do |state|
        %i[draft published].each do |amendment_state|
          expected = state == :published && amendment_state == :draft
          outcome = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: :publish,
                                                                       contract: SpecContract.new(state),
                                                                       amendment_state: amendment_state,
                                                                       action_subject: :amendment)

          expect(outcome.allowed?).to eq(expected),
                                      "publish #{amendment_state} on #{state} must be #{expected}"
        end
      end
    end

    it "denies a reviewer on every amendment writing action (read is role-any)" do
      %i[create update destroy publish].each do |amendment_action|
        outcome = action_for(SpecUser.new(engine_roles: %i[reviewer]), scope: :admin,
                                                                       action: amendment_action,
                                                                       contract: SpecContract.new(:published),
                                                                       amendment_state: :draft,
                                                                       action_subject: :amendment)

        expect(outcome.allowed?).to be(false), "reviewer must not #{amendment_action} an amendment"
      end
    end

    it "answers amendment :read like the contract's :read: any engine role, any state pair" do
      %i[draft published].each do |state|
        %i[draft published].each do |amendment_state|
          editor = action_for(SpecUser.new(engine_roles: %i[editor]), scope: :admin, action: :read,
                                                                      contract: SpecContract.new(state),
                                                                      amendment_state: amendment_state,
                                                                      action_subject: :amendment)
          reviewer = action_for(SpecUser.new(engine_roles: %i[reviewer]), scope: :admin, action: :read,
                                                                          contract: SpecContract.new(state),
                                                                          amendment_state: amendment_state,
                                                                          action_subject: :amendment)

          expect(editor.allowed?).to be(true), "editor must read amendments on #{state}/#{amendment_state}"
          expect(reviewer.allowed?).to be(true), "reviewer must read amendments on #{state}/#{amendment_state}"
        end
      end
    end

    it "denies amendment :read for a roleless user" do
      outcome = action_for(SpecUser.new(engine_roles: []), scope: :admin, action: :read,
                                                           contract: SpecContract.new(:published),
                                                           amendment_state: :draft,
                                                           action_subject: :amendment)

      expect(outcome.allowed?).to be(false)
    end

    it "fails closed when a needed state source is missing (disallowed, not unset)" do
      editor = SpecUser.new(engine_roles: %i[editor])

      # :create needs the CONTRACT's state (published gate); :update,
      # :destroy and :publish additionally need the amendment's own state.
      # Each gate must DENY when its source is missing, never crash unset.
      no_contract = action_for(editor, scope: :admin, action: :create, action_subject: :amendment)

      expect(no_contract.allowed?).to be(false), "create must fail closed without the contract state"
      expect(unset?(editor, scope: :admin, action: :create, action_subject: :amendment)).to be(false)

      aggregate_failures do
        %i[update destroy publish].each do |amendment_action|
          outcome = action_for(editor, scope: :admin, action: amendment_action,
                                       contract: SpecContract.new(:published),
                                       action_subject: :amendment)

          expect(outcome.allowed?).to be(false), "#{amendment_action} must fail closed without the amendment state"
          expect(unset?(editor, scope: :admin, action: amendment_action,
                                contract: SpecContract.new(:published),
                                action_subject: :amendment)).to be(false)
        end
      end
    end

    it "treats String states (Rails enum getters) identically to Symbols" do
      editor = SpecUser.new(engine_roles: %i[editor])

      lifecycle::STATES.each do |state|
        create_outcome = action_for(editor, scope: :admin, action: :create,
                                            contract: SpecContract.new(state.to_s),
                                            amendment_state: "draft",
                                            action_subject: :amendment)

        expect(create_outcome.allowed?).to eq(state == :published), "String state diverged for create on #{state}"
      end

      aggregate_failures do
        %i[update destroy publish].each do |amendment_action|
          string_outcome = action_for(editor, scope: :admin, action: amendment_action,
                                              contract: SpecContract.new("published"),
                                              amendment_state: "draft",
                                              action_subject: :amendment)

          expect(string_outcome.allowed?).to be(true), "String amendment state diverged for #{amendment_action}"
        end
      end
    end
  end

  describe "admin scope — audit_event (civora-org/civora-platform#92: read-only viewer)" do
    # Plain-method helper (not a let) so the group stays within the
    # memoized-helpers budget while every example names its user explicitly.
    def audit_user_with_roles(*roles)
      SpecUser.new(engine_roles: roles)
    end

    # The group's users carry engine_roles, so swap in the engine_roles-driven
    # resolver for the duration of each example (restored afterwards).
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "allows :read for every engine role (editor OR reviewer), no record needed" do
      %i[editor reviewer].each do |role|
        outcome = action_for(
          audit_user_with_roles(role),
          scope: :admin, action: :read, action_subject: :audit_event
        )

        expect(outcome.allowed?).to be(true), "#{role} must read the audit trail"
      end
    end

    it "allows :read with no state reachable (the gate is role-only, org-level)" do
      expect(action_for(audit_user_with_roles(:editor), scope: :admin, action: :read,
                                                        action_subject: :audit_event).allowed?).to be(true)
    end

    it "denies :read for a roleless user and is disallowed (not unset) — fail-closed" do
      outcome = action_for(audit_user_with_roles, scope: :admin, action: :read, action_subject: :audit_event)

      expect(outcome.allowed?).to be(false)
      expect(unset?(audit_user_with_roles, scope: :admin, action: :read, action_subject: :audit_event))
        .to be(false)
    end

    it "leaves write actions unset (the trail is append-only — no write surface exists)" do
      %i[create update destroy].each do |audit_action|
        # Only :read is answered; every other action on the subject is left
        # unset, which Decidim's allowed_to? rescues to false (fail-closed)
        # — nobody can write the trail through the permission layer.
        expect(unset?(audit_user_with_roles(:editor, :reviewer), scope: :admin, action: audit_action,
                                                                 action_subject: :audit_event)).to be(true)
      end
    end

    it "leaves public-scope audit_event actions unset (the trail is never publicly addressable)" do
      expect(unset?(audit_user_with_roles(:editor), scope: :public, action: :read,
                                                    action_subject: :audit_event)).to be(true)
      expect(unset?(nil, scope: :public, action: :read, action_subject: :audit_event)).to be(true)
    end
  end

  describe "org admin with accepted terms (default resolver)" do
    it "may trigger every edge in the transition table" do
      lifecycle::TRANSITIONS.each do |from, edges|
        edges.each_key do |event|
          expect(action_for(org_admin, scope: :admin, action: event, state: from).allowed?)
            .to be(true), "org admin denied #{from} --#{event}-->"
        end
      end
    end

    it "may not trigger non-edges of the table" do
      expect(action_for(org_admin, scope: :admin, action: :archive, state: :draft).allowed?).to be(false)
      expect(action_for(org_admin, scope: :admin, action: :submit, state: :rejected).allowed?).to be(false)
      expect(action_for(org_admin, scope: :admin, action: :publish, state: :in_review).allowed?).to be(false)
    end
  end

  describe "org admin without accepted terms (default resolver)" do
    it "holds no roles: every admin action is denied" do
      actions = %i[create read update confirm_redaction download_crz_handoff import_crz] +
                described_class::TRANSITION_EVENTS

      lifecycle::STATES.each do |state|
        actions.each do |action|
          expect(action_for(org_admin_unaccepted, scope: :admin, action: action, state: state).allowed?)
            .to be(false), "unaccepted admin must not #{action} on #{state}"
        end
      end
    end
  end

  describe "nil user" do
    it "is denied every admin action on a known state" do
      actions = %i[create read update confirm_redaction download_crz_handoff import_crz] +
                described_class::TRANSITION_EVENTS

      actions.each do |action|
        expect(action_for(nil, scope: :admin, action: action, state: :draft).allowed?)
          .to be(false), "nil user must not #{action}"
      end
    end

    it "gets public non-read actions left unset, same as any other user" do
      expect(unset?(nil, scope: :public, action: :submit, state: :published)).to be(true)
    end
  end

  describe "fail-closed semantics" do
    it "leaves subjects the engine does not own unset" do
      expect(unset?(org_admin, scope: :admin, action: :read, state: :draft, action_subject: :component)).to be(true)
      expect(unset?(org_admin, scope: :public, action: :read, state: :published, action_subject: :proposal)).to be(true)
    end

    it "leaves public-scope party actions unset (the catalogue does not render parties)" do
      expect(unset?(org_admin, scope: :public, action: :read, state: :published, action_subject: :party)).to be(true)
      expect(unset?(org_admin, scope: :public, action: :destroy, state: :draft, action_subject: :party)).to be(true)
    end

    it "leaves unknown events unset" do
      expect(unset?(org_admin, scope: :admin, action: :detonate, state: :draft)).to be(true)
    end

    it "leaves unknown scopes unset" do
      expect(unset?(org_admin, scope: :api, action: :read, state: :draft)).to be(true)
    end

    it "disallows (not unset) known events from unknown states" do
      expect(action_for(org_admin, scope: :admin, action: :submit, state: :bogus).allowed?).to be(false)
      expect(unset?(org_admin, scope: :admin, action: :submit, state: :bogus)).to be(false)
    end

    it "disallows known events when no state is reachable at all" do
      expect(action_for(org_admin, scope: :admin, action: :submit).allowed?).to be(false)
    end

    it "disallows public read for unknown or missing state" do
      expect(action_for(nil, scope: :public, action: :read, state: :bogus).allowed?).to be(false)
      expect(action_for(nil, scope: :public, action: :read).allowed?).to be(false)
    end
  end

  describe "public scope — read (leak guard)" do
    Decidim::ContractsSk::ContractLifecycle::STATES.each do |state|
      expected = Decidim::ContractsSk::ContractLifecycle::PUBLIC_STATES.include?(state)

      it "#{expected ? "allows" : "denies"} anonymous read on #{state}" do
        expect(action_for(nil, scope: :public, action: :read, state: state).allowed?).to be(expected)
      end
    end

    it "requires no user and no engine roles for published records" do
      expect(action_for(nil, scope: :public, action: :read, state: :published).allowed?).to be(true)
    end

    it "reads state duck-typed from context[:contract]" do
      published = SpecContract.new(:published)
      expect(action_for(nil, scope: :public, action: :read, contract: published).allowed?).to be(true)
      draft = SpecContract.new(:draft)
      expect(action_for(nil, scope: :public, action: :read, contract: draft).allowed?).to be(false)
    end

    it "falls back to context[:state] when the contract carries no state" do
      expect(action_for(nil, scope: :public, action: :read, contract: SpecContract.new(nil), state: :archived).allowed?)
        .to be(true)
    end

    it "leaves non-read public actions unset" do
      expect(unset?(nil, scope: :public, action: :create, state: :published)).to be(true)
    end
  end

  describe "String state inputs (Rails enum getters) behave exactly like Symbols" do
    # Regression guard (civora-org/civora-platform#55): Rails enum getters
    # return Strings while ContractLifecycle is keyed on Symbols; the
    # permissions layer normalizes at its state boundary, so both input
    # types must yield identical outcomes everywhere.
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "treats String states identically to Symbols across the full admin matrix" do
      events = lifecycle::TRANSITIONS.values.flat_map(&:keys).uniq.sort

      lifecycle::STATES.product(events).each do |state, event|
        user = SpecUser.new(engine_roles: lifecycle.allowed_roles(from: state, event: event))

        symbol_outcome = action_for(user, scope: :admin, action: event, state: state).allowed?
        string_outcome = action_for(user, scope: :admin, action: event, state: state.to_s).allowed?
        via_contract = action_for(user, scope: :admin, action: event, contract: SpecContract.new(state.to_s)).allowed?

        expect(string_outcome).to eq(symbol_outcome), "String state diverged: #{event} on #{state} (context[:state])"
        expect(via_contract).to eq(symbol_outcome), "String state diverged: #{event} on #{state} (context[:contract])"
      end
    end

    it "treats String states identically to Symbols for public read" do
      lifecycle::STATES.each do |state|
        expected = lifecycle.publicly_visible?(state)

        expect(action_for(nil, scope: :public, action: :read, state: state.to_s).allowed?)
          .to eq(expected), "public read diverged for #{state.to_s.inspect} via context[:state]"
        expect(action_for(nil, scope: :public, action: :read, contract: SpecContract.new(state.to_s)).allowed?)
          .to eq(expected), "public read diverged for #{state.to_s.inspect} via context[:contract]"
      end
    end
  end

  describe "custom role_resolver override (config seam)" do
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = resolver_of(%i[reviewer])
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "changes outcomes: a reviewer-only resolver may approve but not submit" do
      expect(action_for(plain_user, scope: :admin, action: :approve, state: :in_review).allowed?).to be(true)
      expect(action_for(plain_user, scope: :admin, action: :submit, state: :draft).allowed?).to be(false)
    end

    it "keeps foreign roles out of the outcome (defensive intersection)" do
      swap_resolver(%i[admin editor]) do
        expect(action_for(plain_user, scope: :admin, action: :submit, state: :draft).allowed?).to be(true)
        expect(action_for(plain_user, scope: :admin, action: :approve, state: :in_review).allowed?).to be(false)
      end
    end

    it "fails closed when the resolver returns nil" do
      swap_resolver(->(_user, _context) { nil }) do
        expect(action_for(org_admin, scope: :admin, action: :submit, state: :draft).allowed?).to be(false)
      end
    end

    it "accepts a bare symbol role from the resolver" do
      swap_resolver(->(_user, _context) { :editor }) do
        expect(action_for(org_admin, scope: :admin, action: :submit, state: :draft).allowed?).to be(true)
      end
    end
  end

  describe "four-eyes rule (civora-org/civora-platform#123)" do
    # Default resolver: an accepted org admin holds both engine roles, so
    # only the per-person rule can deny.
    def submitter
      FourEyesUser.new(id: 7, admin: true, admin_terms_accepted: true)
    end

    def other_admin
      FourEyesUser.new(id: 8, admin: true, admin_terms_accepted: true)
    end

    def in_review
      FourEyesContract.new("in_review", 7)
    end

    after { Decidim::ContractsSk.allow_self_review = false }

    %i[return approve reject].each do |event|
      it "denies #{event} to the recorded submitter" do
        expect(action_for(submitter, scope: :admin, action: event, contract: in_review).allowed?).to be(false)
      end

      it "allows #{event} to another admin" do
        expect(action_for(other_admin, scope: :admin, action: event, contract: in_review).allowed?).to be(true)
      end

      it "allows #{event} to the submitter once allow_self_review is enabled" do
        Decidim::ContractsSk.allow_self_review = true

        expect(action_for(submitter, scope: :admin, action: event, contract: in_review).allowed?).to be(true)
      end
    end

    it "does not touch the non-judgment events for the submitter" do
      expect(action_for(submitter, scope: :admin, action: :submit,
                                   contract: FourEyesContract.new("draft", 7)).allowed?).to be(true)
      expect(action_for(submitter, scope: :admin, action: :publish,
                                   contract: FourEyesContract.new("approved", 7)).allowed?).to be(true)
      expect(action_for(submitter, scope: :admin, action: :archive,
                                   contract: FourEyesContract.new("published", 7)).allowed?).to be(true)
    end

    it "does not block a legacy record with no submitter stamp" do
      expect(action_for(submitter, scope: :admin, action: :approve,
                                   contract: FourEyesContract.new("in_review", nil)).allowed?).to be(true)
    end

    it "is unaffected when the context carries only :state (no record, no submitter)" do
      expect(action_for(submitter, scope: :admin, action: :approve, state: :in_review).allowed?).to be(true)
    end

    it "is unaffected for a contract object that does not expose the stamp" do
      expect(action_for(submitter, scope: :admin, action: :approve,
                                   contract: SpecContract.new("in_review")).allowed?).to be(true)
    end

    it "still denies a roleless submitter regardless of the seam" do
      Decidim::ContractsSk.allow_self_review = true

      roleless = FourEyesUser.new(id: 7, admin: false, admin_terms_accepted: true)

      expect(action_for(roleless, scope: :admin, action: :approve, contract: in_review).allowed?).to be(false)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
