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
# `where(SEARCH_CONDITION, pattern: ...)` on the stubbed scope, so the where
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
  end

  def published_contract_double(overrides = {})
    double(
      title: "Road reconstruction",
      reference: "ZP-2026-001",
      published_at: Time.new(2026, 9, 1, 12, 0, 0),
      # Provenance defaults of an editorial record (civora-org/civora-platform
      # #88): every card renders through imported_contract?/the provenance
      # line, so the double must answer the provenance surface even when the
      # example does not care about it.
      source: "editorial",
      imported_at: nil,
      import_status: nil,
      to_param: "7",
      **overrides
    )
  end

  describe "catalogue index (civora-org/civora-platform#62)" do
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

    it "pins the deterministic catalogue order values" do
      expect(Decidim::ContractsSk::ContractsController::CATALOGUE_ORDER)
        .to eq(published_at: :desc, id: :desc)
    end

    it "pins the search condition identical to the admin index's" do
      # One vocabulary, never a second one: the public search and the admin
      # filter must stay in lockstep by construction.
      expect(Decidim::ContractsSk::ContractsController::SEARCH_CONDITION)
        .to eq(Decidim::ContractsSk::Admin::ContractsController::SEARCH_CONDITION)
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
        expect(q_filter[0].first).to eq(
          "LOWER(title) LIKE :pattern OR LOWER(reference) LIKE :pattern"
        )
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
        expect(response.body).not_to include("No contracts match your search.")
      end
    end

    it "renders the distinct no-results message when a non-blank search finds nothing" do
      stub_published_contracts(SearchablePaginableStub.new([]))

      get "/", params: { q: "zzz" }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("No contracts match your search.")
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
        expect(response.body).to include("No contracts match your search.")
        expect(response.body).not_to include("No published contracts yet.")
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
