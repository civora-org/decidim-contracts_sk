# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Locale handling of every URL the engine emits (civora-org/civora-platform
# #183, spike docs/spikes/decidim-upgrade-path.md section 3 "verify").
#
# Decidim 0.32 changed how locales reach a URL. The suite runs on both lines
# (CI matrix), and these examples run the harness with the REAL
# Decidim::LocaleSwitcher of the line under test switched on
# (:decidim_locale_switcher; spec/dummy/config/application.rb):
#
#   0.31  default_url_options = {} for the default locale, else
#         `?locale=xx`; the layout head links `?locale=` alternates.
#   0.32  default_url_options = {locale: ..} ALWAYS (unless the request's
#         script name already starts with the locale, i.e. the engine is
#         mounted inside `scope "/:locale"`); core routes are path-prefixed
#         (`/sk/...`) with redirects for the legacy paths; the head links
#         `canonical_url(request.url, locale)` alternates, which PREFIX the
#         path with the locale.
#
# Line-specific expectations are guarded by DummyDecidimLine.locale_prefixed?;
# everything else is asserted identically on both lines. The prefixed-mount
# group exists on 0.32 only (the dummy draws that mount on that line only).
# Synthetic data only. Cop note: allow_any_instance_of is the approved seam
# for the controller-level tenancy, like the sibling request specs.
# ---------------------------------------------------------------------------

require "spec_helper"
require "nokogiri"
require "csv"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "locale-aware URLs", :db, :decidim_locale_switcher, type: :request do
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:contract) do
    record = contract_class.create!(
      contract_attributes(state: "published", reference: "ZP-1", title: "Zmluva 1",
                          published_at: Time.utc(2026, 9, 1, 12), amount: BigDecimal("1250.50"),
                          signed_on: Date.new(2026, 8, 30))
    )
    record.parties.create!(role: "contractor", name: "Dodávateľ s.r.o.", ico: "12345678")
    record
  end

  def atom_ns
    { "a" => "http://www.w3.org/2005/Atom" }
  end

  def sitemap_ns
    { "s" => "http://www.sitemaps.org/schemas/sitemap/0.9" }
  end

  def prefixed
    DummyDecidimLine.locale_prefixed?
  end

  before do
    migrate_engine_schema!
    organization.update!(host: "zmluvy.example.org", default_locale: "sk", available_locales: %w[en sk],
                         name: { "sk" => "Obec Zelená", "en" => "Green Village" })
    allow_any_instance_of(Decidim::ApplicationController).to receive(:current_organization).and_return(organization)
    contract
  end

  def doc
    Nokogiri::HTML(response.body)
  end

  def meta(property)
    doc.at_css("head meta[property='#{property}']")&.[]("content")
  end

  def alternates
    doc.css("head link[rel='alternate'][hreflang]").to_h { |link| [link["hreflang"], link["href"]] }
  end

  def feed(path, **opts)
    get path, **opts
    expect(response).to have_http_status(:ok)
    Nokogiri::XML(response.body) { |config| config.strict.nonet }
  end

  # The same assertions on every public page that registers an og:url.
  def canonical_urls(base)
    {
      "#{base}/" => "http://www.example.com#{base}/",
      "#{base}/#{contract.id}" => "http://www.example.com#{base}/#{contract.id}",
      "#{base}/suppliers/12345678" => "http://www.example.com#{base}/suppliers/12345678",
      "#{base}/statistics" => "http://www.example.com#{base}/statistics"
    }
  end

  shared_examples "locale-free machine-readable URLs" do |base|
    it "keeps the sitemap's loc, the Atom links and the open-data url column free of locale parameters" do
      detail = "http://www.example.com#{base}/#{contract.id}"

      sitemap = feed("#{base}/sitemap.xml", params: request_params)
      expect(sitemap.xpath("//s:url/s:loc", sitemap_ns).map(&:text)).to eq([detail])

      atom = feed("#{base}/feed.atom", params: request_params)
      expect(atom.at_xpath("/a:feed/a:link[@rel='alternate']", atom_ns)["href"]).to eq("http://www.example.com#{base}/")
      expect(atom.at_xpath("/a:feed/a:entry/a:link[@rel='alternate']", atom_ns)["href"]).to eq(detail)

      get "#{base}/export.csv", params: request_params
      expect(CSV.parse(response.body.delete_prefix("﻿"), headers: true).first["url"]).to eq(detail)

      get "#{base}/export.json", params: request_params
      expect(JSON.parse(response.body).first["url"]).to eq(detail)
    end

    it "keeps og:url (the canonical page URL) free of locale parameters" do
      canonical_urls(base).each do |path, expected|
        get path, params: request_params

        expect(response).to have_http_status(:ok), "#{path} answered #{response.status}"
        expect(meta("og:url")).to eq(expected), "og:url of #{path}"
      end
    end
  end

  # -------------------------------------------------------------------------
  # The un-prefixed mount: every 0.31 host, and a 0.32 host that mounts the
  # engine without a locale scope.
  # -------------------------------------------------------------------------
  describe "the engine mounted without a locale scope" do
    context "with a non-default request locale (?locale=en)" do
      let(:request_params) { { locale: "en" } }

      include_examples "locale-free machine-readable URLs", ""

      it "carries the Atom self link's locale explicitly (the one place the locale is meant to travel)" do
        atom = feed("/feed.atom", params: request_params)

        expect(atom.at_xpath("/a:feed/a:link[@rel='self']", atom_ns)["href"])
          .to eq("http://www.example.com/feed.atom?locale=en")
      end

      it "keeps the page links on the visitor's locale" do
        get "/", params: request_params

        expect(doc.at_css("li.cs-row .cs-row__title")["href"]).to eq("/#{contract.id}?locale=en")
      end
    end

    context "with the default request locale (no locale parameter)" do
      let(:request_params) { {} }

      include_examples "locale-free machine-readable URLs", ""

      it "differs per Decidim line only in whether page links spell the default locale out" do
        get "/"

        # 0.31 omits the default locale from default_url_options, 0.32 never does.
        expect(doc.at_css("li.cs-row .cs-row__title")["href"])
          .to eq(prefixed ? "/#{contract.id}?locale=sk" : "/#{contract.id}")
      end
    end

    it "resolves the legacy un-prefixed engine paths directly, on both lines" do
      ["/", "/#{contract.id}", "/suppliers/12345678", "/statistics", "/export.csv", "/export.json",
       "/feed.atom", "/sitemap.xml", "/subscriptions/new"].each do |path|
        get path

        expect(response).to have_http_status(:ok), "#{path} answered #{response.status}"
      end
    end

    it "links every alternate language to a URL the engine answers, and says so in the right form" do
      get "/#{contract.id}", params: { locale: "sk" }

      # 0.31 lists every locale (the current one too); 0.32 the others only.
      expect(alternates.keys).to match_array(prefixed ? %w[en] : %w[en sk])
      alternates.each do |hreflang, href|
        uri = URI(href)
        expect(uri.path).to eq("/#{contract.id}")
        expect(URI.decode_www_form(uri.query).to_h).to eq("locale" => hreflang)

        get href
        expect(response).to have_http_status(:ok)
        expect(doc.at_css("html")["lang"]).to eq(hreflang)
      end
    end

    it "rewrites a locale already present in the URL instead of appending a second one" do
      controller = Decidim::ContractsSk::ContractsController.new
      allow(controller).to receive_messages(request: ActionDispatch::TestRequest.create, available_locales: %w[en sk])

      expect(controller.canonical_url("http://www.example.com/5?q=x&locale=sk", "en"))
        .to eq("http://www.example.com/5?q=x&locale=en")
    end
  end

  # -------------------------------------------------------------------------
  # The alert e-mails build absolute URLs outside any request: the explicit
  # locale parameter is the contract, identical on both lines.
  # -------------------------------------------------------------------------
  describe "alert e-mail links" do
    it "spells the subscriber's locale into every absolute link, on the organization's host" do
      subscription = Decidim::ContractsSk::Subscription.create!(
        organization: organization, email: "reader@example.org", locale: "sk", filter_params: { "q" => "cesta" },
        token_digest: Decidim::ContractsSk::Subscription.digest(Decidim::ContractsSk::Subscription.generate_token)
      )

      mail = Decidim::ContractsSk::SubscriptionMailer.digest(subscription, [contract], 30)
      # The layout footer's link to the organization's home page is the host's, not the engine's.
      links = Nokogiri::HTML(mail.body.decoded).css("a").pluck("href")
                      .grep(%r{\Ahttp://zmluvy\.example\.org/.})

      expect(links).to include("http://zmluvy.example.org/#{contract.id}?locale=sk")
      expect(links).to all(match(/[?&]locale=sk\b/))
      expect(mail.header["List-Unsubscribe"].value)
        .to match(%r{\A<http://zmluvy\.example\.org/subscriptions/[^/]+/unsubscribe\?locale=sk>\z})
    end
  end

  # -------------------------------------------------------------------------
  # The in-space component. Its mount is Decidim's own, so on 0.32 it sits
  # below /:locale and on 0.31 it does not.
  # -------------------------------------------------------------------------
  describe "the in-space component" do
    it "registers a canonical og:url without locale parameters" do
      get "/spaces/town/f/7", params: { locale: "en" }

      expect(response).to have_http_status(:ok)
      expect(meta("og:url")).to eq("http://www.example.com/spaces/town/f/7/")
    end
  end

  # -------------------------------------------------------------------------
  # Decidim 0.32: the engine mounted inside `scope "/:locale"`, with the
  # legacy un-prefixed paths redirected through Decidim's own
  # Routes::LocaleRedirects (spec/dummy/config/routes.rb).
  # -------------------------------------------------------------------------
  describe "the engine mounted below /:locale (Decidim 0.32)", if: DummyDecidimLine.locale_prefixed? do
    let(:request_params) { {} }

    include_examples "locale-free machine-readable URLs", "/sk/zmluvy"

    it "redirects a legacy un-prefixed path permanently to the prefixed one, keeping the query" do
      get "/zmluvy/#{contract.id}", params: { locale: "sk" }

      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to eq("http://www.example.com/sk/zmluvy/#{contract.id}")

      get "/zmluvy"
      expect(response).to have_http_status(:moved_permanently)
      expect(URI(response.location).path).to match(%r{\A/(en|sk)/zmluvy\z})
    end

    it "keeps the format and the filters of a stored open-data link when redirecting" do
      get "/zmluvy/export.csv?q=cesta&locale=sk"

      expect(response).to have_http_status(:moved_permanently)
      expect(response.location).to eq("http://www.example.com/sk/zmluvy/export.csv?q=cesta")

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
    end

    it "emits prefixed page links and alternates that all resolve" do
      get "/sk/zmluvy/#{contract.id}"

      expect(response).to have_http_status(:ok)
      expect(alternates).to eq("en" => "http://www.example.com/en/zmluvy/#{contract.id}")
      get alternates.fetch("en")
      expect(response).to have_http_status(:ok)
      expect(doc.at_css("html")["lang"]).to eq("en")
    end

    it "mounts the in-space component below /:locale as Decidim's participatory spaces do" do
      get "/sk/spaces/town/f/7"

      expect(response).to have_http_status(:ok)
      expect(meta("og:url")).to eq("http://www.example.com/sk/spaces/town/f/7/")
      expect(alternates).to eq("en" => "http://www.example.com/en/spaces/town/f/7")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
