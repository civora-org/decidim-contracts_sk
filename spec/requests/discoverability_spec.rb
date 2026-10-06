# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the public pages' discoverability (civora-org/civora-
# platform#122): titles, meta descriptions and Open Graph tags registered
# through Decidim's own MetaTagsHelper (the REAL helper runs in the harness;
# spec/dummy/app/views/layouts/application.html.erb renders its values like
# decidim-core's _head partial), and the XML sitemap. Real SQLite-backed :db
# group (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"
require "nokogiri"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "public discoverability", :db, type: :request do
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:serials) { (1..).each }
  let(:sitemap_ns) { { "s" => "http://www.sitemaps.org/schemas/sitemap/0.9" } }

  before do
    migrate_engine_schema!
    organization.update!(host: "zmluvy.example.org", default_locale: "en", name: { "en" => "Green Village" })
    [Decidim::ContractsSk::ContractsController, Decidim::ContractsSk::SuppliersController,
     Decidim::ContractsSk::StatisticsController, Decidim::ContractsSk::SitemapsController].each do |klass|
      allow_any_instance_of(klass).to receive(:current_organization).and_return(organization)
    end
  end

  def create_contract!(parties: [{ role: "contractor", name: "Dodávateľ s.r.o.", ico: "12345678" }], **overrides)
    serial = serials.next
    contract = contract_class.create!(
      contract_attributes(
        { state: "published", reference: "ZP-#{serial}", title: "Zmluva #{serial}",
          published_at: Time.utc(2026, 9, 1, 12) + serial.minutes, amount: BigDecimal("1250.50"),
          signed_on: Date.new(2026, 8, 30), subject_matter: "Tajný predmet zmluvy" }.merge(overrides)
      )
    )
    parties.each { |attrs| contract.parties.create!(attrs) }
    contract
  end

  def head
    Nokogiri::HTML(response.body).at_css("head")
  end

  def meta(name_or_property)
    head.at_css("meta[name='#{name_or_property}'], meta[property='#{name_or_property}']")&.[]("content")
  end

  def title
    head.at_css("title").text
  end

  describe "the catalogue" do
    it "carries a title, a description, the Open Graph set and the site name" do
      create_contract!

      get "/"

      expect(response).to have_http_status(:ok)
      expect(title).to eq("Contracts - Green Village")
      expect(meta("description")).to eq(meta("og:description"))
      expect(meta("og:description")).to eq(
        "Published contracts of the organisation, with their documents and change history."
      )
      expect(meta("og:title")).to eq("Contracts - Green Village")
      expect(meta("og:description")).to eq(meta("twitter:description"))
      expect(meta("og:url")).to eq("http://www.example.com/")
      expect(meta("og:site_name")).to eq("Green Village")
      expect(meta("robots")).to be_nil
    end

    it "builds og:url from the normalized filters and page, never from foreign request params" do
      create_contract!

      get "/", params: { q: "cesta", evil: "x", utm_source: "y", page: 1 }

      expect(meta("og:url")).to eq("http://www.example.com/?q=cesta")
    end

    it "gives every page after the first its own title" do
      stub_const("Decidim::ContractsSk::CONTRACTS_PER_PAGE", 1)
      2.times { create_contract! }

      get "/", params: { page: 2 }

      expect(title).to eq("Contracts - Page 2 - Green Village")
    end
  end

  describe "a contract detail page" do
    it "carries a unique title, a description of reference, amount and suppliers with IČO, and Open Graph tags" do
      contract = create_contract!(reference: "ZP-77", title: "Oprava cesty")

      get "/#{contract.id}"

      expect(response).to have_http_status(:ok)
      expect(title).to eq("Oprava cesty (ZP-77) - Green Village")
      expect(meta("og:title")).to eq("Oprava cesty (ZP-77) - Green Village")
      expect(meta("og:description")).to eq(
        "Reference: ZP-77. Amount: 1250.5 EUR. Suppliers: Dodávateľ s.r.o. (IČO 12345678)"
      )
      expect(meta("twitter:description")).to eq(meta("og:description"))
      expect(meta("description")).to eq(meta("og:description"))
      expect(meta("og:url")).to eq("http://www.example.com/#{contract.id}")
      expect(meta("og:site_name")).to eq("Green Village")
    end

    it "gives two contracts with the same title different page titles" do
      first = create_contract!(title: "Rovnaká")
      second = create_contract!(title: "Rovnaká")

      get "/#{first.id}"
      first_title = title
      get "/#{second.id}"

      expect(first_title).not_to eq(title)
    end

    it "names no party without an IČO, no object party and never the subject matter" do
      contract = create_contract!(parties: [
                                    { role: "object", name: "Obec Zelená", ico: "00000001" },
                                    { role: "contractor", name: "Jozef Súkromný" },
                                    { role: "contractor", name: "Firma a.s.", ico: "87654321" }
                                  ])

      get "/#{contract.id}"

      description = meta("og:description")
      expect(description).to include("Firma a.s. (IČO 87654321)")
      expect(description).not_to include("Jozef")
      expect(description).not_to include("Obec Zelená")
      expect(description).not_to include("Tajný predmet")
      expect(response.body).to include("Tajný predmet")
    end

    it "lists at most three suppliers" do
      parties = (1..5).map { |i| { role: "contractor", name: "Firma #{i}", ico: format("%08d", i) } }
      contract = create_contract!(parties: parties)

      get "/#{contract.id}"

      expect(meta("og:description").scan("IČO").size).to eq(3)
    end

    it "omits a missing amount and the supplier list without dangling labels" do
      contract = create_contract!(amount: nil, parties: [])

      get "/#{contract.id}"

      expect(meta("og:description")).to eq("Reference: #{contract.reference}")
    end

    it "labels a CRZ mirror as externally confirmed in the title and the description" do
      contract = create_contract!(title: "Zrkadlo", reference: "CRZ-5", source: "crz", source_id: "9001",
                                  imported_at: Time.utc(2026, 9, 2))

      get "/#{contract.id}"

      expect(title).to eq("Zrkadlo (CRZ-5) - Externally confirmed - Green Village")
      expect(meta("og:description")).to end_with(". Externally confirmed")
    end

    it "does not label an editorial record as externally confirmed" do
      contract = create_contract!

      get "/#{contract.id}"

      expect(title).not_to include("Externally confirmed")
      expect(meta("og:description")).not_to include("Externally confirmed")
    end

    it "escapes markup in the title and the supplier names" do
      contract = create_contract!(title: %(<script>alert(1)</script> "q"),
                                  parties: [{ role: "contractor", name: "<b>X</b>", ico: "11111111" }])

      get "/#{contract.id}"

      expect(head.css("script")).to be_empty
      expect(head.at_css("title").text).to include("<script>alert(1)</script>")
      # Decidim strips markup from descriptions.
      expect(meta("og:description")).to include("X (IČO 11111111)")
      expect(response.body).not_to include("<script>alert(1)</script>")
    end
  end

  describe "a supplier page" do
    it "carries the name with the IČO, the contract count and Open Graph tags, and stays noindex" do
      create_contract!
      create_contract!

      get "/suppliers/12345678"

      expect(title).to eq("Dodávateľ s.r.o. (IČO 12345678) - Green Village")
      expect(meta("og:title")).to eq(title)
      expect(meta("og:description")).to eq(
        "Published contracts of Dodávateľ s.r.o. (IČO 12345678) in the catalogue: 2."
      )
      expect(meta("description")).to eq(meta("og:description"))
      expect(meta("og:url")).to eq("http://www.example.com/suppliers/12345678")
      expect(meta("og:site_name")).to eq("Green Village")
      expect(head.css("meta[name='robots']").map { |m| m["content"] }).to eq(["noindex"])
    end
  end

  describe "the statistics page" do
    it "carries a title, a description and Open Graph tags, and is indexable" do
      create_contract!

      get "/statistics"

      expect(title).to eq("Contract statistics - Green Village")
      expect(meta("og:title")).to eq(title)
      expect(meta("og:description")).to start_with("The organisation's published contracts at a glance")
      expect(meta("description")).to eq(meta("og:description"))
      expect(meta("og:url")).to eq("http://www.example.com/statistics")
      expect(meta("og:site_name")).to eq("Green Village")
      expect(meta("robots")).to be_nil
    end
  end

  describe "the sitemap" do
    def locs
      Nokogiri::XML(response.body) { |config| config.strict.nonet }.xpath("//s:url/s:loc", sitemap_ns).map(&:text)
    end

    it "is well-formed sitemap XML listing the published contracts with lastmod = updated_at" do
      contract = create_contract!
      contract.update_column(:updated_at, Time.utc(2026, 9, 5, 8, 30, 15))

      get "/sitemap.xml"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")
      doc = Nokogiri::XML(response.body) { |config| config.strict.nonet }
      expect(doc.root.name).to eq("urlset")
      expect(doc.root.namespace.href).to eq("http://www.sitemaps.org/schemas/sitemap/0.9")
      expect(doc.xpath("//s:url/s:loc", sitemap_ns).map(&:text)).to eq(["http://www.example.com/#{contract.id}"])
      expect(doc.at_xpath("//s:url/s:lastmod", sitemap_ns).text).to eq("2026-09-05T08:30:15Z")
    end

    it "lists only published records of the organization, never drafts, other states or other tenants" do
      published = create_contract!
      create_contract!(state: "draft", published_at: nil)
      create_contract!(state: "archived")
      other = Decidim::Organization.create!
      create_contract!(organization: other, reference: "OTHER-1")

      get "/sitemap.xml"

      expect(locs).to eq(["http://www.example.com/#{published.id}"])
    end

    it "leaves CRZ mirrors out" do
      own = create_contract!
      create_contract!(source: "crz", source_id: "9001", imported_at: Time.utc(2026, 9, 2))

      get "/sitemap.xml"

      expect(locs).to eq(["http://www.example.com/#{own.id}"])
    end

    it "is an empty urlset for an organization without published records" do
      get "/sitemap.xml"

      expect(response).to have_http_status(:ok)
      expect(locs).to eq([])
    end

    it "does not serve other formats" do
      expect { get "/sitemap.json" }.to raise_error(ActiveRecord::RecordNotFound)
      expect { get "/sitemap" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "caps the file at the protocol limit" do
      stub_const("Decidim::ContractsSk::SitemapsController::SITEMAP_LIMIT", 2)
      3.times { create_contract! }

      get "/sitemap.xml"

      expect(locs.size).to eq(2)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
