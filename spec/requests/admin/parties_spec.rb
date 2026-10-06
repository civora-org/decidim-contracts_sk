# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin party management (civora-org/civora-platform#76),
# run against the Stage-1 dummy harness (spec/dummy mounts the engine at "/").
# Two layers, one file — mirroring contracts_spec.rb:
#
# * The default (offline, DB-free) group pins the DENIED paths. The harness'
#   Devise-ish seam (current_user / current_organization) is stubbed
#   per-example with allow_any_instance_of, the engine role resolver is
#   swapped on the config-time seam, and BOTH record lookups are stubbed:
#   the controller deliberately loads the contract (and the party through
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
# Synthetic data only (municipality/supplier names are fictional), no real PII.
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
FakePartyUser = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design: every denial must prove which gate fired, and every success must
# prove what reached the database.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin party management", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [], user: FakePartyUser.new(engine_roles: roles))
    controller = Decidim::ContractsSk::Admin::PartiesController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  # The controller loads the parent contract (and the party through it)
  # before the permission check; offline there is no connection, so the
  # tenant-scoped lookup itself is the seam. The contract double needs only
  # what the permission layer reads (state); the party double only what a
  # granted action would touch.
  def stub_record_lookups(contract: double(state: "draft"), party: double)
    allow_any_instance_of(Decidim::ContractsSk::Admin::PartiesController)
      .to receive(:contracts_scope)
      .and_return(double(find: contract))
    allow(contract).to receive(:parties).and_return(double(find: party))
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous visitor from the party index with the auth flash, not the permission flash" do
      get "/admin/contracts/1/parties"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "bounces an anonymous POST before any permission work happens" do
      post "/admin/contracts/1/parties", params: { party: { role: "object", name: "Obec Zelen" } }

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user on the party index with the permission flash" do
      sign_in(roles: [])
      stub_record_lookups

      get "/admin/contracts/1/parties"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a reviewer on the new-party form (reviewers never draft)" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups

      get "/admin/contracts/1/parties/new"

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on create, with the record lookup stubbed" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups

      post "/admin/contracts/1/parties", params: { party: { role: "object", name: "Obec Zelen" } }

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on the new-party form when the contract is not editable" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "in_review"))

      get "/admin/contracts/1/parties/new"

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on update when the contract is not editable, with the party lookup stubbed" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "in_review"), party: double(role: "object"))

      patch "/admin/contracts/1/parties/9", params: { party: { role: "object", name: "Tampered" } }

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on destroy when the contract is not editable" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "published"), party: double(role: "object"))

      delete "/admin/contracts/1/parties/9"

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on edit even for an editable contract" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups(contract: double(state: "draft"), party: double(role: "object", name: "Obec Zelen"))

      get "/admin/contracts/1/parties/9/edit"

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end
  end

  describe "allowed, validation and tenant paths", :db do
    let(:resolver_roles) { %i[editor] }
    let(:valid_params) { { party: { role: "object", name: "Obec Zelen", ico: "12345678", address: "Hlavná 1" } } }

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

      controller = Decidim::ContractsSk::Admin::PartiesController

      allow_any_instance_of(controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    it "adds a party to a draft contract for an editor and redirects to the party index" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/parties", params: valid_params

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/parties")
      expect(flash[:notice]).to be_present

      party = contract.parties.reload.sole
      expect(party.role).to eq("object")
      expect(party.name).to eq("Obec Zelen")
      expect(party.ico).to eq("12345678")
      expect(party.address).to eq("Hlavná 1")
    end

    it "persists multiple parties with the same role (duplicate roles are legal by design)" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/parties", params: valid_params
      post "/admin/contracts/#{contract.id}/parties",
           params: { party: { role: "object", name: "Obec Zelen II" } }

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/parties")
      expect(contract.parties.where(role: "object").count).to eq(2)
    end

    it "renders the party index with the localized role label and the remove control" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      contract.parties.create!(role: "object", name: "Obec Zelen", ico: "12345678")

      get "/admin/contracts/#{contract.id}/parties"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Obec Zelen")
        expect(response.body).to include("Object party")
        expect(response.body).to include("data-confirm")
        expect(response.body)
          .to include(%(action="/admin/contracts/#{contract.id}/parties/#{contract.parties.sole.id}"))
      end
    end

    it "renders the party index with the localized empty state when the contract has no parties" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      get "/admin/contracts/#{contract.id}/parties"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No parties have been added to this contract yet.")
    end

    it "links the party index from the contract edit page" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      # The edit page is served by the contracts controller, so its Devise-ish
      # seam needs the same per-example stubbing (this file's `before` only
      # covers the parties controller).
      edit_controller = Decidim::ContractsSk::Admin::ContractsController
      allow_any_instance_of(edit_controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(edit_controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(edit_controller).to receive(:current_organization).and_return(organization)

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="/admin/contracts/#{contract.id}/parties"))
    end

    it "updates a party's fields for an editor and redirects to the party index" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      party = contract.parties.create!(role: "object", name: "Obec Zelen")

      patch "/admin/contracts/#{contract.id}/parties/#{party.id}",
            params: { party: { role: "contractor", name: "Zeleň a.s.", ico: "87654321" } }

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/parties")
      expect(flash[:notice]).to be_present

      party.reload
      expect(party.role).to eq("contractor")
      expect(party.name).to eq("Zeleň a.s.")
      expect(party.ico).to eq("87654321")
    end

    it "removes a party for an editor and redirects to the party index" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      party = contract.parties.create!(role: "object", name: "Obec Zelen")

      expect do
        delete "/admin/contracts/#{contract.id}/parties/#{party.id}"
      end.to change(Decidim::ContractsSk::Party, :count).by(-1)

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/parties")
      expect(flash[:notice]).to be_present
      expect(Decidim::ContractsSk::Party.exists?(party.id)).to be(false)
    end

    it "answers 422 with the alert and persists nothing when the ico is not 8 digits" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/parties",
           params: { party: { role: "object", name: "Obec Zelen", ico: "1234" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to be_present
      expect(Decidim::ContractsSk::Party.count).to eq(0)
      # The re-rendered form (civora-org/civora-platform#78, #79): the
      # error summary is announced/focused, the required name input carries
      # the attribute, and the IČO hint is wired through aria-describedby.
      aggregate_failures do
        expect(response.body).to include('role="alert"')
        expect(response.body).to include("autofocus")
        expect(response.body).to include('aria-describedby="party_ico_hint"')
        expect(response.body).to include("Leave blank or enter exactly 8 digits.")
        expect(response.body).to include('required="required"')
      end
    end

    it "answers 422 with the alert and persists nothing when the role is outside the vocabulary" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/parties",
           params: { party: { role: "bogus", name: "Obec Zelen" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::Party.count).to eq(0)
    end

    it "answers 422 with the alert and leaves the row unchanged when an update fails" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      party = contract.parties.create!(role: "object", name: "Obec Zelen")

      patch "/admin/contracts/#{contract.id}/parties/#{party.id}",
            params: { party: { role: "contractor", name: "Obec Zelen", ico: "1234" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to be_present
      party.reload
      expect(party.role).to eq("object")
      expect(party.ico).to be_nil
    end

    it "denies a reviewer-only user on create" do
      # Local override on the same config-time seam; the group's around hook
      # restores the ambient resolver afterwards either way.
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/parties", params: valid_params

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Party.count).to eq(0)
    end

    it "denies an editor on an in_review contract, leaving the rows untouched" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))
      party = contract.parties.create!(role: "object", name: "Obec Zelen")

      post "/admin/contracts/#{contract.id}/parties", params: valid_params

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Party.count).to eq(1)

      delete "/admin/contracts/#{contract.id}/parties/#{party.id}"

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Party.exists?(party.id)).to be(true)
    end

    it "hides another organization's contract's parties from every verb (scoped find raises)" do
      # Tenant isolation: contracts_scope filters on the acting
      # organization, so a foreign contract — and with it its parties — is
      # invisible; the scoped find raises ActiveRecord::RecordNotFound
      # (rendered as 404 in a real deployment with exceptions enabled), not
      # merely permission-denied. The dummy test env does not rescue it, so
      # the raise itself is the asserted not-found behavior.
      foreign_org = Decidim::Organization.create!
      foreign = Decidim::ContractsSk::Contract.create!(contract_attributes(organization: foreign_org))
      foreign_party = foreign.parties.create!(role: "object", name: "Foreign")

      aggregate_failures do
        expect { get "/admin/contracts/#{foreign.id}/parties" }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect { post "/admin/contracts/#{foreign.id}/parties", params: valid_params }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect do
          patch "/admin/contracts/#{foreign.id}/parties/#{foreign_party.id}",
                params: { party: { role: "object", name: "Tampered" } }
        end.to raise_error(ActiveRecord::RecordNotFound)
        expect { delete "/admin/contracts/#{foreign.id}/parties/#{foreign_party.id}" }
          .to raise_error(ActiveRecord::RecordNotFound)
      end

      foreign_party.reload
      expect(foreign_party.name).to eq("Foreign")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
