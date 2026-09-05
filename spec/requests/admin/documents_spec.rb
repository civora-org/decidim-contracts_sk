# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin document management (civora-org/civora-platform
# #73), run against the Stage-1 dummy harness (spec/dummy mounts the engine
# at "/"). Two layers, one file — mirroring parties_spec.rb:
#
# * The default (offline, DB-free) group pins the DENIED paths. The harness'
#   Devise-ish seam (current_user / current_organization) is stubbed
#   per-example with allow_any_instance_of, the engine role resolver is
#   swapped on the config-time seam, and BOTH record lookups are stubbed:
#   the controller deliberately loads the contract (and the document through
#   it) BEFORE the permission check (the check needs the contract's
#   lifecycle state), and an AR lookup would need a connection.
#
# * The :db groups (CONTRACTS_SK_DB=1) pin the allowed, validation and
#   tenant-isolation paths against the real migrations plus the
#   ActiveStorage tables (host-app-owned schema; built here from the pinned
#   gem's own migration) on an in-memory SQLite adapter.
#
# Flash-key discipline: the harness' authenticate_user! redirects with the
# distinct literal key :dummy_authentication_required, while NeedsPermission's
# denial handler uses :alert — every denial example proves WHICH gate fired.
#
# Synthetic fixtures only (PDF-shaped/text bytes, no real content, no PII).
#
# Cop note: allow_any_instance_of is the approved seam for this harness (see
# parties_spec.rb), so the cop is disabled file-wide along with the
# dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Stand-in for a signed-in user in the offline group: only the swapped role
# resolver reads it (via engine_roles); the Devise-ish seam just needs a
# non-nil current_user. Distinct from the other request specs' fakes so the
# spec files stay independent.
FakeDocumentUser = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design: every denial must prove which gate fired, and every success must
# prove what reached the database.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin document management", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [], user: FakeDocumentUser.new(engine_roles: roles))
    controller = Decidim::ContractsSk::Admin::DocumentsController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  # The controller loads the parent contract (and the document through it)
  # before the permission check; offline there is no connection, so the
  # tenant-scoped lookup itself is the seam. The contract double needs only
  # what the permission layer reads (state); the document double only what a
  # granted action would touch.
  def stub_record_lookups(contract: double(state: "draft"), document: double)
    allow_any_instance_of(Decidim::ContractsSk::Admin::DocumentsController)
      .to receive(:contracts_scope)
      .and_return(double(find: contract))
    allow(contract).to receive(:documents).and_return(double(find: document))
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous visitor from the attach form with the auth flash, not the permission flash" do
      get "/admin/contracts/1/documents/new"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "bounces an anonymous POST before any permission work happens" do
      post "/admin/contracts/1/documents", params: { document: { title: "Scan", kind: "contract" } }

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user on the attach form with the permission flash" do
      sign_in(roles: [])
      stub_record_lookups

      get "/admin/contracts/1/documents/new"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "denies a reviewer on the attach form (reviewers never draft)" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups

      get "/admin/contracts/1/documents/new"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on create, with the record lookup stubbed" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups

      post "/admin/contracts/1/documents", params: { document: { title: "Scan", kind: "contract" } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on the attach form when the contract is not editable" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "in_review"))

      get "/admin/contracts/1/documents/new"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on replace when the contract is not editable, with the document lookup stubbed" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "in_review"), document: double(title: "Scan", kind: "contract"))

      patch "/admin/contracts/1/documents/9",
            params: { document: { file: fixture_file_upload("spec/fixtures/files/sample.pdf") } }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on destroy when the contract is not editable" do
      sign_in(roles: %i[editor])
      stub_record_lookups(contract: double(state: "published"), document: double(title: "Scan"))

      delete "/admin/contracts/1/documents/9"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies a reviewer on the replace form even for an editable contract" do
      sign_in(roles: %i[reviewer])
      stub_record_lookups(contract: double(state: "draft"), document: double(title: "Scan", kind: "contract"))

      get "/admin/contracts/1/documents/9/edit"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
    end
  end

  describe "allowed, validation and tenant paths", :db do
    let(:resolver_roles) { %i[editor] }

    def sample_fixture(name)
      # This file sits at spec/requests/admin/, so three levels up is the
      # engine root.
      File.expand_path("../../../spec/fixtures/files/#{name}", __dir__)
    end

    def upload(name, content_type)
      Rack::Test::UploadedFile.new(sample_fixture(name), content_type)
    end

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

      controller = Decidim::ContractsSk::Admin::DocumentsController

      allow_any_instance_of(controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    it "attaches a document for an editor and syncs the metadata columns from the blob" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/documents", params: {
        document: { title: "Signed contract scan", kind: "contract", file: upload("sample.pdf", "application/pdf") }
      }

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present

      document = contract.documents.reload.sole
      aggregate_failures do
        expect(document.title).to eq("Signed contract scan")
        expect(document.kind).to eq("contract")
        expect(document.file_name).to eq("sample.pdf")
        expect(document.content_type).to eq("application/pdf")
        expect(document.file_size).to eq(File.size(sample_fixture("sample.pdf")))
      end
    end

    it "renders the attach form with the localized labels" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      get "/admin/contracts/#{contract.id}/documents/new"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("New document")
        expect(response.body).to include("Contract document")
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/documents"))
        expect(response.body).to include("multipart")
        # The generated handoff artifact's kind is never offered
        # (civora-org/civora-platform#74).
        expect(response.body).not_to include("CRZ export")
      end
    end

    it "renders the replace form with the record's content fields read-only" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      document = contract.documents.create!(title: "Signed contract scan", kind: "annex")

      get "/admin/contracts/#{contract.id}/documents/#{document.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Signed contract scan")
        expect(response.body).to include("Annex")
        # No title/kind inputs on the replace page — a replace swaps the
        # file only.
        expect(response.body).not_to include("document[title]")
        expect(response.body).not_to include("document[kind]")
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/documents/#{document.id}"))
      end
    end

    it "replaces a document's file for an editor and re-syncs the metadata" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      document = contract.documents.create!(title: "Signed contract scan", kind: "annex")
      document.attach_file!(upload("sample-notes.txt", "text/plain"))

      patch "/admin/contracts/#{contract.id}/documents/#{document.id}", params: {
        document: { file: upload("sample.pdf", "application/pdf") }
      }

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present

      document.reload
      aggregate_failures do
        expect(document.file_name).to eq("sample.pdf")
        expect(document.content_type).to eq("application/pdf")
        expect(document.title).to eq("Signed contract scan")
        expect(document.kind).to eq("annex")
      end
    end

    it "lists the documents with replace and remove controls on the contract edit page" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      document = contract.documents.create!(title: "Signed contract scan", kind: "contract")

      # The edit page is served by the contracts controller, so its Devise-ish
      # seam needs the same per-example stubbing (this file's `before` only
      # covers the documents controller).
      edit_controller = Decidim::ContractsSk::Admin::ContractsController
      allow_any_instance_of(edit_controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(edit_controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(edit_controller).to receive(:current_organization).and_return(organization)

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Signed contract scan")
        expect(response.body).to include(%(href="/admin/contracts/#{contract.id}/documents/new"))
        expect(response.body).to include(%(href="/admin/contracts/#{contract.id}/documents/#{document.id}/edit"))
        expect(response.body).to include(%(action="/admin/contracts/#{contract.id}/documents/#{document.id}"))
        expect(response.body).to include("data-confirm")
      end
    end

    it "removes a document for an editor and destroys the attachment row with it" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      document = contract.documents.create!(title: "Signed contract scan", kind: "contract")
      document.attach_file!(upload("sample.pdf", "application/pdf"))
      attachment_id = document.file_attachment.id

      expect do
        delete "/admin/contracts/#{contract.id}/documents/#{document.id}"
      end.to change(Decidim::ContractsSk::Document, :count).by(-1)

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/edit")
      expect(flash[:notice]).to be_present
      aggregate_failures do
        expect(Decidim::ContractsSk::Document.exists?(document.id)).to be(false)
        expect(ActiveStorage::Attachment.exists?(attachment_id)).to be(false)
      end
    end

    it "answers 422 with the alert and persists nothing when the title is missing" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/documents", params: {
        document: { title: "", kind: "contract", file: upload("sample.pdf", "application/pdf") }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to be_present
      expect(Decidim::ContractsSk::Document.count).to eq(0)
    end

    it "answers 422 with the alert and persists nothing when the file is missing" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/documents", params: {
        document: { title: "Signed contract scan", kind: "contract" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::Document.count).to eq(0)
    end

    it "answers 422 with the alert and persists nothing when the kind is outside the vocabulary" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/documents", params: {
        document: { title: "Signed contract scan", kind: "bogus", file: upload("sample.pdf", "application/pdf") }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::Document.count).to eq(0)
    end

    it "answers 422 and persists nothing when the kind is the generated artifact's (civora-org/civora-platform#74)" do
      # crz_export stays in the MODEL's vocabulary (generated artifacts land
      # there legitimately) but the upload form rejects it, so a hand-crafted
      # request cannot collide with the generated handoff document.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/documents", params: {
        document: { title: "Impostor export", kind: "crz_export", file: upload("sample.pdf", "application/pdf") }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::Document.count).to eq(0)
    end

    it "answers 422 and changes nothing when the replace path targets the generated artifact's kind" do
      # Consequence of the form-level guard: a replace pre-fills the
      # persisted kind, so a crz_export document fails the form's narrower
      # vocabulary — the artifact is regenerated through the handoff action,
      # never file-swapped here.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      document = contract.documents.create!(title: "CRZ handoff export", kind: "crz_export")
      document.attach_file!(upload("sample.pdf", "application/pdf"))

      patch "/admin/contracts/#{contract.id}/documents/#{document.id}", params: {
        document: { file: upload("sample-notes.txt", "text/plain") }
      }

      document.reload
      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(document.file_name).to eq("sample.pdf")
        expect(document.content_type).to eq("application/pdf")
      end
    end

    it "denies a reviewer-only user on create" do
      # Local override on the same config-time seam; the group's around hook
      # restores the ambient resolver afterwards either way.
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      post "/admin/contracts/#{contract.id}/documents", params: {
        document: { title: "Signed contract scan", kind: "contract", file: upload("sample.pdf", "application/pdf") }
      }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Document.count).to eq(0)
    end

    it "denies an editor on an in_review contract, leaving the rows untouched" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))
      document = contract.documents.create!(title: "Signed contract scan", kind: "contract")

      post "/admin/contracts/#{contract.id}/documents", params: {
        document: { title: "Another scan", kind: "annex", file: upload("sample.pdf", "application/pdf") }
      }

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Document.count).to eq(1)

      delete "/admin/contracts/#{contract.id}/documents/#{document.id}"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(Decidim::ContractsSk::Document.exists?(document.id)).to be(true)
    end

    it "hides another organization's contract's documents from every verb (scoped find raises)" do
      # Tenant isolation: contracts_scope filters on the acting
      # organization, so a foreign contract — and with it its documents — is
      # invisible; the scoped find raises ActiveRecord::RecordNotFound
      # (rendered as 404 in a real deployment with exceptions enabled), not
      # merely permission-denied. The dummy re-raises exceptions out of the
      # request (show_exceptions :none), so the raise itself is the asserted
      # not-found behavior.
      foreign_org = Decidim::Organization.create!
      foreign = Decidim::ContractsSk::Contract.create!(contract_attributes(organization: foreign_org))
      foreign_document = foreign.documents.create!(title: "Foreign scan", kind: "annex")

      aggregate_failures do
        expect { get "/admin/contracts/#{foreign.id}/documents/new" }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect { post "/admin/contracts/#{foreign.id}/documents", params: { document: { title: "Tampered" } } }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect do
          patch "/admin/contracts/#{foreign.id}/documents/#{foreign_document.id}",
                params: { document: { file: upload("sample.pdf", "application/pdf") } }
        end.to raise_error(ActiveRecord::RecordNotFound)
        expect { delete "/admin/contracts/#{foreign.id}/documents/#{foreign_document.id}" }
          .to raise_error(ActiveRecord::RecordNotFound)
      end

      foreign_document.reload
      expect(foreign_document.title).to eq("Foreign scan")
    end

    it "raises RecordNotFound for a nonexistent contract id and a nonexistent document id" do
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      document = contract.documents.create!(title: "Signed contract scan", kind: "contract")

      aggregate_failures do
        expect { get "/admin/contracts/#{contract.id + 100_000}/documents/new" }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect do
          patch "/admin/contracts/#{contract.id}/documents/#{document.id + 100_000}",
                params: { document: { file: upload("sample.pdf", "application/pdf") } }
        end
          .to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
