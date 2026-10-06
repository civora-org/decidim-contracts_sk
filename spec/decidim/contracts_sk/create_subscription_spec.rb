# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the subscribe command (civora-org/civora-platform#121): the
# catalogue's normalization of the posted search, the duplicate rules and the
# per-address cap. :db group, synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CreateSubscription, :db do
  let(:subscription_class) { Decidim::ContractsSk::Subscription }

  before { migrate_engine_schema! }

  def subscribe(email: "reader@example.org", params: { "q" => "cesta" }, org: organization, locale: "en")
    described_class.call(organization: org, email: email, params: params, locale: locale)
  end

  it "creates an unconfirmed subscription and returns the raw token once" do
    result = subscribe

    expect(result.status).to eq(:created)
    expect(result.subscription).to be_persisted
    expect(result.subscription.confirmed_at).to be_nil
    expect(result.subscription.token_digest).to eq(subscription_class.digest(result.token))
    expect(subscription_class.find_by_token(result.token)).to eq(result.subscription)
  end

  it "stores the catalogue's NORMALIZED params, without the sort and without unknown keys" do
    result = subscribe(params: { "q" => "  cesta ", "amount_min" => "10 000,50", "published_from" => "2026-09-30",
                                 "published_to" => "2026-09-01", "sort" => "amount_asc", "evil" => "1",
                                 "party" => "36396567", "amount_max" => "junk" })

    expect(result.subscription.filter_params)
      .to eq("q" => "cesta", "amount_min" => "10000.5", "published_from" => "2026-09-01",
             "published_to" => "2026-09-30", "party" => "36396567")
  end

  it "stores an empty search as {} (all newly published contracts)" do
    expect(subscribe(params: {}).subscription.filter_params).to eq({})
  end

  it "survives hostile param shapes: arrays, hashes and NUL bytes are normalized away, never raised" do
    result = subscribe(params: { "q" => ["x"], "party" => { "a" => "b" }, "amount_min" => "1\u0000" })

    expect(result.status).to eq(:created)
    expect(result.subscription.filter_params).not_to include("amount_min" => "1\u0000")
  end

  it "strips NUL bytes from the search before it is stored (PostgreSQL would refuse them later)" do
    result = subscribe(params: { "q" => "ce\u0000sta", "party" => "Fir\u0000ma" })

    expect(result.status).to eq(:created)
    expect(result.subscription.filter_params.values.join).not_to include("\u0000")
  end

  it "reports an invalid address without persisting anything" do
    result = subscribe(email: "not-an-address")

    expect(result.status).to eq(:invalid)
    expect(result.token).to be_nil
    expect(subscription_class.count).to eq(0)
  end

  it "reports a search limited to CRZ mirrors as invalid" do
    result = subscribe(params: { "source" => "crz" })

    expect(result.status).to eq(:invalid)
    expect(result.subscription.errors).to be_added(:filter_params, :unsupported_source)
    expect(subscription_class.count).to eq(0)
  end

  it "treats an overlong address as invalid rather than truncating it into a valid one" do
    result = subscribe(email: "#{"a" * 250}@example.org")

    expect(result.status).to eq(:invalid)
  end

  it "reuses nothing for a different search of the same address: a second row is created" do
    subscribe
    result = subscribe(params: { "q" => "most" })

    expect(result.status).to eq(:created)
    expect(subscription_class.where(email: "reader@example.org").count).to eq(2)
  end

  it "answers :already_confirmed, and creates nothing, for a confirmed subscription of the same search" do
    subscribe.subscription.confirm!

    result = subscribe(email: "READER@example.org ")

    expect(result.status).to eq(:already_confirmed)
    expect(result.token).to be_nil
    expect(subscription_class.count).to eq(1)
  end

  it "replaces a pending duplicate with a fresh row and a new token (a resend), keeping one row" do
    first = subscribe
    second = subscribe

    expect(second.status).to eq(:created)
    expect(second.token).not_to eq(first.token)
    expect(subscription_class.count).to eq(1)
    expect(subscription_class.find_by_token(first.token)).to be_nil
    expect(subscription_class.find_by_token(second.token)).to eq(second.subscription)
  end

  it "caps the active subscriptions per address and organization" do
    Decidim::ContractsSk::Subscription::MAX_PER_EMAIL.times { |i| subscribe(params: { "q" => "term#{i}" }) }

    result = subscribe(params: { "q" => "one-too-many" })

    expect(result.status).to eq(:limit)
    expect(result.token).to be_nil
    expect(subscription_class.count).to eq(Decidim::ContractsSk::Subscription::MAX_PER_EMAIL)
  end

  it "does not count another address, or another organization, against the cap" do
    Decidim::ContractsSk::Subscription::MAX_PER_EMAIL.times { |i| subscribe(params: { "q" => "term#{i}" }) }
    other_org = Decidim::Organization.create!

    expect(subscribe(email: "someone.else@example.org", params: { "q" => "x" }).status).to eq(:created)
    expect(subscribe(org: other_org, params: { "q" => "x" }).status).to eq(:created)
  end

  it "does not let a pending duplicate resend count toward the cap" do
    (Decidim::ContractsSk::Subscription::MAX_PER_EMAIL - 1).times { |i| subscribe(params: { "q" => "term#{i}" }) }
    subscribe(params: { "q" => "last" })

    expect(subscribe(params: { "q" => "last" }).status).to eq(:created)
    expect(subscription_class.count).to eq(Decidim::ContractsSk::Subscription::MAX_PER_EMAIL)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
