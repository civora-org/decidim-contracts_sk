# frozen_string_literal: true

# ---------------------------------------------------------------------------
# The public catalogue as a results-first register: the compact header, the
# filter chips with their removable applied filters, the results toolbar
# (summary, sort, downloads, follow), the two-line rows and the pager. Real
# SQLite-backed :db group (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "public catalogue register", :db, type: :request do
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:serials) { (1..).each }
  let(:doc) { Nokogiri::HTML(response.body) }
  let(:nbsp) { " " }

  before do
    migrate_engine_schema!
    [Decidim::ContractsSk::ContractsController].each do |klass|
      allow_any_instance_of(klass).to receive(:current_organization).and_return(organization)
    end
  end

  def create_contract!(overrides = {})
    serial = serials.next
    contract_class.create!(
      contract_attributes(
        { state: "published", reference: "ZP-#{serial}", title: "Zmluva #{serial}",
          published_at: Time.utc(2026, 9, 1, 12, 0, 0) + serial.minutes, amount: BigDecimal("100.00"),
          currency: "EUR" }.merge(overrides)
      )
    )
  end

  def add_party!(contract, name, ico = nil, role: "contractor")
    Decidim::ContractsSk::Party.create!(contract: contract, role: role, name: name, ico: ico)
  end

  def summary_text
    # Not #squish: it would turn the non-breaking spaces of the figures into plain ones.
    doc.at_css("p.cs-bar__sum").text.gsub(/[ \t\n]+/, " ").strip
  end

  def count_queries(&block)
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])

      count += 1 if payload[:sql].match?(/\A\s*SELECT/i)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  describe "header" do
    it "puts the compact title and the view switch in one header row, with no lead paragraph" do
      create_contract!

      get "/"

      header = doc.at_css("main header.cs-top")
      expect(header.at_css("h1.cs-top__title").text.strip).to eq("Contracts")
      expect(header.at_css("nav.cs-switch")).to be_present
      expect(header.at_css("nav.cs-switch a[aria-current=page]")).to be_present
      expect(doc.css("h1").size).to eq(1)
      expect(response.body).not_to include("cs-head__lead")
    end

    it "orders the headings h1, then the hidden results heading, with no open-data or alerts block inline" do
      create_contract!

      get "/"

      expect(doc.css("h1, h2").map { |node| [node.name, node.text.strip] })
        .to eq([["h1", "Contracts"], ["h2", "Contract register"]])
      expect(doc.at_css("h2#cs-register-title")["class"]).to include("cs-sr")
      expect(response.body).not_to include("cs-opendata")
      expect(doc.at_css("form[action='/subscriptions']")).to be_nil
    end
  end

  describe "results summary" do
    it "shows the filtered count and the EUR total of the filtered set only" do
      create_contract!(title: "Gas supply", amount: BigDecimal("1000"))
      create_contract!(title: "Gas pipeline", amount: BigDecimal("250.50"))
      create_contract!(title: "Road repair", amount: BigDecimal("9999"))

      get "/", params: { q: "gas" }

      expect(summary_text).to eq("2 contracts Total: 1250.5#{nbsp}EUR")
    end

    it "states the records the total leaves out: no amount, and another currency, never summed in" do
      create_contract!(amount: BigDecimal("100"))
      create_contract!(amount: nil)
      create_contract!(amount: nil)
      create_contract!(amount: BigDecimal("777")).update_column(:currency, "USD")

      get "/"

      expect(summary_text).to eq("4 contracts Total: 100.0#{nbsp}EUR 2 without an amount 1 in another currency")
      expect(doc.css("p.cs-bar__sum .cs-bar__note").map { |node| node.text.strip })
        .to eq(["2 without an amount", "1 in another currency"])
    end

    it "shows the count alone when no record carries an EUR amount" do
      create_contract!(amount: nil)

      get "/"

      expect(summary_text).to eq("1 contract 1 without an amount")
      expect(doc.css(".cs-bar__figure").size).to eq(1)
    end

    it "sets the total in millions from a million up, in Slovak with non-breaking spaces" do
      create_contract!(amount: BigDecimal("12_400_000"))
      create_contract!(amount: nil)

      I18n.with_locale(:sk) { get "/" }

      expect(summary_text).to start_with("2 zm")
      expect(summary_text).to include("Súčet: 12,4#{nbsp}mil.#{nbsp}EUR").and include("1 bez sumy")
    end

    it "sets a smaller total exactly, grouped with non-breaking spaces, and uses the Slovak plurals" do
      5.times { create_contract!(amount: BigDecimal("1000.50")) }

      I18n.with_locale(:sk) { get "/" }

      expect(summary_text).to include("5 zmlúv").and include("Súčet: 5#{nbsp}002,50#{nbsp}EUR")
    end

    it "answers from at most two queries of its own, whatever the number of records" do
      create_contract!
      get "/" # warm-up: first-request schema work is not under test
      query = Decidim::ContractsSk::CatalogueQuery.new(scope: contract_class.published, params: {})

      with_few = count_queries { query.summary }
      10.times { create_contract!(amount: BigDecimal("5")) }
      with_many = count_queries { Decidim::ContractsSk::CatalogueQuery.new(scope: contract_class.published, params: {}).summary }

      expect(with_few).to be <= 2
      expect(with_many).to eq(with_few)
    end

    it "skips the sum query when no EUR amount exists" do
      create_contract!(amount: nil)

      queries = count_queries { Decidim::ContractsSk::CatalogueQuery.new(scope: contract_class.published, params: {}).summary }

      expect(queries).to eq(1)
    end
  end

  describe "filter chips" do
    before { create_contract!(title: "Gas supply", amount: BigDecimal("3000")) }

    it "carries the applied value in the chip label and tints the chip" do
      get "/", params: { amount_min: "1000", amount_max: "5000", published_from: "2026-09-01", party: "Stavby",
                         source: "editorial" }

      labels = doc.css("details.cs-chip.cs-chip--on > summary").map { |node| node.text.gsub(/[ \t\n]+/, " ").strip }
      expect(labels).to eq(["Amount: 1,000–5,000#{nbsp}€", "Publication date: from 2026-09-01",
                            "Party / IČO: Stavby", "Source: Organisation's own records"])
      expect(doc.css("details.cs-chip:not(.cs-chip--on) > summary").map { |node| node.text.squish })
        .to eq(["Signing date"])
    end

    it "submits one form: every chip's fields live inside the single search form" do
      get "/"

      form = doc.at_css("form[role=search]")
      expect(doc.css("form").size).to eq(1)
      expect(form.css("details.cs-chip").size).to eq(5)
      expect(form.css("details.cs-chip button[type=submit]").size).to eq(5)
      expect(form.css("input[name], select[name]").map { |node| node["name"] })
        .to include("q", "amount_min", "amount_max", "published_from", "published_to", "signed_from", "signed_to",
                    "party", "source")
    end

    it "lists every applied filter as a link that drops that one param and keeps the rest" do
      get "/", params: { q: "gas", amount_min: "1000", source: "editorial", sort: "amount_desc" }

      links = doc.css("ul.cs-active__list a.cs-tag").to_h do |a|
        [a.text.squish.sub(/\ARemove filter: /, ""), a["href"]]
      end
      expect(links).to eq(
        "Search: gas" => "/?amount_min=1000&sort=amount_desc&source=editorial",
        "Amount from: 1000.0 EUR" => "/?q=gas&sort=amount_desc&source=editorial",
        "Source: Organisation's own records" => "/?amount_min=1000&q=gas&sort=amount_desc"
      )
      expect(doc.at_css("a.cs-active__clear")["href"]).to eq("/")
    end

    it "offers no removal links, and no clear link, on the plain catalogue" do
      get "/"

      expect(doc.at_css(".cs-active")).to be_nil
    end

    it "never turns the sort into a removable filter" do
      get "/", params: { sort: "amount_asc" }

      expect(doc.at_css(".cs-active")).to be_nil
      expect(doc.at_css("input[type=hidden][name=sort]")["value"]).to eq("amount_asc")
    end
  end

  describe "toolbar" do
    before do
      create_contract!(title: "Gas supply", amount: BigDecimal("3000"))
      create_contract!(title: "Gas pipeline", amount: BigDecimal("40"))
    end

    let(:filters) { { q: "gas", amount_min: "10", sort: "amount_asc" } }

    it "lists the sort choices as links carrying the filters, marks the current one, and drops the page" do
      get "/", params: filters.merge(page: "1")

      menu = doc.css("details.cs-menu").first
      expect(menu.at_css("summary").text.squish).to eq("Sort: lowest amount")
      links = menu.css("li a").to_h { |a| [a.text.strip, a["href"]] }
      expect(links).to eq(
        "Newest first" => "/?amount_min=10&q=gas",
        "Oldest first" => "/?amount_min=10&q=gas&sort=published_asc",
        "Highest amount first" => "/?amount_min=10&q=gas&sort=amount_desc",
        "Lowest amount first" => "/?amount_min=10&q=gas&sort=amount_asc"
      )
      expect(menu.css("a[aria-current]").map { |a| a.text.strip }).to eq(["Lowest amount first"])
    end

    it "offers the four downloads with the filters but without the sort, and the terms line" do
      get "/", params: filters

      menu = doc.css("details.cs-menu")[1]
      expect(menu.at_css("summary").text.squish).to eq("Download")
      expect(menu.css("li a").to_h { |a| [a.text.strip, a["href"]] }).to eq(
        "CSV" => "/export.csv?amount_min=10&q=gas",
        "CSV for Excel" => "/export.csv?amount_min=10&profile=excel&q=gas",
        "JSON" => "/export.json?amount_min=10&q=gas",
        "Atom feed" => "/feed.atom?amount_min=10&locale=en&q=gas"
      )
      expect(menu.at_css("p.cs-small").text).to include("Reuse terms").and include("own records")
    end

    it "links Follow to the alerts page with the filters but without the sort" do
      get "/", params: filters

      follow = doc.at_css("a.cs-bar__follow")
      expect(follow["href"]).to eq("/subscriptions/new?amount_min=10&q=gas")
      expect(follow.text.strip).to eq("Follow")
      expect(follow.at_css("svg[aria-hidden=true]")).to be_present
    end

    it "swaps the downloads for a pointer to crz.gov.sk and drops Follow for the source=crz filter" do
      create_contract!(title: "Mirror", source: "crz", source_id: "7002", amount: BigDecimal("5"))

      get "/", params: { source: "crz" }

      menu = doc.css("details.cs-menu")[1]
      expect(menu.css("a").map { |a| a["href"] }).to eq(["https://www.crz.gov.sk/"])
      expect(response.body).not_to include("/export.")
      expect(response.body).not_to include("/feed.")
      expect(doc.at_css("a.cs-bar__follow")).to be_nil
    end

    it "uses one native <details> group, so only one menu or chip is open at a time" do
      get "/"

      names = doc.css("details").map { |node| node["name"] }
      expect(names).to all(eq("cs-pop"))
      expect(names.size).to eq(7)
    end
  end

  describe "rows" do
    it "renders the date, the title link, the amount, the contractors, the reference and the CRZ label" do
      contract = create_contract!(title: "Gas supply", reference: "ZP-9", amount: BigDecimal("1250.5"),
                                  source: "crz", source_id: "7001", imported_at: Time.utc(2026, 10, 6, 8),
                                  crz_published_on: Date.new(2026, 10, 5))
      add_party!(contract, "Plyn s.r.o.", "36396567")
      add_party!(contract, "Jana Nováková")
      add_party!(contract, "Obec Ukážková", "00306100", role: "object")

      get "/"

      row = doc.at_css("ol.cs-list > li.cs-row")
      date = row.at_css("time.cs-row__date:not(.cs-row__date--meta)")
      expect(date.text.squish).to eq("Published in CRZ on: 2026-10-05")
      expect(row.at_css("a.cs-row__title")["href"]).to eq("/#{contract.id}")
      expect(row.at_css(".cs-row__amount").text).to eq("1250.5 EUR")
      parties = row.at_css(".cs-row__parties")
      expect(parties.css("a").map { |a| [a.text, a["href"]] }).to eq([["Plyn s.r.o.", "/suppliers/36396567"]])
      expect(parties.text.squish).to eq("Plyn s.r.o., Jana Nováková")
      expect(parties.text).not_to include("Obec Ukážková")
      expect(row.at_css(".cs-row__meta").text).to include("ZP-9")
      expect(row.at_css(".cs-row__src").text.squish).to eq("Externally confirmed: CRZ · 2026-10-06")
    end

    it "never links a contractor without an IČO" do
      contract = create_contract!
      add_party!(contract, "Jana Nováková")

      get "/"

      expect(doc.at_css(".cs-row__parties a")).to be_nil
      expect(doc.at_css(".cs-row__parties").text.squish).to eq("Jana Nováková")
    end

    it "renders no amount element for a record without an amount, and no CRZ label for an editorial one" do
      create_contract!(amount: nil)

      get "/"

      expect(doc.at_css(".cs-row__amount")).to be_nil
      expect(doc.at_css(".cs-row__src")).to be_nil
    end

    it "keeps the date once in the accessibility tree: the narrow-screen copy sits in the meta line" do
      create_contract!

      get "/"

      dates = doc.css("li.cs-row time")
      expect(dates.size).to eq(2)
      expect(dates.map { |node| node["class"] }).to eq(["cs-row__date", "cs-row__date cs-row__date--meta"])
      expect(dates.map { |node| node["datetime"] }.uniq.size).to eq(1)
      css = File.read(Decidim::ContractsSk::Engine.root.join("app/views/decidim/contracts_sk/shared/_public_styles.html.erb"))
      expect(css).to include(".cs-row__date--meta { display: none; }")
      expect(css).to include(".cs-row__date:not(.cs-row__date--meta) { display: none; }")
    end

    it "shows at most three contractors and counts the rest" do
      contract = create_contract!
      %w[Alfa Beta Gama Delta Epsilon].each { |name| add_party!(contract, name) }

      get "/"

      expect(doc.at_css(".cs-row__parties").text.squish).to eq("Alfa, Beta, Gama, +2")
    end

    it "runs a constant number of queries whatever the number of rows and parties" do
      add_all = lambda do |count|
        count.times do
          contract = create_contract!
          add_party!(contract, "Plyn s.r.o.", "36396567")
          add_party!(contract, "Voda a.s.", "12345678")
        end
      end
      add_all.call(1)
      get "/"
      with_few = count_queries { get "/" }

      add_all.call(8)
      with_many = count_queries { get "/" }

      expect(doc.css("li.cs-row").size).to eq(9)
      expect(with_many).to eq(with_few)
    end
  end

  describe "pager" do
    before { (Decidim::ContractsSk::CONTRACTS_PER_PAGE * 3).times { create_contract! } }

    it "links the pages with the filters, marks the current one and drops it from the links" do
      get "/", params: { page: "2", amount_min: "1" }

      pager = doc.at_css("nav.cs-pager")
      expect(pager.at_css("[aria-current=page]").text).to eq("2")
      expect(pager.at_css("[aria-current=page]").name).to eq("span")
      expect(pager.css("a").map { |a| [a.text.strip, a["href"]] }).to eq(
        [["Previous", "/?amount_min=1&page=1"], ["1", "/?amount_min=1&page=1"], ["3", "/?amount_min=1&page=3"],
         ["Next", "/?amount_min=1&page=3"]]
      )
      expect(pager.at_css("a[rel=next]")["href"]).to eq("/?amount_min=1&page=3")
      expect(pager.at_css("a[rel=prev]")).to be_present
    end

    it "keeps the page-of text for screen readers" do
      get "/", params: { page: "2" }

      expect(doc.at_css("nav.cs-pager p.cs-sr").text).to eq("Page 2 of 3")
    end
  end

  describe "empty states" do
    it "says nothing matches in one line, with a way to clear the filters, when filters match nothing" do
      create_contract!

      get "/", params: { q: "nothing-like-this" }

      empty = doc.at_css("p.cs-empty")
      expect(empty.text.squish).to start_with("No contracts match your search or filters.")
      expect(empty.css("a").map { |a| a.text.squish }).to eq(["Clear filters", "Follow"])
      expect(empty.at_css("a[href='/']")).to be_present
      expect(doc.at_css(".cs-bar")).to be_nil
    end

    it "keeps the plain empty state for an empty catalogue" do
      get "/"

      expect(doc.at_css("p.cs-empty").text.squish).to eq("No published contracts yet.")
      expect(doc.at_css(".cs-bar")).to be_nil
    end
  end

  describe "style guards" do
    let(:css) do
      File.read(Decidim::ContractsSk::Engine.root.join("app/views/decidim/contracts_sk/shared/_public_styles.html.erb"))
    end

    it "hides the chips, the toolbar menus, the pager and the switch in print" do
      print_block = css[/@media print \{.*?\n  \}/m]

      expect(print_block).to include(".cs-find", ".cs-bar__tools", ".cs-pager", ".cs-switch")
      expect(print_block).to include("display: none")
    end

    it "gives every summary a visible focus ring" do
      expect(css).to include(".cs-reg summary:focus-visible { outline: 3px solid #0b5cad")
    end

    it "resets the list style of the register" do
      expect(css).to include(".cs-list { list-style: none;")
      expect(css).to match(/\.cs-pager__list \{[^}]*list-style: none;/)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
