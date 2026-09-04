# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin lifecycle transitions (civora-org/civora-platform#59),
# run against the Stage-1 dummy harness (spec/dummy mounts the engine at "/").
#
# Two layers, one file (mirroring contracts_spec.rb):
#
# * The default (offline, DB-free) group pins the DENIED paths. The harness'
#   Devise-ish seam (current_user / current_organization) is stubbed
#   per-example with allow_any_instance_of, and the engine role resolver is
#   swapped on the config-time seam. The record lookup is stubbed too: the
#   transition actions deliberately load the record BEFORE the permission
#   check (the check needs the record's lifecycle state), and an AR lookup
#   would need a connection.
#
# * The :db groups (CONTRACTS_SK_DB=1) pin the allowed, invalid and audited
#   paths against the real migrations on an in-memory SQLite adapter.
#
# Flash-key discipline: the harness' authenticate_user! redirects with the
# distinct literal key :dummy_authentication_required, NeedsPermission's
# denial handler uses :alert, and the transition pipeline's own failure path
# uses :alert with the transition.invalid message — every example proves
# WHICH gate fired.
#
# Fail-closed note: a NON-EDGE event (e.g. submit on in_review) is denied at
# the PERMISSION layer, not by the command — Permissions#transition_roles
# intersects to [] for events the record's state has no edge for, so the
# request is admitted nowhere near the command. The command's :invalid
# broadcast is the concurrency-loss path (edge valid at permission time,
# gone inside the row lock) and is pinned in
# spec/decidim/contracts_sk/admin/transition_contract_spec.rb.
#
# Synthetic data only (ZP-2026-00x references), no real PII.
#
# Cop note: allow_any_instance_of is the approved seam for this harness (see
# contracts_spec.rb), so the cop is disabled file-wide along with the
# dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Stand-in for a signed-in user in the offline group: only the swapped role
# resolver reads it (via engine_roles); the Devise-ish seam just needs a
# non-nil current_user. Distinct from contracts_spec.rb's FakeAdminUser so
# the two spec files stay independent.
FakeTransitionUser = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design; the flow examples assert one audit row per step on purpose.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin contract transitions", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [], user: FakeTransitionUser.new(engine_roles: roles))
    controller = Decidim::ContractsSk::Admin::ContractsController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  # The controller loads the record before the permission check; offline
  # there is no connection, so the tenant-scoped lookup itself is the seam.
  def stub_record_lookup(record)
    allow_any_instance_of(Decidim::ContractsSk::Admin::ContractsController)
      .to receive(:contracts_scope).and_return(double(find: record))
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous POST with the auth flash, not the permission flash" do
      post "/admin/contracts/1/submit"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user with the permission flash" do
      sign_in(roles: [])
      stub_record_lookup(double(state: "draft"))

      post "/admin/contracts/1/submit"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a reviewer submitting a draft (reviewers never submit)" do
      sign_in(roles: %i[reviewer])
      stub_record_lookup(double(state: "draft"))

      post "/admin/contracts/1/submit"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor approving an in_review record (editors never review)" do
      sign_in(roles: %i[editor])
      stub_record_lookup(double(state: "in_review"))

      post "/admin/contracts/1/approve"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end
  end

  describe "allowed, invalid and audited paths", :db do
    # Role control per group: the resolver defaults to editor, which keeps
    # the signed-in user a plain persistence record (the actor column
    # target) while the role decision stays explicit and deterministic.
    let(:resolver_roles) { %i[editor] }

    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    before do
      migrate_engine_schema!

      controller = Decidim::ContractsSk::Admin::ContractsController

      allow_any_instance_of(controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    # Per-step role override: swaps the resolver for the block, restoring
    # the ambient one afterwards (the around hook restores the original at
    # example end either way).
    def with_roles(*roles)
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { roles }
      yield
    ensure
      Decidim::ContractsSk.role_resolver = original
    end

    it "walks the full happy path draft→…→archive, writing one audit row per step" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      steps = [
        %i[submit editor],
        %i[return reviewer],
        %i[submit editor],
        %i[approve reviewer],
        %i[publish editor],
        %i[archive editor]
      ]

      # The publish stamp is nil for every step BEFORE publish, then present
      # from the publish step onward — it is never cleared
      # (civora-org/civora-platform#75).
      publish_index = steps.index { |event, _role| event == :publish }

      steps.each_with_index do |(event, role), step_index|
        from = contract.reload.state.to_sym

        expect do
          with_roles(role) { post "/admin/contracts/#{contract.id}/#{event}" }
        end.to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

        expect(response).to redirect_to("/admin/contracts")
        expect(flash[:notice]).to be_present

        contract.reload
        expect(contract.state.to_sym)
          .to eq(Decidim::ContractsSk::ContractLifecycle.next_state(from: from, event: event))

        if step_index < publish_index
          expect(contract.published_at).to be_nil
        else
          expect(contract.published_at).to be_present
        end

        audit = Decidim::ContractsSk::AuditEvent.order(:id).last
        expect(audit.action).to eq("contract.#{event}")
        expect(audit.target).to eq(contract)
        expect(audit.organization).to eq(organization)
        expect(audit.actor).to eq(author)
      end

      expect(contract.state).to eq("archived")
    end

    it "supports the reviewer reject branch from in_review" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      expect do
        with_roles(:reviewer) { post "/admin/contracts/#{contract.id}/reject" }
      end.to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:notice]).to be_present

      contract.reload
      expect(contract.state).to eq("rejected")

      audit = Decidim::ContractsSk::AuditEvent.order(:id).last
      expect(audit.action).to eq("contract.reject")
      expect(audit.target).to eq(contract)
      expect(audit.organization).to eq(organization)
      expect(audit.actor).to eq(author)
    end

    it "flashes the transition.invalid alert and persists nothing when the audit write fails mid-transition" do
      # The request-layer twin of the command spec's atomicity example: the
      # same injection boundary (the audit table's create!), driven through
      # a real allowed-transition POST. The state UPDATE and the audit
      # INSERT share the command's with_lock transaction, so the raise must
      # roll the state back — and the controller must surface the command's
      # :invalid as the transition.invalid flash (PRG, no re-render).
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      allow(Decidim::ContractsSk::AuditEvent).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid)

      expect do
        post "/admin/contracts/#{contract.id}/submit"
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:alert])
        .to eq(I18n.t("decidim.contracts_sk.admin.contracts.transition.invalid"))

      contract.reload
      expect(contract.state).to eq("draft")
    end

    it "refuses a non-edge event with the permission flash, writing no state and no audit row" do
      # Editor submits an in_review record: the lifecycle table has no
      # submit edge from in_review, so the permission layer denies (see the
      # file-header fail-closed note) — the command is never reached.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      expect do
        post "/admin/contracts/#{contract.id}/submit"
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)

      contract.reload
      expect(contract.state).to eq("in_review")
    end

    it "denies archive on a draft (non-edge ⇒ permission deny)" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      expect do
        post "/admin/contracts/#{contract.id}/archive"
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)

      contract.reload
      expect(contract.state).to eq("draft")
    end

    it "renders transition buttons exactly for the events the acting role may fire" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      get "/admin/contracts"

      # button_to renders a form per allowed event — derive expectations
      # from the same source the view uses (the lifecycle table).
      Decidim::ContractsSk::ContractLifecycle.events_from(:draft).each do |event|
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/#{event}"))
      end
      # Events that exist in the table but belong to other states or roles.
      %w[approve return reject publish archive].each do |event|
        expect(response.body).not_to include(%(action="/admin/contracts/#{contract.id}/#{event}"))
      end
    end

    it "renders no transition buttons for a role that owns no edge of the record's state" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      with_roles(:reviewer) { get "/admin/contracts" }

      # A reviewer passes :read (any engine role may read the index) but owns
      # no edge from draft — so no buttons at all, derived, not hand-picked.
      %w[submit return approve reject publish archive].each do |event|
        expect(response.body).not_to include(%(action="/admin/contracts/#{contract.id}/#{event}"))
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
