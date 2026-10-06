# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the digest delivery (civora-org/civora-platform#121): who is
# mailed (confirmed only), what is in the digest (the organization's own
# published contracts, newer than the last window, matching the stored
# filters through the catalogue's own query), that nothing is mailed twice,
# and that one failure does not stop the run. A fixed clock and an explicit
# `now`; synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::DeliverSubscriptionDigests, :db do
  let(:confirmed_at) { Time.utc(2026, 10, 13, 6, 0, 0) }
  let(:now) { Time.utc(2026, 10, 14, 7, 0, 0) }
  let(:log) { StringIO.new }

  before do
    migrate_engine_schema!
    organization.update!(host: "zmluvy.example.org", default_locale: "en", name: { "en" => "Green Village" })
    ActionMailer::Base.deliveries.clear
  end

  def subscription_class
    Decidim::ContractsSk::Subscription
  end

  def contract_class
    Decidim::ContractsSk::Contract
  end

  def create_contract!(overrides = {})
    serial = contract_class.count + 1
    contract_class.create!(
      contract_attributes(
        { state: "published", reference: "ZP-#{serial}", title: "Contract #{serial}",
          published_at: Time.utc(2026, 10, 13, 12), amount: BigDecimal("1000") }.merge(overrides)
      )
    )
  end

  def subscribe!(email: "reader@example.org", params: {}, confirm: true, org: organization, **attrs)
    token = subscription_class.generate_token
    subscription_class.create!(
      { organization: org, email: email, filter_params: params, locale: "en", created_at: confirmed_at - 1.hour,
        token_digest: subscription_class.digest(token) }.merge(attrs)
    ).tap { |subscription| subscription.confirm!(confirmed_at) if confirm }
  end

  def run(at: now, org: organization)
    described_class.call(organization: org, now: at, logger: Logger.new(log))
  end

  def mails
    ActionMailer::Base.deliveries
  end

  def mail_body(mail = mails.last)
    mail.body.decoded
  end

  it "mails a confirmed subscriber one digest of a matching contract published since the confirmation" do
    subscribe!
    contract = create_contract!(title: "Road works")

    summary = run

    expect(summary.to_h).to eq(purged: 0, checked: 1, delivered: 1, failed: 0)
    expect(mails.size).to eq(1)
    expect(mails.first.to).to eq(["reader@example.org"])
    expect(mail_body).to include("Road works").and include("/#{contract.id}?locale=en")
  end

  it "never mails an unconfirmed subscription" do
    subscribe!(confirm: false)
    create_contract!

    summary = run

    expect(summary.checked).to eq(0)
    expect(mails).to be_empty
  end

  it "sends nothing when nothing new matches, and still moves the window" do
    subscription = subscribe!

    expect(run.delivered).to eq(0)
    expect(mails).to be_empty
    expect(subscription.reload.last_notified_at).to eq(now - 1.minute)
  end

  it "does not mail a contract published before the confirmation (no backlog)" do
    subscribe!
    create_contract!(published_at: confirmed_at - 1.hour)

    expect(run.delivered).to eq(0)
  end

  it "mails each contract once: a second run sends nothing, a third only the newer contract" do
    subscribe!
    create_contract!(title: "First", published_at: Time.utc(2026, 10, 13, 12))

    run
    run(at: now + 1.hour)
    expect(mails.size).to eq(1)

    create_contract!(title: "Second", published_at: now + 90.minutes)
    run(at: now + 3.hours)

    expect(mails.size).to eq(2)
    expect(mail_body).to include("Second")
    expect(mail_body).not_to include("First")
  end

  it "does not double-deliver to a stale in-memory copy of a subscription already delivered by another run" do
    subscription = subscribe!
    create_contract!
    stale = subscription_class.find(subscription.id)

    run
    described_class.new(organization: organization, now: now, logger: Logger.new(log)).send(:process, stale)

    expect(mails.size).to eq(1)
  end

  it "applies the stored filters with the catalogue's own semantics" do
    subscribe!(params: { "amount_min" => "5000", "q" => "bridge" })
    create_contract!(title: "Bridge repair", amount: BigDecimal("9000"))
    create_contract!(title: "Bridge paint", amount: BigDecimal("100"))
    create_contract!(title: "Road repair", amount: BigDecimal("9000"))

    run

    expect(mail_body).to include("Bridge repair")
    expect(mail_body).not_to include("Bridge paint")
    expect(mail_body).not_to include("Road repair")
  end

  it "mails only the organization's own published records: not drafts, mirrors, archived or another tenant's" do
    subscribe!
    other_org = Decidim::Organization.create!
    other_author = Decidim::User.create!(organization: other_org)
    create_contract!(title: "OWN PUBLISHED")
    create_contract!(title: "A DRAFT", state: "draft", published_at: nil)
    create_contract!(title: "A MIRROR", source: "crz", source_id: "9001")
    create_contract!(title: "ARCHIVED", state: "archived")
    contract_class.create!(organization: other_org, author: other_author, title: "OTHER TENANT",
                           reference: "X-1", state: "published", published_at: Time.utc(2026, 10, 13, 12))

    run

    expect(mail_body).to include("OWN PUBLISHED")
    %w[DRAFT MIRROR ARCHIVED TENANT].each { |sentinel| expect(mail_body).not_to include(sentinel) }
  end

  it "does not touch another organization's subscriptions" do
    other_org = Decidim::Organization.create!(host: "other.example.org")
    other_author = Decidim::User.create!(organization: other_org)
    subscribe!(email: "theirs@example.org", org: other_org)
    contract_class.create!(organization: other_org, author: other_author, title: "THEIRS", reference: "X-1",
                           state: "published", published_at: Time.utc(2026, 10, 13, 12))

    expect(run.checked).to eq(0)
    expect(mails).to be_empty
  end

  it "lists at most DIGEST_LIMIT contracts, newest first, and states the total with a catalogue link" do
    subscribe!
    25.times { |i| create_contract!(title: "Bulk #{i}", published_at: Time.utc(2026, 10, 13, 10) + i.minutes) }

    run

    html = mail_body
    expect(mails.size).to eq(1)
    expect(html.scan("Bulk ").size).to eq(described_class::DIGEST_LIMIT)
    expect(html).to include("Bulk 24").and include("Bulk 5<")
    expect(html).not_to include("Bulk 4<")
    expect(html).to include("matching your alert were published by Green Village: 25.")
    expect(html).to include("and 5 more in the catalogue")
  end

  it "leaves out a contract published inside the settle margin and picks it up next run" do
    subscribe!
    fresh = create_contract!(title: "Just published", published_at: now - 20.seconds)

    expect(run.delivered).to eq(0)

    run(at: now + 10.minutes)
    expect(mails.size).to eq(1)
    expect(mail_body).to include("Just published").and include("/#{fresh.id}?")
  end

  it "mails every confirmed subscription its own digest, in its own locale" do
    subscribe!(email: "en@example.org")
    subscribe!(email: "sk@example.org", locale: "sk")
    create_contract!

    run

    expect(mails.map(&:to)).to contain_exactly(["en@example.org"], ["sk@example.org"])
    expect(mails.find { |m| m.to == ["sk@example.org"] }.subject).to start_with("Nové zmluvy")
  end

  it "stops mailing an unsubscribed (deleted) subscription" do
    subscribe!.destroy!
    create_contract!

    expect(run.checked).to eq(0)
    expect(mails).to be_empty
  end

  it "purges unconfirmed subscriptions past 48 hours before delivering, and reports it" do
    subscribe!(email: "stale@example.org", confirm: false, created_at: now - 49.hours)
    subscribe!(email: "recent@example.org", confirm: false, created_at: now - 1.hour)

    expect(run.purged).to eq(1)
    expect(subscription_class.pending.pluck(:email)).to eq(["recent@example.org"])
  end

  describe "failure handling" do
    it "keeps going after one subscription fails, counts it, logs class and id only, and retries it next run" do
      bad = subscribe!(email: "bad@example.org")
      good = subscribe!(email: "good@example.org")
      create_contract!
      allow(Decidim::ContractsSk::SubscriptionMailer).to receive(:digest).and_wrap_original do |original, sub, *rest|
        raise Net::SMTPServerBusy, "451 secret detail for #{sub.email}" if sub.id == bad.id

        original.call(sub, *rest)
      end

      summary = run

      expect(summary.to_h).to include(delivered: 1, failed: 1)
      expect(mails.map(&:to)).to eq([["good@example.org"]])
      expect(bad.reload.last_notified_at).to eq(confirmed_at)
      expect(good.reload.last_notified_at).to eq(now - 1.minute)
      expect(log.string).to include("subscription #{bad.id} digest failed: Net::SMTPServerBusy")
      expect(log.string).not_to include("bad@example.org")
      expect(log.string).not_to include("secret detail")

      allow(Decidim::ContractsSk::SubscriptionMailer).to receive(:digest).and_call_original
      expect(run(at: now + 1.hour).delivered).to eq(1)
      expect(mails.last.to).to eq(["bad@example.org"])
    end

    it "does not fail the run when a subscription is unsubscribed while it is going" do
      subscription = subscribe!
      create_contract!
      allow_any_instance_of(subscription_class).to receive(:with_lock).and_raise(ActiveRecord::RecordNotFound) # rubocop:disable RSpec/AnyInstance

      summary = run

      expect(summary.to_h).to include(checked: 1, delivered: 0, failed: 0)
      expect(subscription.reload.last_notified_at).to eq(confirmed_at)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
