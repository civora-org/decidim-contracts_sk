# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the embeddable "Related contracts" block (civora-org/civora-
# platform#131): the reverse lookup of the contract link join
# (RelatedContractsQuery / Decidim::ContractsSk.related_contracts_for) and
# the partial a host renders from a result or project page. Real
# SQLite-backed :db group (CONTRACTS_SK_DB=1). Synthetic data only.
#
# The Decidim resource is a stand-in Struct registered under the real class
# name (stub_const): the engine only needs +id+, +organization+ and the
# class name the polymorphic join stores.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::RelatedContractsQuery, :db do
  let(:serials) { (1..).each }
  let(:other_organization) { Decidim::Organization.create! }
  let(:result_class) { stub_const("Decidim::Accountability::Result", Struct.new(:id, :organization)) }
  let(:result) { result_class.new(4242, organization) }
  let(:previous_types) { Decidim::ContractsSk.supported_link_target_types }

  before do
    migrate_engine_schema!
    previous_types
    Decidim::ContractsSk.supported_link_target_types = %w[Decidim::Accountability::Result Decidim::Budgets::Project]
  end

  after { Decidim::ContractsSk.supported_link_target_types = previous_types }

  def linked_contract!(target: result, org: organization, **overrides)
    serial = serials.next
    contract = Decidim::ContractsSk::Contract.create!(
      contract_attributes(
        { state: "published", reference: "ZP-#{serial}", title: "Zmluva #{serial}", organization: org,
          published_at: Time.utc(2026, 9, 1, 12, 0, 0) + serial.minutes,
          amount: BigDecimal("1250.50") }.merge(overrides)
      )
    )
    contract.links.create!(target_type: target.class.name, target_id: target.id)
    contract
  end

  # A host-like view context: a fresh controller class (so it picks up the
  # app's mounted engine route proxies, as a host controller does) that has
  # NOT included the engine's helpers.
  def host_renderer
    Class.new(ActionController::Base).renderer
  end

  def render_block(resource = result, **locals)
    host_renderer.render(
      partial: "decidim/contracts_sk/related_contracts/list", locals: { resource: resource, **locals }
    )
  end

  describe "the lookup" do
    it "returns only PUBLISHED contracts, whatever the other lifecycle states" do
      published = linked_contract!(title: "Verejná")
      %w[draft in_review approved returned rejected archived].each do |state|
        linked_contract!(state: state, title: "Stav #{state}")
      end

      expect(described_class.call(result).to_a).to eq([published])
      expect(Decidim::ContractsSk.related_contracts_for(result).to_a).to eq([published])
    end

    it "never returns another organization's contract linked to the same target id" do
      mine = linked_contract!
      linked_contract!(title: "Cudzia zmluva", org: other_organization)

      expect(described_class.call(result).to_a).to eq([mine])
      expect(described_class.call(result_class.new(4242, other_organization)).map(&:title)).to eq(["Cudzia zmluva"])
    end

    it "only follows links to this target: another id or another target type never matches" do
      linked_contract!(title: "Iný výsledok", target: result_class.new(1, organization))
      stub_const("Decidim::Budgets::Project", Struct.new(:id, :organization))
      linked_contract!(title: "Projekt s rovnakým id", target: Decidim::Budgets::Project.new(4242, organization))
      mine = linked_contract!

      expect(described_class.call(result).to_a).to eq([mine])
    end

    it "is empty for a target type the host has not whitelisted" do
      linked_contract!
      Decidim::ContractsSk.supported_link_target_types = []

      expect(described_class.call(result)).to be_empty
    end

    it "is empty, never raising, for a missing, unsaved or organization-less resource" do
      linked_contract!

      expect(described_class.call(nil)).to be_empty
      expect(described_class.call(result_class.new(nil, organization))).to be_empty
      expect(described_class.call(result_class.new(4242, nil))).to be_empty
      expect(described_class.call(Object.new)).to be_empty
    end

    it "orders newest first and honours the limit (invalid limits fall back to the page size)" do
      oldest = linked_contract!
      middle = linked_contract!
      newest = linked_contract!

      expect(described_class.call(result).to_a).to eq([newest, middle, oldest])
      expect(described_class.call(result, limit: 2).to_a).to eq([newest, middle])
      expect(described_class.call(result, limit: 0).size).to eq(3)
      expect(described_class.call(result, limit: "x").size).to eq(3)
    end

    it "costs a constant number of queries however many contracts are related" do
      count_queries = lambda do
        n = 0
        counter = ->(*, payload) { n += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { render_block }
        n
      end
      linked_contract!.parties.create!(role: "contractor", name: "Prvý s.r.o.", ico: "12345678")
      one = count_queries.call
      4.times { linked_contract!.parties.create!(role: "contractor", name: "Ďalší s.r.o.", ico: "87654321") }

      expect(count_queries.call).to eq(one)
    end
  end

  describe "the rendered block" do
    it "renders nothing at all when there is nothing to show" do
      linked_contract!(state: "draft")

      expect(render_block.strip).to eq("")
      expect(render_block(result_class.new(999, organization)).strip).to eq("")
    end

    it "lists title, reference, amount and a link to the contract detail on the engine mount" do
      contract = linked_contract!(title: "Rekonštrukcia cesty", reference: "ZP-77")
      contract.parties.create!(role: "contractor", name: "Stavby s.r.o.", ico: "12345678")

      html = Nokogiri::HTML.fragment(render_block)

      expect(html.at_css("h2").text).to eq("Related contracts")
      link = html.at_css("a.cs-related__title")
      expect(link.text).to eq("Rekonštrukcia cesty")
      expect(link["href"]).to eq("/#{contract.id}")
      expect(html.at_css(".cs-related__meta").text).to include("ZP-77").and include("Stavby s.r.o.")
      expect(html.at_css(".cs-related__meta a")["href"]).to eq("/suppliers/12345678")
      expect(html.at_css(".cs-related__amount").text).to eq("1250.5 EUR")
      expect(html.at_css(".label")).to be_nil
    end

    it "labels a CRZ mirror with the provenance badge and the mirror date, and no editorial record" do
      linked_contract!(title: "Zrkadlo", source: "crz", imported_at: Time.utc(2026, 9, 20, 8, 0, 0))
      linked_contract!(title: "Redakčná")

      items = Nokogiri::HTML.fragment(render_block).css("li")
      mirror = items.find { |li| li.text.include?("Zrkadlo") }
      editorial = items.find { |li| li.text.include?("Redakčná") }

      expect(mirror.at_css(".label").text.squish).to start_with("Externally confirmed")
      expect(mirror.at_css(".label").text).to include("2026")
      expect(editorial.at_css(".label")).to be_nil
    end

    it "escapes every contract-supplied string" do
      linked_contract!(title: %(<script>alert("t")</script>), reference: "<img src=x onerror=alert(1)>")
        .parties.create!(role: "contractor", name: "<b>Firma</b>", ico: "12345678")

      body = render_block

      expect(body).not_to include("<script>")
      expect(body).not_to include("<img")
      expect(body).not_to include("<b>Firma")
      expect(body).to include("&lt;script&gt;").and include("&lt;b&gt;Firma&lt;/b&gt;")
    end

    it "shows no party without an IČO and never the object party" do
      contract = linked_contract!
      contract.parties.create!(role: "contractor", name: "Ján Súkromný", ico: nil)
      contract.parties.create!(role: "object", name: "Obec Vzorová", ico: "11111111")
      contract.parties.create!(role: "contractor", name: "Verejná firma s.r.o.", ico: "22222222")

      body = render_block

      expect(body).to include("Verejná firma s.r.o.")
      expect(body).not_to include("Ján Súkromný")
      expect(body).not_to include("Obec Vzorová")
    end

    it "shows a contractor once when two of its parties share the IČO" do
      contract = linked_contract!
      contract.parties.create!(role: "contractor", name: "Firma s.r.o.", ico: "12345678")
      contract.parties.create!(role: "contractor", name: "Firma s.r.o. (konzorcium)", ico: "12345678")

      expect(Nokogiri::HTML.fragment(render_block).css(".cs-related__meta a").size).to eq(1)
    end

    it "renders the stylesheet once even when the block is embedded twice on a page" do
      linked_contract!
      page = host_renderer.render(
        inline: <<~ERB, locals: { resource: result }
          <%= render partial: "decidim/contracts_sk/related_contracts/list", locals: { resource: resource } %>
          <%= render partial: "decidim/contracts_sk/related_contracts/list", locals: { resource: resource } %>
          <%= content_for(:css_content) %>
        ERB
      )

      expect(page.scan("<style>").size).to eq(1)
      expect(page.scan('cs-related__item"').size).to eq(2)
    end

    it "carries only .cs-related classes and Decidim component classes" do
      linked_contract!(source: "crz", imported_at: Time.utc(2026, 9, 20))
        .parties.create!(role: "contractor", name: "Firma s.r.o.", ico: "12345678")

      classes = Nokogiri::HTML.fragment(render_block).css("[class]").flat_map { |node| node["class"].split }.uniq

      expect(classes - %w[h4 decorator label]).to all(start_with("cs-related"))
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
