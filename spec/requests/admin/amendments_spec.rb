# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin amendment management (M02-05-B,
# civora-org/civora-platform#65), run against the Stage-1 dummy harness
# (spec/dummy mounts the engine at "/"). Two layers, one file — mirroring
# parties_spec.rb:
#
# * The default (offline, DB-free) group pins the DENIED paths. The harness'
#   Devise-ish seam (current_user / current_organization) is stubbed
#   per-example with allow_any_instance_of, the engine role resolver is
#   swapped on the config-time seam, and BOTH record lookups are stubbed:
#   the controller deliberately loads the contract (and the amendment
#   through it) BEFORE the permission check (the check needs the
#   amendment's draft state), and an AR lookup would need a connection.
#
# * The :db groups (CONTRACTS_SK_DB=1) pin the allowed, validation and
#   tenant-isolation paths against the real migrations on an in-memory
#   SQLite adapter — including the end-to-end publish flow (snapshot,
#   stamp and audit row).
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
FakeAmendmentUser = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design: every denial must prove which gate fired, and every success must
# prove what reached the database.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin amendment management", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [], user: FakeAmendmentUser.new(engine_roles: roles))
    controller = Decidim::ContractsSk::Admin::AmendmentsController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  # The controller loads the parent contract (and the amendment through it)
  # before the permission check; offline there is no connection, so the
  # tenant-scoped lookup itself is the seam. The contract double needs what
  # the permission layer reads (state); the amendment double only what a
  # granted action would touch.
  def stub_record_lookups(contract: double(state: "published"), amendment: double)
    allow_any_instance_of(Decidim::ContractsSk::Admin::AmendmentsController)
      .to receive(:contracts_scope)
      .and_return(double(find: contract))
    allow(contract).to receive(:amendments).and_return(double(find: amendment))
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous visitor from the amendment index with the auth flash, not the permission flash" do
      get "/admin/contracts/1/amendments"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "bounces an anonymous POST before any permission work happens" do
      post "/admin/contracts/1/amendments", params: { amendment: { summary: "Forged" } }

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user on the amendment index with the permission flash" do
      sign_in(roles: [])
      stub_record_lookups

      get "/admin/contracts/1/amendments"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a reviewer on the new-amendment form (reviewers never draft)" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups

      get "/admin/contracts/1/amendments/new"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on create, with the record lookup stubbed" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups

      post "/admin/contracts/1/amendments", params: { amendment: { summary: "Forged" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on the new-amendment form when the contract is not published" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "in_review"))

      get "/admin/contracts/1/amendments/new"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on update when the amendment is published, with the amendment lookup stubbed" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "published"), amendment: double(state: "published"))

      patch "/admin/contracts/1/amendments/9", params: { amendment: { summary: "Tampered" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on publish when the amendment is already published" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "published"), amendment: double(state: "published"))

      post "/admin/contracts/1/amendments/9/publish"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on destroy when the amendment is already published" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "published"), amendment: double(state: "published"))

      delete "/admin/contracts/1/amendments/9"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on edit even for a draft amendment" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups(contract: double(state: "published"), amendment: double(state: "draft",
                                                                                  summary: "Draft change"))

      get "/admin/contracts/1/amendments/9/edit"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end
  end

  describe "allowed, validation and tenant paths", :db do
    let(:resolver_roles) { %i[editor] }
    let(:valid_params) { { amendment: { summary: "Extended delivery deadline" } } }

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

      controller = Decidim::ContractsSk::Admin::AmendmentsController

      allow_any_instance_of(controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    # Amendments are seeded onto published contracts only (ADR-006). The
    # ADR-007 invariant (#91) rides along: the normal flow confirms the
    # privacy redaction before (or at latest at) publication, so the
    # seeded parents carry the stamp — amendment publication backstops on
    # it.
    def create_contract!(overrides = {})
      Decidim::ContractsSk::Contract
        .create!(contract_attributes(state: "published", redaction_confirmed_at: Time.current).merge(overrides))
    end

    it "adds a draft amendment to a published contract for an editor and redirects to the index" do
      contract = create_contract!

      post "/admin/contracts/#{contract.id}/amendments", params: valid_params

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/amendments")
      expect(flash[:notice]).to be_present

      amendment = contract.amendments.reload.sole
      expect(amendment).to be_draft
      expect(amendment.version).to eq(1)
      expect(amendment.summary).to eq("Extended delivery deadline")
      expect(amendment.organization).to eq(organization)
      expect(amendment.author).to eq(author)
    end

    it "renders the amendment index with version, summary, state and the draft controls" do
      contract = create_contract!
      draft = contract.amendments.create!(version: 1, summary: "Draft change",
                                          organization: organization, author: author)
      published = contract.amendments.create!(version: 2, summary: "Published change", state: "published",
                                              published_at: Time.utc(2026, 9, 2, 12, 0, 0),
                                              organization: organization, author: author)

      get "/admin/contracts/#{contract.id}/amendments"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Draft change")
        expect(response.body).to include("Published change")
        expect(response.body).to include("Draft")
        expect(response.body).to include("Published")
        expect(response.body).to include("data-confirm")
        # Draft rows carry the publish/remove POST targets; published rows
        # render bare (immutable, ADR-006).
        expect(response.body).not_to include(%(action="/admin/contracts/#{contract.id}/amendments/#{published.id}"))
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/amendments/#{draft.id}"))
      end
    end

    it "renders the amendment index with the localized empty state when the contract has no amendments" do
      contract = create_contract!

      get "/admin/contracts/#{contract.id}/amendments"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No amendments have been added to this contract yet.")
    end

    it "links the amendment index from the contract edit page" do
      # The edit page serves editable records (the :update gate), so a
      # plain draft record is the right fixture here.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      # The edit page is served by the contracts controller, so its Devise-ish
      # seam needs the same per-example stubbing (this file's `before` only
      # covers the amendments controller).
      edit_controller = Decidim::ContractsSk::Admin::ContractsController
      allow_any_instance_of(edit_controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(edit_controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(edit_controller).to receive(:current_organization).and_return(organization)

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="/admin/contracts/#{contract.id}/amendments"))
    end

    it "updates a draft's summary for an editor and redirects to the index" do
      contract = create_contract!
      amendment = contract.amendments.create!(version: 1, summary: "Draft change",
                                              organization: organization, author: author)

      patch "/admin/contracts/#{contract.id}/amendments/#{amendment.id}",
            params: { amendment: { summary: "Retitled amendment" } }

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/amendments")
      expect(flash[:notice]).to be_present
      expect(amendment.reload.summary).to eq("Retitled amendment")
    end

    it "removes a draft for an editor and redirects to the index" do
      contract = create_contract!
      amendment = contract.amendments.create!(version: 1, summary: "Draft change",
                                              organization: organization, author: author)

      expect do
        delete "/admin/contracts/#{contract.id}/amendments/#{amendment.id}"
      end.to change(Decidim::ContractsSk::Amendment, :count).by(-1)

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/amendments")
      expect(flash[:notice]).to be_present
      expect(Decidim::ContractsSk::Amendment.exists?(amendment.id)).to be(false)
    end

    it "publishes a draft end-to-end: snapshot, stamp, version and audit row" do
      contract = create_contract!(
        subject_matter: "Supply and installation of road signage",
        amount: BigDecimal("1250.50"),
        signed_on: Date.new(2026, 9, 1),
        effective_from: Date.new(2026, 8, 15),
        crz_url: "https://crz.gov.sk/record/123"
      )
      amendment = contract.amendments.create!(version: 1, summary: "Draft change",
                                              organization: organization, author: author)

      expect do
        post "/admin/contracts/#{contract.id}/amendments/#{amendment.id}/publish"
      end.to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/amendments")
      expect(flash[:notice]).to be_present

      amendment.reload
      expect(amendment).to be_published
      expect(amendment.published_at).to be_present
      expect(amendment.content_snapshot).to eq(
        "subject_matter" => "Supply and installation of road signage",
        "amount" => "1250.5",
        "currency" => "EUR",
        "signed_on" => "2026-09-01",
        "effective_from" => "2026-08-15",
        "crz_url" => "https://crz.gov.sk/record/123"
      )

      audit = Decidim::ContractsSk::AuditEvent.order(:id).last
      expect(audit.action).to eq("amendment.publish")
      expect(audit.target_id).to eq(amendment.id)
    end

    it "answers 422 with the alert and persists nothing when the summary is blank" do
      contract = create_contract!

      post "/admin/contracts/#{contract.id}/amendments",
           params: { amendment: { summary: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to be_present
      expect(Decidim::ContractsSk::Amendment.count).to eq(0)
      # The re-rendered form (civora-org/civora-platform#78): the announced,
      # focused error summary and the required attribute on the
      # presence-validated summary input.
      aggregate_failures do
        expect(response.body).to include('role="alert"')
        expect(response.body).to include("autofocus")
        expect(response.body).to include('required="required"')
      end
    end

    it "denies a reviewer-only user on create" do
      # Local override on the same config-time seam; the group's around hook
      # restores the ambient resolver afterwards either way.
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      contract = create_contract!

      post "/admin/contracts/#{contract.id}/amendments", params: valid_params

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Amendment.count).to eq(0)
    end

    it "denies an editor on a contract that is not published, leaving the rows untouched" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      post "/admin/contracts/#{contract.id}/amendments", params: valid_params

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Amendment.count).to eq(0)
    end

    it "denies the member writes on a published amendment (draft-only, ADR-006)" do
      contract = create_contract!
      amendment = contract.amendments.create!(version: 1, summary: "Frozen change", state: "published",
                                              published_at: Time.utc(2026, 9, 2, 12, 0, 0),
                                              organization: organization, author: author)

      aggregate_failures do
        patch "/admin/contracts/#{contract.id}/amendments/#{amendment.id}",
              params: { amendment: { summary: "Tampered" } }
        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq(unauthorized)

        post "/admin/contracts/#{contract.id}/amendments/#{amendment.id}/publish"
        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq(unauthorized)

        delete "/admin/contracts/#{contract.id}/amendments/#{amendment.id}"
        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq(unauthorized)
      end

      amendment.reload
      expect(amendment.summary).to eq("Frozen change")
      expect(amendment).to be_published
    end

    it "hides another organization's contract's amendments from every verb (scoped find raises)" do
      # Tenant isolation: contracts_scope filters on the acting
      # organization, so a foreign contract — and with it its amendments —
      # is invisible; the scoped find raises ActiveRecord::RecordNotFound
      # (rendered as 404 in a real deployment with exceptions enabled), not
      # merely permission-denied. The dummy test env does not rescue it, so
      # the raise itself is the asserted not-found behavior.
      foreign_org = Decidim::Organization.create!
      foreign = Decidim::ContractsSk::Contract.create!(contract_attributes(organization: foreign_org,
                                                                           state: "published"))
      foreign_amendment = foreign.amendments.create!(version: 1, summary: "Foreign change",
                                                     organization: foreign_org, author: author)

      aggregate_failures do
        expect { get "/admin/contracts/#{foreign.id}/amendments" }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect { post "/admin/contracts/#{foreign.id}/amendments", params: valid_params }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect do
          patch "/admin/contracts/#{foreign.id}/amendments/#{foreign_amendment.id}",
                params: { amendment: { summary: "Tampered" } }
        end.to raise_error(ActiveRecord::RecordNotFound)
        expect { post "/admin/contracts/#{foreign.id}/amendments/#{foreign_amendment.id}/publish" }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect { delete "/admin/contracts/#{foreign.id}/amendments/#{foreign_amendment.id}" }
          .to raise_error(ActiveRecord::RecordNotFound)
      end

      foreign_amendment.reload
      expect(foreign_amendment.summary).to eq("Foreign change")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
