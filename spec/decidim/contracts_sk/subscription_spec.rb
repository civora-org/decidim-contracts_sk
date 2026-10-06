# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Model specs for the e-mail alert subscription (civora-org/civora-platform
# #121): validations, the two token kinds (random + digest, signed id), the
# confirmation window and the purge. :db group, synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Subscription, :db do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2026, 10, 13, 8, 0, 0) }

  before { migrate_engine_schema! }

  # A fixed clock: every created_at is relative to it.
  around { |example| travel_to(now) { example.run } }

  def build_subscription(overrides = {})
    token = described_class.generate_token
    described_class.new({ organization: organization, email: "Reader@Example.ORG ", filter_params: { "q" => "cesta" },
                          locale: "en", token_digest: described_class.digest(token) }.merge(overrides))
  end

  def create_subscription!(overrides = {})
    build_subscription(overrides).tap(&:save!)
  end

  describe "validations" do
    it "normalizes the address (stripped, lower-cased) and accepts a plain one" do
      subscription = build_subscription

      expect(subscription).to be_valid
      expect(subscription.email).to eq("reader@example.org")
    end

    it "refuses blank, dotless-domain, spaced, multiple-@ and overlong addresses" do
      ["", "no-at-sign", "a@b", "a b@example.org", "a@@example.org", "a@example.org\nBcc: x@example.org",
       "[\"a@example.org\"]", "<a@example.org>", "\"a b\"@example.org", "a@exa mple.org",
       "#{"a" * 250}@example.org"].each do |email|
        expect(build_subscription(email: email)).not_to be_valid, "#{email.inspect} must be refused"
      end
    end

    it "requires a supported locale" do
      expect(build_subscription(locale: "xx")).not_to be_valid
      expect(build_subscription(locale: "sk")).to be_valid
    end

    it "requires an organization and a unique token digest" do
      first = create_subscription!

      expect(build_subscription(organization: nil)).not_to be_valid
      expect(build_subscription(token_digest: first.token_digest)).not_to be_valid
    end

    it "refuses a search limited to CRZ mirrors (alerts cover the own records only)" do
      subscription = build_subscription(filter_params: { "source" => "crz" })

      expect(subscription).not_to be_valid
      expect(subscription.errors).to be_added(:filter_params, :unsupported_source)
    end

    it "refuses filter params that are not a hash" do
      expect(build_subscription(filter_params: "q=cesta")).not_to be_valid
    end
  end

  describe "tokens" do
    it "generates random 256-bit URL-safe confirmation tokens" do
      tokens = Array.new(20) { described_class.generate_token }

      expect(tokens.uniq.size).to eq(20)
      expect(tokens).to all(match(/\A[A-Za-z0-9_-]{43}\z/))
    end

    it "finds a subscription by the raw token through its digest, and never stores the raw token" do
      token = described_class.generate_token
      subscription = create_subscription!(token_digest: described_class.digest(token))

      expect(described_class.find_by_token(token)).to eq(subscription)
      expect(subscription.token_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(token))
      expect(subscription.attributes.values.map(&:to_s).join(" ")).not_to include(token)
    end

    it "finds nothing for a tampered, blank or digest-as-token value" do
      token = described_class.generate_token
      subscription = create_subscription!(token_digest: described_class.digest(token))
      tampered = token.dup.tap { |t| t[0] = t[0] == "A" ? "B" : "A" }

      expect(described_class.find_by_token(tampered)).to be_nil
      expect(described_class.find_by_token("")).to be_nil
      expect(described_class.find_by_token(nil)).to be_nil
      expect(described_class.find_by_token(subscription.token_digest)).to be_nil
    end

    it "signs the unsubscribe token: it round-trips, and a tampered or foreign one finds nothing" do
      subscription = create_subscription!
      token = subscription.unsubscribe_token

      expect(described_class.find_by_unsubscribe_token(token)).to eq(subscription)
      expect(described_class.find_by_unsubscribe_token("#{token}x")).to be_nil
      expect(described_class.find_by_unsubscribe_token(token.sub(/.\z/) { |c| c == "a" ? "b" : "a" })).to be_nil
      expect(described_class.find_by_unsubscribe_token(subscription.id.to_s)).to be_nil
      expect(described_class.find_by_unsubscribe_token(nil)).to be_nil
    end

    it "does not accept a signed id minted for another purpose" do
      subscription = create_subscription!
      other_purpose = subscription.signed_id(purpose: :something_else)

      expect(described_class.find_by_unsubscribe_token(other_purpose)).to be_nil
    end

    it "stops resolving once the row is deleted (an unsubscribed link is dead)" do
      subscription = create_subscription!
      token = subscription.unsubscribe_token
      subscription.destroy!

      expect(described_class.find_by_unsubscribe_token(token)).to be_nil
    end
  end

  describe "#confirm!" do
    it "confirms a fresh pending row and starts the delivery window at the confirmation" do
      subscription = create_subscription!

      expect(subscription.confirm!(now)).to eq(:confirmed)
      subscription.reload
      expect(subscription.confirmed_at).to eq(now)
      expect(subscription.last_notified_at).to eq(now)
      expect(subscription).to be_confirmed
    end

    it "is idempotent: a second confirmation changes nothing" do
      subscription = create_subscription!
      subscription.confirm!(now)

      expect(subscription.confirm!(now + 1.day)).to eq(:already_confirmed)
      expect(subscription.reload.confirmed_at).to eq(now)
    end

    it "refuses an expired pending row and deletes it" do
      subscription = create_subscription!(created_at: now - 49.hours)

      expect(subscription.confirm!(now)).to eq(:expired)
      expect(described_class.exists?(subscription.id)).to be(false)
    end

    it "confirms right up to the end of the window" do
      subscription = create_subscription!(created_at: now - 47.hours)

      expect(subscription.confirm!(now)).to eq(:confirmed)
    end

    it "re-checks under the row lock: a stale pending copy cannot re-confirm a row someone else confirmed" do
      subscription = create_subscription!
      stale = described_class.find(subscription.id)
      subscription.confirm!(now)

      expect(stale.confirm!(now + 1.hour)).to eq(:already_confirmed)
      expect(subscription.reload.confirmed_at).to eq(now)
    end
  end

  describe "expiry" do
    it "expires only unconfirmed rows, 48 hours after creation" do
      pending_old = create_subscription!(email: "old@example.org", created_at: now - 49.hours)
      confirmed_old = create_subscription!(email: "kept@example.org", created_at: now - 49.hours)
      confirmed_old.confirm!(now - 48.hours)
      pending_fresh = create_subscription!(email: "fresh@example.org", created_at: now - 47.hours)

      expect(pending_old.expired?(now)).to be(true)
      expect(pending_fresh.expired?(now)).to be(false)
      expect(confirmed_old.reload.expired?(now)).to be(false)
      expect(described_class.expired(now)).to contain_exactly(pending_old)
    end

    it "purges the expired rows, deleting them for good, and reports how many" do
      2.times { |i| create_subscription!(email: "old#{i}@example.org", created_at: now - 49.hours) }
      kept = create_subscription!(email: "new@example.org", created_at: now - 1.hour)

      expect(described_class.purge_expired(now)).to eq(2)
      expect(described_class.all).to contain_exactly(kept)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
