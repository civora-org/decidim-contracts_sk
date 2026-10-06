# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the public contracts catalogue (civora-org/civora-platform
# #62, #63), run against the Stage-1 dummy harness (spec/dummy mounts the
# engine at "/"). Two layers, one file — mirroring the admin request specs:
#
# * The default (offline, DB-free) group pins the rendering and the
#   not-found path. The controller's #published_contracts is the record
#   seam: an AR scope execution would need a connection, so request specs
#   stub it per-example with allow_any_instance_of (the approved harness
#   seam — see spec/requests/admin/contracts_spec.rb). Documents are part
#   of the show render since M02-05-A0 (#73): the offline doubles carry
#   plain arrays of document doubles — a blob-backed link needs a real
#   blob row, so the offline group covers only the not-attached/empty
#   shapes, while the real download links run in the :db group.
#
# * The :db group (CONTRACTS_SK_DB=1) pins the published-only scoping, the
#   organization tenancy, the document links against the real ActiveStorage
#   tables (built from the pinned activestorage gem's own migration; the
#   engine ships none — the host app owns that schema) and the end-to-end
#   rendering on an in-memory SQLite adapter.
#
# Not-found semantics: both actions read exclusively through the published
# scope, so an unpublished record, another organization's record and a
# nonexistent id take the SAME code path and raise the SAME exception
# (ActiveRecord::RecordNotFound). The harness re-raises exceptions out of
# the request (show_exceptions :none — see spec/dummy/config/application.rb),
# so the raise itself is the asserted behavior, exactly as in the admin
# specs.
#
# Synthetic data only, no real PII (the uploaded fixtures are synthetic
# PDF-shaped/text bytes, no real content).
#
# Cop note: allow_any_instance_of is the approved seam for this harness (the
# record scope lives on the controller; request specs cannot inject records
# into the framework's instantiation path), so the cop is disabled file-wide
# along with the dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Attributes of the published fixture contract shared by the :db examples
# (a fresh database per example; the overrides keep identities unique). Kept
# in a plain module (not inside a describe block) so that its constant stays
# lint-clean, mirroring the locales/routing spec pattern.
module PublishedContractFixture
  DEFAULTS = {
    state: "published",
    published_at: Time.utc(2026, 9, 1, 12, 0, 0),
    subject_matter: "Supply and installation of road signage",
    amount: BigDecimal("1250.50"),
    currency: "EUR",
    signed_on: Date.new(2026, 9, 1),
    effective_from: Date.new(2026, 8, 15),
    crz_url: "https://crz.gov.sk/record/123"
  }.freeze
end

# Status and body are asserted per example by design: every example must
# prove what rendered and why.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance

# Minimal paginable wrapper for the offline group (civora-org/civora-platform
# #86b): the controller paginates the published scope through Kaminari
# (.page/.per), so the offline stub must answer the chain with an object
# carrying the pagination surface the view renders. Defaults render exactly
# one page, so the pagination partial stays hidden and the pre-pagination
# assertions below are unchanged.
class PaginableStub
  include Enumerable

  def initialize(records, total_pages: 1)
    @records = records
    @total_pages = total_pages
  end

  attr_reader :total_pages

  # The catalogue query orders the (stubbed) scope; the stub ignores it.
  def reorder(*)
    self
  end

  # The register preloads parties; the stub's doubles carry none.
  def includes(*)
    self
  end

  # The toolbar's summary reads the filtered set through
  # relation.group(:currency).pluck(...) and .sum(:amount); the stub answers
  # both from its records (one EUR group).
  def group(*)
    self
  end

  def pluck(*)
    [["EUR", @records.size, @records.count { |record| record.amount.present? }]]
  end

  def sum(*)
    { "EUR" => @records.sum(BigDecimal("0")) { |record| record.amount.to_d } }
  end

  def page(_num)
    self
  end

  def per(_num)
    self
  end

  def each(&block)
    @records.each(&block)
  end

  def any?
    @records.any?
  end

  def current_page
    1
  end

  def prev_page; end

  def next_page
    total_pages > 1 ? 2 : nil
  end
end

# Recording twin of PaginableStub for the catalogue's :q search (mirrors the
# admin specs' RecordingIndexScope): the controller applies its search with
# `where(TextSearch::CONTRACT_CONDITION, pattern: ...)` on the stubbed scope, so the where
# args/kwargs land in #applied and the offline group can pin the condition
# and the escaped pattern without a connection.
class SearchablePaginableStub < PaginableStub
  def applied
    @applied ||= []
  end

  def where(*args, **kwargs)
    applied << [args, kwargs]
    self
  end
end

RSpec.describe "public contracts catalogue", type: :request do
  # The controller's published scope is the single offline seam (see the
  # header): both actions read every record through it.
  def stub_published_contracts(scope)
    allow_any_instance_of(Decidim::ContractsSk::ContractsController)
      .to receive(:published_contracts).and_return(scope)
    # The index also builds the feed auto-discovery link (#120), which names
    # the organization; the harness has no Decidim organization middleware.
    allow_any_instance_of(Decidim::ContractsSk::ContractsController)
      .to receive(:current_organization)
      .and_return(double(name: { "en" => "Test Org" }, host: "example.org", default_locale: "en"))
  end

  # rubocop:disable Metrics/MethodLength -- one literal double; splitting it would hide the surface it fakes
  def published_contract_double(overrides = {})
    double(
      title: "Road reconstruction",
      reference: "ZP-2026-001",
      published_at: Time.new(2026, 9, 1, 12, 0, 0),
      crz_published_on: nil,
      # Provenance defaults of an editorial record (civora-org/civora-platform
      # #88): every card renders through imported_contract?/the provenance
      # line, so the double must answer the provenance surface even when the
      # example does not care about it.
      source: "editorial",
      imported_at: nil, import_status: nil,
      # The register row's amount column (guarded: a blank amount renders
      # no cell).
      amount: BigDecimal("1250.5"), currency: "EUR",
      to_param: "7",
      # The register row's contractor names; none by default.
      parties: [],
      **overrides
    )
  end
  # rubocop:enable Metrics/MethodLength

  describe "open-data download block (civora-org/civora-platform#119)" do
    before { stub_published_contracts(SearchablePaginableStub.new([published_contract_double])) }

    it "links the three downloads carrying the active filters but never the sort" do
      get "/", params: { q: "road", amount_min: "100", sort: "amount_asc" }

      body = response.body
      aggregate_failures do
        expect(body).to include(">Download<")
        expect(body).to include(%(href="/export.csv?amount_min=100&amp;q=road"))
        expect(body).to include(%(href="/export.csv?amount_min=100&amp;profile=excel&amp;q=road"))
        expect(body).to include(%(href="/export.json?amount_min=100&amp;q=road"))
        expect(body).not_to include("export.csv?amount_min=100&amp;q=road&amp;sort")
        expect(body).to include(%(href="/feed.atom?amount_min=100&amp;locale=en&amp;q=road"),
                                %(type="application/atom+xml"))
        expect(body).not_to include("feed.atom?amount_min=100&amp;locale=en&amp;q=road&amp;sort")
        expect(body).to include(%(type="text/csv"), %(type="application/json"))
        expect(body).to include("records taken from CRZ are not included")
      end
    end

    it "offers the plain downloads on the unfiltered catalogue" do
      get "/"

      expect(response.body).to include(%(href="/export.json"))
    end

    it "swaps the links for a pointer to crz.gov.sk when the source filter is crz" do
      get "/", params: { source: "crz" }

      aggregate_failures do
        expect(response.body).to include("crz.gov.sk")
        expect(response.body).to include("not offered as downloads")
        expect(response.body).not_to include("/export.")
        expect(response.body).not_to include("/feed.")
      end
    end
  end

  describe "catalogue index (civora-org/civora-platform#62)" do
    it "shows the amount with its currency in the register row" do
      stub_published_contracts(PaginableStub.new([published_contract_double]))

      get "/"

      expect(response.body).to include("1250.5 EUR")
    end

    it "renders no amount cell when the amount is blank" do
      stub_published_contracts(PaginableStub.new([published_contract_double(amount: nil)]))

      get "/"

      expect(response.body).not_to include("cs-amount")
    end

    it "lists a published contract with title, reference, publication date and a detail link" do
      stub_published_contracts(PaginableStub.new([published_contract_double]))

      get "/"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Road reconstruction")
        expect(response.body).to include("ZP-2026-001")
        expect(response.body).to include("2026-09-01")
        expect(response.body).to include(%(href="/7"))
        # A single page renders no page controls (civora-org/civora-platform#86b).
        expect(response.body).not_to include("Page 1 of 1")
      end
    end

    it "renders the localized empty state when nothing is published" do
      stub_published_contracts(PaginableStub.new([]))

      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No published contracts yet.")
    end

    it "renders page controls carrying the page param when a second page exists (civora-org/civora-platform#86b)" do
      stub_published_contracts(PaginableStub.new([published_contract_double], total_pages: 2))

      get "/"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Page 1 of 2")
        expect(response.body).to include("page=2")
      end
    end

    it "answers 200 when the page param is an array (the controller stringifies it before Kaminari)" do
      stub_published_contracts(PaginableStub.new([published_contract_double]))

      get "/", params: { page: ["2"] }

      expect(response).to have_http_status(:ok)
    end

    it "builds pagination links from allowlisted params only (spoofed routing params never reach url_for)" do
      stub_published_contracts(PaginableStub.new([published_contract_double], total_pages: 2))

      get "/", params: { controller: "evil", action: "evil" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("page=2")
      # The partial carries no query params for this filter-less listing, so
      # a spoofed controller/action can neither break nor re-route the links.
      expect(response.body).not_to include("evil")
    end

    it "pins the shared search condition: down-cased column and an explicit ESCAPE clause" do
      # One vocabulary for the public q and the admin q (civora-org/civora-platform#116).
      expect(Decidim::ContractsSk::Admin::ContractsController::SEARCH_CONDITION)
        .to eq(Decidim::ContractsSk::TextSearch::CONTRACT_CONDITION)
      expect(Decidim::ContractsSk::TextSearch::CONTRACT_CONDITION).to eq(
        "LOWER(decidim_contracts_sk_contracts.title) LIKE :pattern ESCAPE '\\' OR " \
        "LOWER(decidim_contracts_sk_contracts.reference) LIKE :pattern ESCAPE '\\'"
      )
    end

    it "renders the free-text search form above the results" do
      stub_published_contracts(PaginableStub.new([published_contract_double]))

      get "/"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Search contracts")
        expect(response.body).to include(%(name="q"))
        # A GET form, so the search state lives in the URL and survives the
        # pagination links.
        expect(response.body).to include(%(action="/"))
        expect(response.body).to include(%(method="get"))
      end
    end

    it "shows the active query in the search field" do
      stub_published_contracts(SearchablePaginableStub.new([published_contract_double]))

      get "/", params: { q: "road" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(value="road"))
    end

    it "applies the admin-mirrored LIKE condition with the stripped, escaped pattern" do
      scope = SearchablePaginableStub.new([published_contract_double])
      stub_published_contracts(scope)

      get "/", params: { q: "  road  " }

      expect(response).to have_http_status(:ok)
      q_filter = scope.applied.find { |(_args, kwargs)| kwargs.key?(:pattern) }
      aggregate_failures do
        expect(q_filter[0].first).to eq(Decidim::ContractsSk::TextSearch::CONTRACT_CONDITION)
        expect(q_filter[1][:pattern]).to eq("%road%")
      end
    end

    it "escapes the LIKE wildcards in the search term" do
      scope = SearchablePaginableStub.new([])
      stub_published_contracts(scope)

      get "/", params: { q: "100%_deal" }

      expect(response).to have_http_status(:ok)
      q_filter = scope.applied.find { |(_args, kwargs)| kwargs.key?(:pattern) }
      # sanitize_sql_like pre-escapes % and _, so user-supplied wildcards
      # stay literal (the same rule the admin :q filter follows).
      expect(q_filter[1][:pattern]).to eq("%100\\%\\_deal%")
    end

    it "applies no WHERE clause when q is blank and falls back to the plain empty state" do
      scope = SearchablePaginableStub.new([])
      stub_published_contracts(scope)

      get "/", params: { q: "   " }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(scope.applied).to eq([])
        expect(response.body).to include("No published contracts yet.")
        expect(response.body).not_to include("No contracts match your search or filters.")
      end
    end

    it "renders the distinct no-results message when a non-blank search finds nothing" do
      stub_published_contracts(SearchablePaginableStub.new([]))

      get "/", params: { q: "zzz" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("No contracts match your search or filters.")
        # The search-miss state is distinct from the empty-catalogue one.
        expect(response.body).not_to include("No published contracts yet.")
      end
    end

    it "carries the active query over the pagination links" do
      stub_published_contracts(SearchablePaginableStub.new([published_contract_double],
                                                           total_pages: 2))

      get "/", params: { q: "road" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Page 1 of 2")
        # The shared pagination partial carries the catalogue's single
        # filter key over, so paging never drops the search state.
        expect(response.body).to include("q=road")
        expect(response.body).to include("page=2")
      end
    end

    # Catalogue filters and sorting (civora-org/civora-platform#116). The
    # offline group pins the form and the normalization seam through the
    # recording stub (party filters need a real connection: :db group).
    describe "filters (civora-org/civora-platform#116)" do
      let(:scope) { SearchablePaginableStub.new([published_contract_double]) }

      before { stub_published_contracts(scope) }

      it "renders the filter form: native details, labelled fields, grouped ranges and a party hint" do
        get "/"

        expect(response).to have_http_status(:ok)
        body = response.body
        aggregate_failures do
          # One GET form carries the search and the five chips; each chip is a native <details> in one
          # exclusive group, and its label is the idle name.
          page = Nokogiri::HTML.parse(body)
          expect(page.css("form[role=search] details.cs-chip[name=cs-pop]").size).to eq(5)
          expect(page.css("form[role=search] details.cs-chip > summary").map { |node| node.text.strip })
            .to eq(["Amount", "Publication date", "Signing date", "Party / IČO", "Source"])
          expect(body).to include("<summary")
          expect(body.scan("<fieldset").size).to eq(3)
          %w[amount_min amount_max published_from published_to signed_from signed_to party source].each do |name|
            expect(body).to include(%(name="#{name}"))
            expect(body).to include(%(for="#{name}"))
          end
          expect(body).to include(%(inputmode="decimal"))
          expect(body).to include(%(type="date"))
          expect(body).to include(%(aria-describedby="party-hint"))
          expect(body).to include(%(id="party-hint")).and include("8-digit IČO, or the name of a party with an IČO")
          expect(body).to include("Any").and include("Organisation&#39;s own records").and include("Mirrored from CRZ")
          # The sort moved to the toolbar menu; the form carries it only when it is not the default.
          expect(body).not_to include(%(name="sort"))
        end
      end

      it "keeps every chip idle and shows no applied filters or clear link without filters" do
        get "/"

        aggregate_failures do
          expect(response.body).not_to include("cs-chip--on")
          expect(response.body).not_to include("Active filters")
          expect(response.body).not_to include("Clear filters")
        end
      end

      it "keeps every chip idle when only q is active, and offers the clear link" do
        get "/", params: { q: "road" }

        expect(response.body).not_to include("cs-chip--on")
        expect(response.body).to include("Clear filters")
      end

      it "opens the filters and prefills NORMALIZED values when filters are active" do
        get "/", params: { amount_min: "10 000,50", published_from: "1.9.2026", signed_to: "2026-09-30",
                           party: "  Obec   Ukážková ", source: "CRZ", sort: "amount_asc" }

        expect(response).to have_http_status(:ok)
        body = response.body
        aggregate_failures do
          expect(body).to include(%(value="10000.5"))
          expect(body).to include(%(value="2026-09-01"))
          expect(body).to include(%(value="2026-09-30"))
          expect(body).to include(%(value="Obec Ukážková"))
          expect(body).to include(%(<option selected="selected" value="crz">))
          expect(body).to include(%(<input type="hidden" name="sort" value="amount_asc" autocomplete="off" />))
        end
      end

      it "summarises the active filters and links to the unfiltered catalogue" do
        get "/", params: { q: "road", amount_max: "500", source: "crz", sort: "published_asc" }

        body = response.body
        aggregate_failures do
          expect(body).to include("Active filters")
          expect(body).to include("Search: road")
          expect(body).to include("Amount to: 500.0 EUR")
          expect(body).to include("Source: Mirrored from CRZ")
          # The sort has its own menu: it is no removable filter.
          expect(body).not_to include("Sort: Oldest first")
          expect(body).to include(%(<a class="cs-active__clear" href="/">Clear filters</a>))
        end
      end

      it "shows a swapped range swapped in the form" do
        get "/", params: { amount_min: "500", amount_max: "100",
                           published_from: "2026-09-10", published_to: "2026-09-01" }

        page = Nokogiri::HTML.parse(response.body)
        aggregate_failures do
          expect(page.at_css("#amount_min")["value"]).to eq("100")
          expect(page.at_css("#amount_max")["value"]).to eq("500")
          expect(page.at_css("#published_from")["value"]).to eq("2026-09-01")
          expect(page.at_css("#published_to")["value"]).to eq("2026-09-10")
        end
      end

      it "ignores every invalid value: 200, no filter applied, no summary" do
        get "/", params: { amount_min: "10.000", amount_max: "-5", published_from: "2026-02-30",
                           published_to: "garbage", signed_from: "32.1.2026", signed_to: "x",
                           party: "   ", source: "bogus", sort: "bogus; DROP TABLE" }

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(scope.applied).to eq([])
          expect(response.body).not_to include("Active filters")
          expect(response.body).not_to include(%(class="cs-filters" open))
        end
      end

      it "answers 200 for array and hash params instead of raising" do
        get "/?q[]=a&amount_min[x]=1&party[]=b&sort[]=amount_asc&source[a]=crz&published_from[]=2026-01-01"

        expect(response).to have_http_status(:ok)
        expect(scope.applied).to eq([])
      end

      it "hands normalized ranges to the scope (amount, signed ranges, the published condition)" do
        get "/", params: { amount_min: "100", amount_max: "200,5", signed_from: "1.5.2026", signed_to: "2026-05-31",
                           published_from: "2026-09-01", published_to: "2026-09-30" }

        ranges = scope.applied.filter_map { |(_args, kwargs)| kwargs }.reduce({}, :merge)
        aggregate_failures do
          expect(ranges[:amount]).to eq(BigDecimal(100)..BigDecimal("200.5"))
          expect(ranges[:signed_on]).to eq(Date.new(2026, 5, 1)..Date.new(2026, 5, 31))
          # The publication filter is one Arel condition (CRZ date, else
          # published_at; CatalogueQuery::Conditions#by_published), not a range.
          expect(scope.applied.map(&:first).flatten).to include(be_a(Arel::Nodes::Node))
        end
      end

      it "splits sources on the stubbed scope" do
        get "/", params: { source: "crz" }

        expect(scope.applied.last[1]).to eq(source: "crz")
      end

      it "renders the no-results variant, not the empty-catalogue one, for a filter-only miss" do
        stub_published_contracts(SearchablePaginableStub.new([]))

        get "/", params: { source: "crz" }

        aggregate_failures do
          expect(response.body).to include("No contracts match your search or filters.")
          expect(response.body).not_to include("No published contracts yet.")
        end
      end

      it "carries every filter key over the pagination links" do
        stub_published_contracts(SearchablePaginableStub.new([published_contract_double], total_pages: 2))
        params = { q: "road", amount_min: "1", amount_max: "9", published_from: "2026-01-01",
                   published_to: "2026-12-31", signed_from: "2026-02-01", signed_to: "2026-03-01",
                   party: "Obec", source: "crz", sort: "amount_desc" }

        get "/", params: params

        link = response.body[/href="([^"]*page=2[^"]*)"/, 1].to_s.gsub("&amp;", "&")
        carried = Rack::Utils.parse_query(URI(link).query)
        expect(carried.keys).to match_array(params.keys.map(&:to_s) + ["page"])
        params.each { |key, value| expect(carried[key.to_s]).to eq(value) }
      end

      it "carries normalized values only: invalid and empty params never reach the page links" do
        stub_published_contracts(SearchablePaginableStub.new([published_contract_double], total_pages: 2))

        get "/", params: { q: "road", amount_min: "10 000,50", amount_max: "garbage", signed_from: "",
                           published_from: "1.9.2026", source: "bogus", sort: "nope" }

        link = response.body[/href="([^"]*page=2[^"]*)"/, 1].to_s.gsub("&amp;", "&")
        carried = Rack::Utils.parse_query(URI(link).query)
        expect(carried).to eq("q" => "road", "amount_min" => "10000.5", "published_from" => "2026-09-01",
                              "page" => "2")
      end

      it "survives a NUL byte in q and party without raising (PostgreSQL rejects NUL binds)" do
        get "/?q=ro%00ad&party=ab%00"

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("%00")
        expect(scope.applied.first[1][:pattern]).to eq("%ro ad%")
      end

      it "never carries foreign params over the pagination links" do
        stub_published_contracts(SearchablePaginableStub.new([published_contract_double], total_pages: 2))

        get "/", params: { q: "road", evil: "1", controller: "evil" }

        expect(response.body).not_to include("evil")
      end
    end

    it "labels a crz-mirrored card with the provenance badge and import date (civora-org/civora-platform#88)" do
      stub_published_contracts(
        PaginableStub.new([published_contract_double(source: "crz",
                                                     imported_at: Time.new(2026, 9, 10, 8, 0, 0),
                                                     import_status: "succeeded")])
      )

      get "/"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Externally confirmed")
        expect(response.body).to include("2026-09-10")
        # The stale indicator is deliberately detail-only (issue #88): cards
        # stay lean even for stale mirrors.
        expect(response.body).not_to include("may be out of date")
      end
    end

    it "renders no provenance label on an editorial card (civora-org/civora-platform#88)" do
      stub_published_contracts(PaginableStub.new([published_contract_double]))

      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Externally confirmed")
    end
  end

  describe "contract detail (civora-org/civora-platform#63)" do
    let(:parties) { [] }
    let(:documents) { [] }
    let(:links) { [] }
    # The controller loads the public version history through the
    # amendment association (published scope + newest-version-first
    # order); the offline double mirrors that chain (#65).
    let(:amendments) { [] }
    let(:contract) { detail_contract_double }

    # Builds the detail double (civora-org/civora-platform#88: every render
    # consults the provenance predicates, so the default answers the
    # provenance surface of an editorial record). The provenance examples
    # below override the mirror fields. Declarative fixture list, not
    # logic — the same reason .rubocop.yml exempts demo-data builders from
    # the length budget.
    # rubocop:disable Metrics/MethodLength
    def detail_contract_double(overrides = {})
      double(
        title: "Road reconstruction",
        reference: "ZP-2026-001",
        published_at: Time.new(2026, 9, 1, 12, 0, 0),
        subject_matter: "Supply and installation of road signage",
        amount: BigDecimal("1250.50"),
        currency: "EUR",
        signed_on: Date.new(2026, 9, 1),
        effective_from: Date.new(2026, 8, 15),
        crz_url: "https://crz.gov.sk/record/123",
        crz_filed_at: nil,
        crz_published_on: nil,
        source: "editorial",
        imported_at: nil,
        import_status: nil,
        parties: parties,
        documents: documents,
        amendments: double(published: double(order: amendments)),
        links: links,
        **overrides
      )
    end
    # rubocop:enable Metrics/MethodLength

    it "renders the published-safe content fields and the associated parties" do
      parties << double(role: "object", name: "Obec Zelen", ico: "12345678", address: nil)
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Road reconstruction")
        expect(response.body).to include("ZP-2026-001")
        expect(response.body).to include("2026-09-01")
        expect(response.body).to include("Supply and installation of road signage")
        expect(response.body).to include("1250.5")
        expect(response.body).to include("EUR")
        expect(response.body).to include("2026-08-15")
        expect(response.body).to include(%(href="https://crz.gov.sk/record/123"))
        expect(response.body).to include("Object party")
        expect(response.body).to include("Obec Zelen")
      end
    end

    it "renders no blank field rows for a sparse published record (civora-org/civora-platform#80)" do
      # Only the identity is filled: every optional live field is blank —
      # the exact shape that used to render an empty subject dd and a
      # dangling "EUR" dd (and metadata spans).
      sparse = detail_contract_double(
        published_at: Time.new(2026, 9, 1, 12, 0, 0),
        subject_matter: nil,
        amount: nil,
        signed_on: nil,
        effective_from: nil,
        crz_url: nil
      )
      stub_published_contracts(double(find: sparse))

      get "/7"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        # The identity pair stays unconditional — title/reference are NOT NULL.
        expect(response.body).to include("Road reconstruction")
        expect(response.body).to include("ZP-2026-001")
        # The guarded optional pairs disappear entirely: no blank dd
        # placeholders, no dangling currency label next to a nil amount.
        expect(response.body).not_to include("Subject matter")
        expect(response.body).not_to include("EUR")
        expect(response.body).not_to include("Signed on")
        expect(response.body).not_to include("Effective from")
        expect(response.body).not_to include('<dd class="text-md text-black mt-0"></dd>')
      end
    end

    it "renders the empty-party state gracefully" do
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No parties have been recorded for this contract.")
    end

    it "renders the empty-document state gracefully (civora-org/civora-platform#73)" do
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Documents")
        expect(response.body).to include("No documents have been attached to this contract.")
      end
    end

    it "renders the published amendments as a labelled version history (M02-05-B, civora-org/civora-platform#65)" do
      amendments << double(version: 2,
                           summary: "Extended delivery deadline",
                           published_at: Time.new(2026, 9, 2, 12, 0, 0),
                           content_snapshot: {
                             "subject_matter" => "Supply and installation of road signage",
                             "amount" => "1000.0",
                             "currency" => "EUR"
                           })
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Version history")
        # The current/historical distinction is labelled (ADR-006).
        expect(response.body).to include("Current version")
        expect(response.body).to include("Version 2")
        expect(response.body).to include("Extended delivery deadline")
        expect(response.body).to include("2026-09-02")
        # The frozen snapshot fields render under the record's own
        # content-field vocabulary.
        expect(response.body).to include("Subject matter")
        expect(response.body).to include("1000.0")
      end
    end

    it "skips metadata-only documents that carry no attached file (civora-org/civora-platform#73)" do
      documents << double(file: double(attached?: false))
      stub_published_contracts(double(find: contract))

      get "/7"

      expect(response).to have_http_status(:ok)
      # A document without a file has neither a link nor a size to show —
      # it is skipped, and the section falls back to the empty state.
      expect(response.body).to include("No documents have been attached to this contract.")
    end

    describe "related links section (civora-org/civora-platform#87)" do
      # Swaps both link-seam settings for the duration of an example and
      # restores them afterwards (config-time only — no override may leak).
      def with_link_seam(types, resolver)
        original_types = Decidim::ContractsSk.supported_link_target_types
        original_resolver = Decidim::ContractsSk.link_target_resolver
        Decidim::ContractsSk.supported_link_target_types = types
        Decidim::ContractsSk.link_target_resolver = resolver
        yield
      ensure
        Decidim::ContractsSk.supported_link_target_types = original_types
        Decidim::ContractsSk.link_target_resolver = original_resolver
      end

      def link_double(overrides = {})
        double(target_type: "Decidim::Accountability::Result", target: Object.new, **overrides)
      end

      it "renders resolvable links with their seam-provided label and URL" do
        links << link_double
        stub_published_contracts(double(find: contract))
        with_link_seam(["Decidim::Accountability::Result"],
                       ->(_link) { { label: "Result 12", url: "https://host/results/12" } }) do
          get "/7"
        end

        expect(response).to have_http_status(:ok)
        aggregate_failures do
          expect(response.body).to include(">Links</h2>")
          expect(response.body).to include(%(href="https://host/results/12"))
          expect(response.body).to include("Result 12")
        end
      end

      it "renders a label without a URL as plain text" do
        links << link_double
        stub_published_contracts(double(find: contract))
        with_link_seam(["Decidim::Accountability::Result"], ->(_link) { { label: "Result 12", url: nil } }) do
          get "/7"
        end

        expect(response).to have_http_status(:ok)
        aggregate_failures do
          expect(response.body).to include(">Links</h2>")
          expect(response.body).to include("Result 12")
          expect(response.body).not_to include("https://host/results/12")
        end
      end

      it "hides dangling targets and hides the section entirely when nothing remains" do
        # A dangling link (target row gone) and an unresolvable one are both
        # hidden — the default seam resolves nothing, so even the heading
        # disappears (no empty state on the public page).
        links << link_double(target: nil)
        links << link_double(target_type: "Decidim::User")
        stub_published_contracts(double(find: contract))

        get "/7"

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(">Links</h2>")
      end
    end

    describe "CRZ-mirror provenance block (civora-org/civora-platform#88)" do
      # The offline mirror cases drive the helper's decision surface: the
      # helper compares against Time.current, so a fixed past relative
      # timestamp (X.hours/days.ago) is deterministic without freezing
      # time — fresh stays fresh and stale stays stale on every run.
      it "renders badge, import date and attribution for a fresh crz mirror" do
        imported_at = 1.hour.ago
        stub_published_contracts(
          double(find: detail_contract_double(source: "crz", imported_at: imported_at,
                                              import_status: "succeeded"))
        )

        get "/7"

        expect(response).to have_http_status(:ok)
        aggregate_failures do
          expect(response.body).to include("Externally confirmed")
          expect(response.body).to include("Mirrored from the CRZ register on")
          expect(response.body).to include(imported_at.to_date.to_fs(:db))
          # Attribution preserved verbatim (ADR-008 decision 6 / ekosystem
          # terms).
          expect(response.body).to include("ekosystem.slovensko.digital")
          expect(response.body).to include("not a legal publication")
          # Fresh within the default 48 h stale_after: no stale notice.
          expect(response.body).not_to include("may be out of date")
        end
      end

      it "renders no provenance content for an editorial record" do
        stub_published_contracts(double(find: contract))

        get "/7"

        expect(response).to have_http_status(:ok)
        aggregate_failures do
          expect(response.body).not_to include("Externally confirmed")
          expect(response.body).not_to include("Mirrored from the CRZ register on")
          expect(response.body).not_to include("ekosystem.slovensko.digital")
        end
      end

      it "renders the stale line when imported_at exceeds the stale threshold (ADR-008 D4)" do
        stub_published_contracts(
          double(find: detail_contract_double(source: "crz", imported_at: 3.days.ago,
                                              import_status: "succeeded"))
        )

        get "/7"

        expect(response).to have_http_status(:ok)
        aggregate_failures do
          # 3 days > the 48 h default stale_after: the badge still renders,
          # but with the out-of-date warning instead of silence.
          expect(response.body).to include("Externally confirmed")
          expect(response.body).to include("may be out of date")
        end
      end

      it "renders the stale line when the last import failed, even with a recent timestamp" do
        stub_published_contracts(
          double(find: detail_contract_double(source: "crz", imported_at: 1.hour.ago,
                                              import_status: "failed"))
        )

        get "/7"

        expect(response).to have_http_status(:ok)
        # A failed re-import cannot prove the mirror current (the
        # stale-fallback signal, docs/crz-import.md) — recency is not enough.
        expect(response.body).to include("may be out of date")
      end

      it "renders the stale line and no mirror date when imported_at is blank (freshness cannot be proven)" do
        stub_published_contracts(
          double(find: detail_contract_double(source: "crz", imported_at: nil,
                                              import_status: "succeeded"))
        )

        get "/7"

        expect(response).to have_http_status(:ok)
        aggregate_failures do
          # A crz record without an import timestamp counts as stale (the
          # helper fails closed — freshness cannot be proven), and the view
          # guards the mirror-date line on imported_at presence, so no
          # date-less "Mirrored from..." line may render either.
          expect(response.body).to include("may be out of date")
          expect(response.body).not_to include("Mirrored from the CRZ register on")
        end
      end
    end

    it "raises the not-found exception for a nonexistent id through the published scope" do
      # Offline the raise is all that can be asserted (see the header); the
      # :db group proves below that an unpublished record takes exactly the
      # same path.
      scope = double
      allow(scope).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      stub_published_contracts(scope)

      expect { get "/nonexistent" }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  # Real end-to-end group: the published-only scope, the organization
  # tenancy, the rendering and the not-found indistinguishability against
  # the REAL migrations (in-memory SQLite; fresh database per example via
  # the shared :db support). Document examples additionally build the
  # ActiveStorage tables (host-app-owned schema, test-built from the pinned
  # gem's migration) and wipe the Disk service root for hermeticity.
  describe "published-only scoping and real rendering (civora-org/civora-platform#62, #63)", :db do
    before do
      migrate_engine_schema!
      FileUtils.rm_rf(active_storage_root)

      # Tenancy seam (Gate-1 fold-in): the catalogue reads
      # current_organization, exactly like the admin side; the :db group
      # carries the shared-context organization on it.
      allow_any_instance_of(Decidim::ContractsSk::ContractsController)
        .to receive(:current_organization).and_return(organization)
    end

    # Creates a contract with the published fixture defaults; the overrides
    # adjust identity fields, the lifecycle state and anything else per
    # example.
    def create_contract!(overrides = {})
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(PublishedContractFixture::DEFAULTS.merge(overrides))
      )
    end

    # Path to a synthetic fixture (PDF-shaped/text bytes, no real content).
    def sample_fixture(name)
      File.join(engine_root, "spec", "fixtures", "files", name)
    end

    # Creates a document on the contract and attaches a real fixture file.
    def attach!(contract, title:, kind:, fixture:, type:)
      document = contract.documents.create!(title: title, kind: kind)
      document.attach_file!(Rack::Test::UploadedFile.new(sample_fixture(fixture), type))
      document
    end

    it "lists only published contracts, newest publication first, linked to their detail pages" do
      newer = create_contract!(
        title: "First published road", reference: "ZP-2026-001"
      )
      older = create_contract!(
        title: "Second published road", reference: "ZP-2026-002",
        published_at: Time.utc(2026, 6, 1, 12, 0, 0)
      )
      create_contract!(
        title: "Draft road", reference: "ZP-2026-003",
        state: "draft", published_at: nil
      )
      create_contract!(
        title: "Archived road", reference: "ZP-2026-004",
        state: "archived", published_at: Time.utc(2026, 7, 1, 12, 0, 0)
      )

      get "/"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("First published road")
        expect(response.body).to include("Second published road")
        # The published-only scope is the Gate-1 decision: drafts AND
        # archived records stay out of the catalogue.
        expect(response.body).not_to include("Draft road")
        expect(response.body).not_to include("Archived road")
        # Newest publication first.
        expect(response.body.index("First published road")).to be < response.body.index("Second published road")
        expect(response.body).to include(%(href="/#{newer.id}"))
        expect(response.body).to include(%(href="/#{older.id}"))
      end
    end

    # civora-org/civora-platform#159: the CRZ publication date, labelled as
    # such, replaces the catalogue entry date wherever the record has one.
    describe "publication date (#159)" do
      let!(:mirror) do
        create_contract!(title: "Mirrored road", reference: "ZP-M-1", source: "crz", source_id: "7001",
                         crz_published_on: Date.new(2026, 3, 2), published_at: Time.utc(2026, 9, 5, 12),
                         imported_at: Time.utc(2026, 9, 5, 12))
      end
      let!(:editorial) do
        create_contract!(title: "Editorial road", reference: "ZP-E-1", published_at: Time.utc(2026, 6, 1, 12))
      end

      it "labels the CRZ date on the list card and keeps the entry date bare for a record without one" do
        get "/"

        cards = Nokogiri::HTML(response.body).css("li.cs-row")
                        .to_h { |li| [li.at_css(".cs-row__title").text, li.text.squish] }
        aggregate_failures do
          expect(cards["Mirrored road"]).to include("Published in CRZ on: 2026-03-02")
          # The import time (September) is not shown as the publication date.
          expect(cards["Mirrored road"].sub(/·.*\z/, "")).not_to include("2026-09-05")
          expect(cards["Editorial road"]).to include("2026-06-01")
          expect(cards["Editorial road"]).not_to include("Published in CRZ on")
        end
      end

      it "orders the list by the CRZ date: the older-entered editorial record leads the March mirror" do
        get "/"

        expect(response.body.index("Editorial road")).to be < response.body.index("Mirrored road")
      end

      it "shows the CRZ date with the CRZ label on the detail page, identity line and facts panel" do
        get "/#{mirror.id}"

        doc = Nokogiri::HTML(response.body)
        identity = doc.at_css(".cs-meta").text.squish
        facts = doc.at_css(".cs-facts").text.squish
        aggregate_failures do
          expect(identity).to include("Published in CRZ on: 2026-03-02")
          expect(facts).to include("Published in CRZ on 2026-03-02")
          expect(identity + facts).not_to include("2026-09-05")
        end
      end

      it "shows the CRZ date once in the facts panel of a record confirmed as filed" do
        filed = create_contract!(title: "Filed road", reference: "ZP-F-1", crz_published_on: Date.new(2026, 3, 2),
                                 crz_filed_at: Time.utc(2026, 3, 3, 9), published_at: Time.utc(2026, 9, 5, 12))

        get "/#{filed.id}"

        doc = Nokogiri::HTML(response.body)
        facts = doc.at_css(".cs-facts").text.squish
        aggregate_failures do
          expect(facts.scan("2026-03-02").size).to eq(1)
          expect(facts).to include("Published in CRZ on 2026-03-02") # the existing filed row
          # The identity line keeps its date.
          expect(doc.at_css(".cs-meta").text.squish).to include("Published in CRZ on: 2026-03-02")
        end
      end

      it "keeps the publication row for a record confirmed as filed without a CRZ date" do
        filed = create_contract!(title: "Filed road", reference: "ZP-F-2", crz_filed_at: Time.utc(2026, 3, 3, 9),
                                 published_at: Time.utc(2026, 9, 5, 12))

        get "/#{filed.id}"

        expect(Nokogiri::HTML(response.body).at_css(".cs-facts").text.squish).to include("Published on 2026-09-05")
      end

      it "shows published_at with the original label for a record without a CRZ date" do
        get "/#{editorial.id}"

        doc = Nokogiri::HTML(response.body)
        aggregate_failures do
          expect(doc.at_css(".cs-meta").text.squish).to include("Published on: 2026-06-01")
          expect(doc.at_css(".cs-facts").text.squish).to include("Published on 2026-06-01")
          expect(response.body).not_to include("Published in CRZ on")
        end
      end

      it "filters the catalogue by the CRZ date, not the import time" do
        get "/", params: { published_from: "2026-03-01", published_to: "2026-03-31" }

        aggregate_failures do
          expect(response.body).to include("Mirrored road")
          expect(response.body).not_to include("Editorial road")
        end
      end
    end

    it "survives hostile page values (huge, non-numeric, NUL, array, negative) by clamping" do
      create_contract!

      ["999999999999999999999", "abc", "%00", "-1", "0"].each do |page|
        get "/?page=#{page}"
        expect(response).to have_http_status(:ok)
      end
      get "/", params: { page: ["2"] }
      expect(response).to have_http_status(:ok)
    end

    it "paginates the catalogue at 25 per page, oldest publications last (civora-org/civora-platform#86b)" do
      30.times do |i|
        create_contract!(
          title: "Catalogue road #{i}",
          reference: format("ZP-CAT-%03d", i),
          published_at: Time.utc(2026, 9, 1, 12, 0, 0) + i * 60
        )
      end

      get "/"
      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body.scan(/ZP-CAT-\d{3}/).uniq.size).to eq(25)
        expect(response.body).to include("Page 1 of 2")
        expect(response.body).to include("page=2")
      end

      get "/", params: { page: 2 }
      expect(response).to have_http_status(:ok)
      second_page = response.body.scan(/ZP-CAT-\d{3}/).uniq
      aggregate_failures do
        expect(second_page.size).to eq(5)
        expect(response.body).to include("Page 2 of 2")
        # The catalogue orders newest-first, so the second page holds the
        # five oldest publications.
        expect(second_page.sort).to eq(%w[ZP-CAT-000 ZP-CAT-001 ZP-CAT-002 ZP-CAT-003 ZP-CAT-004])
      end

      # The array page param reaches Kaminari only as a string (controller
      # coercion) and clamps back to page 1.
      get "/", params: { page: ["2"] }
      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/ZP-CAT-\d{3}/).uniq.size).to eq(25)
    end

    it "tie-breaks same-moment publications by id, newest id first" do
      create_contract!(title: "Tie older", reference: "ZP-CAT-100",
                       published_at: Time.utc(2026, 9, 2, 12, 0, 0))
      create_contract!(title: "Tie newer", reference: "ZP-CAT-101",
                       published_at: Time.utc(2026, 9, 2, 12, 0, 0))

      get "/"

      expect(response).to have_http_status(:ok)
      # Equal published_at: the id: :desc tiebreaker decides — the later-
      # created (higher id) record lists first, deterministically.
      expect(response.body.index("Tie newer")).to be < response.body.index("Tie older")
    end

    it "shows a published contract with its content fields and both party roles" do
      contract = create_contract!
      contract.parties.create!(role: "object", name: "Obec Zelen", ico: "12345678")
      contract.parties.create!(role: "contractor", name: "Zeleň a.s.", ico: "87654321")

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Road reconstruction")
        expect(response.body).to include("ZP-2026-001")
        expect(response.body).to include("2026-09-01")
        expect(response.body).to include("Supply and installation of road signage")
        expect(response.body).to include("1250.5")
        expect(response.body).to include("EUR")
        expect(response.body).to include("2026-08-15")
        expect(response.body).to include(%(href="https://crz.gov.sk/record/123"))
        expect(response.body).to include("Object party")
        expect(response.body).to include("Obec Zelen")
        expect(response.body).to include("Contractor")
        expect(response.body).to include("Zeleň a.s.")
      end
    end

    it "renders the provenance block end-to-end for a real crz-sourced record (civora-org/civora-platform#88)" do
      imported_at = Time.current
      contract = create_contract!(
        title: "Imported road", reference: "ZP-IMP-001",
        source: "crz", source_id: "900000001",
        imported_at: imported_at, import_status: "succeeded",
        crz_url: "https://crz.gov.sk/zmluva/900000001/"
      )

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Externally confirmed")
        expect(response.body).to include("Mirrored from the CRZ register on")
        expect(response.body).to include(imported_at.to_date.to_fs(:db))
        expect(response.body).to include("ekosystem.slovensko.digital")
        expect(response.body).to include("not a legal publication")
        # A fresh timestamp relative to the run (the helper compares against
        # Time.current): no stale notice.
        expect(response.body).not_to include("may be out of date")
      end
    end

    it "says the CRZ publication is confirmed, with the date and the official link (#125)" do
      contract = create_contract!(crz_url: "https://crz.gov.sk/zmluva/2142424/", crz_filed_at: Time.current,
                                  crz_published_on: Date.new(2026, 4, 20))

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Published in CRZ on 2026-04-20")
        expect(response.body).to include('href="https://crz.gov.sk/zmluva/2142424/"')
        expect(response.body).not_to include("CRZ URL")
      end
    end

    it "falls back to the plain confirmation line when CRZ carried no publication date (#125)" do
      contract = create_contract!(crz_url: "https://crz.gov.sk/zmluva/2142424/", crz_filed_at: Time.current,
                                  crz_published_on: nil)

      get "/#{contract.id}"

      aggregate_failures do
        expect(response.body).to include("Publication in CRZ confirmed")
        expect(response.body).not_to include("Published in CRZ on")
        expect(response.body).to include('href="https://crz.gov.sk/zmluva/2142424/"')
      end
    end

    it "keeps the plain CRZ URL row for a record not confirmed as filed (#125)" do
      contract = create_contract!(crz_url: "https://crz.gov.sk/zmluva/2142424/")

      get "/#{contract.id}"

      aggregate_failures do
        expect(response.body).to include("CRZ URL")
        expect(response.body).not_to include("Published in CRZ")
        expect(response.body).not_to include("Publication in CRZ confirmed")
      end
    end

    it "omits the CRZ link section entirely when the record carries no crz_url" do
      contract = create_contract!(crz_url: nil)

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      # Neither the localized label nor any link residue may render — the
      # section is guarded, not rendered with an empty href.
      aggregate_failures do
        expect(response.body).not_to include("CRZ URL")
        expect(response.body).not_to include("crz.gov.sk")
      end
    end

    it "renders the empty-party state gracefully for a published record without parties" do
      contract = create_contract!

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No parties have been recorded for this contract.")
    end

    it "lists a published record's documents as download links with kind and size (civora-org/civora-platform#73)" do
      contract = create_contract!
      attach!(contract, title: "Signed contract scan", kind: "contract",
                        fixture: "sample.pdf", type: "application/pdf")
      attach!(contract, title: "Annex notes", kind: "annex",
                        fixture: "sample-notes.txt", type: "text/plain")

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      scan = contract.documents.reload.first
      expected_link = "/rails/active_storage/blobs/redirect/#{scan.file.blob.signed_id}/sample.pdf"
      # A sub-1024-byte fixture humanizes as "<n> Bytes" under the en locale.
      annex_size = "#{File.size(sample_fixture("sample-notes.txt"))} Bytes"
      aggregate_failures do
        # Download links through the host's ActiveStorage route, forced
        # attachment disposition, one per document.
        expect(response.body).to include("Signed contract scan")
        expect(response.body).to include(%(href="#{expected_link}?disposition=attachment))
        expect(response.body).to include("Annex notes")
        expect(response.body).to include("Contract document")
        expect(response.body).to include("(Annex, #{annex_size})")
      end
    end

    it "renders the empty-document state for a published record without attachments (#73)" do
      contract = create_contract!
      # A metadata-only row without an attachment is legal (the #56 shape):
      # it renders nothing rather than a dead entry.
      contract.documents.create!(title: "Placeholder", kind: "other")

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No documents have been attached to this contract.")
    end

    # Swaps both link-seam settings for the duration of the block (the
    # config-time seam — restored even when an assertion fails).
    def with_link_seam(types, resolver)
      original_types = Decidim::ContractsSk.supported_link_target_types
      original_resolver = Decidim::ContractsSk.link_target_resolver
      Decidim::ContractsSk.supported_link_target_types = types
      Decidim::ContractsSk.link_target_resolver = resolver
      yield
    ensure
      Decidim::ContractsSk.supported_link_target_types = original_types
      Decidim::ContractsSk.link_target_resolver = original_resolver
    end

    it "renders a resolvable link end-to-end for a published record (civora-org/civora-platform#87)" do
      contract = create_contract!
      # A REAL polymorphic target: the harness stand-in organization row.
      contract.links.create!(target_type: "Decidim::Organization", target_id: organization.id)

      with_link_seam(["Decidim::Organization"],
                     ->(link) { { label: "Partner municipality", url: "https://host/orgs/#{link.target_id}" } }) do
        get "/#{contract.id}"
      end

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include(">Links</h2>")
        expect(response.body).to include(%(href="https://host/orgs/#{organization.id}"))
        expect(response.body).to include("Partner municipality")
      end
    end

    it "hides a dangling link publicly even with a configured seam, and hides the section under the default seam" do
      contract = create_contract!
      contract.links.create!(target_type: "Decidim::Organization", target_id: 4_242_424)

      with_link_seam(["Decidim::Organization"],
                     ->(link) { { label: "Partner municipality", url: "https://host/orgs/#{link.target_id}" } }) do
        get "/#{contract.id}"
      end

      # The target row does not exist — the polymorphic load fails, the
      # resolution fails closed, the section stays hidden entirely.
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(">Links</h2>")
      expect(response.body).not_to include("Partner municipality")

      # And the standalone default (no host configuration at all) hides a
      # persisted link all the same — the engine links nothing by default.
      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(">Links</h2>")
    end

    it "renders the published amendments newest-first as a labelled version history (#65)" do
      # M02-05-B (civora-org/civora-platform#65): published amendments are
      # the frozen historical versions; created directly here with a
      # pinned snapshot shape (the publish command's own spec pins how the
      # snapshot is taken).
      contract = create_contract!
      contract.amendments.create!(
        version: 1, summary: "Original scope",
        state: "published", published_at: Time.utc(2026, 9, 1, 12, 0, 0),
        content_snapshot: { "subject_matter" => "Original signage scope", "amount" => "1000.0", "currency" => "EUR" },
        organization: organization, author: author
      )
      contract.amendments.create!(
        version: 2, summary: "Extended delivery deadline",
        state: "published", published_at: Time.utc(2026, 9, 2, 12, 0, 0),
        content_snapshot: { "subject_matter" => "Extended signage scope", "amount" => "1500.0",
                            "currency" => "EUR" },
        organization: organization, author: author
      )

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Version history")
        expect(response.body).to include("Current version")
        expect(response.body).to include("Version 1")
        expect(response.body).to include("Original scope")
        expect(response.body).to include("Original signage scope")
        expect(response.body).to include("Version 2")
        expect(response.body).to include("Extended delivery deadline")
        expect(response.body).to include("2026-09-02")
        # Newest version first (ADR-006 presentation order).
        expect(response.body.index("Version 2")).to be < response.body.index("Version 1")
        # The live fields above stay the current version — the record's own
        # amount is unchanged by the published versions.
        expect(response.body).to include("1250.5")
      end
    end

    it "never renders draft amendments publicly (#65, ADR-006)" do
      contract = create_contract!
      contract.amendments.create!(
        version: 1, summary: "Secret upcoming change",
        organization: organization, author: author
      )
      contract.amendments.create!(
        version: 2, summary: "Public change",
        state: "published", published_at: Time.utc(2026, 9, 2, 12, 0, 0),
        content_snapshot: { "subject_matter" => "Public scope", "currency" => "EUR" },
        organization: organization, author: author
      )

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        # The published version renders; the draft is indistinguishable
        # from an absent one.
        expect(response.body).to include("Public change")
        expect(response.body).not_to include("Secret upcoming change")
        expect(response.body).not_to include("Version 1")
      end
    end

    it "renders the empty-versions state for a record without amendments (#65)" do
      contract = create_contract!

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No amendments have been published for this contract.")
    end

    it "hides an unpublished record's documents behind the same not-found path (civora-org/civora-platform#73)" do
      draft = create_contract!(
        title: "Draft road with documents", reference: "ZP-2026-008",
        state: "draft", published_at: nil
      )
      draft.documents.create!(title: "Hidden scan", kind: "contract")
           .attach_file!(Rack::Test::UploadedFile.new(sample_fixture("sample.pdf"), "application/pdf"))

      # The published-only scope is the entire public gate: a draft record's
      # documents cannot leak through the detail page.
      expect { get "/#{draft.id}" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "hides an unpublished record and a nonexistent id behind the same not-found path" do
      draft = create_contract!(
        title: "Draft road", reference: "ZP-2026-005",
        state: "draft", published_at: nil
      )

      # Same exception through the same scoped find: the response cannot
      # distinguish "hidden" from "absent" (see the header for the
      # raise-vs-404 harness note).
      aggregate_failures do
        expect { get "/#{draft.id}" }.to raise_error(ActiveRecord::RecordNotFound)
        expect { get "/#{draft.id + 100_000}" }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "hides an archived record from the detail page too (the scope is published-only, Gate 1)" do
      archived = create_contract!(
        title: "Archived road", reference: "ZP-2026-006",
        state: "archived", published_at: Time.utc(2026, 7, 1, 12, 0, 0)
      )

      expect { get "/#{archived.id}" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "hides another organization's published contract from the index and 404s its id like a nonexistent one" do
      # Tenant isolation (Gate-1 fold-in): the catalogue is org-scoped, so
      # a PUBLISHED record of another organization is as invisible as a
      # hidden one — absent from the index, and its id takes the same
      # tenant-scoped find as a nonexistent id (indistinguishable raise;
      # see the header for the raise-vs-404 harness note).
      foreign_org = Decidim::Organization.create!
      foreign = create_contract!(
        organization: foreign_org,
        title: "Foreign road", reference: "ZP-2026-007"
      )

      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Foreign road")
      expect(response.body).not_to include("ZP-2026-007")

      aggregate_failures do
        expect { get "/#{foreign.id}" }.to raise_error(ActiveRecord::RecordNotFound)
        expect { get "/#{foreign.id + 100_000}" }.to raise_error(ActiveRecord::RecordNotFound)
      end

      # The foreign record itself is untouched — scoping hides, never harms.
      foreign.reload
      expect(foreign.state).to eq("published")
    end

    # Free-text catalogue search (the public twin of the admin index's :q
    # filter): real end-to-end hits/misses on the two editorial identity
    # fields, with the published-only and organization scoping still in
    # force UNDER the search — the filter is applied on top of the scope,
    # never around it.
    it "searches titles and references case-insensitively" do
      by_title = create_contract!(title: "Library construction", reference: "ZP-LIB-001")
      by_reference = create_contract!(title: "Road reconstruction", reference: "ZP-SEW-002")

      get "/", params: { q: "library" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Library construction")
        expect(response.body).to include(%(href="/#{by_title.id}"))
        expect(response.body).not_to include("ZP-SEW-002")
      end

      get "/", params: { q: "zp-sew" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("ZP-SEW-002")
        expect(response.body).to include(%(href="/#{by_reference.id}"))
        expect(response.body).not_to include("Library construction")
      end
    end

    it "keeps the search inside the published-only scope (a draft match never surfaces)" do
      create_contract!(title: "Water treatment plant", reference: "ZP-WTR-001")
      create_contract!(
        title: "Draft water plant", reference: "ZP-WTR-002",
        state: "draft", published_at: nil
      )

      get "/", params: { q: "water" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Water treatment plant")
        expect(response.body).not_to include("Draft water plant")
        expect(response.body).not_to include("ZP-WTR-002")
      end
    end

    it "keeps the search inside the organization scope" do
      create_contract!(title: "Municipal library", reference: "ZP-LIB-001")
      create_contract!(
        organization: Decidim::Organization.create!,
        title: "Foreign municipal library", reference: "ZP-FOR-001"
      )

      get "/", params: { q: "library" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Municipal library")
        expect(response.body).not_to include("Foreign municipal library")
        expect(response.body).not_to include("ZP-FOR-001")
      end
    end

    it "renders the distinct no-results message on a real search miss" do
      create_contract!(title: "Road reconstruction", reference: "ZP-2026-001")

      get "/", params: { q: "nonexistent" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("No contracts match your search or filters.")
        expect(response.body).not_to include("No published contracts yet.")
      end
    end

    # Catalogue filters and sorting end to end (civora-org/civora-platform#116).
    describe "filters and sorting" do
      def filter_refs(params = {})
        get "/", params: params
        expect(response).to have_http_status(:ok)
        response.body.scan(/ZP-F-\d+/).uniq
      end

      def add_party!(contract, name, ico = nil)
        Decidim::ContractsSk::Party.create!(contract: contract, role: "contractor", name: name, ico: ico)
      end

      def count_queries(&block)
        count = 0
        counter = lambda do |_name, _start, _finish, _id, payload|
          next if %w[SCHEMA TRANSACTION].include?(payload[:name])
          next if payload[:sql].match?(/\A\s*(?:SAVEPOINT|RELEASE|BEGIN|COMMIT)/i)

          count += 1
        end
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
        count
      end

      before do
        create_contract!(reference: "ZP-F-001", title: "Alpha road", amount: 100, signed_on: Date.new(2026, 3, 1),
                         published_at: Time.utc(2026, 4, 1, 10))
        create_contract!(reference: "ZP-F-002", title: "Beta bridge", amount: 5000, signed_on: Date.new(2026, 5, 1),
                         published_at: Time.utc(2026, 5, 1, 10))
        create_contract!(reference: "ZP-F-003", title: "Gamma school", amount: nil, signed_on: nil,
                         published_at: Time.utc(2026, 6, 1, 10), source: "crz", source_id: "77")
        add_party!(Decidim::ContractsSk::Contract.find_by!(reference: "ZP-F-001"), "Obec Ukážková", "00123456")
        add_party!(Decidim::ContractsSk::Contract.find_by!(reference: "ZP-F-002"), "Stavby s.r.o.", "36396567")
      end

      it "sorts newest first by default and honours every sort option" do
        expect(filter_refs).to eq(%w[ZP-F-003 ZP-F-002 ZP-F-001])
        expect(filter_refs(sort: "published_asc")).to eq(%w[ZP-F-001 ZP-F-002 ZP-F-003])
        expect(filter_refs(sort: "amount_desc")).to eq(%w[ZP-F-002 ZP-F-001 ZP-F-003])
        expect(filter_refs(sort: "amount_asc")).to eq(%w[ZP-F-001 ZP-F-002 ZP-F-003])
        expect(filter_refs(sort: "nonsense")).to eq(%w[ZP-F-003 ZP-F-002 ZP-F-001])
      end

      it "filters by amount (stored amount, inclusive) and drops amount-less records only then" do
        expect(filter_refs(amount_min: "100", amount_max: "5000")).to eq(%w[ZP-F-002 ZP-F-001])
        expect(filter_refs(amount_min: "101")).to eq(%w[ZP-F-002])
        expect(filter_refs(amount_min: "5 000,00")).to eq(%w[ZP-F-002])
        expect(filter_refs(amount_min: "10.000")).to eq(%w[ZP-F-003 ZP-F-002 ZP-F-001])
        expect(filter_refs(amount_min: "-1", amount_max: "abc")).to eq(%w[ZP-F-003 ZP-F-002 ZP-F-001])
      end

      it "filters by publication and signing dates, ISO or Slovak format, swapping reversed ranges" do
        expect(filter_refs(published_from: "2026-05-01", published_to: "2026-05-01")).to eq(%w[ZP-F-002])
        expect(filter_refs(published_from: "1.6.2026")).to eq(%w[ZP-F-003])
        expect(filter_refs(published_from: "2026-06-30", published_to: "2026-05-01")).to eq(%w[ZP-F-003 ZP-F-002])
        expect(filter_refs(signed_from: "1.3.2026", signed_to: "1.3.2026")).to eq(%w[ZP-F-001])
        expect(filter_refs(signed_from: "2026-01-01")).to eq(%w[ZP-F-002 ZP-F-001])
        expect(filter_refs(signed_from: "2026-02-30", published_to: "nope")).to eq(%w[ZP-F-003 ZP-F-002 ZP-F-001])
      end

      it "filters by party IČO or name" do
        expect(filter_refs(party: "00123456")).to eq(%w[ZP-F-001])
        expect(filter_refs(party: "0012 3456")).to eq(%w[ZP-F-001])
        expect(filter_refs(party: "stavby")).to eq(%w[ZP-F-002])
        expect(filter_refs(party: "OBEC")).to eq(%w[ZP-F-001])
        expect(filter_refs(party: "nobody")).to eq([])
      end

      it "filters by source" do
        expect(filter_refs(source: "crz")).to eq(%w[ZP-F-003])
        expect(filter_refs(source: "editorial")).to eq(%w[ZP-F-002 ZP-F-001])
        expect(filter_refs(source: "bogus")).to eq(%w[ZP-F-003 ZP-F-002 ZP-F-001])
      end

      it "combines filters with q and sort" do
        expect(filter_refs(q: "ALPHA", amount_max: "200", source: "editorial", sort: "amount_asc")).to eq(%w[ZP-F-001])
        expect(filter_refs(q: "road", party: "stavby")).to eq([])
        expect(filter_refs(q: "a", signed_from: "2026-01-01", sort: "amount_desc")).to eq(%w[ZP-F-002 ZP-F-001])
      end

      it "keeps published-only and organization scoping under every filter" do
        create_contract!(reference: "ZP-F-900", title: "Hidden draft", state: "draft", published_at: nil, amount: 100)
        create_contract!(reference: "ZP-F-901", title: "Foreign", amount: 100,
                         organization: Decidim::Organization.create!)

        expect(filter_refs(amount_min: "0")).to eq(%w[ZP-F-002 ZP-F-001])
        expect(filter_refs(source: "editorial", sort: "amount_asc")).to eq(%w[ZP-F-001 ZP-F-002])
      end

      it "shows the swapped range and the summary, and the clear link resets the page to everything" do
        get "/", params: { amount_min: "9000", amount_max: "100", party: "stavby" }

        expect(response.body).to include("Amount from: 100.0 EUR").and include("Party: stavby")
        expect(response.body).to include(%(<a class="cs-active__clear" href="/">Clear filters</a>))
        expect(filter_refs).to eq(%w[ZP-F-003 ZP-F-002 ZP-F-001])
      end

      it "renders the no-results message on a filter miss, not the empty-catalogue one" do
        get "/", params: { amount_min: "999999" }

        expect(response.body).to include("No contracts match your search or filters.")
        expect(response.body).not_to include("No published contracts yet.")
      end

      it "paginates a filtered listing with every active filter carried" do
        26.times do |i|
          create_contract!(reference: format("ZP-F-%03d", 100 + i), title: "Bulk #{i}", amount: 700 + i,
                           source: "crz", source_id: format("b%d", i))
        end
        params = { source: "crz", amount_min: "700", sort: "amount_asc" }

        get "/", params: params

        expect(response.body).to include("Page 1 of 2")
        link = response.body[/href="([^"]*page=2[^"]*)"/, 1].to_s.gsub("&amp;", "&")
        carried = Rack::Utils.parse_query(URI(link).query)
        expect(carried).to include("source" => "crz", "amount_min" => "700", "sort" => "amount_asc", "page" => "2")

        get link
        expect(response.body.scan(/ZP-F-\d+/).uniq.size).to eq(1)
        expect(response.body).to include("ZP-F-125")
      end

      it "runs a constant number of queries whatever the row count, with a party filter" do
        add_all = lambda do |count, offset|
          count.times do |i|
            contract = create_contract!(reference: format("ZP-F-%03d", 300 + offset + i), title: "Perf #{offset + i}",
                                        amount: 10)
            add_party!(contract, "Perf party", "00000001")
          end
        end

        add_all.call(2, 0)
        get "/", params: { party: "perf" } # warm-up: first-request schema work is not under test
        with_few = count_queries { get "/", params: { party: "perf" } }

        add_all.call(18, 10)
        with_many = count_queries { get "/", params: { party: "perf" } }

        expect(response.body.scan(/ZP-F-3\d+/).uniq.size).to eq(20)
        expect(with_many).to eq(with_few)
      end

      it "matches q upper-case terms and treats % and _ literally (search-bug regression)" do
        create_contract!(reference: "ZP-F-800", title: "Rate 5% off")
        create_contract!(reference: "ZP-F-801", title: "Rate 5X off")
        create_contract!(reference: "ZP-F-802", title: "Under_score")

        expect(filter_refs(q: "ALPHA ROAD")).to eq(%w[ZP-F-001])
        expect(filter_refs(q: "5%")).to eq(%w[ZP-F-800])
        expect(filter_refs(q: "5_")).to eq([])
        expect(filter_refs(q: "e_5")).to eq([])
        expect(filter_refs(q: "UNDER_")).to eq(%w[ZP-F-802])

        create_contract!(reference: "ZP-F-803", title: "Oprava štúrovej ulice")
        expect(filter_refs(q: "ŠTÚR")).to eq(%w[ZP-F-803])
      end
    end
  end

  # Cross-cutting guard carried over from the scaffold era: an
  # unauthenticated admin visit must never render the public catalogue body.
  it "does not render the public catalogue body for an unauthenticated admin visit" do
    get "/admin/contracts"

    expect(response).to have_http_status(:redirect)
    # Both markers: the catalogue page itself (its h1) and any record data
    # that only a real catalogue render could have carried.
    expect(response.body).not_to include("Contracts")
    expect(response.body).not_to include("Road reconstruction")
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
