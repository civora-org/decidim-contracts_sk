# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin project/result link management (M01-87,
# civora-org/civora-platform#87), run against the Stage-1 dummy harness
# (spec/dummy mounts the engine at "/"). Two layers, one file — mirroring
# parties_spec.rb:
#
# * The default (offline, DB-free) group pins the DENIED paths. The harness'
#   Devise-ish seam (current_user / current_organization) is stubbed
#   per-example with allow_any_instance_of, the engine role resolver is
#   swapped on the config-time seam, and BOTH record lookups are stubbed:
#   the controller deliberately loads the contract (and the link through
#   it) BEFORE the permission check (the check needs the contract's
#   lifecycle state), and an AR lookup would need a connection.
#
# * The :db groups (CONTRACTS_SK_DB=1) pin the allowed, validation and
#   tenant-isolation paths against the real migrations on an in-memory
#   SQLite adapter.
#
# Flash-key discipline: the harness' authenticate_user! redirects with the
# distinct literal key :dummy_authentication_required, while NeedsPermission's
# denial handler uses :alert — every denial example proves WHICH gate fired.
#
# Synthetic data only, no real PII.
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
FakeLinkUser = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design: every denial must prove which gate fired, and every success must
# prove what reached the database.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin link management", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }
  let(:supported_type) { "Decidim::Accountability::Result" }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [], user: FakeLinkUser.new(engine_roles: roles))
    controller = Decidim::ContractsSk::Admin::LinksController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  # The controller loads the parent contract (and the link through it)
  # before the permission check; offline there is no connection, so the
  # tenant-scoped lookup itself is the seam. The contract double needs only
  # what the permission layer reads (state); the link double only what a
  # granted action would touch.
  def stub_record_lookups(contract: double(state: "draft"), link: double)
    allow_any_instance_of(Decidim::ContractsSk::Admin::LinksController)
      .to receive(:contracts_scope)
      .and_return(double(find: contract))
    allow(contract).to receive(:links).and_return(double(find: link))
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous visitor from create with the auth flash, not the permission flash" do
      post "/admin/contracts/1/links", params: { link: { target_type: supported_type, target_id: "12" } }

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "bounces an anonymous DELETE before any permission work happens" do
      delete "/admin/contracts/1/links/9"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user on create with the permission flash" do
      sign_in(roles: [])
      stub_record_lookups

      post "/admin/contracts/1/links", params: { link: { target_type: supported_type, target_id: "12" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a reviewer on create (reviewers never draft)" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups

      post "/admin/contracts/1/links", params: { link: { target_type: supported_type, target_id: "12" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on create when the contract is not editable" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "published"))

      post "/admin/contracts/1/links", params: { link: { target_type: supported_type, target_id: "12" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on destroy when the contract is not editable, with the link lookup stubbed" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "in_review"), link: double(target_type: supported_type))

      delete "/admin/contracts/1/links/9"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on destroy even for an editable contract" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups(contract: double(state: "draft"), link: double(target_type: supported_type))

      delete "/admin/contracts/1/links/9"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end
  end

  describe "allowed, validation and tenant paths", :db do
    let(:resolver_roles) { %i[editor] }
    let(:valid_params) { { link: { target_type: supported_type, target_id: "12" } } }

    # Role control per group: the resolver defaults to editor, keeping the
    # role decision explicit and deterministic. The link whitelist seam is
    # configured for the group too, so a create can actually pass the form.
    around do |example|
      original_roles = Decidim::ContractsSk.role_resolver
      original_types = Decidim::ContractsSk.supported_link_target_types
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
      Decidim::ContractsSk.supported_link_target_types = [supported_type]
      example.run
      Decidim::ContractsSk.role_resolver = original_roles
      Decidim::ContractsSk.supported_link_target_types = original_types
    end

    before do
      migrate_engine_schema!

      controller = Decidim::ContractsSk::Admin::LinksController

      allow_any_instance_of(controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    it "adds a link to a draft contract for an editor and redirects to the contract edit page" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/links", params: valid_params

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present

      link = contract.links.reload.sole
      expect(link.target_type).to eq(supported_type)
      expect(link.target_id).to eq(12)
    end

    it "renders the links list with the dangling flag and remove control on the edit page" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      contract.links.create!(target_type: supported_type, target_id: 4_242_424)

      # The edit page is served by the contracts controller, so its Devise-ish
      # seam needs the same per-example stubbing (this file's `before` only
      # covers the links controller).
      edit_controller = Decidim::ContractsSk::Admin::ContractsController
      allow_any_instance_of(edit_controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(edit_controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(edit_controller).to receive(:current_organization).and_return(organization)

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        # The target does not exist and the ambient seam resolves nothing,
        # so the row renders with the explicit dangling flag.
        expect(response.body).to include(supported_type)
        expect(response.body).to include("Target no longer available")
        expect(response.body).to include("data-confirm")
        expect(response.body)
          .to include(%(action="/admin/contracts/#{contract.id}/links/#{contract.links.sole.id}"))
      end
    end

    it "renders the localized empty state when the contract has no links" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      edit_controller = Decidim::ContractsSk::Admin::ContractsController
      allow_any_instance_of(edit_controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(edit_controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(edit_controller).to receive(:current_organization).and_return(organization)

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No links have been added to this contract yet.")
    end

    it "removes a link for an editor and redirects to the contract edit page" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      link = contract.links.create!(target_type: supported_type, target_id: 12)

      expect do
        delete "/admin/contracts/#{contract.id}/links/#{link.id}"
      end.to change(Decidim::ContractsSk::ContractLink, :count).by(-1)

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present
      expect(Decidim::ContractsSk::ContractLink.exists?(link.id)).to be(false)
    end

    it "answers with the alert and persists nothing when the target type is outside the whitelist" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/links",
           params: { link: { target_type: "Decidim::User", target_id: "12" } }

      expect(flash[:alert]).to be_present
      expect(Decidim::ContractsSk::ContractLink.count).to eq(0)
    end

    it "answers with the alert and persists nothing when the target id is not numeric" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/links",
           params: { link: { target_type: supported_type, target_id: "12abc" } }

      expect(flash[:alert]).to be_present
      expect(Decidim::ContractsSk::ContractLink.count).to eq(0)
    end

    it "denies a reviewer-only user on create" do
      # Local override on the same config-time seam; the group's around hook
      # restores the ambient resolver afterwards either way.
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/links", params: valid_params

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::ContractLink.count).to eq(0)
    end

    it "denies an editor on a published contract, leaving the rows untouched" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "published"))
      link = contract.links.create!(target_type: supported_type, target_id: 12)

      post "/admin/contracts/#{contract.id}/links", params: valid_params

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::ContractLink.count).to eq(1)

      delete "/admin/contracts/#{contract.id}/links/#{link.id}"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::ContractLink.exists?(link.id)).to be(true)
    end

    it "hides another organization's contract's links from every verb (scoped find raises)" do
      # Tenant isolation: contracts_scope filters on the acting
      # organization, so a foreign contract — and with it its links — is
      # invisible; the scoped find raises ActiveRecord::RecordNotFound
      # (rendered as 404 in a real deployment with exceptions enabled), not
      # merely permission-denied. The dummy test env does not rescue it, so
      # the raise itself is the asserted not-found behavior.
      foreign_org = Decidim::Organization.create!
      foreign = Decidim::ContractsSk::Contract.create!(contract_attributes(organization: foreign_org))
      foreign_link = foreign.links.create!(target_type: supported_type, target_id: 12)

      aggregate_failures do
        expect { post "/admin/contracts/#{foreign.id}/links", params: valid_params }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect { delete "/admin/contracts/#{foreign.id}/links/#{foreign_link.id}" }
          .to raise_error(ActiveRecord::RecordNotFound)
      end

      expect(foreign_link.reload).to be_present
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
