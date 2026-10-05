# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the public statistics page (civora-org/civora-platform
# #118): GET /statistics over the current organization's published records,
# its data-derived cache, and the catalogue's link to it. Real SQLite-backed
# :db group (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "statistics page", :db, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:statistics_class) { Decidim::ContractsSk::CatalogueStatistics }
  let(:serials) { (1..).each }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }
  let(:builds) { [] }

  before do
    migrate_engine_schema!
    stub_organization(organization)
    allow(Rails).to receive(:cache).and_return(store)
    allow(statistics_class).to receive(:new).and_wrap_original do |original, **kwargs|
      builds << kwargs
      original.call(**kwargs)
    end
  end

  def stub_organization(org)
    [Decidim::ContractsSk::StatisticsController, Decidim::ContractsSk::ContractsController,
     Decidim::ContractsSk::SuppliersController].each do |klass|
      allow_any_instance_of(klass).to receive(:current_organization).and_return(org)
    end
  end

  def create_contract!(overrides = {}, contractor: { name: "Dodávateľ s.r.o.", ico: "12345678" }, org: organization)
    serial = serials.next
    contract = contract_class.create!(
      contract_attributes(
        { organization: org, state: "published", reference: "ST-#{serial}", title: "Zmluva #{serial}",
          published_at: Time.utc(2026, 9, 1, 12) + serial.minutes, amount: BigDecimal("100.00"),
          signed_on: Date.new(2026, 10, 1) }.merge(overrides)
      )
    )
    contract.parties.create!({ role: "contractor" }.merge(contractor)) if contractor
    contract
  end

  def page
    Nokogiri::HTML(response.body)
  end

  def body_text
    page.text.squish
  end

  around { |example| travel_to(Time.utc(2026, 10, 15, 12)) { example.run } }

  describe "with published contracts" do
    before do
      create_contract!({ amount: BigDecimal("1250.50") })
      other_supplier = { name: "Iný s.r.o.", ico: "87654321" }
      create_contract!({ signed_on: Date.new(2026, 9, 5), amount: nil }, contractor: other_supplier)
      create_contract!({ signed_on: nil, source: "crz", source_id: "9001" }, contractor: nil)
    end

    it "renders the summary record, the numbered tables with captions and the supplier links" do
      get "/statistics"

      expect(response).to have_http_status(:ok)
      expect(page.at_css("h1").text).to eq("Contract statistics")
      facts = page.css(".cs-yb__fact").map { |fact| fact.at_css("dt").text }
      expect(facts).to eq(["Signed this month", "Signed this year", "All published contracts",
                           "Organisation's own records"])
      expect(page.at_css(".cs-yb__figure").text).to eq("1")
      expect(body_text).to include("1250.5 EUR").and include("1 without an amount")
      expect(body_text).to include("Data as of")

      sections = page.css("section.cs-yb__tab").map { |section| section.at_css("h2").text.squish }
      expect(sections).to eq(["Table 1 Last 12 months", "Table 2 By year of signing",
                              "Table 3 Top suppliers by value (EUR)", "Table 4 Top suppliers by number of contracts",
                              "Table 5 Own records and records from CRZ"])
      expect(page.css("section.cs-yb__tab").map { |section| section.at_css("h2")["id"] })
        .to eq(%w[cs-yb-months cs-yb-years cs-yb-value-eur cs-yb-count cs-yb-sources])
      expect(page.css("section.cs-yb__tab").map { |section| section["aria-labelledby"] })
        .to eq(page.css("section.cs-yb__tab h2").map { |heading| heading["id"] })
    end

    it "gives every table a caption, scoped headers and a source line" do
      get "/statistics"

      tables = page.css("table.cs-yb__table")
      expect(tables.size).to eq(5)
      expect(tables.map { |table| table.at_css("caption.cs-sr").text.squish }).to include(
        "Contracts by month of signing, the last twelve months", "Contracts by year of signing",
        "Top suppliers by value (EUR)", "Top suppliers by number of contracts"
      )
      expect(page.css("table.cs-yb__table tbody th").all? { |th| th["scope"] == "row" }).to be(true)
      expect(page.css("table.cs-yb__table thead th").all? { |th| th["scope"] == "col" }).to be(true)
      expect(page.css("section.cs-yb__tab").all? { |section| section.at_css("p.cs-yb__src") }).to be(true)
      expect(page.css("table.cs-yb__table--rank").size).to eq(2)
      expect(page.at_css("table.cs-yb__table--sources")).to be_present
    end

    it "links the supplier names to their pages, ranked, and nowhere else inside the tables" do
      get "/statistics"

      links = page.css("table.cs-yb__table a").map { |a| a["href"] }.uniq
      expect(links).to contain_exactly("/suppliers/12345678", "/suppliers/87654321")
      by_count = page.at_css("#cs-yb-count").parent
      expect(by_count.css("td.cs-yb__rank").map { |cell| cell.text.squish }).to eq(%w[1 2])
      # Only the supplier with an amount is ranked by value.
      expect(page.at_css("#cs-yb-value-eur").parent.css("td.cs-yb__rank").map(&:text)).to eq(%w[1])
    end

    it "states the provenance with a crz.gov.sk link and offers the catalogue and the CSV export next" do
      get "/statistics"

      expect(page.at_css(".cs-yb__note a")["href"]).to eq("https://www.crz.gov.sk/")
      expect(page.css("nav.cs-yb__next a").map { |link| link["href"] }).to eq(["/", "/export.csv"])
      expect(page.at_css("nav.cs-yb__next")["aria-label"]).to eq("Continue")
    end

    it "keeps the bars decorative: aria-hidden, no text, a bounded width" do
      get "/statistics"

      bars = page.css(".cs-yb__bar")
      expect(bars).not_to be_empty
      expect(bars.all? { |bar| bar["aria-hidden"] == "true" && bar.text.strip.empty? }).to be(true)
      styles = bars.map { |bar| bar.at_css("span")["style"] }
      expect(styles).to all(match(/\A--cs-bar: \d+(\.\d+)?%\z/))
      expect(page.css(".cs-yb__bar").map { |bar| bar.at_css("span")["style"][/[\d.]+/].to_f }.max).to be <= 100
    end

    it "draws bars in the value table too (Table 3)" do
      get "/statistics"

      value_table = page.at_css("#cs-yb-value-eur").parent
      expect(value_table.css(".cs-yb__bar").size).to eq(1)
    end

    it "shows the CRZ split when mirrors exist, with the double-counting note" do
      get "/statistics"

      expect(body_text).to include("Taken from CRZ").and include("counted twice")
      expect(page.at_css(".cs-yb__key--crz")).to be_present
    end

    it "is indexable: no robots meta is contributed" do
      snippets = []
      allow_any_instance_of(ActionView::Base).to receive(:content_for)
        .and_wrap_original do |original, name, *args, &block|
        snippets << args.first if name == :header_snippets && args.first
        original.call(name, *args, &block)
      end

      get "/statistics"

      expect(snippets).to be_empty
      expect(response.body).not_to include("noindex")
    end

    it "agrees with the supplier page on the supplier's count" do
      get "/statistics"
      listed = page.at_css("#cs-yb-count").parent.css("tbody tr").find { |row| row.text.include?("Dodávateľ") }
      count = listed.css("td.cs-yb__num").first.text.squish.to_i
      get "/suppliers/12345678"

      expect(page.at_css(".cs-dl__figure").text.to_i).to eq(count)
    end

    it "names suppliers exactly like the supplier page when publication dates tie" do
      same = Time.utc(2026, 9, 1, 12)
      # Contract id decides first: the newer contract's spelling wins even
      # though its party row is OLDER than the other contract's party row.
      older = create_contract!({ published_at: same }, contractor: nil)
      newer = create_contract!({ published_at: same }, contractor: nil)
      newer.parties.create!(role: "contractor", ico: "55555555", name: "Spelling of the newer contract")
      older.parties.create!(role: "contractor", ico: "55555555", name: "Spelling of the older contract")
      # Party id decides next: one contract carrying two spellings of an IČO.
      both = create_contract!({ published_at: same }, contractor: nil)
      both.parties.create!(role: "contractor", ico: "66666666", name: "First spelling")
      both.parties.create!(role: "contractor", ico: "66666666", name: "Second spelling")

      get "/statistics"
      listed = page.at_css("#cs-yb-count").parent.css("tbody th a").to_h do |link|
        [link["href"][/\d+\z/], link.text.tr("\u00A0", " ")]
      end
      names = %w[55555555 66666666].index_with do |ico|
        get "/suppliers/#{ico}"
        page.at_css("h1").text.tr("\u00A0", " ")
      end

      expect(names).to eq("55555555" => "Spelling of the newer contract", "66666666" => "Second spelling")
      expect(listed.slice(*names.keys)).to eq(names)
    end

    it "labels the closing CSV link as the organisation's own records and says mirrors are not in it" do
      get "/statistics"

      expect(page.at_css("nav.cs-yb__next a[href='/export.csv']").text.strip)
        .to eq("Download the organisation's own records (CSV)")
      expect(page.at_css(".cs-yb__note").text).to include("records taken from CRZ are not part of it")
    end

    it "explains in the year table that future-dated contracts are not in this month or this year" do
      get "/statistics"

      expect(page.at_css("#cs-yb-years").parent.at_css(".cs-yb__unit").text).to include("future signing date")
    end

    it "renders in Slovak with the engine's month names" do
      I18n.with_locale(:sk) { get "/statistics" }

      expect(page.at_css("h1").text).to eq("Štatistiky zmlúv")
      expect(body_text).to include("október 2026").and include("Údaje k").and include("Tab. 1")
    end

    it "ignores hostile parameters" do
      get "/statistics", params: { q: "x", sort: ["a"], page: "999999999999", source: { a: 1 }, locale: "%00" }

      expect(response).to have_http_status(:ok)
    end

    it "is reached from the catalogue's view switch, which marks the current view" do
      get "/"

      switch = page.at_css("nav.cs-switch")
      expect(switch.at_css("a[href='/statistics']").text.strip).to eq("Statistics")
      expect(switch.at_css("a[aria-current='page']").text.strip).to eq("Contract list")
      expect(switch.css(".cs-switch__ink").size).to eq(1)

      get "/statistics"

      switch = page.at_css("nav.cs-switch")
      expect(switch.at_css("a[aria-current='page']").text.strip).to eq("Statistics")
      expect(switch.at_css("a[href='/']").text.strip).to eq("Contract list")
    end
  end

  describe "published-only and tenancy" do
    it "ignores drafts and another organization's records" do
      other = Decidim::Organization.create!
      create_contract!({ state: "draft" })
      create_contract!({}, org: other)
      create_contract!({}, contractor: nil)

      get "/statistics"

      figures = page.css(".cs-yb__figure").map(&:text)
      expect(figures[0]).to eq("1")
      expect(figures[2]).to eq("1")
    end
  end

  describe "the empty state" do
    it "renders 200 with a message and a catalogue link, and no tables" do
      get "/statistics"

      expect(response).to have_http_status(:ok)
      expect(page.at_css("h1").text).to eq("Contract statistics")
      expect(page.at_css(".cs-yb__empty").text).to include("no published contracts")
      expect(page.at_css(".cs-yb__empty a")["href"]).to eq("/")
      expect(page.css("table")).to be_empty
      expect(page.css(".cs-yb__fact, nav.cs-yb__next")).to be_empty
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe "the cache" do
    let!(:first_contract) { create_contract! }

    it "builds once and serves the second request from the cache" do
      get "/statistics"
      get "/statistics"

      expect(builds.size).to eq(1)
    end

    it "caches plain data, not HTML" do
      get "/statistics"

      keys = store.instance_variable_get(:@data).keys
      expect(keys.map { |key| store.read(key).class }).to eq([statistics_class::Result])
    end

    it "rebuilds when a contract is published, edited or removed" do
      get "/statistics"
      published = create_contract!({}, contractor: nil)
      get "/statistics"
      travel 1.minute
      published.update!(amount: BigDecimal("5.00"))
      get "/statistics"
      first_contract.destroy!
      get "/statistics"

      expect(builds.size).to eq(4)
    end

    it "rebuilds after the TTL" do
      get "/statistics"
      travel 59.minutes
      get "/statistics"
      travel 2.minutes
      get "/statistics"

      expect(builds.size).to eq(2)
    end

    it "rebuilds when the month rolls over" do
      get "/statistics"
      travel_to(Time.utc(2026, 11, 2, 12))
      get "/statistics"

      expect(builds.size).to eq(2)
    end

    it "keeps one entry per organization, even when two organizations look identical to the key" do
      other = Decidim::Organization.create!
      # Same count and same newest updated_at (time is frozen): only the
      # organization id in the key tells the two apart.
      create_contract!({}, contractor: { name: "Cudzí s.r.o.", ico: "99999999" }, org: other)
      get "/statistics"
      stub_organization(other)
      get "/statistics"

      expect(builds.size).to eq(2)
      expect(body_text).to include("Cudzí s.r.o.")
    end

    it "reuses the cached data across locales" do
      get "/statistics"
      I18n.with_locale(:sk) { get "/statistics" }

      expect(builds.size).to eq(1)
      expect(page.at_css("h1").text).to eq("Štatistiky zmlúv")
    end

    it "costs one query on a hit and three on a miss" do
      count = lambda do
        queries = []
        callback = lambda do |*, payload|
          queries << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached]
        end
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get "/statistics" }
        queries.size
      end

      expect(count.call).to eq(3)
      expect(count.call).to eq(1)
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
