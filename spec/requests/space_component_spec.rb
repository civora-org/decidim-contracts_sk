# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the in-space contracts component (civora-org/civora-
# platform#89), run against the dummy harness: the component engine is
# mounted under /spaces/:participatory_process_slug/f/:component_id behind a
# constraint that exposes a stand-in component (the real CurrentComponent
# does the same in a host; see spec/dummy/config/application.rb,
# DummySpaceHarness). Real data on the in-memory SQLite adapter (:db group).
#
# What this harness CANNOT prove, and the router verifies on the host (see
# tmp/evidence/89.md): the space layout, breadcrumbs and menu, the
# space-visibility and component-published gates of Decidim's real
# BaseController, the core announcement partial's cell markup, Decidim's
# real permission chain, and whether the engine's inline .cs- styles reach
# <head> through the space layout.
#
# Synthetic data only, no real PII.
#
# Cop note: allow_any_instance_of is the approved seam for this harness (the
# tenancy and the scope live on the controller, which request specs cannot
# otherwise reach), like spec/requests/contracts_spec.rb.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "in-space contracts component", :db, type: :request do
  let(:base) { "/spaces/town/f/7" }
  let(:controller_class) { Decidim::ContractsSk::SpaceComponent::ContractsController }
  let(:other_organization) { Decidim::Organization.create! }

  before do
    migrate_engine_schema!
    FileUtils.rm_rf(active_storage_root)
    allow_any_instance_of(controller_class).to receive(:current_organization).and_return(organization)
  end

  def create_contract!(overrides = {})
    Decidim::ContractsSk::Contract.create!(
      contract_attributes(
        { state: "published", published_at: Time.utc(2026, 9, 1, 12), reference: next_reference,
          title: "Road reconstruction", amount: BigDecimal("1250.50"), currency: "EUR" }.merge(overrides)
      )
    )
  end

  # Unique per example: the table is fresh for each one.
  def next_reference
    "ZP-2026-#{format("%03d", Decidim::ContractsSk::Contract.count + 1)}"
  end

  describe "the list (index)" do
    it "renders the component name as the heading and lists only the organization's published contracts" do
      create_contract!(title: "Published road")
      create_contract!(title: "Draft road", state: "draft", published_at: nil)
      create_contract!(title: "Archived road", state: "archived")
      create_contract!(title: "In review road", state: "in_review", published_at: nil)
      foreign_author = Decidim::User.create!(organization: other_organization)
      Decidim::ContractsSk::Contract.create!(
        organization: other_organization, author: foreign_author, title: "Foreign published road",
        reference: "ZP-X-1", state: "published", published_at: Time.utc(2026, 9, 1, 12)
      )

      get base

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      aggregate_failures do
        expect(doc.at_css("h1.title-decorator").text.strip).to eq("Town contracts")
        expect(doc.css("li.cs-row .cs-row__title").map(&:text)).to eq(["Published road"])
        ["Draft", "Archived", "In review", "Foreign"].each do |hidden|
          expect(response.body).not_to include("#{hidden} road")
        end
      end
    end

    it "links every row to the in-space detail page, never to the standalone catalogue" do
      contract = create_contract!

      get base

      hrefs = Nokogiri::HTML(response.body).css("li.cs-row a.cs-row__title").pluck("href")
      expect(hrefs).to eq(["#{base}/contracts/#{contract.id}"])
    end

    it "carries no standalone-only surface: no search form, filters, open-data block or statistics switch" do
      create_contract!

      get base

      doc = Nokogiri::HTML(response.body)
      aggregate_failures do
        expect(doc.css("form[role=search], details.cs-filters, .cs-opendata, nav.cs-switch")).to be_empty
        expect(response.body).not_to include("/export", "/feed", "/statistics", "/suppliers")
      end
    end

    it "ignores catalogue search, filter and sort parameters (the list is the plain default list)" do
      create_contract!(title: "Cheap road", amount: BigDecimal("10"))
      create_contract!(title: "Dear road", amount: BigDecimal("9000"))

      get base, params: { q: "Dear", amount_max: "100", sort: "amount_asc", source: "crz" }

      expect(Nokogiri::HTML(response.body).css("li.cs-row .cs-row__title").map(&:text))
        .to contain_exactly("Cheap road", "Dear road")
    end

    it "shows the standalone catalogue's empty state when nothing is published" do
      create_contract!(state: "draft", published_at: nil)

      get base

      expect(response.body).to include("No published contracts yet.")
      expect(response.body).not_to include("cs-row")
    end

    it "paginates in the space: page links stay under the component path and carry no foreign params" do
      (Decidim::ContractsSk::CONTRACTS_PER_PAGE + 1).times { |i| create_contract!(title: "Road #{i}") }

      get base, params: { q: "x", evil: "1" }

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("li.cs-row").size).to eq(Decidim::ContractsSk::CONTRACTS_PER_PAGE)
      next_link = doc.at_css("nav.cs-pager a[rel=next]")
      expect(next_link["href"]).to eq("#{base}/?page=2")

      get base, params: { page: 2 }
      expect(Nokogiri::HTML(response.body).css("li.cs-row").size).to eq(1)
    end

    it "survives hostile page values" do
      create_contract!

      ["abc", "0", "-3", "99999999999999999999"].each do |page|
        get base, params: { page: page }
        expect(response).to have_http_status(:ok), "page=#{page}"
      end
      get "#{base}?page[]=2"
      expect(response).to have_http_status(:ok)
    end

    it "renders the component announcement from the global settings" do
      create_contract!
      component = DummySpaceHarness.component(7, announcement: { "en" => "<p>Budget season notice</p>" })
      allow(DummySpaceHarness).to receive(:component).and_return(component)

      get base

      expect(response.body).to include("Budget season notice")
    end

    it "renders no announcement markup when the settings are empty" do
      create_contract!

      get base

      expect(response.body).not_to include("layout-main__section")
    end

    it "sets the in-space canonical URL and the page number from page 2" do
      (Decidim::ContractsSk::CONTRACTS_PER_PAGE + 1).times { |i| create_contract!(title: "Road #{i}") }

      get base
      expect(response.body).to include(%(property="og:url" content="http://www.example.com#{base}/"))
      expect(response.body).to include("<title>Town contracts - www.example.com</title>")

      get base, params: { page: 2 }
      expect(response.body).to include(%(property="og:url" content="http://www.example.com#{base}/?page=2"))
      expect(response.body).to include("<title>Town contracts - Page 2 - www.example.com</title>")
    end
  end

  describe "the detail page (show)" do
    it "renders the shared detail view for a published contract, with the contractor as plain text" do
      contract = create_contract!(title: "Playground equipment", subject_matter: "Swings and a slide")
      contract.parties.create!(role: "object", name: "Obec Zelen", ico: "12345678")
      contract.parties.create!(role: "contractor", name: "Zeleň a.s.", ico: "87654321")

      get "#{base}/contracts/#{contract.id}"

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      aggregate_failures do
        expect(doc.at_css("h1.title-decorator").text.strip).to eq("Playground equipment")
        expect(response.body).to include("Swings and a slide")
        expect(doc.css(".cs-party__name").map { |node| node.text.strip }).to include("Zeleň a.s.", "Obec Zelen")
        # No supplier route exists in a space: the name is text, not a link.
        expect(doc.css("a[href*='suppliers']")).to be_empty
        expect(response.body).not_to include("/suppliers/")
      end
    end

    it "shows published amendments only" do
      contract = create_contract!
      contract.amendments.create!(version: 1, summary: "Secret upcoming change",
                                  organization: organization, author: author)
      contract.amendments.create!(version: 2, summary: "Public change", state: "published",
                                  published_at: Time.utc(2026, 9, 2, 12),
                                  content_snapshot: { "currency" => "EUR" },
                                  organization: organization, author: author)

      get "#{base}/contracts/#{contract.id}"

      expect(response.body).to include("Public change")
      expect(response.body).not_to include("Secret upcoming change")
    end

    it "404s (RecordNotFound) for a draft, an archived, a foreign and a nonexistent contract alike" do
      draft = create_contract!(state: "draft", published_at: nil)
      archived = create_contract!(state: "archived")
      foreign = Decidim::ContractsSk::Contract.create!(
        organization: other_organization, author: Decidim::User.create!(organization: other_organization),
        title: "Foreign", reference: "ZP-X-2", state: "published", published_at: Time.utc(2026, 9, 1, 12)
      )

      [draft.id, archived.id, foreign.id, 999_999, "abc"].each do |id|
        expect { get "#{base}/contracts/#{id}" }.to raise_error(ActiveRecord::RecordNotFound), "id=#{id}"
      end
    end

    it "denies a record the permission table does not admit to the public, even if the scope let it through" do
      draft = create_contract!(state: "draft", published_at: nil)
      # Defence in depth: bypass the published scope so ONLY the manifest's
      # permissions class stands between the record and the page.
      allow_any_instance_of(controller_class)
        .to receive(:published_contracts).and_return(Decidim::ContractsSk::Contract.all)

      get "#{base}/contracts/#{draft.id}"

      expect(response).to redirect_to("/")
      expect(response.body).not_to include(draft.title)
    end

    it "admits the same record through the permission class once published (the control for the denial above)" do
      published = create_contract!
      allow_any_instance_of(controller_class)
        .to receive(:published_contracts).and_return(Decidim::ContractsSk::Contract.all)

      get "#{base}/contracts/#{published.id}"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the standalone catalogue next to it" do
    it "keeps serving the same records at its own mount, unchanged" do
      contract = create_contract!(title: "Shared road")
      allow_any_instance_of(Decidim::ContractsSk::ContractsController)
        .to receive(:current_organization).and_return(organization)

      get "/"
      expect(response.body).to include("Shared road")
      expect(response.body).to include(%(href="/#{contract.id}"))

      get base
      expect(response.body).to include("Shared road")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
