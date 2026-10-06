# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin spreadsheet import (civora-org/civora-platform
# #129), against the Stage-1 dummy harness (spec/dummy mounts the engine at
# "/"). Two layers, like crz_import_spec.rb: an offline group for the denied
# paths and the :db group for the whole upload -> preview -> import flow,
# including the hostile-input cases. The harness' Devise-ish seam is stubbed
# per example. Fictional data only.
#
# Set WRITE_EVIDENCE=1 to also dump the rendered preview HTML to
# tmp/evidence/ (used for the PR evidence file; never in a normal run).
# ---------------------------------------------------------------------------

require "spec_helper"
require "tempfile"
require "fileutils"

FakeImportUser = Struct.new(:engine_roles, keyword_init: true)

# Every example proves status, flash and persistence together by design.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin spreadsheet import", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }
  let(:fixtures_dir) { File.expand_path("../../fixtures/files/spreadsheet_import", __dir__) }
  let(:controller_class) { Decidim::ContractsSk::Admin::ContractImportsController }
  let(:contract_model) { Decidim::ContractsSk::Contract }
  let(:tempfiles) { [] }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
  ensure
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles:, user: FakeImportUser.new(engine_roles: roles), organization: nil)
    allow_any_instance_of(controller_class).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller_class).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller_class).to receive(:current_organization).and_return(organization)
  end

  def upload(bytes, name: "zmluvy.csv")
    file = Tempfile.new(["import", ".csv"], binmode: true)
    file.write(bytes)
    file.flush
    tempfiles << file
    Rack::Test::UploadedFile.new(file.path, "text/csv", true, original_filename: name)
  end

  def fixture_bytes(name)
    File.binread(File.join(fixtures_dir, name))
  end

  def dump_evidence(name)
    return unless ENV["WRITE_EVIDENCE"]

    dir = File.expand_path("../../../tmp/evidence", __dir__)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, name), response.body)
  end

  after { tempfiles.each(&:close!) }

  describe "denied paths (offline, DB-free)" do
    {
      "GET the upload form" => [:get, "/admin/contracts/import"],
      "POST the dry run" => [:post, "/admin/contracts/import/preview"],
      "POST the import" => [:post, "/admin/contracts/import"]
    }.each do |label, (verb, path)|
      it "bounces an anonymous visitor on #{label} with the auth flash" do
        public_send(verb, path)

        expect(response).to redirect_to("/")
        expect(flash[:dummy_authentication_required]).to be_present
        expect(flash[:alert]).to be_nil
      end

      [[], %i[reviewer]].each do |roles|
        it "denies #{label} with the permission flash for roles #{roles.inspect}" do
          sign_in(roles: roles)
          public_send(verb, path, params: { payload: "reference,title\nDEMO-1,Cesta\n" })

          expect(response).to redirect_to(roles.empty? ? "/" : "/admin")
          expect(flash[:alert]).to eq(unauthorized)
        end
      end
    end
  end

  describe "preview and import", :db do
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[editor] }
      example.run
    ensure
      Decidim::ContractsSk.role_resolver = original
    end

    before do
      migrate_engine_schema!
      sign_in(roles: %i[editor], user: author, organization: organization)
    end

    it "renders the form, the rules and the documented caps for an editor" do
      get "/admin/contracts/import"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('enctype="multipart/form-data"', 'type="file"', "500 rows", "512 KB")
      expect(response.body).to include("Every row becomes a draft owned by you")
    end

    def payload_from(body)
      CGI.unescapeHTML(body[/name="payload" value="([^"]*)"/, 1])
    end

    it "previews a mixed file: 3 good and 2 bad rows with their lines, writes nothing, offers no import" do
      post "/admin/contracts/import/preview", params: { file: upload(fixture_bytes("mixed-contracts.csv")) }
      dump_evidence("preview-mixed.html")

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body.scan('class="label success"').size).to eq(3)
        expect(response.body.scan('class="label alert"').size).to eq(2)
        expect(response.body).to include("2 of 5 rows have errors")
        expect(response.body).to include("signed_on: not a valid date")
        expect(response.body).to include("amount: is not a number")
        expect(response.body).to include("reference: starts with a formula character")
        expect(response.body).to include("Ignored columns: published_at, url")
        expect(response.body).to include('<th scope="row">5</th>', '<th scope="row">6</th>')
        expect(response.body).not_to include('name="payload"')
        expect(contract_model.count).to eq(0)
      end
    end

    it "previews a clean file with a confirm form carrying the text, still writing nothing" do
      post "/admin/contracts/import/preview", params: { file: upload(fixture_bytes("sample-contracts.csv")) }
      dump_evidence("preview-clean.html")

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("All 3 rows are valid", "Import 3 contracts as drafts")
        expect(response.body).to include('name="payload"')
        expect(contract_model.count).to eq(0)
      end
    end

    it "imports the previewed text as drafts, then answers a repeat of it with a refusal (idempotent)" do
      post "/admin/contracts/import/preview", params: { file: upload(fixture_bytes("sample-contracts.csv")) }
      payload = payload_from(response.body)

      post "/admin/contracts/import", params: { payload: payload }

      aggregate_failures do
        expect(response).to redirect_to("/admin/contracts?state=draft")
        expect(flash[:notice]).to eq("3 contracts were imported as drafts.")
        expect(contract_model.pluck(:state).uniq).to eq(["draft"])
        expect(contract_model.pluck(:reference).sort).to eq(%w[DEMO-2026-001 DEMO-2026-002 DEMO-2026-003])
        expect(Decidim::ContractsSk::AuditEvent.pluck(:action).uniq).to eq(["contract.imported_from_file"])
        expect(Decidim::ContractsSk::Party.count).to eq(4)
      end

      post "/admin/contracts/import", params: { payload: payload }
      dump_evidence("reimport-refused.html")

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("reference: this reference already exists in your organization")
        expect(contract_model.count).to eq(3)
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(3)
      end
    end

    it "never trusts the preview: a tampered payload with bad rows imports nothing" do
      post "/admin/contracts/import", params: { payload: fixture_bytes("mixed-contracts.csv").force_encoding("UTF-8") }

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to include("Nothing was imported")
        expect(response.body).to include("2 of 5 rows have errors")
        expect(contract_model.count).to eq(0)
      end
    end

    it "reads a Windows-1250 upload and stores the text as UTF-8" do
      bytes = "reference,title\nDEMO-1,Ľubovňa – údržba čistiarne\n".encode(Encoding::Windows_1250)
      post "/admin/contracts/import/preview", params: { file: upload(bytes) }
      post "/admin/contracts/import", params: { payload: payload_from(response.body) }

      expect(contract_model.find_by!(reference: "DEMO-1").title).to eq("Ľubovňa – údržba čistiarne")
    end

    it "renders hostile cell text escaped, never as markup" do
      post "/admin/contracts/import/preview",
           params: { file: upload("reference,title\nDEMO-1,\"<script>alert(1)</script>\"\n") }

      expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
      expect(response.body).not_to include("<script>alert(1)")
    end

    {
      "an empty file" => ["", "The file is empty or has no data rows."],
      "a header-only file" => ["reference,title\n", "The file is empty or has no data rows."],
      "wrong headers" => ["nazov,suma\nCesta,1\n", "Required column missing in the header row: reference, title."],
      "an xlsx-like binary" => ["PK\x03\x04\x00\x00\x00".b, "This is not a plain-text CSV file"],
      "an unclosed quote" => ["reference,title\nDEMO-1,\"Cesta\n", "The CSV is malformed near line 2"],
      "an oversized file" => ["reference,title\n#{"DEMO-1,Cesta\n" * 50_000}", "The file is larger than 512 KB."],
      "too many rows" => ["reference,title\n#{(1..501).map { |i| "DEMO-#{i},Cesta" }.join("\n")}\n",
                          "The file has more than 500 rows."]
    }.each do |label, (bytes, message)|
      it "answers #{label} with a readable 422 and writes nothing" do
        post "/admin/contracts/import/preview", params: { file: upload(bytes) }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include(message)
        expect(response.body).to include("The file could not be read")
        expect(contract_model.count).to eq(0)
      end
    end

    it "treats a missing file and a non-file file param as an empty upload" do
      post "/admin/contracts/import/preview"
      expect(response.body).to include("The file is empty or has no data rows.")

      post "/admin/contracts/import/preview", params: { file: "reference,title\nDEMO-1,Cesta\n" }
      expect(response.body).to include("The file is empty or has no data rows.")
      expect(contract_model.count).to eq(0)
    end

    it "reads an upload at most one byte past the cap, never the whole file" do
      limits = []
      allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:read).and_wrap_original do |original, *args|
        limits << args.first
        original.call(*args)
      end

      post "/admin/contracts/import/preview", params: { file: upload("reference,title\nDEMO-1,Cesta\n") }

      expect(limits).to eq([Decidim::ContractsSk::SpreadsheetImport::MAX_BYTES + 1])
    end

    it "refuses an oversized re-posted payload" do
      post "/admin/contracts/import", params: { payload: "reference,title\n#{"DEMO-1,Cesta\n" * 120_000}" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("The file is larger than 1024 KB.")
      expect(contract_model.count).to eq(0)
    end

    it "never publishes: the imported records carry no publication or submission stamp" do
      post "/admin/contracts/import", params: { payload: fixture_bytes("sample-contracts.csv") }

      expect(contract_model.pluck(:state, :published_at, :decidim_submitted_by_id).uniq).to eq([["draft", nil, nil]])
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
