# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the alert e-mails (civora-org/civora-platform#121): the double
# opt-in confirmation and the digest. They pin the headers (List-Unsubscribe
# and the RFC 8058 one-click companion), the links (organization host, signed
# unsubscribe token), the locale, and above all the escaping: titles, search
# terms and the organization's name are hostile input. The layout is the
# harness stand-in of decidim-core's (spec/dummy/app/views/layouts/decidim).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::SubscriptionMailer, :db do
  let(:token) { Decidim::ContractsSk::Subscription.generate_token }
  let(:subscription) do
    Decidim::ContractsSk::Subscription.create!(
      organization: organization, email: "reader@example.org", locale: "en",
      filter_params: { "q" => "cesta", "amount_min" => "10000" },
      token_digest: Decidim::ContractsSk::Subscription.digest(token)
    )
  end

  before do
    migrate_engine_schema!
    organization.update!(host: host, default_locale: "en", name: { "en" => "Green Village", "sk" => "Obec Zelená" })
  end

  def host
    "zmluvy.example.org"
  end

  def create_contract!(overrides = {})
    Decidim::ContractsSk::Contract.create!(
      contract_attributes(
        { state: "published", reference: "ZP-1", title: "Road works", amount: BigDecimal("1250.50"),
          signed_on: Date.new(2026, 10, 1), published_at: Time.utc(2026, 10, 12, 9) }.merge(overrides)
      )
    )
  end

  def body(mail)
    mail.body.decoded
  end

  # The part this engine renders. The layout's footer link prints the
  # organization's name the way decidim-core's real layout does (html_safe
  # on an admin-entered name): that is the host's, not this engine's.
  def content(mail)
    body(mail).split('<div class="cityhall-bar">').first
  end

  def unsubscribe_url(mail)
    body(mail)[%r{http://#{Regexp.escape(host)}/subscriptions/[^/"]+/unsubscribe\?locale=\w+}]
  end

  describe "#confirmation" do
    subject(:mail) { described_class.confirmation(subscription, token) }

    it "is addressed to the subscriber only, from the sender, with the organization in the subject" do
      expect(mail.to).to eq(["reader@example.org"])
      expect(mail.cc).to be_blank
      expect(mail.bcc).to be_blank
      expect(mail.from).to eq(["noreply@example.org"])
      expect(mail.subject).to eq("Confirm your contract alerts - Green Village")
    end

    it "links the confirmation page by raw token, on the organization's host, in the subscriber's locale" do
      expect(body(mail)).to include(%(href="http://#{host}/subscriptions/#{token}/confirm?locale=en"))
    end

    it "carries List-Unsubscribe and the one-click List-Unsubscribe-Post headers pointing at the unsubscribe page" do
      url = unsubscribe_url(mail)

      expect(url).to be_present
      expect(mail["List-Unsubscribe"].to_s).to eq("<#{url}>")
      expect(mail["List-Unsubscribe-Post"].to_s).to eq("List-Unsubscribe=One-Click")
      expect(url).to include(subscription.unsubscribe_token)
      expect(body(mail)).to include(%(href="#{url}"))
    end

    it "states the search and never the raw unsubscribe-less data: no address, no digest in the body" do
      text = body(mail)

      expect(text).to include("Search: cesta")
      expect(text).not_to include("reader@example.org")
      expect(text).not_to include(subscription.token_digest)
    end

    it "renders in the subscription's locale" do
      subscription.update!(locale: "sk")
      mail = described_class.confirmation(subscription.reload, token)

      expect(mail.subject).to eq("Potvrďte upozornenia na zmluvy - Obec Zelená")
      expect(body(mail)).to include("Potvrdiť odber").and include("locale=sk")
    end

    it "escapes markup in the search terms and in the organization's name" do
      organization.update!(name: { "en" => "Village <img src=x onerror=alert(1)>" })
      subscription.update!(filter_params: { "q" => "<script>alert(1)</script>", "party" => "\"><b>x</b>" })

      html = content(described_class.confirmation(subscription.reload, token))

      expect(html).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
      expect(html).to include("&lt;img src=x onerror=alert(1)&gt;")
      expect(html).not_to include("<script>")
      expect(html).not_to include("<b>x</b>")
      expect(html).not_to match(/<img src=x/)
    end
  end

  describe "#digest" do
    subject(:mail) { described_class.digest(subscription, contracts, contracts.size) }

    let(:contracts) { [create_contract!] }

    it "lists the contract with a public link, reference, amount and signing date" do
      html = body(mail)

      expect(mail.subject).to eq("New contracts - Green Village")
      expect(html).to include(%(href="http://#{host}/#{contracts.first.id}?locale=en">Road works</a>))
      expect(html).to include("ZP-1, 1250.5 EUR, signed 2026-10-01")
      expect(html).to include("New contracts matching your alert were published by Green Village: 1.")
    end

    it "carries the unsubscribe link and both headers, like every alert e-mail" do
      url = unsubscribe_url(mail)

      expect(url).to be_present
      expect(mail["List-Unsubscribe"].to_s).to eq("<#{url}>")
      expect(mail["List-Unsubscribe-Post"].to_s).to eq("List-Unsubscribe=One-Click")
      expect(body(mail)).to include("You get this e-mail because you subscribed")
    end

    it "escapes hostile contract titles, references and search terms" do
      hostile = create_contract!(title: "<script>alert('t')</script>", reference: "<b>REF</b>",
                                 published_at: Time.utc(2026, 10, 12, 10))
      subscription.update!(filter_params: { "q" => "<i>q</i>" })

      html = content(described_class.digest(subscription.reload, [hostile], 1))

      expect(html).to include("&lt;script&gt;alert(&#39;t&#39;)&lt;/script&gt;")
      expect(html).to include("&lt;b&gt;REF&lt;/b&gt;")
      expect(html).to include("&lt;i&gt;q&lt;/i&gt;")
      expect(html).not_to include("<script>")
      expect(html).not_to include("<b>REF</b>")
      expect(html).not_to include("<i>q</i>")
    end

    it "never prints a party: not a natural person without an IČO, not even one with an IČO" do
      contract = contracts.first
      contract.parties.create!(role: "contractor", name: "Jan Privatny Novak", address: "Tajna 1, Bratislava")
      contract.parties.create!(role: "contractor", name: "Firma s.r.o.", ico: "36396567")

      html = body(described_class.digest(subscription, [contract.reload], 1))

      expect(html).not_to include("Jan Privatny Novak")
      expect(html).not_to include("Tajna")
      expect(html).not_to include("Firma s.r.o.")
      expect(html).not_to include("36396567")
    end

    it "points to the catalogue with the stored filters when the total exceeds the listed contracts" do
      html = body(described_class.digest(subscription, contracts, 25))

      expect(html).to include("and 24 more in the catalogue")
      expect(html).to match(%r{href="http://#{Regexp.escape(host)}/\?amount_min=10000&amp;locale=en&amp;q=cesta"})
    end

    it "omits the more-link when everything is listed" do
      expect(body(mail)).not_to include("more in the catalogue")
    end

    it "renders in Slovak with the Slovak amount format" do
      subscription.update!(locale: "sk")

      mail = described_class.digest(subscription.reload, contracts, 1)

      expect(mail.subject).to eq("Nové zmluvy - Obec Zelená")
      expect(body(mail)).to include("ZP-1, 1 250,50 EUR, podpísaná")
      expect(body(mail)).to include("Odhlásiť")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
