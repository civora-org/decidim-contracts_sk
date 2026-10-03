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
  # DB-only (the lazy let creates a row); the offline group never touches it.
  let(:reviewer_user) { Decidim::User.create!(organization: organization) }

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

  # Signs the controller's current_user stub in as +user+ for the block,
  # restoring the author afterwards (the DB groups' default actor). The
  # four-eyes rule (civora-org/civora-platform#123) separates the
  # submitting and the judging PERSON, so DB-backed flows that walk a
  # record through review need a second signed-in user.
  def acting_as(user)
    controller = Decidim::ContractsSk::Admin::ContractsController
    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    yield
  ensure
    allow_any_instance_of(controller).to receive(:current_user).and_return(author)
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

      # The ADR-007 gate (civora-org/civora-platform#91): the publish step
      # below refuses without the privacy-redaction confirmation, so the
      # happy path stamps it first — through the real POST (with the
      # checkbox value the controller consumes server-side), which writes
      # its own audit row ahead of the loop's per-step assertions.
      post "/admin/contracts/#{contract.id}/confirm_redaction", params: { redaction_confirmed: "1" }

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present
      expect(contract.reload.redaction_confirmed_at).to be_present

      # Per-step payloads: the judgment edges (return/reject, #90) demand a
      # decision reason through the real POST too.
      steps = [
        { event: :submit, role: :editor },
        { event: :return, role: :reviewer, reason: "Annex misses the cost breakdown." },
        { event: :submit, role: :editor },
        { event: :approve, role: :reviewer },
        { event: :publish, role: :editor },
        { event: :archive, role: :editor }
      ]

      # The publish stamp is nil for every step BEFORE publish, then present
      # from the publish step onward — it is never cleared
      # (civora-org/civora-platform#75).
      publish_index = steps.index { |step| step[:event] == :publish }

      steps.each_with_index do |step, step_index|
        event = step[:event]
        role = step[:role]
        from = contract.reload.state.to_sym
        # Four-eyes (#123): the judgment steps are taken by a second person.
        actor = role == :reviewer ? reviewer_user : author

        expect do
          acting_as(actor) do
            with_roles(role) do
              post "/admin/contracts/#{contract.id}/#{event}",
                   params: step[:reason] ? { reason: step[:reason] } : {}
            end
          end
        end.to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

        expect(response).to redirect_to("/admin/contracts")
        expect(flash[:notice]).to be_present

        contract.reload
        expect(contract.state.to_sym)
          .to eq(Decidim::ContractsSk::ContractLifecycle.next_state(from: from, event: event))

        # The reviewer decision text is stamped with the return and cleared
        # by the resubmit (civora-org/civora-platform#90) — pinned on
        # exactly the two steps where the fact changes.
        if event == :return
          expect(contract.review_reason).to eq(step[:reason])
        elsif step_index == 2
          expect(contract.review_reason).to be_nil
        end

        if step_index < publish_index
          expect(contract.published_at).to be_nil
        else
          expect(contract.published_at).to be_present
        end

        audit = Decidim::ContractsSk::AuditEvent.order(:id).last
        expect(audit.action).to eq("contract.#{event}")
        expect(audit.target).to eq(contract)
        expect(audit.organization).to eq(organization)
        expect(audit.actor).to eq(actor)
      end

      expect(contract.state).to eq("archived")
    end

    it "supports the reviewer reject branch from in_review" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      expect do
        with_roles(:reviewer) do
          post "/admin/contracts/#{contract.id}/reject", params: { reason: "Duplicate of ZP-2026-001." }
        end
      end.to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:notice]).to be_present

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("rejected")
        expect(contract.review_reason).to eq("Duplicate of ZP-2026-001.")
        expect(contract.reviewed_at).to be_present
      end

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

    it "renders the transition buttons with the per-event confirmation prompt" do
      Decidim::ContractsSk::Contract.create!(contract_attributes)

      get "/admin/contracts"

      expect(response.body).to include("data-confirm")
      # The draft/editor row carries exactly one event (submit), so the
      # message on the page is that event's confirm string.
      expect(response.body)
        .to include(I18n.t("decidim.contracts_sk.admin.contracts.transition.confirm.submit"))
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

  describe "publish-time redaction gate (ADR-007, civora-org/civora-platform#91)", :db do
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

    it "fails a publish POST on an approved record without the stamp, persisting nothing" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "approved"))

      expect do
        post "/admin/contracts/#{contract.id}/publish"
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts")
        # The dedicated redaction-gate flash (#91 review round): the
        # command's :redaction_gate refusal payload maps onto its own
        # localized, actionable message instead of the generic one.
        expect(flash[:alert])
          .to eq(I18n.t("decidim.contracts_sk.admin.contracts.transition.redaction_required"))
        expect(flash[:alert]).not_to eq(I18n.t("decidim.contracts_sk.admin.contracts.transition.invalid"))
      end

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("approved")
        expect(contract.published_at).to be_nil
        expect(contract.redaction_confirmed_at).to be_nil
      end
    end

    # The generic-alert contrast case (a non-redaction refusal flashing
    # transition.invalid, never the dedicated key) is pinned by the audit-
    # failure example in the sibling :db group above — no extra example
    # needed here.

    it "publishes an approved record the confirmation POST stamped after approval (#91 H-1)" do
      # The review round widened the CONFIRMATION window to include
      # :approved: a record can reach its reviewer sign-off unstamped, the
      # editor confirms right before publishing, and the publish edge
      # opens — no draft-walk required.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "approved"))
      expect(contract.redaction_confirmed_at).to be_nil

      post "/admin/contracts/#{contract.id}/confirm_redaction", params: { redaction_confirmed: "1" }
      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present

      expect do
        post "/admin/contracts/#{contract.id}/publish"
      end.to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:notice]).to be_present

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("published")
        expect(contract.published_at).to be_present
        expect(contract.redaction_confirmed_at).to be_present
      end
    end

    it "publishes the same record once the confirmation POST has stamped it" do
      # The confirmation is admittable from the editable states too (the
      # window is CONFIRMABLE_STATES: draft/returned/approved), so the
      # stamp may also land on the DRAFT — before the record walks
      # submit → approve → publish, mirroring the real editorial order.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/confirm_redaction", params: { redaction_confirmed: "1" }
      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")

      # Per-step role overrides, same shape as the with_roles helper in the
      # sibling group (the group's around hook restores the resolver).
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[editor] }
      post "/admin/contracts/#{contract.id}/submit"
      expect(response).to redirect_to("/admin/contracts")
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      acting_as(reviewer_user) { post "/admin/contracts/#{contract.id}/approve" }
      expect(response).to redirect_to("/admin/contracts")
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }

      expect do
        post "/admin/contracts/#{contract.id}/publish"
      end.to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:notice]).to be_present

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("published")
        expect(contract.published_at).to be_present
        expect(contract.redaction_confirmed_at).to be_present
      end
    end
  end

  describe "reviewer decision reasons (civora-org/civora-platform#90)", :db do
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

    it "persists a reviewer return with its reason through the real POST, with the audit row" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      expect do
        with_roles(:reviewer) do
          post "/admin/contracts/#{contract.id}/return", params: { reason: "Annex misses the cost breakdown." }
        end
      end.to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:notice]).to be_present

      contract.reload
      audit = Decidim::ContractsSk::AuditEvent.order(:id).last
      aggregate_failures do
        expect(contract.state).to eq("returned")
        expect(contract.review_reason).to eq("Annex misses the cost breakdown.")
        expect(contract.reviewed_at).to be_present
        expect(audit.action).to eq("contract.return")
      end
    end

    it "answers the localized reason-required alert and writes nothing when the reason is missing" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      expect do
        with_roles(:reviewer) { post "/admin/contracts/#{contract.id}/return" }
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts")
        expect(flash[:alert])
          .to eq(I18n.t("decidim.contracts_sk.admin.contracts.transition.review_reason_required"))
        expect(flash[:alert])
          .not_to eq(I18n.t("decidim.contracts_sk.admin.contracts.transition.invalid"))
      end

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("in_review")
        expect(contract.review_reason).to be_nil
        expect(contract.reviewed_at).to be_nil
      end
    end

    it "fails an editor publish closed when a stray reason arrives, with the localized reason-rejected alert" do
      contract = Decidim::ContractsSk::Contract.create!(
        contract_attributes(state: "approved", redaction_confirmed_at: Time.current)
      )

      expect do
        post "/admin/contracts/#{contract.id}/publish", params: { reason: "Not a reviewer." }
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts")
        expect(flash[:alert])
          .to eq(I18n.t("decidim.contracts_sk.admin.contracts.transition.review_reason_rejected"))
        expect(flash[:alert])
          .not_to eq(I18n.t("decidim.contracts_sk.admin.contracts.transition.redaction_required"))
      end

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("approved")
        expect(contract.review_reason).to be_nil
        expect(contract.reviewed_at).to be_nil
      end
    end

    it "clears the stale decision through the real resubmit POST" do
      contract = Decidim::ContractsSk::Contract.create!(
        contract_attributes(state: "returned", review_reason: "Fix the annex.", reviewed_at: Time.current)
      )

      expect do
        post "/admin/contracts/#{contract.id}/submit"
      end.to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("in_review")
        expect(contract.review_reason).to be_nil
        expect(contract.reviewed_at).to be_nil
      end
    end

    it "renders the decision banner on the edit page for a returned record carrying its reason" do
      # The banner is historical record: it renders for the editor who owns
      # the returned (editable) record, regardless of anything else. (A
      # rejected record carries the banner defensively too, but its edit
      # page is permission-locked, so the reachable pin is the returned one.)
      contract = Decidim::ContractsSk::Contract.create!(
        contract_attributes(state: "returned", review_reason: "Fix the <annex> & resubmit.",
                            reviewed_at: Time.zone.local(2026, 9, 26))
      )

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Reviewer decision")
        expect(response.body).to include("Returned for changes")
        expect(response.body).to include("Decided on 2026-09-26.")
        # Escaped output on purpose: the reason is reviewer-typed free text.
        expect(response.body).to include("Fix the &lt;annex&gt; &amp; resubmit.")
        expect(response.body).not_to include("Fix the <annex>")
      end
    end

    it "renders no decision banner without a reason or outside the decision states" do
      # A returned record without a reason can only predate #90 — the
      # command refuses reason-less judgments — so the banner stays hidden
      # rather than rendering an empty frame; a draft never carried one.
      unstamped = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-101", state: "returned")
      )
      draft = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-102", review_reason: "Stale?", reviewed_at: Time.current)
      )

      get "/admin/contracts/#{unstamped.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Reviewer decision")

      get "/admin/contracts/#{draft.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Reviewer decision")
    end

    it "renders the banner for a reason carrying a nil reviewed_at without raising" do
      # The timestamp is nil-guarded in the view: a reason-present/
      # timestamp-nil row (only possible from pre-#90-style data or manual
      # seeds — the command stamps reason and stamp atomically) must render
      # the banner, not a 500.
      contract = Decidim::ContractsSk::Contract.create!(
        contract_attributes(state: "returned", review_reason: "Fix the annex.", reviewed_at: nil)
      )

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Reviewer decision")
        expect(response.body).to include("Fix the annex.")
      end
    end

    it "renders the collapsed decision reason on the index row for rejected and returned records" do
      # The index row card is a rejected record's only reachable surface
      # for its reason: a terminal state renders no transition controls and
      # the edit page is permission-locked. Gated on reason presence only —
      # the same audience as the index — so it shows for whichever role
      # views the page (the editor below holds no edge on a rejected record
      # at all and still reads it).
      # The rejected row pins the terminal-state surface (the reason is
      # otherwise unreachable), the returned row the editable one.
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-105", state: "rejected",
                            review_reason: "Duplicate of ZP-2026-001. <crz.gov.sk/example> & refile.",
                            reviewed_at: Time.zone.local(2026, 9, 26))
      )
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-106", state: "returned",
                            review_reason: "Fix the annex.", reviewed_at: Time.current)
      )

      with_roles(:reviewer) { get "/admin/contracts" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("<details")
        expect(response.body).to include("Reviewer decision")
        expect(response.body).to include("Decided on 2026-09-26.")
        # Escaped output on purpose: the reason is reviewer-typed free text.
        expect(response.body).to include("Duplicate of ZP-2026-001. &lt;crz.gov.sk/example&gt; &amp; refile.")
        expect(response.body).to include("Fix the annex.")
        expect(response.body).not_to include("Duplicate of ZP-2026-001. <crz.gov.sk/example>")
      end

      with_roles(:editor) { get "/admin/contracts" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Reviewer decision")
        expect(response.body).to include("Duplicate of ZP-2026-001. &lt;crz.gov.sk/example&gt; &amp; refile.")
      end
    end

    it "renders no collapsed decision reason on the index without a reason or outside the decision states" do
      # Mirrors the banner's hidden cases on the row: a returned record
      # without a reason can only predate #90, and a draft carrying a stale
      # reason is not in a decision state — neither renders an empty frame.
      # A returned record without a reason can only predate #90; a draft
      # carrying a stale reason is not in a decision state — neither row
      # may render an empty frame.
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-107", state: "returned")
      )
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-108", review_reason: "Stale?",
                            reviewed_at: Time.current)
      )

      with_roles(:reviewer) { get "/admin/contracts" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).not_to include("Reviewer decision")
        expect(response.body).not_to include("Stale?")
      end
    end

    it "renders the inline reason form for a reviewer on an in_review record only" do
      # Gating per the lifecycle table: the reviewer owns the return/reject
      # edges out of in_review — both render as collapsed decision forms.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      with_roles(:reviewer) { get "/admin/contracts" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/return"))
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/reject"))
        expect(response.body).to include(%(name="reason"))
        expect(response.body).to include(%(id="review_reason_#{contract.id}_return"))
        expect(response.body).to include(I18n.t("decidim.contracts_sk.admin.contracts.transition.review_reason.label"))
      end
    end

    it "renders no reason form for a role that owns no judgment edge" do
      # An editor holds no edge out of in_review; a reviewer holds none out
      # of draft — neither sees a decision form on those rows. (The reviewer
      # DOES see one on the in_review row — that gating is the prior
      # example's pin — so this half scopes its assertions to the draft's
      # derived ids.)
      in_review = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-103", state: "in_review")
      )
      draft = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-104"))

      with_roles(:editor) { get "/admin/contracts" }

      aggregate_failures do
        expect(response.body).not_to include(%(action="/admin/contracts/#{in_review.id}/return"))
        expect(response.body).not_to include(%(action="/admin/contracts/#{in_review.id}/reject"))
        expect(response.body).not_to include(%(name="reason"))
      end

      with_roles(:reviewer) { get "/admin/contracts" }

      aggregate_failures do
        expect(response.body).not_to include(%(action="/admin/contracts/#{draft.id}/return"))
        expect(response.body).not_to include(%(action="/admin/contracts/#{draft.id}/reject"))
        expect(response.body).not_to include(%(id="review_reason_#{draft.id}_return"))
        expect(response.body).not_to include(%(id="review_reason_#{draft.id}_reject"))
      end
    end
  end

  describe "four-eyes rule (civora-org/civora-platform#123)", :db do
    # The default resolver gives org admins both roles; model that so only
    # the per-person rule can separate the submitter from the judgment.
    let(:resolver_roles) { %i[editor reviewer] }
    let(:in_review) do
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(state: "in_review", decidim_submitted_by_id: author.id)
      )
    end

    around do |example|
      original = Decidim::ContractsSk.role_resolver
      original_seam = Decidim::ContractsSk.allow_self_review
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
      example.run
      Decidim::ContractsSk.role_resolver = original
      Decidim::ContractsSk.allow_self_review = original_seam
    end

    before do
      migrate_engine_schema!

      controller = Decidim::ContractsSk::Admin::ContractsController

      allow_any_instance_of(controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    def judgment_action(contract, event)
      %(action="/admin/contracts/#{contract.id}/#{event}")
    end

    it "renders no return/approve/reject controls on the submitter's own row" do
      in_review

      get "/admin/contracts"

      %w[return approve reject].each do |event|
        expect(response.body).not_to include(judgment_action(in_review, event)), "submitter sees #{event}"
      end
    end

    it "renders the judgment controls on the same row for another admin" do
      in_review

      acting_as(reviewer_user) { get "/admin/contracts" }

      %w[return approve reject].each do |event|
        expect(response.body).to include(judgment_action(in_review, event)), "reviewer misses #{event}"
      end
    end

    it "renders the judgment controls for the submitter once allow_self_review is enabled" do
      Decidim::ContractsSk.allow_self_review = true
      in_review

      get "/admin/contracts"

      %w[return approve reject].each do |event|
        expect(response.body).to include(judgment_action(in_review, event))
      end
    end

    %w[approve return reject].each do |event|
      it "denies a direct #{event} POST by the submitter with the permission flash, changing nothing" do
        expect do
          post "/admin/contracts/#{in_review.id}/#{event}", params: { reason: "Because." }
        end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq(unauthorized)

        in_review.reload
        aggregate_failures do
          expect(in_review.state).to eq("in_review")
          expect(in_review.review_reason).to be_nil
        end
      end
    end

    it "lets another admin approve the same record" do
      acting_as(reviewer_user) { post "/admin/contracts/#{in_review.id}/approve" }

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:notice]).to be_present
      expect(in_review.reload.state).to eq("approved")
      expect(Decidim::ContractsSk::AuditEvent.order(:id).last.action).to eq("contract.approve")
    end

    it "lets the submitter approve under allow_self_review, audited as contract.approve_self" do
      Decidim::ContractsSk.allow_self_review = true

      post "/admin/contracts/#{in_review.id}/approve"

      expect(response).to redirect_to("/admin/contracts")
      expect(in_review.reload.state).to eq("approved")
      expect(Decidim::ContractsSk::AuditEvent.order(:id).last.action).to eq("contract.approve_self")
    end

    it "flashes the dedicated self-review alert when the command refuses a request admission let through" do
      # Permission-vs-command race: admission passed (the stamp was not the
      # submitter's yet), the in-lock re-check then refuses. Simulated by
      # neutralizing the permission twin only.
      allow_any_instance_of(Decidim::ContractsSk::Permissions)
        .to receive(:self_review_blocked?).and_return(false)

      expect do
        post "/admin/contracts/#{in_review.id}/approve"
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:alert]).to eq(I18n.t("decidim.contracts_sk.admin.contracts.transition.self_review"))
      expect(in_review.reload.state).to eq("in_review")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
