# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin ADR-007 privacy-redaction confirmation POST
# (civora-org/civora-platform#91), run against the Stage-1 dummy harness
# (spec/dummy mounts the engine at "/"). Two layers, one file — mirroring
# crz_handoff_spec.rb:
#
# * The default (offline, DB-free) group pins the DENIED paths. The harness'
#   Devise-ish seam (current_user / current_organization) is stubbed
#   per-example with allow_any_instance_of, the engine role resolver is
#   swapped on the config-time seam, and the contract lookup is stubbed: the
#   controller deliberately loads the contract BEFORE the permission check
#   (the check needs the contract's lifecycle state), and an AR lookup would
#   need a connection.
#
# * The :db groups (CONTRACTS_SK_DB=1) pin the allowed paths, the
#   server-side affirmation consumption (a POST without the checkbox value
#   refuses), the idempotent refusal, the approved-state confirmation
#   window (#91 H-1), the edit-page rendering (checklist + labelled
#   checkbox vs. confirmation stamp line) and the admin-index surface (the
#   collapsed row card for confirmable, unstamped records — nothing once
#   stamped, for reviewers, or outside the confirmable window) against the
#   real migrations on an in-memory SQLite adapter.
#
# Flash-key discipline: the harness' authenticate_user! redirects with the
# distinct literal key :dummy_authentication_required, while NeedsPermission's
# denial handler uses :alert — every denial example proves WHICH gate fired.
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
# non-nil current_user. Distinct from the other request specs' fakes so the
# spec files stay independent.
FakeRedactionUser = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design: every denial must prove which gate fired, and every success must
# prove what reached the database or the response body.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin redaction confirmation", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [], user: FakeRedactionUser.new(engine_roles: roles))
    controller = Decidim::ContractsSk::Admin::ContractsController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  # The controller loads the contract before the permission check; offline
  # there is no connection, so the tenant-scoped lookup itself is the seam.
  # The contract double needs only what the permission layer reads (state).
  def stub_record_lookup(record)
    allow_any_instance_of(Decidim::ContractsSk::Admin::ContractsController)
      .to receive(:contracts_scope)
      .and_return(double(find: record))
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous POST with the auth flash, not the permission flash" do
      post "/admin/contracts/1/confirm_redaction"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user with the permission flash" do
      sign_in(roles: [])
      stub_record_lookup(double(state: "draft"))

      post "/admin/contracts/1/confirm_redaction"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a reviewer on an editable record (non-editors never hold the gate)" do
      sign_in(roles: %i[reviewer])
      stub_record_lookup(double(state: "draft"))

      post "/admin/contracts/1/confirm_redaction"

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on a non-confirmable record (in_review is outside the window)" do
      sign_in(roles: %i[editor])
      stub_record_lookup(double(state: "in_review"))

      post "/admin/contracts/1/confirm_redaction"

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end
  end

  describe "allowed paths, idempotent refusal and edit-page rendering", :db do
    let(:resolver_roles) { %i[editor] }

    # Role control per group: the resolver defaults to editor, keeping the
    # role decision explicit and deterministic.
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

    it "stamps the record, writes the audit row and PRG-redirects to the edit page with a notice" do
      before = Time.current
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/confirm_redaction",
           params: { redaction_confirmed: "1" }

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present

      contract.reload
      aggregate_failures do
        expect(contract.redaction_confirmed_at).to be_present
        expect(contract.redaction_confirmed_at).to be >= before
      end

      audit = Decidim::ContractsSk::AuditEvent.sole
      aggregate_failures do
        expect(audit.action).to eq("contract.redaction_confirmed")
        expect(audit.target).to eq(contract)
        expect(audit.organization).to eq(organization)
        expect(audit.actor).to eq(author)
      end
    end

    it "stamps an approved record too — the confirmable window reaches the publish edge (#91 H-1)" do
      # The review round widened the CONFIRMATION window to include
      # :approved (a reviewer sign-off can arrive unstamped); editability
      # itself is NOT widened.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "approved"))

      post "/admin/contracts/#{contract.id}/confirm_redaction",
           params: { redaction_confirmed: "1" }

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("approved")
        expect(contract.redaction_confirmed_at).to be_present
      end
      expect(Decidim::ContractsSk::AuditEvent.where(action: "contract.redaction_confirmed").count).to eq(1)
    end

    it "refuses the POST without the checkbox value server-side, writing no stamp and no audit row" do
      # M-1 review round: the affirmation is consumed server-side — the
      # checkbox's `required` attribute is a UX aid, never the gate. A
      # missing (unchecked / stale / hand-crafted) value answers the same
      # localized alert as any other refusal and persists nothing.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/confirm_redaction"

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
        expect(flash[:notice]).to be_nil
        expect(flash[:alert])
          .to eq(I18n.t("decidim.contracts_sk.admin.contracts.confirm_redaction.invalid"))
      end

      contract.reload
      aggregate_failures do
        expect(contract.redaction_confirmed_at).to be_nil
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end

    it 'refuses a falsy checkbox value ("0" / "false") the same way' do
      # The pinned affirmation vocabulary: ActiveModel::Type::Boolean truthy
      # values only ("1", "true", "t", "on") — "0" and "false" refuse.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/confirm_redaction", params: { redaction_confirmed: "0" }

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
        expect(flash[:alert]).to be_present
      end

      contract.reload
      aggregate_failures do
        expect(contract.redaction_confirmed_at).to be_nil
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end

    it "refuses a repeat POST with the localized alert, keeping the first stamp and a single audit row" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      post "/admin/contracts/#{contract.id}/confirm_redaction", params: { redaction_confirmed: "1" }
      first_stamp = contract.reload.redaction_confirmed_at

      post "/admin/contracts/#{contract.id}/confirm_redaction", params: { redaction_confirmed: "1" }

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
        expect(flash[:alert])
          .to eq(I18n.t("decidim.contracts_sk.admin.contracts.confirm_redaction.invalid"))
      end

      contract.reload
      aggregate_failures do
        expect(contract.redaction_confirmed_at).to eq(first_stamp)
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(1)
      end
    end

    it "denies an editor on a non-editable record, persisting nothing" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      post "/admin/contracts/#{contract.id}/confirm_redaction"

      aggregate_failures do
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq(unauthorized)
      end

      contract.reload
      expect(contract.redaction_confirmed_at).to be_nil
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end

    it "hides another organization's contract from the confirm POST (scoped find raises)" do
      # Tenant isolation: contracts_scope filters on the acting
      # organization, so a foreign record is invisible — the scoped find
      # raises ActiveRecord::RecordNotFound (rendered as 404 in a real
      # deployment with exceptions enabled), not merely permission-denied.
      # The dummy test env does not rescue it, so the raise itself is the
      # asserted contract-not-found behavior.
      foreign_org = Decidim::Organization.create!
      foreign = Decidim::ContractsSk::Contract.create!(contract_attributes(organization: foreign_org))

      expect do
        post "/admin/contracts/#{foreign.id}/confirm_redaction"
      end.to raise_error(ActiveRecord::RecordNotFound)

      foreign.reload
      aggregate_failures do
        expect(foreign.redaction_confirmed_at).to be_nil
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end

    it "renders the checklist and the required checkbox on the edit page while unstamped" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Privacy redaction")
        expect(response.body).to include("personal names and addresses of natural persons")
        expect(response.body).to include("bank and account details")
        expect(response.body).to include("amounts tying the contract to identifiable persons")
        expect(response.body).to include("sensitive content inside attached documents")
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/confirm_redaction"))
        expect(response.body).to include(%(name="redaction_confirmed"))
        # Accessible label markup (L-3): the checkbox's label points at the
        # input's id, so screen readers announce the affirmation. The id is
        # derived per record (the index can carry several confirmable rows
        # on one page), the name stays the server-side contract.
        expect(response.body).to include(%(<label for="redaction_confirmed_#{contract.id}">))
        expect(response.body).to include(%(id="redaction_confirmed_#{contract.id}"))
        expect(response.body).not_to include("Redaction confirmed on")
      end
    end

    it "renders the confirmation stamp line instead of the checkbox form once stamped" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      post "/admin/contracts/#{contract.id}/confirm_redaction", params: { redaction_confirmed: "1" }
      stamp_date = contract.reload.redaction_confirmed_at.to_date.to_fs(:db)

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Redaction confirmed on #{stamp_date}")
        expect(response.body).not_to include(%(action="/admin/contracts/#{contract.id}/confirm_redaction"))
        expect(response.body).not_to include(%(name="redaction_confirmed"))
      end
    end
  end

  describe "index surface rendering (collapsed row card, ADR-007)", :db do
    let(:resolver_roles) { %i[editor] }

    # Role control per group: the resolver defaults to editor, keeping the
    # role decision explicit and deterministic.
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

    def create_contract!(overrides = {})
      Decidim::ContractsSk::Contract.create!(contract_attributes(overrides))
    end

    it "renders the collapsed card (checklist, checkbox, POST) for an editor on confirmable unstamped records" do
      # Both confirmable-window members: the editable draft and the
      # reviewer-approved record waiting for its stamp right before publish.
      draft = create_contract!(reference: "ZP-2026-101")
      approved = create_contract!(reference: "ZP-2026-102", state: "approved")

      get "/admin/contracts"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("<details")
        expect(response.body).to include("Privacy redaction")
        expect(response.body).to include("personal names and addresses of natural persons")
        expect(response.body).to include(%(action="/admin/contracts/#{draft.id}/confirm_redaction"))
        expect(response.body).to include(%(action="/admin/contracts/#{approved.id}/confirm_redaction"))
        expect(response.body).to include(%(name="redaction_confirmed"))
        # Per-record derived id (two confirmable rows share the page), so
        # the label-for pairing stays unique and accessible.
        expect(response.body).to include(%(<label for="redaction_confirmed_#{draft.id}">))
        expect(response.body).to include(%(id="redaction_confirmed_#{draft.id}"))
      end
    end

    it "renders nothing for the record on the index once stamped" do
      contract = create_contract!
      post "/admin/contracts/#{contract.id}/confirm_redaction", params: { redaction_confirmed: "1" }
      expect(contract.reload.redaction_confirmed_at).to be_present

      get "/admin/contracts"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).not_to include("<details")
        expect(response.body).not_to include(%(action="/admin/contracts/#{contract.id}/confirm_redaction"))
        expect(response.body).not_to include(%(name="redaction_confirmed"))
        # The confirmation line is the edit page's historical record; the
        # index row carries no trace of it.
        expect(response.body).not_to include("Redaction confirmed on")
      end
    end

    it "renders nothing for a reviewer on a confirmable unstamped record (non-editors never hold the gate)" do
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      contract = create_contract!

      get "/admin/contracts"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).not_to include("<details")
        expect(response.body).not_to include(%(action="/admin/contracts/#{contract.id}/confirm_redaction"))
        expect(response.body).not_to include(%(name="redaction_confirmed"))
      end
    end

    it "renders nothing for an editor on non-confirmable records (in_review / published)" do
      in_review = create_contract!(reference: "ZP-2026-103", state: "in_review")
      published = create_contract!(reference: "ZP-2026-104", state: "published")

      get "/admin/contracts"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).not_to include("<details")
        expect(response.body).not_to include(%(action="/admin/contracts/#{in_review.id}/confirm_redaction"))
        expect(response.body).not_to include(%(action="/admin/contracts/#{published.id}/confirm_redaction"))
        expect(response.body).not_to include(%(name="redaction_confirmed"))
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
