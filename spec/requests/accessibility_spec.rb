# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Accessibility regressions on the public catalogue (civora-org/civora-platform
# #133, WCAG 2.1 AA / EN 301 549). Each example pins one attribute or
# structure the axe-core audit asked for, so a refactor cannot silently drop
# it. Real SQLite-backed :db group (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "public accessibility markup (#133)", :db, type: :request do
  let(:doc) { Nokogiri::HTML(response.body) }

  before do
    migrate_engine_schema!
    allow_any_instance_of(Decidim::ContractsSk::ContractsController)
      .to receive(:current_organization).and_return(organization)
  end

  def create_contract!(overrides = {})
    Decidim::ContractsSk::Contract.create!(
      contract_attributes({ state: "published", published_at: Time.utc(2026, 9, 1, 12) }.merge(overrides))
    )
  end

  describe "catalogue" do
    it "names the search landmark so it is not an anonymous region" do
      get "/"

      form = doc.at_css("form[role=search]")
      expect(form["aria-label"]).to eq("Search contracts")
    end

    it "gives the register a heading and names the list by it" do
      create_contract!

      get "/"

      heading = doc.at_css("h2#cs-register-title")
      expect(heading.text.strip).to eq("Contract register")
      expect(heading["class"]).to include("cs-sr")
      expect(doc.at_css("ol.cs-list")["aria-labelledby"]).to eq("cs-register-title")
      expect(doc.css("h1").size).to eq(1)
    end

    it "renders no register heading when the catalogue is empty" do
      get "/"

      expect(doc.at_css("#cs-register-title")).to be_nil
    end

    it "ships a visible focus ring for engine links and underlines links set inside a sentence" do
      # The stylesheet is delivered through the host's :css_content slot, which the harness layout does
      # not yield, so the rules are pinned in the partial's source.
      css = File.read(Decidim::ContractsSk::Engine.root.join("app/views/decidim/contracts_sk/shared/_public_styles.html.erb"))

      expect(css).to include(".cs-page a:focus-visible { outline: 3px solid var(--secondary)")
      expect(css).to include(".cs-small .cs-link { text-decoration: underline")
    end

    it "keeps one labelled control per filter field" do
      get "/", params: { amount_min: "1" }

      fields = doc.css("form[role=search] input:not([type=hidden]), form[role=search] select")
      expect(fields).not_to be_empty
      fields.each do |field|
        expect(doc.at_css("label[for='#{field["id"]}']")).not_to be_nil, "#{field["name"]} has no label"
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
