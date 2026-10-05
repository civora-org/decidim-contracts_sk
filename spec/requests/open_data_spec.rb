# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the open-data export (civora-org/civora-platform#119):
# GET /export.csv and /export.json over the OWN-records published scope.
# Real SQLite-backed :db group (CONTRACTS_SK_DB=1): the scoping, the batching
# and the streamed body are only meaningful against real queries. Synthetic
# data only; the sentinel strings below exist to prove they never leak.
# ---------------------------------------------------------------------------

require "spec_helper"
require "csv"
require "json"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "open data export", :db, type: :request do
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:fields) { Decidim::ContractsSk::OpenData::ContractRecord::FIELDS }
  let(:sentinel) { "SENTINEL-INTERNAL-VALUE" }
  let(:record_class) { Decidim::ContractsSk::OpenData::ContractRecord }

  before do
    migrate_engine_schema!
    allow_any_instance_of(Decidim::ContractsSk::OpenDataController)
      .to receive(:current_organization).and_return(organization)
  end

  def create_contract!(overrides = {})
    contract_class.create!(
      contract_attributes(
        { state: "published", published_at: Time.utc(2026, 9, 1, 12, 0, 0), amount: BigDecimal("1250.50"),
          signed_on: Date.new(2026, 9, 1), effective_from: Date.new(2026, 8, 15),
          subject_matter: "Road signage", crz_url: "https://crz.gov.sk/record/123" }.merge(overrides)
      )
    )
  end

  def csv_rows(body = response.body, **opts)
    CSV.parse(body.delete_prefix("﻿"), headers: true, **opts)
  end

  def json_rows
    JSON.parse(response.body)
  end

  describe "CSV" do
    it "serves a BOM-prefixed UTF-8 CSV attachment with the documented header and parses back" do
      contract = create_contract!(title: "Cesta; \"Hlavná\"\nulica", reference: "ZP-1")
      contract.parties.create!(role: "object", name: "Obec Zelená", ico: "12345678")
      contract.parties.create!(role: "contractor", name: "Dodávateľ s.r.o.", ico: "87654321")

      get "/export.csv"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.media_type).to eq("text/csv")
        expect(response.headers["Content-Type"]).to include("charset=utf-8")
        expect(response.headers["Content-Disposition"])
          .to match(/\Aattachment; filename="contracts-\d{4}-\d{2}-\d{2}\.csv"\z/)
        expect(response.body.b).to start_with("\xEF\xBB\xBF".b)
        expect(response.headers["ETag"]).to be_present
        rows = csv_rows
        expect(rows.headers).to eq(fields)
        row = rows.first
        expect(row["title"]).to eq("Cesta; \"Hlavná\"\nulica")
        expect(row["amount"]).to eq("1250.50")
        expect(row["signed_on"]).to eq("2026-09-01")
        expect(row["published_at"]).to eq("2026-09-01T12:00:00Z")
        expect(row["party_roles"]).to eq("contractor | object")
        expect(row["party_icos"]).to eq("87654321 | 12345678")
        expect(row["party_names"]).to eq("Dodávateľ s.r.o. | Obec Zelená")
        expect(row["url"]).to eq("http://www.example.com/#{contract.id}")
      end
    end

    it "uses the semicolon separator and decimal-comma amounts for profile=excel" do
      create_contract!(title: "Cesta, Hlavná")

      get "/export.csv", params: { profile: "excel" }

      expect(response.body).to include("reference;title;")
      rows = csv_rows(col_sep: ";")
      expect(rows.first["amount"]).to eq("1250,50")
      expect(rows.first["title"]).to eq("Cesta, Hlavná")
    end

    it "keeps the comma profile for an unknown or array profile value" do
      create_contract!
      get "/export.csv", params: { profile: ["excel"] }

      expect(response.body).to include("reference,title,")
      expect(csv_rows.first["amount"]).to eq("1250.50")
    end

    it "emits empty cells for nulls and neutralizes formula-looking text" do
      create_contract!(title: "=HYPERLINK(\"x\")", reference: "+1", amount: nil, signed_on: nil,
                       effective_from: nil, subject_matter: nil, crz_url: nil)

      get "/export.csv"

      row = csv_rows.first
      expect(row["title"]).to eq("'=HYPERLINK(\"x\")")
      expect(row["reference"]).to eq("'+1")
      expect(row.to_h.values_at("amount", "signed_on", "effective_from", "subject_matter", "crz_url"))
        .to eq([nil, nil, nil, nil, nil])
    end
  end

  describe "HEAD" do
    it "answers 200 with the download headers, an empty body and never runs the stream" do
      create_contract!
      expect_any_instance_of(Decidim::ContractsSk::OpenDataController).not_to receive(:stream_csv)

      head "/export.csv"

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
      expect(response.headers["Content-Type"]).to start_with("text/csv")
      expect(response.headers["Content-Disposition"]).to start_with("attachment; filename=\"contracts-")
      expect(response.headers["ETag"]).to be_present
    end
  end

  describe "JSON" do
    it "serves a JSON array with ISO dates, a numeric amount, nulls and nested parties" do
      contract = create_contract!(effective_from: nil)
      contract.parties.create!(role: "contractor", name: "Dodávateľ", ico: "87654321")
      contract.parties.create!(role: "object", name: "Fyzická osoba", ico: nil)

      get "/export.json"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.media_type).to eq("application/json")
        expect(response.headers["Content-Disposition"]).to match(/filename="contracts-.*\.json"/)
        expect(json_rows.size).to eq(1)
        row = json_rows.first
        expect(row.keys).to eq(Decidim::ContractsSk::OpenData::ContractRecord::JSON_KEYS)
        expect(row["amount"]).to eq(1250.5)
        expect(row["effective_from"]).to be_nil
        expect(row["signed_on"]).to eq("2026-09-01")
        expect(row["published_at"]).to eq("2026-09-01T12:00:00Z")
        expect(row["parties"]).to eq([{ "role" => "contractor", "ico" => "87654321", "name" => "Dodávateľ" }])
      end
    end

    it "serves an empty array when nothing is published" do
      get "/export.json"

      expect(json_rows).to eq([])
    end
  end

  describe "scope" do
    it "exports only the current organization's published editorial records" do
      create_contract!(reference: "PUB-1")
      create_contract!(reference: "DRAFT", state: "draft", published_at: nil)
      create_contract!(reference: "REVIEW", state: "in_review", published_at: nil)
      create_contract!(reference: "ARCH", state: "archived")
      create_contract!(reference: "MIRROR", source: "crz", source_id: "9001")
      other = Decidim::Organization.create!
      create_contract!(reference: "OTHER-ORG", organization: other, author: Decidim::User.create!(organization: other))

      get "/export.json"

      expect(json_rows.pluck("reference")).to eq(["PUB-1"])
    end

    it "answers an honest empty export for source=crz (mirrors are never exported)" do
      create_contract!(reference: "PUB-1")
      create_contract!(reference: "MIRROR", source: "crz", source_id: "9001")

      get "/export.csv", params: { source: "crz" }

      expect(response).to have_http_status(:ok)
      expect(csv_rows.size).to eq(0)
    end

    it "applies the catalogue filters" do
      create_contract!(reference: "CHEAP", amount: BigDecimal("10"))
      create_contract!(reference: "DEAR", amount: BigDecimal("5000"))

      get "/export.json", params: { amount_min: "1000", q: "dear" }

      expect(json_rows.pluck("reference")).to eq(["DEAR"])
    end

    it "survives hostile params" do
      create_contract!

      [{ q: "%00" }, { q: "\u0000" }, { party: [""] }, { published_from: "nonsense" }, { amount_min: ["x"] },
       { sort: { a: 1 } }, { page: ["2"] }, { source: "bogus" }].each do |params|
        get "/export.csv", params: params
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "whitelist" do
    it "never exposes an internal column or a party address" do
      author_user = Decidim::User.create!(organization: organization)
      contract = create_contract!(
        review_reason: sentinel, reviewed_at: Time.utc(2026, 8, 1), redaction_confirmed_at: Time.utc(2026, 8, 2),
        submitted_by: author_user, crz_filing_reason: sentinel, crz_filed_at: Time.utc(2026, 8, 3),
        checksum: sentinel, import_status: "failed", source_id: sentinel, imported_at: Time.utc(2026, 8, 4)
      )
      contract.parties.create!(role: "contractor", name: "Dodávateľ", ico: "87654321", address: sentinel)

      get "/export.csv"
      csv_body = response.body
      get "/export.json"

      expect(csv_body).not_to include(sentinel)
      expect(response.body).not_to include(sentinel)
      expect(csv_rows(csv_body).headers).to eq(fields)
      expect(response.body).not_to match(
        /review_reason|reviewed_at|redaction|submitted_by|crz_filing|checksum|import_status|source_id|author|address/
      )
    end
  end

  describe "streaming" do
    it "reads in batches without the query cache retaining them" do
      stub_const("Decidim::ContractsSk::OpenDataController::EXPORT_BATCH_SIZE", 2)
      5.times { |i| create_contract!(reference: "ZP-#{i}", title: "Contract #{i}") }
      selects = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        selects << payload[:sql] if payload[:sql].match?(/FROM "decidim_contracts_sk_contracts"/) &&
                                    payload[:sql].include?("LIMIT") && !payload[:cached]
      end

      get "/export.csv"

      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(csv_rows.map { |r| r["reference"] }).to eq(%w[ZP-0 ZP-1 ZP-2 ZP-3 ZP-4])
      expect(selects.size).to be >= 3
    end

    it "preloads the parties once per batch instead of once per contract" do
      stub_const("Decidim::ContractsSk::OpenDataController::EXPORT_BATCH_SIZE", 3)
      5.times do |i|
        contract = create_contract!(reference: "ZP-#{i}")
        contract.parties.create!(role: "contractor", ico: "1234567#{i}", name: "Supplier #{i}")
      end
      party_selects = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        party_selects += 1 if payload[:sql].match?(/FROM "decidim_contracts_sk_parties"/)
      end

      get "/export.json"

      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(json_rows.size).to eq(5)
      expect(party_selects).to eq(2)
    end

    it "does not buffer the body: no contract row is read until the server pulls the stream" do
      create_contract!
      reads = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        sql = payload[:sql]
        reads << sql if sql.include?("LIMIT") && sql.include?("decidim_contracts_sk_contracts")
      end

      _status, _headers, body = Rails.application.call(Rack::MockRequest.env_for("/export.csv"))
      before_pull = reads.size
      parts = []
      body.each { |part| parts << part }
      body.close
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(before_pull).to eq(0)
      expect(reads.size).to be >= 1
      expect(parts.size).to be >= 2
    end

    it "streams with the query cache disabled (the executor's cache would retain every batch)" do
      create_contract!
      enabled = []
      allow(record_class).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        enabled << Decidim::ContractsSk::Contract.connection_pool.query_cache_enabled
        original.call(*args, **kwargs)
      end

      get "/export.csv"

      expect(enabled).to eq([false])
    end

    it "keeps a valid JSON array across batch boundaries" do
      stub_const("Decidim::ContractsSk::OpenDataController::EXPORT_BATCH_SIZE", 2)
      5.times { |i| create_contract!(reference: "ZP-#{i}") }

      get "/export.json"

      expect(json_rows.pluck("reference")).to eq(%w[ZP-0 ZP-1 ZP-2 ZP-3 ZP-4])
    end

    it "logs the failure class and last id (never the message) and re-raises mid-stream" do
      stub_const("Decidim::ContractsSk::OpenDataController::EXPORT_BATCH_SIZE", 1)
      2.times { |i| create_contract!(reference: "ZP-#{i}") }
      calls = 0
      allow(record_class).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        calls += 1
        raise "secret #{sentinel}" if calls == 2

        original.call(*args, **kwargs)
      end
      logged = []
      allow(Rails.logger).to receive(:error) { |message| logged << message }

      expect { get "/export.csv" }.to raise_error(RuntimeError)
      expect(logged.join).to match(/aborted after contract id \d+: RuntimeError/)
      expect(logged.join).not_to include(sentinel)
    end
  end

  describe "caching" do
    it "answers 304 to a matching If-None-Match and a fresh body once the data changes" do
      contract = create_contract!
      get "/export.csv"
      etag = response.headers["ETag"]

      get "/export.csv", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty

      get "/export.json", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)

      get "/export.csv", params: { profile: "excel" }, headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)

      contract.update_columns(updated_at: 1.minute.from_now)
      get "/export.csv", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)
    end

    it "changes the ETag when the export version changes" do
      create_contract!
      get "/export.csv"
      etag = response.headers["ETag"]

      stub_const("Decidim::ContractsSk::OpenDataController::EXPORT_VERSION", 2)
      get "/export.csv", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)
    end

    it "changes the ETag when the field list changes" do
      create_contract!
      get "/export.csv"
      etag = response.headers["ETag"]

      stub_const("Decidim::ContractsSk::OpenData::ContractRecord::FIELDS", record_class::FIELDS.reverse.freeze)
      get "/export.csv", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)
    end

    it "changes the ETag when the base URL changes (the url column)" do
      create_contract!
      get "/export.csv"
      etag = response.headers["ETag"]

      host! "other.example.org"
      get "/export.csv", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)
    end

    it "changes the ETag when the time zone changes (date filter boundaries)" do
      create_contract!
      get "/export.csv"
      etag = response.headers["ETag"]

      allow(Time).to receive(:zone).and_return(ActiveSupport::TimeZone["Pacific/Auckland"])
      get "/export.csv", headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:ok)
    end

    it "ignores sort in the ETag (the export is always ordered by id)" do
      create_contract!
      get "/export.csv"
      etag = response.headers["ETag"]

      get "/export.csv", params: { sort: "amount_desc" }, headers: { "If-None-Match" => etag }
      expect(response).to have_http_status(:not_modified)
    end

    it "does not build the stream for a conditional hit" do
      create_contract!
      get "/export.csv"
      etag = response.headers["ETag"]

      expect_any_instance_of(Decidim::ContractsSk::OpenDataController).not_to receive(:send_export)
      get "/export.csv", headers: { "If-None-Match" => etag }

      expect(response).to have_http_status(:not_modified)
    end

    it "does not share an ETag across organizations" do
      stamp = Time.utc(2026, 9, 2, 8, 0, 0)
      create_contract!.update_columns(updated_at: stamp)
      get "/export.csv"
      etag = response.headers["ETag"]

      # Same count, same newest update: only the tenant id tells them apart.
      other = Decidim::Organization.create!
      create_contract!(organization: other, author: Decidim::User.create!(organization: other))
        .update_columns(updated_at: stamp)
      allow_any_instance_of(Decidim::ContractsSk::OpenDataController)
        .to receive(:current_organization).and_return(other)
      get "/export.csv", headers: { "If-None-Match" => etag }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "unsupported formats" do
    it "falls through to the detail route and 404s" do
      %w[/export /export.xml].each do |path|
        expect { get path }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
