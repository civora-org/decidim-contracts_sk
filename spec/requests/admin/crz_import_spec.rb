# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin single-record CRZ import (ADR-008,
# civora-org/civora-platform#86), run against the Stage-1 dummy harness
# (spec/dummy mounts the engine at "/"). Two layers, one file — mirroring
# crz_handoff_spec.rb:
#
# * The default (offline, DB-free) group pins the DENIED paths and the
#   input-validation path (blank/non-numeric id never reaches the
#   network). The harness' Devise-ish seam is stubbed per-example with
#   allow_any_instance_of and the engine role resolver is swapped on the
#   config-time seam — the same pattern as the sibling request specs.
#
# * The :db groups pin the allowed paths END TO END: the transport is
#   stubbed (the engine's own injection seam), while the real Client,
#   Sync orchestrator and upsert command run against the real migrations —
#   the flash outcomes and the persisted mirrors are both real.
#
# Flash-key discipline: the harness' authenticate_user! redirects with the
# distinct literal key :dummy_authentication_required, while NeedsPermission's
# denial handler uses :alert — every denial example proves WHICH gate fired.
#
# Synthetic data only ("Obec Ukážková", fake IČO patterns), no real PII.
#
# Cop note: allow_any_instance_of is the approved seam for this harness, so
# the cop is disabled file-wide along with the dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Stand-in for a signed-in user in the offline group: only the swapped role
# resolver reads it (via engine_roles); the Devise-ish seam just needs a
# non-nil current_user.
FakeCrzImportUser = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design: every denial must prove which gate fired, every success what
# reached the database.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin CRZ import", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [], user: FakeCrzImportUser.new(engine_roles: roles))
    controller = Decidim::ContractsSk::Admin::ContractsController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  describe "denied and guarded paths (offline, DB-free)" do
    it "bounces an anonymous visitor with the auth flash, not the permission flash" do
      post "/admin/contracts/import_crz", params: { source_id: "2142424" }

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user with the permission flash" do
      sign_in(roles: [])
      post "/admin/contracts/import_crz", params: { source_id: "2142424" }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a reviewer with the permission flash (import is an editor gate)" do
      sign_in(roles: %i[reviewer])
      post "/admin/contracts/import_crz", params: { source_id: "2142424" }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "answers an editor with the localized alert when the id is blank — before any network work" do
      sign_in(roles: %i[editor])
      post "/admin/contracts/import_crz", params: { source_id: "" }

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:alert]).to eq("Enter the numeric CRZ contract id to import.")
    end

    it "answers an editor with the same alert for a non-numeric id (the CRZ id is numeric)" do
      sign_in(roles: %i[editor])
      post "/admin/contracts/import_crz", params: { source_id: "UKÁŽKA/001" }

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:alert]).to eq("Enter the numeric CRZ contract id to import.")
    end

    it "flashes the not-found outcome gracefully for an unknown source id" do
      sign_in(roles: %i[editor])
      allow(Decidim::ContractsSk::CrzImport::Sync).to receive(:import_one).and_return(:not_found)

      post "/admin/contracts/import_crz", params: { source_id: "2142424" }

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts")
        expect(flash[:alert])
          .to eq("No CRZ contract with id 2142424 was found.")
        expect(Decidim::ContractsSk::CrzImport::Sync).to have_received(:import_one)
          .with(source_id: "2142424", organization: nil, actor: an_instance_of(FakeCrzImportUser))
      end
    end
  end

  describe "allowed paths", :db do
    # The current_user belongs to the stubbed organization, like a real
    # signed-in editor — the import's actor/authorship checks read
    # actor.organization (see the shared :db support's author note).
    let(:author) { Decidim::User.create!(organization: organization) }

    # The :db group's current_user is a REAL persistence record (the author
    # column target), so the resolver decision is decoupled from the user:
    # the group pins the editor path explicitly on the config-time seam
    # (same pattern as the contracts CRUD spec's resolver_roles).
    let(:resolver_roles) { %i[editor] }

    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    include_context "with the CRZ scope configured"

    before do
      migrate_engine_schema!

      controller = Decidim::ContractsSk::Admin::ContractsController

      allow_any_instance_of(controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    # The engine's own injection seam: a stubbed transport, with the real
    # Client/Sync/command stack running over it — end to end, still offline.
    def stub_transport(*responses)
      transport = instance_double(Decidim::ContractsSk::CrzImport::Transport)
      allow(transport).to receive(:get).and_return(*responses)
      allow(Decidim::ContractsSk::CrzImport::Transport).to receive(:new).and_return(transport)
    end

    def response_with(status, body: "")
      Decidim::ContractsSk::CrzImport::Transport::Result.new(
        status: status, body: body, headers: {}, error: nil
      )
    end

    it "imports one contract by CRZ id end to end: notice flash, published mirror with provenance" do
      stub_transport(response_with(200, body: crz_payload("2142424").to_json))

      post "/admin/contracts/import_crz", params: { source_id: "2142424" }

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts")
        expect(flash[:notice]).to eq("Contract 2142424 imported and published.")

        record = Decidim::ContractsSk::Contract.find_by!(source_id: "2142424")
        expect(record.state).to eq("published")
        expect(record.source).to eq("crz")
        expect(record.import_status).to eq("succeeded")
        expect(record.author).to eq(author)
        expect(record.organization).to eq(organization)
      end
    end

    it "flashes the linked notice and writes nothing when a filing-confirmed editorial record holds the id (#125)" do
      filed = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", state: "published", source_id: "2142424",
                            crz_filed_at: Time.current)
      )
      before = filed.updated_at
      stub_transport(response_with(200, body: crz_payload("2142424").to_json))

      post "/admin/contracts/import_crz", params: { source_id: "2142424" }

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts")
        expect(flash[:notice]).to eq("Contract 2142424 is already linked to a record confirmed as filed in CRZ " \
                                     "— nothing was changed.")
        expect(flash[:alert]).to be_nil
        expect(Decidim::ContractsSk::Contract.count).to eq(1)
        expect(filed.reload.updated_at).to eq(before)
      end
    end

    it "flashes the out-of-scope alert and imports nothing for another organization's contract" do
      stub_transport(response_with(200, body: crz_payload("505", "contracting_authority_cin" => "00 000 009").to_json))

      post "/admin/contracts/import_crz", params: { source_id: "505" }

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts")
        expect(flash[:alert]).to eq("Contract 505 does not involve this organization " \
                                    "(its IČO is on neither party); it was not imported.")
        expect(Decidim::ContractsSk::Contract.count).to eq(0)
      end
    end

    it "flashes the graceful not-found alert when the source answers 404" do
      stub_transport(response_with(404))

      post "/admin/contracts/import_crz", params: { source_id: "404404" }

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts")
        expect(flash[:alert]).to eq("No CRZ contract with id 404404 was found.")
        expect(Decidim::ContractsSk::Contract.count).to eq(0)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
