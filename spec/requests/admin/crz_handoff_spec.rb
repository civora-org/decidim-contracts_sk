# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin CRZ-handoff download/generate pair
# (M02-05-C, civora-org/civora-platform#74), run against the Stage-1 dummy
# harness (spec/dummy mounts the engine at "/"). Two layers, one file —
# mirroring documents_spec.rb:
#
# * The default (offline, DB-free) group pins the DENIED paths, plus the
#   download gate's any-state pass (an editor may fetch the artifact on a
#   non-editable contract) via stubbed lookups. The harness'
#   Devise-ish seam (current_user / current_organization) is stubbed
#   per-example with allow_any_instance_of, the engine role resolver is
#   swapped on the config-time seam, and the contract lookup is stubbed: the
#   controller deliberately loads the contract BEFORE the permission check
#   (the check needs the contract's lifecycle state), and an AR lookup would
#   need a connection.
#
# * The :db groups (CONTRACTS_SK_DB=1) pin the allowed paths against the
#   real migrations plus the ActiveStorage tables. The PDF generation runs
#   FOR REAL (Prawn is pure Ruby; the DejaVu font ships in the gem), so the
#   examples assert actual generated artifacts end to end.
#
# Flash-key discipline: the harness' authenticate_user! redirects with the
# distinct literal key :dummy_authentication_required, while NeedsPermission's
# denial handler uses :alert — every denial example proves WHICH gate fired.
#
# Synthetic fixtures only (ZP-2026-00x references), no real content, no PII.
#
# Cop note: allow_any_instance_of is the approved seam for this harness (see
# documents_spec.rb), so the cop is disabled file-wide along with the
# dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Stand-in for a signed-in user in the offline group: only the swapped role
# resolver reads it (via engine_roles); the Devise-ish seam just needs a
# non-nil current_user. Distinct from the other request specs' fakes so the
# spec files stay independent.
FakeHandoffUser = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design: every denial must prove which gate fired, and every success must
# prove what reached the database or the response body.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin CRZ handoff", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [], user: FakeHandoffUser.new(engine_roles: roles))
    controller = Decidim::ContractsSk::Admin::ContractsController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  # The controller loads the contract before the permission check; offline
  # there is no connection, so the tenant-scoped lookup itself is the seam.
  # The contract double needs only what the permission layer reads (state).
  def stub_record_lookups(contract: double(state: "draft"))
    allow_any_instance_of(Decidim::ContractsSk::Admin::ContractsController)
      .to receive(:contracts_scope)
      .and_return(double(find: contract))
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous visitor from the download with the auth flash, not the permission flash" do
      get "/admin/contracts/1/crz_handoff"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "bounces an anonymous POST (generate) before any permission work happens" do
      post "/admin/contracts/1/crz_handoff"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user on the download with the permission flash" do
      sign_in(roles: [])
      stub_record_lookups

      get "/admin/contracts/1/crz_handoff"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a signed-in roleless user on generate with the permission flash" do
      sign_in(roles: [])
      stub_record_lookups

      post "/admin/contracts/1/crz_handoff"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on the download (non-editors never hold the gate, any state)" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups(contract: double(state: "published"))

      get "/admin/contracts/1/crz_handoff"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on generate" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups

      post "/admin/contracts/1/crz_handoff"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "streams the artifact for an editor on a non-editable contract (the download gate is role-only)" do
      sign_in(roles: %i[editor])
      # The gate passes, so the controller proceeds to the artifact lookup:
      # a stubbed attached document lets the stream answer offline, and a
      # 200 %PDF body proves the permission gate did NOT fire (a denial
      # would redirect to "/" with the :alert unauthorized flash instead).
      document = double(file: double(attached?: true, download: "%PDF-offline"),
                        file_name: "crz-handoff.pdf", content_type: "application/pdf")
      stub_record_lookups(contract: double(state: "in_review", documents: double(find_by: document)))

      get "/admin/contracts/1/crz_handoff"

      expect(response).to have_http_status(:ok)
      expect(response.body).to start_with("%PDF-")
      expect(flash[:alert]).to be_nil
    end

    it "denies an editor on generate when the contract is not editable" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "in_review"))

      post "/admin/contracts/1/crz_handoff"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end
  end

  describe "allowed paths", :db do
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
      FileUtils.rm_rf(active_storage_root)

      controller = Decidim::ContractsSk::Admin::ContractsController

      allow_any_instance_of(controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    it "generates the handoff PDF for an editor and stores it as the single crz_export document" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/crz_handoff"

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present

      document = contract.documents.reload.sole
      aggregate_failures do
        expect(document.kind).to eq("crz_export")
        expect(document.title).to eq("CRZ handoff export")
        # The generated artifact's fixed name survives the filename
        # sanitizer verbatim (civora-org/civora-platform#64).
        expect(document.file_name).to eq("crz-handoff.pdf")
        expect(document.content_type).to eq("application/pdf")
        expect(document.file.download).to start_with("%PDF-")
      end
    end

    it "replaces the artifact on regeneration without ever creating a second crz_export document" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      post "/admin/contracts/#{contract.id}/crz_handoff"
      first_attachment_id = contract.documents.reload.sole.file_attachment.id

      post "/admin/contracts/#{contract.id}/crz_handoff"

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")

      document = contract.documents.reload.sole
      aggregate_failures do
        expect(Decidim::ContractsSk::Document.count).to eq(1)
        expect(document.kind).to eq("crz_export")
        expect(document.file_attachment.id).not_to eq(first_attachment_id)
      end
    end

    it "streams the generated PDF from the blob on download (no temp files, attachment disposition)" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      post "/admin/contracts/#{contract.id}/crz_handoff"

      get "/admin/contracts/#{contract.id}/crz_handoff"

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to start_with("%PDF-")
        expect(response.headers["Content-Type"]).to eq("application/pdf")
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("crz-handoff.pdf")
      end
    end

    it "redirects a download with a localized alert when nothing has been generated yet" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      get "/admin/contracts/#{contract.id}/crz_handoff"

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:alert]).to be_present
    end

    it "renders the handoff section on the edit page: generate button when absent" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("CRZ handoff")
        expect(response.body).to include("not a legal publication")
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/crz_handoff"))
        expect(response.body).not_to include(%(href="/admin/contracts/#{contract.id}/crz_handoff"))
      end
    end

    it "renders the handoff section on the edit page: download link + regenerate button when present" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      post "/admin/contracts/#{contract.id}/crz_handoff"

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include(%(href="/admin/contracts/#{contract.id}/crz_handoff"))
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/crz_handoff"))
        # The generated document shows up in the documents table too.
        expect(response.body).to include("CRZ handoff export")
      end
    end

    it "keeps the handoff section on a failed update's re-render (civora-org/civora-platform#77)" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      post "/admin/contracts/#{contract.id}/crz_handoff"
      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")

      patch "/admin/contracts/#{contract.id}",
            params: { contract: { title: "Road reconstruction", reference: "ZP-2026-001", amount: "abc" } }

      expect(response).to have_http_status(:unprocessable_entity)
      aggregate_failures do
        expect(response.body).to include(%(href="/admin/contracts/#{contract.id}/crz_handoff"))
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/crz_handoff"))
      end
    end

    it "denies an editor's generate on a non-editable contract, persisting nothing" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      post "/admin/contracts/#{contract.id}/crz_handoff"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Document.count).to eq(0)
    end

    it "allows the download on a non-editable contract while generate stays denied" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      post "/admin/contracts/#{contract.id}/crz_handoff"
      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")

      contract.update!(state: "in_review")

      # The split gates (M02-05-C review): download is editor-only on ANY
      # state — the artifact stays retrievable after the record leaves the
      # editable states.
      get "/admin/contracts/#{contract.id}/crz_handoff"

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to start_with("%PDF-")
      end

      # Generate remains :update-gated — non-editable states deny it, and no
      # second artifact appears.
      post "/admin/contracts/#{contract.id}/crz_handoff"

      aggregate_failures do
        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq(unauthorized)
        expect(Decidim::ContractsSk::Document.count).to eq(1)
      end
    end

    it "leaves the public catalogue unaffected: the handoff lists like any other document" do
      # The handoff is generated while the record is editable (draft); once
      # published, it is displayed through the existing public document
      # surface — no new public route, no public behaviour change.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/crz_handoff"
      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")

      contract.update!(state: "published")

      # The public controller is a different Devise-ish seam than the admin
      # one: its tenant scope reads current_organization off the public
      # base, so this example stubs it separately (same as the public
      # catalogue specs do).
      public_controller = Decidim::ContractsSk::ContractsController
      allow_any_instance_of(public_controller).to receive(:current_organization).and_return(organization)

      get "/#{contract.id}"

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("CRZ handoff export")
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
