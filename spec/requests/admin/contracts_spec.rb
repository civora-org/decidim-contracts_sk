# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin contracts CRUD (civora-org/civora-platform#58),
# run against the Stage-1 dummy harness (spec/dummy mounts the engine at "/").
#
# Two layers, one file:
#
# * The default (offline, DB-free) group pins the DENIED paths. The harness'
#   Devise-ish seam (current_user / current_organization) is stubbed
#   per-example with allow_any_instance_of, and the engine role resolver is
#   swapped on the config-time seam — the same pattern the permissions specs
#   use. No DB connection is ever opened: for the edit/update denials the
#   controller's record lookup is stubbed too (the lookup deliberately
#   precedes the permission check, and an AR lookup would need a connection).
#
# * The :db groups (CONTRACTS_SK_DB=1) pin the allowed and validation paths
#   against the real migrations on an in-memory SQLite adapter; there the
#   seam carries REAL Decidim::Organization / Decidim::User records so the
#   command layer's tenancy and authorship columns can persist.
#
# Flash-key discipline: the harness' authenticate_user! redirects with the
# distinct literal key :dummy_authentication_required, while NeedsPermission's
# denial handler uses :alert — every denial example proves WHICH gate fired.
#
# Synthetic data only (ZP-2026-00x references), no real PII.
#
# Cop note: allow_any_instance_of is the approved seam for this harness (the
# Devise-ish methods live on the controllers; request specs cannot inject
# substitutes into the framework's instantiation path), so the cop is
# disabled file-wide along with the dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Stand-in for a signed-in user in the offline group: only the swapped role
# resolver reads it (via engine_roles); the Devise-ish seam just needs a
# non-nil current_user.
FakeAdminUser = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design: every denial must prove which gate fired, and every success must
# prove what reached the database.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin contracts CRUD", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [], user: FakeAdminUser.new(engine_roles: roles))
    controller = Decidim::ContractsSk::Admin::ContractsController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous visitor from the index with the auth flash, not the permission flash" do
      get "/admin/contracts"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "bounces an anonymous POST before any permission work happens" do
      post "/admin/contracts", params: { contract: { title: "Road reconstruction", reference: "ZP-2026-001" } }

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user on the index with the permission flash" do
      sign_in(roles: [])
      get "/admin/contracts"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a signed-in roleless user on create with the permission flash" do
      sign_in(roles: [])
      post "/admin/contracts", params: { contract: { title: "Road reconstruction", reference: "ZP-2026-001" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a reviewer on the new-contract form (reviewers never draft)" do
      sign_in(roles: %i[reviewer])
      get "/admin/contracts/new"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a reviewer on edit, with the record lookup stubbed" do
      sign_in(roles: %i[reviewer])
      stub_record_lookup(double(state: "draft"))

      get "/admin/contracts/1/edit"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on update even for an editable record" do
      sign_in(roles: %i[reviewer])
      stub_record_lookup(double(state: "draft"))

      patch "/admin/contracts/1", params: { contract: { title: "Tampered", reference: "ZP-2026-001" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    # The controller loads the record before the permission check; offline
    # there is no connection, so the tenant-scoped lookup itself is the seam.
    def stub_record_lookup(record)
      allow_any_instance_of(Decidim::ContractsSk::Admin::ContractsController)
        .to receive(:contracts_scope).and_return(double(find: record))
    end
  end

  describe "allowed and validation paths", :db do
    let(:author) { Decidim::User.create! }
    let(:valid_params) { { contract: { title: "Road reconstruction", reference: "ZP-2026-002" } } }

    # Role control per group: the resolver defaults to editor, which keeps
    # the signed-in user a plain persistence record (the author column
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

    it "creates a draft contract for an editor, with org and author set, and redirects to the index" do
      post "/admin/contracts", params: valid_params

      expect(response).to redirect_to("/admin/contracts")

      record = Decidim::ContractsSk::Contract.find_by!(reference: "ZP-2026-002")
      expect(record.state).to eq("draft")
      expect(record.organization).to eq(organization)
      expect(record.author).to eq(author)
      expect(record.title).to eq("Road reconstruction")
    end

    it "updates a draft contract's editorial identity fields for an editor" do
      record = Decidim::ContractsSk::Contract.create!(contract_attributes)

      patch "/admin/contracts/#{record.id}",
            params: { contract: { title: "Road reconstruction II", reference: "ZP-2026-003" } }

      expect(response).to redirect_to("/admin/contracts")
      record.reload
      expect(record.title).to eq("Road reconstruction II")
      expect(record.reference).to eq("ZP-2026-003")
      expect(record.state).to eq("draft")
    end

    it "creates a contract with the full content field set for an editor (civora-org/civora-platform#75)" do
      post "/admin/contracts", params: {
        contract: {
          title: "Road reconstruction",
          reference: "ZP-2026-005",
          subject_matter: "Supply and installation of road signage",
          amount: "1250.50",
          currency: "EUR",
          signed_on: "2026-09-01",
          effective_from: "2026-08-15",
          crz_url: "https://crz.gov.sk/record/123"
        }
      }

      expect(response).to redirect_to("/admin/contracts")

      record = Decidim::ContractsSk::Contract.find_by!(reference: "ZP-2026-005")
      expect(record.subject_matter).to eq("Supply and installation of road signage")
      expect(record.amount).to eq(BigDecimal("1250.50"))
      expect(record.currency).to eq("EUR")
      expect(record.signed_on).to eq(Date.new(2026, 9, 1))
      expect(record.effective_from).to eq(Date.new(2026, 8, 15))
      expect(record.crz_url).to eq("https://crz.gov.sk/record/123")
      # The publication stamp is a system field — never set through the form.
      expect(record.published_at).to be_nil
    end

    it "updates a draft contract's content fields for an editor (civora-org/civora-platform#75)" do
      record = Decidim::ContractsSk::Contract.create!(contract_attributes)

      patch "/admin/contracts/#{record.id}", params: {
        contract: {
          title: "Road reconstruction",
          reference: "ZP-2026-001",
          subject_matter: "Revised scope: signage and barrier-free access",
          amount: "98000.40",
          currency: "EUR",
          signed_on: "2026-09-01",
          effective_from: "2026-08-15",
          crz_url: "https://crz.gov.sk/record/123"
        }
      }

      expect(response).to redirect_to("/admin/contracts")
      record.reload
      expect(record.subject_matter).to eq("Revised scope: signage and barrier-free access")
      expect(record.amount).to eq(BigDecimal("98000.40"))
      expect(record.signed_on).to eq(Date.new(2026, 9, 1))
      expect(record.effective_from).to eq(Date.new(2026, 8, 15))
      expect(record.crz_url).to eq("https://crz.gov.sk/record/123")
      expect(record.published_at).to be_nil
    end

    it "answers 422 with the alert and persists nothing when the amount is negative" do
      post "/admin/contracts", params: {
        contract: { title: "Road reconstruction", reference: "ZP-2026-006", amount: "-5" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to be_present
      expect(Decidim::ContractsSk::Contract.count).to eq(0)
    end

    it "answers 422 with the alert and persists nothing when the amount is a non-numeric string" do
      # The :decimal cast would silently zero "abc"; the form's strict
      # format guard must catch it before the command boundary (#75 review).
      post "/admin/contracts", params: {
        contract: { title: "Road reconstruction", reference: "ZP-2026-007", amount: "abc" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to be_present
      expect(Decidim::ContractsSk::Contract.count).to eq(0)
    end

    it "answers 422 and leaves the record untouched when an update posts a non-numeric amount" do
      record = Decidim::ContractsSk::Contract.create!(contract_attributes)

      patch "/admin/contracts/#{record.id}", params: {
        contract: { title: "Road reconstruction", reference: "ZP-2026-001", amount: "abc" }
      }

      expect(response).to have_http_status(:unprocessable_entity)

      record.reload
      expect(record.title).to eq("Road reconstruction")
      expect(record.amount).to be_nil
    end

    it "answers 422 with the alert and persists nothing when the currency is outside the allowlist" do
      post "/admin/contracts", params: {
        contract: { title: "Road reconstruction", reference: "ZP-2026-008", currency: "USD" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::Contract.count).to eq(0)
    end

    it "answers 422 with the alert and persists nothing when the CRZ URL is not http(s)" do
      post "/admin/contracts", params: {
        contract: { title: "Road reconstruction", reference: "ZP-2026-010", crz_url: "javascript:alert(1)" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::Contract.count).to eq(0)
    end

    it "updates a returned contract too (returned is editable)" do
      record = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "returned"))

      patch "/admin/contracts/#{record.id}",
            params: { contract: { title: "Revised after review", reference: "ZP-2026-001" } }

      expect(response).to redirect_to("/admin/contracts")
      record.reload
      expect(record.title).to eq("Revised after review")
      expect(record.state).to eq("returned")
    end

    it "answers 422 and persists nothing when the title is missing" do
      post "/admin/contracts", params: { contract: { title: "", reference: "ZP-2026-004" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::Contract.count).to eq(0)
    end

    it "answers 422 and persists nothing on a duplicate (organization, reference)" do
      Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts", params: { contract: { title: "Another road", reference: "ZP-2026-001" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::Contract.count).to eq(1)
    end

    it "denies an editor on an in_review contract, leaving the row untouched" do
      record = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      patch "/admin/contracts/#{record.id}",
            params: { contract: { title: "Sneaky edit", reference: "ZP-2026-009" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      record.reload
      expect(record.title).to eq("Road reconstruction")
      expect(record.reference).to eq("ZP-2026-001")
    end

    it "denies an editor on a published contract, leaving the row untouched" do
      record = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "published"))

      patch "/admin/contracts/#{record.id}",
            params: { contract: { title: "Sneaky edit", reference: "ZP-2026-009" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      record.reload
      expect(record.title).to eq("Road reconstruction")
      expect(record.state).to eq("published")
    end

    it "denies a reviewer-only user on create" do
      # Local override on the same config-time seam; the group's around hook
      # restores the ambient resolver afterwards either way.
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }

      post "/admin/contracts", params: valid_params

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Contract.count).to eq(0)
    end

    it "denies a reviewer-only user on update, leaving the content fields untouched" do
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      record = Decidim::ContractsSk::Contract.create!(contract_attributes)

      patch "/admin/contracts/#{record.id}", params: {
        contract: { title: "Tampered", reference: "ZP-2026-009", amount: "-5" }
      }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)

      record.reload
      expect(record.title).to eq("Road reconstruction")
      expect(record.amount).to be_nil
    end

    it "ignores injected state, source, published_at and author params on create and update" do
      # Negative param-injection probe: the form allow-list (and the
      # commands' explicit attribute writes) must keep lifecycle state,
      # provenance, the system-stamped published_at and authorship out of
      # form reach (civora-org/civora-platform#75).
      other_author = Decidim::User.create!
      injected = {
        state: "published",
        source: "crz",
        published_at: "2026-01-01 00:00:00",
        decidim_author_id: other_author.id
      }

      post "/admin/contracts", params: { contract: valid_params[:contract].merge(injected) }

      expect(response).to redirect_to("/admin/contracts")
      record = Decidim::ContractsSk::Contract.find_by!(reference: "ZP-2026-002")
      expect(record.state).to eq("draft")
      expect(record.source).to eq("editorial")
      expect(record.published_at).to be_nil
      expect(record.author).to eq(author)

      patch "/admin/contracts/#{record.id}", params: { contract: valid_params[:contract].merge(injected) }

      expect(response).to redirect_to("/admin/contracts")
      record.reload
      expect(record.state).to eq("draft")
      expect(record.source).to eq("editorial")
      expect(record.published_at).to be_nil
      expect(record.author).to eq(author)
      expect(record.decidim_author_id).to eq(author.id)
    end

    it "hides another organization's contract from admin edit and update (scoped find raises)" do
      # Tenant isolation: contracts_scope filters on the acting
      # organization, so a foreign record is invisible — the scoped find
      # raises ActiveRecord::RecordNotFound (rendered as 404 in a real
      # deployment with exceptions enabled), not merely permission-denied.
      # The dummy test env does not rescue it, so the raise itself is the
      # asserted contract-not-found behavior.
      foreign_org = Decidim::Organization.create!
      foreign = Decidim::ContractsSk::Contract.create!(contract_attributes(organization: foreign_org))

      expect do
        get "/admin/contracts/#{foreign.id}/edit"
      end.to raise_error(ActiveRecord::RecordNotFound)

      expect do
        patch "/admin/contracts/#{foreign.id}",
              params: { contract: { title: "Cross-org tamper", reference: "ZP-2026-777" } }
      end.to raise_error(ActiveRecord::RecordNotFound)

      foreign.reload
      expect(foreign.title).to eq("Road reconstruction")
      expect(foreign.reference).to eq("ZP-2026-001")
      expect(foreign.state).to eq("draft")
    end

    it "renders the index with the localized empty state when the organization has no contracts yet" do
      get "/admin/contracts"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No contracts have been created yet.")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
