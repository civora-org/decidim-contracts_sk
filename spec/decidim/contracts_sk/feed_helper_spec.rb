# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Offline specs for the Atom feed's view helpers (civora-org/civora-platform
# #120), including the catalogue's feed auto-discovery link: the harness has
# no Decidim layout (_head renders :header_snippets), so the head tag is
# pinned here as a helper contract rather than through the page.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe Decidim::ContractsSk::FeedHelper do
  let(:view_class) do
    Class.new do
      include ActionView::Helpers::TagHelper
      include ActionView::Helpers::AssetTagHelper
      include Decidim::ContractsSk::ApplicationHelper
      include Decidim::ContractsSk::CatalogueHelper
      include Decidim::ContractsSk::FeedHelper

      attr_accessor :current_organization

      def request
        Struct.new(:host).new("request.example")
      end

      def t(key, **options)
        I18n.t(key, **options)
      end

      def feed_url(options)
        query = options.except(:format).compact.sort.to_h.to_query
        "https://zmluvy.example/feed.#{options[:format]}#{"?#{query}" unless query.empty?}"
      end
    end
  end
  let(:view) { view_class.new.tap { |v| v.current_organization = organization } }
  let(:organization) do
    Struct.new(:name, :host, :default_locale, :created_at)
          .new({ "sk" => "Obec Zelená", "en" => "Green Village" }, "zmluvy.example", "sk", Time.utc(2026, 1, 2))
  end

  def query(params = {})
    Decidim::ContractsSk::CatalogueQuery.new(scope: nil, params: params)
  end

  def with_locale(locale)
    original = I18n.locale
    I18n.locale = locale
    yield
  ensure
    I18n.locale = original
  end

  describe "#feed_discovery_link" do
    it "renders an alternate Atom link with the localized title and the filters, never the sort" do
      with_locale(:sk) do
        html = view.feed_discovery_link(query("q" => "cesta", "amount_min" => "100", "sort" => "amount_asc"))

        expect(html).to include('rel="alternate"', 'type="application/atom+xml"')
        expect(html).to include('title="Zmluvy — Obec Zelená"')
        expect(html).to include('href="https://zmluvy.example/feed.atom?amount_min=100&amp;locale=sk&amp;q=cesta"')
        expect(html).not_to include("sort")
      end
    end

    it "carries the visitor's locale explicitly" do
      with_locale(:en) do
        expect(view.feed_discovery_link(query)).to include('href="https://zmluvy.example/feed.atom?locale=en"')
      end
    end
  end

  describe "#feed_link_params" do
    it "is the one parameter set of the button, the head link and the self link, carrying the locale" do
      with_locale(:en) do
        q = query("q" => "cesta", "sort" => "amount_asc")
        params = view.feed_link_params(q)

        expect(params).to eq(q: "cesta", locale: "en", format: :atom)
        expect(view.feed_discovery_link(q)).to include('href="https://zmluvy.example/feed.atom?locale=en&amp;q=cesta"')
        expect(view.feed_id(q)).not_to include("locale")
      end
    end
  end

  describe "#feed_organization_name" do
    it "prefers the current locale, then the default locale, then any translation, then the host" do
      with_locale(:en) { expect(view.feed_organization_name).to eq("Green Village") }
      organization.name = { "sk" => "Obec Zelená" }
      with_locale(:en) { expect(view.feed_organization_name).to eq("Obec Zelená") }
      organization.name = { "de" => "  Grüne Gemeinde ", "sk" => " " }
      with_locale(:en) { expect(view.feed_organization_name).to eq("Grüne Gemeinde") }
      organization.name = { "sk" => nil, "machine_translations" => { "en" => "x" } }
      expect(view.feed_organization_name).to eq("zmluvy.example")
      organization.name = nil
      expect(view.feed_organization_name).to eq("zmluvy.example")
      organization.host = ""
      expect(view.feed_organization_name).to eq("request.example")
    end
  end

  describe "#feed_id and #feed_entry_id" do
    it "are tag URIs, stable for the same filters in any order and free of the sort" do
      a = view.feed_id(query("q" => "x", "amount_min" => "5"))
      b = view.feed_id(query("amount_min" => "5.00", "q" => "x", "sort" => "amount_asc").with(sort: "published_desc"))

      expect(a).to eq("tag:zmluvy.example,2026:contracts_sk/feed?amount_min=5&q=x")
      expect(b).to eq(a)
      expect(view.feed_id(query)).to eq("tag:zmluvy.example,2026:contracts_sk/feed")
      expect(view.feed_entry_id(Struct.new(:id).new(7))).to eq("tag:zmluvy.example,2026:contracts_sk/contract/7")
    end

    it "falls back to the request host when the organization has none" do
      organization.host = nil

      expect(view.feed_entry_id(Struct.new(:id).new(7))).to start_with("tag:request.example,2026:")
    end
  end

  describe "#feed_subtitle" do
    it "lists the active filters, localized, or says only what the feed is" do
      with_locale(:sk) do
        expect(view.feed_subtitle(query)).to eq("Novozverejnené zmluvy")
        expect(view.feed_subtitle(query("q" => "cesta"))).to eq("Novozverejnené zmluvy. Filtre: Hľadanie: cesta")
      end
    end
  end

  describe "#feed_updated_at" do
    it "is the newest entry time, else the organization's creation" do
      contracts = [Struct.new(:published_at, :created_at).new(Time.utc(2026, 5, 1), nil),
                   Struct.new(:published_at, :created_at).new(Time.utc(2026, 7, 1), nil)]

      expect(view.feed_updated_at(contracts)).to eq(Time.utc(2026, 7, 1))
      expect(view.feed_updated_at([])).to eq(Time.utc(2026, 1, 2))
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
