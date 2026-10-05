# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the Atom feed (civora-org/civora-platform#120):
# GET /feed.atom over the OWN-records published scope, newest 50 first.
# Real SQLite-backed :db group (CONTRACTS_SK_DB=1). Synthetic data only. The
# body is parsed STRICTLY (Nokogiri without recovery): a feed reader would
# reject anything that is not well-formed XML.
# ---------------------------------------------------------------------------

require "spec_helper"
require "nokogiri"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "atom feed", :db, type: :request do
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:serials) { (1..).each }
  let(:atom_ns) { { "a" => "http://www.w3.org/2005/Atom" } }

  before do
    migrate_engine_schema!
    organization.update!(host: "zmluvy.example.org", default_locale: "sk",
                         name: { "sk" => "Obec Zelená", "en" => "Green Village" })
    allow_any_instance_of(Decidim::ContractsSk::FeedsController)
      .to receive(:current_organization).and_return(organization)
  end

  def create_contract!(overrides = {})
    serial = serials.next
    contract_class.create!(
      contract_attributes(
        { state: "published", reference: "ZP-#{serial}", title: "Zmluva #{serial}",
          published_at: Time.utc(2026, 9, 1, 12, 0, 0), amount: BigDecimal("1250.50"),
          signed_on: Date.new(2026, 8, 30) }.merge(overrides)
      )
    )
  end

  def feed(path = "/feed.atom", **opts)
    get path, **opts
    expect(response).to have_http_status(:ok)
    Nokogiri::XML(response.body) { |config| config.strict.nonet }
  end

  def entries(doc)
    doc.xpath("/a:feed/a:entry", atom_ns)
  end

  def entry_titles(doc)
    entries(doc).map { |entry| entry.at_xpath("a:title", atom_ns).text }
  end

  describe "document shape" do
    it "is a strictly well-formed Atom feed with the required feed and entry elements" do
      contract = create_contract!(title: "Cesta", reference: "ZP-9")

      doc = feed

      expect(response.media_type).to eq("application/atom+xml")
      root = doc.root
      expect(root.name).to eq("feed")
      expect(root.namespace.href).to eq("http://www.w3.org/2005/Atom")
      expect(root["xml:lang"]).to eq(I18n.locale.to_s)
      aggregate_failures do
        expect(doc.at_xpath("/a:feed/a:id", atom_ns).text).to eq("tag:zmluvy.example.org,2026:contracts_sk/feed")
        expect(doc.at_xpath("/a:feed/a:title", atom_ns).text).to eq("Contracts — Green Village")
        expect(doc.at_xpath("/a:feed/a:subtitle", atom_ns).text).to be_present
        expect(doc.at_xpath("/a:feed/a:updated", atom_ns).text).to eq("2026-09-01T12:00:00Z")
        expect(doc.at_xpath("/a:feed/a:author/a:name", atom_ns).text).to eq("Green Village")
        expect(doc.at_xpath("/a:feed/a:link[@rel='self']", atom_ns)["href"]).to eq("http://www.example.com/feed.atom?locale=en")
        expect(doc.at_xpath("/a:feed/a:link[@rel='alternate']", atom_ns)["href"]).to eq("http://www.example.com/")
        entry = entries(doc).first
        expect(entry.at_xpath("a:id", atom_ns).text)
          .to eq("tag:zmluvy.example.org,2026:contracts_sk/contract/#{contract.id}")
        expect(entry.at_xpath("a:title", atom_ns).text).to eq("Cesta")
        expect(entry.at_xpath("a:link[@rel='alternate']", atom_ns)["href"]).to eq("http://www.example.com/#{contract.id}")
        expect(entry.at_xpath("a:published", atom_ns).text).to eq("2026-09-01T12:00:00Z")
        expect(entry.at_xpath("a:updated", atom_ns).text).to eq("2026-09-01T12:00:00Z")
        expect(entry.at_xpath("a:summary", atom_ns).text)
          .to include("ZP-9").and include("1250.5 EUR").and include("signed 2026-08-30")
        expect(entry.at_xpath("a:summary", atom_ns)["type"]).to eq("text")
      end
    end

    it "falls back from the locale to the default locale, then any name, then the host for the author" do
      create_contract!
      organization.update!(name: { "sk" => "Obec Zelená" })
      expect(feed.at_xpath("/a:feed/a:author/a:name", atom_ns).text).to eq("Obec Zelená")

      organization.update!(name: { "cs" => "Obec Česká" })
      expect(feed.at_xpath("/a:feed/a:author/a:name", atom_ns).text).to eq("Obec Česká")

      organization.update!(name: nil)
      expect(feed.at_xpath("/a:feed/a:author/a:name", atom_ns).text).to eq("zmluvy.example.org")
    end

    it "serves a valid feed with no entries and a stable updated stamp when nothing is published" do
      doc = feed

      expect(entries(doc)).to be_empty
      expect(doc.at_xpath("/a:feed/a:updated", atom_ns).text)
        .to eq(organization.created_at.utc.xmlschema)
    end
  end

  describe "entries" do
    it "caps the feed at 50 entries (the 51st-newest is dropped)" do
      51.times { |i| create_contract!(published_at: Time.utc(2026, 1, 1) + i.hours) }

      doc = feed

      expect(entries(doc).size).to eq(50)
      expect(entry_titles(doc)).not_to include("Zmluva 1")
      expect(entry_titles(doc).first).to eq("Zmluva 51")
    end

    it "orders newest first, breaking published_at ties by id descending" do
      create_contract!(title: "old", published_at: Time.utc(2026, 1, 1))
      create_contract!(title: "tie-a", published_at: Time.utc(2026, 5, 1))
      create_contract!(title: "tie-b", published_at: Time.utc(2026, 5, 1))
      create_contract!(title: "new", published_at: Time.utc(2026, 6, 1))

      expect(entry_titles(feed)).to eq(%w[new tie-b tie-a old])
    end

    it "lists only the current organization's published editorial records" do
      create_contract!(title: "PUB")
      create_contract!(title: "DRAFT", state: "draft", published_at: nil)
      create_contract!(title: "REVIEW", state: "in_review", published_at: nil)
      create_contract!(title: "ARCH", state: "archived")
      create_contract!(title: "MIRROR", source: "crz", source_id: "9001")
      other = Decidim::Organization.create!
      create_contract!(title: "OTHER", organization: other, author: Decidim::User.create!(organization: other))

      expect(entry_titles(feed)).to eq(["PUB"])
    end

    it "sets entry published and updated to published_at, never the row's updated_at" do
      contract = create_contract!(published_at: Time.utc(2026, 3, 4, 5, 6, 7))
      contract.update_columns(updated_at: Time.utc(2027, 1, 1))

      entry = entries(feed).first

      expect(entry.at_xpath("a:published", atom_ns).text).to eq("2026-03-04T05:06:07Z")
      expect(entry.at_xpath("a:updated", atom_ns).text).to eq("2026-03-04T05:06:07Z")
    end

    it "keeps ids stable across requests and independent of later edits" do
      contract = create_contract!
      first = entries(feed).first.at_xpath("a:id", atom_ns).text
      contract.update!(title: "Renamed")
      second = entries(feed).first.at_xpath("a:id", atom_ns).text

      expect(second).to eq(first)
    end
  end

  describe "filters and sort" do
    it "applies the catalogue filters and carries them into the ids and links" do
      create_contract!(title: "Cesta A", amount: BigDecimal("500"))
      create_contract!(title: "Cesta B", amount: BigDecimal("5000"))

      doc = feed("/feed.atom?amount_min=1000&q=cesta")

      expect(entry_titles(doc)).to eq(["Cesta B"])
      expect(doc.at_xpath("/a:feed/a:id", atom_ns).text)
        .to eq("tag:zmluvy.example.org,2026:contracts_sk/feed?amount_min=1000&q=cesta")
      expect(doc.at_xpath("/a:feed/a:link[@rel='self']", atom_ns)["href"])
        .to eq("http://www.example.com/feed.atom?amount_min=1000&locale=en&q=cesta")
      expect(doc.at_xpath("/a:feed/a:subtitle", atom_ns).text).to include("cesta")
    end

    it "gives one id for the same filters in any order or spelling" do
      create_contract!
      a = feed("/feed.atom?q=Cesta&amount_min=1000").at_xpath("/a:feed/a:id", atom_ns).text
      b = feed("/feed.atom?amount_min=1000.00&q=Cesta").at_xpath("/a:feed/a:id", atom_ns).text

      expect(a).to eq(b)
    end

    it "ignores the reader's sort (and keeps it out of the id and self link)" do
      create_contract!(title: "cheap", amount: 1, published_at: Time.utc(2026, 9, 2))
      create_contract!(title: "dear", amount: 9000, published_at: Time.utc(2026, 9, 1))

      doc = feed("/feed.atom?sort=amount_desc")
      expect(entry_titles(doc)).to eq(%w[cheap dear])
      expect(doc.at_xpath("/a:feed/a:id", atom_ns).text).to eq("tag:zmluvy.example.org,2026:contracts_sk/feed")
      expect(doc.at_xpath("/a:feed/a:link[@rel='self']", atom_ns)["href"]).not_to include("sort")

      expect(entry_titles(feed("/feed.atom?sort=published_asc"))).to eq(%w[cheap dear])
    end

    it "honestly serves an empty feed for source=crz (mirrors are never exported)" do
      create_contract!(title: "MIRROR", source: "crz", source_id: "9001")

      expect(entries(feed("/feed.atom?source=crz"))).to be_empty
    end
  end

  describe "conditional requests" do
    it "answers 304 to If-None-Match with the ETag of the previous response" do
      create_contract!

      get "/feed.atom"
      etag = response.headers["ETag"]
      expect(etag).to be_present

      get "/feed.atom", headers: { "If-None-Match" => etag }

      expect(response).to have_http_status(:not_modified)
      expect(response.body).to be_empty
    end
  end

  describe "hostile input" do
    it "escapes markup characters and survives control characters in titles and references" do
      create_contract!(title: "A <b>&</b> \"B\" 'C' ]]> \u0000\u0001\u001F\u007F end", reference: "R<&>\u0008")
      contract = create_contract!(title: "Tab\tand\nnewline", published_at: Time.utc(2026, 9, 2))

      doc = feed

      expect(entries(doc).size).to eq(2)
      expect(entry_titles(doc).first).to eq("Tab\tand\nnewline")
      expect(entry_titles(doc).last).to include("<b>&</b> \"B\" 'C' ]]>")
      expect(response.body).not_to match(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/)
      expect(contract).to be_persisted
    end

    it "answers 200 with valid XML for NUL bytes, arrays, bad dates and an unknown locale" do
      create_contract!
      [
        "/feed.atom?q=%00", "/feed.atom?party[]=&q[]=x", "/feed.atom?published_from=nonsense&amount_min[]=x",
        "/feed.atom?sort[]=amount_desc", "/feed.atom?party=%00%00", "/feed.atom?locale=%00",
        "/feed.atom?locale[]=sk", "/feed.atom?page=%00&format=xml"
      ].each do |path|
        get path
        expect(response).to have_http_status(:ok), path
        expect { Nokogiri::XML(response.body, &:strict) }.not_to raise_error, path
      end
    end
  end

  describe "other formats" do
    it "gives the catch-all 404 for /feed and /feed.rss, and no route at all for /feed.atom.bak" do
      create_contract!

      %w[/feed /feed.rss].each do |path|
        expect { get path }.to raise_error(ActiveRecord::RecordNotFound), path
      end
      expect { get "/feed.atom.bak" }.to raise_error(ActionController::RoutingError)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
