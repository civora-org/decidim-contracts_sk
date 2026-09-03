# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, class-level specs for the engine's permissions
# class (M02-01-B, civora-org/civora-platform#54).
#
# No dummy Rails app is required: Decidim::PermissionAction and
# Decidim::DefaultPermissions (from the pinned decidim-core gem) are plain
# Ruby once their few ActiveSupport pieces are loaded, so they are required
# here by absolute path, resolved through RubyGems without shelling out.
# The engine's Permissions class is loaded directly afterwards.
#
# Fail-closed semantics asserted here follow the REAL pinned-gem classes:
# a permission action left UNSET raises PermissionNotSetError on #allowed?
# (Decidim's NeedsPermission#allowed_to? rescues it to false), while an
# action explicitly disallowed answers #allowed? with false.
#
# Once a dummy-app harness exists, delete the explicit requires and let the
# application autoloader provide the real classes instead.
#
# The exhaustive matrix example walks the full state x event x role grid on
# both state sources, so it intentionally holds many expectations and
# exceeds the default example-length budget.
# ---------------------------------------------------------------------------

require "spec_helper"

# Workaround for activesupport 6.1.x on Ruby >= 3.3: ActiveSupport references
# ::Logger, which is no longer a default gem. Must load before ActiveSupport.
require "logger"

require "active_support/concern"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/module/delegation"

decidim_core = Gem::Specification.find_by_name("decidim-core").full_gem_path
require File.join(decidim_core, "app/helpers/concerns/decidim/user_role_checker.rb")
require File.join(decidim_core, "app/models/decidim/permission_action.rb")
require File.join(decidim_core, "app/permissions/decidim/default_permissions.rb")

engine_root = File.expand_path("../../..", __dir__)
require File.join(engine_root, "app/permissions/decidim/contracts_sk/permissions.rb")

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

# Minimal stand-in for the upcoming Contract model (#55): a duck-typed state
# holder exercised via context[:contract].
SpecContract = Struct.new(:state)

RSpec.describe Decidim::ContractsSk::Permissions do
  let(:lifecycle) { Decidim::ContractsSk::ContractLifecycle }
  let(:org_admin) { SpecUser.new(admin: true, admin_terms_accepted: true) }
  let(:org_admin_unaccepted) { SpecUser.new(admin: true, admin_terms_accepted: false) }
  let(:plain_user) { SpecUser.new(admin: false, admin_terms_accepted: true) }

  # Runs the engine's permissions class the way Decidim's chain does and
  # returns the (mutated) permission action for #allowed? / raise assertions.
  # The six named parameters mirror Decidim's vocabulary (user, scope,
  # action, subject, state sources) and keep every call site self-describing.
  # rubocop:disable Metrics/ParameterLists
  def action_for(user, scope:, action:, state: nil, contract: nil, action_subject: :contract)
    context = {}
    context[:state] = state if state
    context[:contract] = contract if contract
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
      actions = %i[create read] + described_class::TRANSITION_EVENTS

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
      actions = %i[create read] + described_class::TRANSITION_EVENTS

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
    it "leaves non-:contract subjects unset" do
      expect(unset?(org_admin, scope: :admin, action: :read, state: :draft, action_subject: :component)).to be(true)
      expect(unset?(org_admin, scope: :public, action: :read, state: :published, action_subject: :proposal)).to be(true)
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
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
