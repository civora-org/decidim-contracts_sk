# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the supplier pages (civora-org/civora-platform#117):
# GET /suppliers/:ico over the current organization's published contracts
# naming the IČO as CONTRACTOR, plus the detail page's links to it. Real
# SQLite-backed :db group (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "supplier pages", :db, type: :request do
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:serials) { (1..).each }
  let(:ico) { "12345678" }

  before do
    migrate_engine_schema!
    [Decidim::ContractsSk::SuppliersController, Decidim::ContractsSk::ContractsController].each do |klass|
      allow_any_instance_of(klass).to receive(:current_organization).and_return(organization)
    end
  end

  def create_contract!(overrides = {}, contractor: { name: "Dodávateľ s.r.o.", ico: ico })
    serial = serials.next
    contract = contract_class.create!(
      contract_attributes(
        { state: "published", reference: "ZP-#{serial}", title: "Zmluva #{serial}",
          published_at: Time.utc(2026, 9, 1, 12, 0, 0) + serial.minutes, amount: BigDecimal("100.00"),
          signed_on: Date.new(2026, 8, 30) }.merge(overrides)
      )
    )
    contract.parties.create!({ role: "contractor" }.merge(contractor)) if contractor
    contract
  end

  def body_text
    Nokogiri::HTML(response.body).text.squish
  end

  describe "a supplier with published contracts" do
    it "renders the name, the count, the totals per currency, the per-year tally and the list newest first" do
      create_contract!({ title: "Stará zmluva", signed_on: Date.new(2025, 3, 1), amount: BigDecimal("1000.50") })
      create_contract!({ title: "Nová zmluva", amount: BigDecimal("250.25") })
      create_contract!({ title: "Bez dátumu", signed_on: nil, amount: nil })
      # Only EUR passes validation today; a second currency is planted
      # straight in the column to prove the totals group per currency.
      create_contract!({ title: "Dolárová", amount: BigDecimal("5.00") }).update_column(:currency, "USD")

      get "/suppliers/#{ico}"

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("h1").text).to eq("Dodávateľ s.r.o.")
      expect(body_text).to include(ico)
      expect(doc.at_css(".cs-dl__figure").text).to eq("4")
      expect(response.body).to include("1250.75 EUR").and include("5.0 USD")
      # The record without a signing date lands in the "unknown" bucket.
      years = doc.css(".cs-years li").map { |li| li.text.squish }
      expect(years).to eq(["2026: 2", "2025: 1", "Signing date unknown: 1"])
      titles = doc.css(".cs-row__title").map(&:text)
      expect(titles).to eq(["Dolárová", "Bez dátumu", "Nová zmluva", "Stará zmluva"])
    end

    it "marks the page noindex" do
      create_contract!

      get "/suppliers/#{ico}"

      robots = Nokogiri::HTML(response.body).css("head meta[name='robots']")
      expect(robots.map { |meta| meta["content"] }).to eq(["noindex"])
    end

    it "keeps leading zeros of the IČO" do
      create_contract!({}, contractor: { name: "Nuly s.r.o.", ico: "00123456" })

      get "/suppliers/00123456"

      expect(response).to have_http_status(:ok)
      expect(body_text).to include("00123456")
    end

    it "names the supplier by its most recent spelling" do
      create_contract!({ published_at: Time.utc(2026, 1, 1) }, contractor: { name: "Starý názov", ico: ico })
      create_contract!({ published_at: Time.utc(2026, 6, 1) }, contractor: { name: "Nový názov", ico: ico })

      get "/suppliers/#{ico}"

      expect(Nokogiri::HTML(response.body).at_css("h1").text).to eq("Nový názov")
    end

    it "orders the list and names the supplier by the CRZ publication date, not the import time (#159)" do
      create_contract!({ title: "Mirror March", source: "crz", source_id: "8001",
                         crz_published_on: Date.new(2026, 3, 1), published_at: Time.utc(2026, 9, 9) },
                       contractor: { name: "Zrkadlený názov", ico: ico })
      create_contract!({ title: "Editorial May", published_at: Time.utc(2026, 5, 1) },
                       contractor: { name: "Redakčný názov", ico: ico })

      get "/suppliers/#{ico}"

      doc = Nokogiri::HTML(response.body)
      titles = doc.css(".cs-row__title").map(&:text)
      aggregate_failures do
        # Entered in September but published in CRZ in March: it sorts BEHIND the May record.
        expect(titles).to eq(["Editorial May", "Mirror March"])
        expect(doc.at_css("h1").text).to eq("Redakčný názov")
      end
    end

    it "does not take the name from a draft or another organization's newer record" do
      create_contract!({ published_at: Time.utc(2026, 1, 1) }, contractor: { name: "Verejný názov", ico: ico })
      create_contract!({ state: "draft", published_at: Time.utc(2027, 1, 1) },
                       contractor: { name: "Koncept názov", ico: ico })
      other = Decidim::Organization.create!
      create_contract!({ organization: other, author: Decidim::User.create!(organization: other),
                         published_at: Time.utc(2028, 1, 1) },
                       contractor: { name: "Cudzí názov", ico: ico })

      get "/suppliers/#{ico}"

      expect(Nokogiri::HTML(response.body).at_css("h1").text).to eq("Verejný názov")
      expect(response.body).not_to include("Koncept názov")
      expect(response.body).not_to include("Cudzí názov")
    end

    it "counts and lists only published records of this organization" do
      create_contract!({ title: "Zverejnená" })
      create_contract!({ state: "draft", title: "Koncept" })
      create_contract!({ state: "archived", title: "Archív" })
      other = Decidim::Organization.create!
      create_contract!({ organization: other, author: Decidim::User.create!(organization: other), title: "Cudzia" })

      get "/suppliers/#{ico}"

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css(".cs-dl__figure").text).to eq("1")
      expect(doc.css(".cs-row__title").map(&:text)).to eq(["Zverejnená"])
    end

    it "includes CRZ mirrors with their provenance badge" do
      create_contract!({ source: "crz", title: "Zrkadlo", imported_at: Time.utc(2026, 9, 2) })

      get "/suppliers/#{ico}"

      expect(response).to have_http_status(:ok)
      expect(body_text).to include("Zrkadlo").and include("CRZ")
    end

    it "counts only contractor-role parties of the IČO and lists a contract once" do
      contract = create_contract!
      contract.parties.create!(role: "contractor", name: "Dodávateľ druhý", ico: ico)

      get "/suppliers/#{ico}"

      expect(Nokogiri::HTML(response.body).css(".cs-row")).to be_one
    end

    it "paginates 25 per page while the figures cover every record" do
      26.times { create_contract! }

      get "/suppliers/#{ico}"
      expect(Nokogiri::HTML(response.body).css(".cs-row").size).to eq(25)
      expect(response.body).to include(%(rel="next"))
      expect(response.body).to include("/suppliers/#{ico}?page=2")
      expect(Nokogiri::HTML(response.body).at_css(".cs-dl__figure").text).to eq("26")

      get "/suppliers/#{ico}", params: { page: 2 }
      expect(Nokogiri::HTML(response.body).css(".cs-row").size).to eq(1)
    end

    it "shows a short line with a link to page 1 for a page past the last one" do
      create_contract!

      get "/suppliers/#{ico}", params: { page: 5 }

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.css(".cs-row")).to be_empty
      expect(doc.at_css(".cs-empty").text).to include("There are no contracts on this page.")
      expect(doc.at_css(".cs-empty a")["href"]).to eq("/suppliers/#{ico}")
    end

    it "breaks a same-contract name tie deterministically: newest party id wins" do
      contract = create_contract!({}, contractor: { name: "Prvé písanie", ico: ico })
      contract.parties.create!(role: "contractor", name: "Druhé písanie", ico: ico)

      get "/suppliers/#{ico}"

      expect(Nokogiri::HTML(response.body).at_css("h1").text).to eq("Druhé písanie")
    end

    it "treats the same IČO as object on one contract and contractor on another: only the latter counts" do
      create_contract!({ title: "Dodávka" }, contractor: { name: "Dodávateľ s.r.o.", ico: ico })
      object_only = create_contract!({ title: "Objednávka" }, contractor: nil)
      object_only.parties.create!(role: "object", name: "Obec X", ico: ico)

      get "/suppliers/#{ico}"

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css(".cs-dl__figure").text).to eq("1")
      expect(doc.at_css("h1").text).to eq("Dodávateľ s.r.o.")
      expect(doc.css(".cs-row__title").map(&:text)).to eq(["Dodávka"])
    end

    it "counts an editorial record and its CRZ mirror twice (documented: no dedupe in V1)" do
      create_contract!({ title: "Vlastný záznam" })
      create_contract!({ title: "Zrkadlo toho istého", source: "crz", imported_at: Time.utc(2026, 9, 2) })

      get "/suppliers/#{ico}"

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css(".cs-dl__figure").text).to eq("2")
      expect(doc.css(".cs-row")).to have_attributes(size: 2)
    end

    it "survives hostile page and unknown params" do
      create_contract!

      [{ page: "abc" }, { page: ["2"] }, { page: "%00" }, { page: "-1" }, { page: "999999999999999999999" },
       { q: "x", party: "y", sort: "bogus" }].each do |params|
        get "/suppliers/#{ico}", params: params
        expect(response).to have_http_status(:ok)
      end
      get "/suppliers/#{ico}?page=%00&q=%00"
      expect(response).to have_http_status(:ok)
    end

    it "reads no request filters: q and party do not narrow the page" do
      create_contract!({ title: "Prvá" })
      create_contract!({ title: "Druhá" })

      get "/suppliers/#{ico}", params: { q: "Prvá", party: "Nikto", amount_min: "99999" }

      expect(Nokogiri::HTML(response.body).css(".cs-row").size).to eq(2)
    end
  end

  describe "a page that cannot exist" do
    it "is a 404 for an IČO without any contract" do
      expect { get "/suppliers/99999999" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "is a 404 when the IČO only has drafts" do
      create_contract!({ state: "draft" })

      expect { get "/suppliers/#{ico}" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "is a 404 when the IČO only has another organization's published contracts" do
      other = Decidim::Organization.create!
      create_contract!({ organization: other, author: Decidim::User.create!(organization: other) })

      expect { get "/suppliers/#{ico}" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "is a 404 when the IČO is only an object party" do
      create_contract!({}, contractor: nil).parties.create!(role: "object", name: "Obec", ico: ico)

      expect { get "/suppliers/#{ico}" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not route IČOs of 7 or 9 digits or with letters" do
      create_contract!

      %w[1234567 123456789 abcdefgh 1234567a].each do |bad|
        expect { get "/suppliers/#{bad}" }.to raise_error(ActionController::RoutingError)
      end
    end
  end

  describe "the contract detail page" do
    def party_markup(contract)
      get "/#{contract.id}"
      expect(response).to have_http_status(:ok)
      Nokogiri::HTML(response.body).css(".cs-party")
    end

    it "links a contractor with an IČO to its supplier page" do
      contract = create_contract!

      link = party_markup(contract).css("a").first

      expect(link["href"]).to eq("/suppliers/#{ico}")
      expect(link.text).to eq("Dodávateľ s.r.o.")
    end

    it "renders a contractor without an IČO as plain text" do
      contract = create_contract!({}, contractor: { name: "Bez IČO", ico: nil })

      parties = party_markup(contract)

      expect(parties.css("a")).to be_empty
      expect(parties.text).to include("Bez IČO")
    end

    it "renders a malformed stored IČO as plain text without raising" do
      contract = create_contract!({}, contractor: nil)
      party = contract.parties.build(role: "contractor", name: "Chybné IČO", ico: "12AB")
      party.save!(validate: false)

      parties = party_markup(contract)

      expect(parties.css("a")).to be_empty
      expect(parties.text).to include("Chybné IČO")
    end

    it "does not link an object party even with a valid IČO" do
      contract = create_contract!({}, contractor: nil)
      contract.parties.create!(role: "object", name: "Obec Zelená", ico: "87654321")

      parties = party_markup(contract)

      expect(parties.css("a")).to be_empty
      expect(parties.text).to include("Obec Zelená")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
