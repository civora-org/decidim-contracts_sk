# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Internal review notes must NEVER leak onto a public surface
# (civora-org/civora-platform#128): catalogue list, detail page, supplier
# page, statistics, CSV and JSON exports, the Atom feed, the sitemap, the
# public meta tags and the CRZ handoff PDF. Every example plants a sentinel
# note on a PUBLISHED record (and on a draft one), requests the surface and
# asserts on the response body. The sentinel also doubles as a canary for the
# whole class of "someone serialized the association" regressions.
# Real SQLite-backed :db group (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"
require "nokogiri"

# rubocop:disable RSpec/MultipleExpectations, RSpec/AnyInstance
RSpec.describe "internal notes on public surfaces", :db, type: :request do
  let(:sentinel) { "SENTINEL-INTERNAL-NOTE-9f3a" }
  let(:ico) { "12345678" }
  let(:published) do
    contract = Decidim::ContractsSk::Contract.create!(
      contract_attributes(state: "published", reference: "ZP-1", title: "Zmluva o diele",
                          published_at: Time.utc(2026, 9, 1, 12), amount: BigDecimal("1250.50"),
                          signed_on: Date.new(2026, 8, 30), subject_matter: "Verejny predmet")
    )
    contract.parties.create!(role: "contractor", name: "Dodavatel s.r.o.", ico: ico)
    contract
  end
  let(:draft) { Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2", title: "Rozpracovana")) }

  before do
    migrate_engine_schema!
    organization.update!(host: "zmluvy.example.org", default_locale: "en", name: { "en" => "Green Village" })
    [Decidim::ContractsSk::ContractsController, Decidim::ContractsSk::SuppliersController,
     Decidim::ContractsSk::StatisticsController, Decidim::ContractsSk::SitemapsController,
     Decidim::ContractsSk::OpenDataController, Decidim::ContractsSk::FeedsController].each do |klass|
      allow_any_instance_of(klass).to receive(:current_organization).and_return(organization)
    end
    published.notes.create!(author: author, body: "#{sentinel} published")
    draft.notes.create!(author: author, body: "#{sentinel} draft")
  end

  def expect_no_note_content
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(sentinel)
    expect(response.body.downcase).not_to include("internal note")
  end

  it "does not render a note on the catalogue list" do
    get "/"

    expect_no_note_content
    expect(response.body).to include("Zmluva o diele")
  end

  it "does not render a note on the detail page of a published record" do
    get "/#{published.id}"

    expect_no_note_content
    expect(response.body).to include("Zmluva o diele")
  end

  it "does not expose a draft record's detail page or its note" do
    expect { get "/#{draft.id}" }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "does not render a note on the supplier page" do
    get "/suppliers/#{ico}"

    expect_no_note_content
    expect(response.body).to include("Zmluva o diele")
  end

  it "does not render a note on the statistics page" do
    get "/statistics"

    expect_no_note_content
  end

  it "does not export a note in the CSV" do
    get "/export.csv"

    expect_no_note_content
    expect(response.body).to include("ZP-1")
    expect(response.body.lines.first.downcase).not_to include("note")
  end

  it "does not export a note in the JSON" do
    get "/export.json"

    expect_no_note_content
    expect(response.body).to include("ZP-1")
    expect(response.body.downcase).not_to include("\"notes\"")
  end

  it "keeps the open-data field vocabulary free of notes" do
    fields = Decidim::ContractsSk::OpenData::ContractRecord::FIELDS.map { |field| field.to_s.downcase }

    expect(fields.grep(/note/)).to be_empty
  end

  it "does not put a note in the Atom feed" do
    get "/feed.atom"

    expect_no_note_content
    expect(response.body).to include("Zmluva o diele")
  end

  it "does not put a note in the sitemap" do
    get "/sitemap.xml"

    expect_no_note_content
    expect(response.body).to include("/#{published.id}")
  end

  it "does not put a note in the meta tags of the detail page, catalogue or supplier page" do
    ["/#{published.id}", "/", "/suppliers/#{ico}"].each do |path|
      get path

      head = Nokogiri::HTML(response.body).at_css("head").to_s
      expect(head).not_to include(sentinel), "head of #{path}"
    end
  end

  it "does not read the notes when rendering the CRZ handoff PDF" do
    record = Decidim::ContractsSk::Contract.find(published.id)
    allow(record).to receive(:notes).and_raise("the handoff PDF must not touch notes")

    expect { Decidim::ContractsSk::CrzHandoffPdf.new(record).render }.not_to raise_error
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/AnyInstance
