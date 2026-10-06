# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Offline specs for the in-process subscription rate limit
# (civora-org/civora-platform#121): per e-mail and per IP, fixed counts in a
# sliding window, with an injected clock (no sleeping, no globals).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::SubscriptionThrottle do
  subject(:throttle) { described_class.new(limits: { email: 3, ip: 5 }, window: 1.hour) }

  let(:t0) { Time.utc(2026, 10, 13, 8, 0, 0) }

  it "allows the configured number of attempts per address and refuses the next" do
    results = Array.new(4) { |i| throttle.allow?(email: "a@example.org", ip: "10.0.0.#{i}", now: t0) }

    expect(results).to eq([true, true, true, false])
  end

  it "limits per IP independently of the address" do
    results = Array.new(6) { |i| throttle.allow?(email: "user#{i}@example.org", ip: "10.0.0.9", now: t0) }

    expect(results).to eq([true, true, true, true, true, false])
  end

  it "does not let one address's or IP's budget touch another's" do
    3.times { throttle.allow?(email: "a@example.org", ip: "10.0.0.1", now: t0) }

    expect(throttle.allow?(email: "b@example.org", ip: "10.0.0.2", now: t0)).to be(true)
  end

  it "forgets attempts once the window has passed" do
    3.times { throttle.allow?(email: "a@example.org", ip: "10.0.0.1", now: t0) }
    expect(throttle.allow?(email: "a@example.org", ip: "10.0.0.1", now: t0 + 30.minutes)).to be(false)

    expect(throttle.allow?(email: "a@example.org", ip: "10.0.0.1", now: t0 + 61.minutes)).to be(true)
  end

  it "keeps neither the address nor the IP: only digests are held in memory" do
    throttle.allow?(email: "secret.person@example.org", ip: "203.0.113.77", now: t0)

    held = throttle.instance_variable_get(:@hits).keys.join
    expect(held).not_to include("secret.person")
    expect(held).not_to include("203.0.113.77")
    expect(held).to match(/\A\h+\z/)
  end

  it "bounds its memory: past MAX_KEYS the stale keys go, and a flood of fresh ones clears the table" do
    stub_const("#{described_class}::MAX_KEYS", 6)
    3.times { |i| throttle.allow?(email: "old#{i}@example.org", ip: "10.1.0.#{i}", now: t0) }
    throttle.allow?(email: "late@example.org", ip: "10.2.0.1", now: t0 + 2.hours)
    expect(throttle.size).to be <= 2

    20.times { |i| throttle.allow?(email: "flood#{i}@example.org", ip: "10.3.0.#{i}", now: t0 + 3.hours) }
    expect(throttle.size).to be <= 6
  end

  it "drops only the stale keys when it prunes: a fresh counter keeps limiting" do
    stub_const("#{described_class}::MAX_KEYS", 8)
    2.times { |i| throttle.allow?(email: "old#{i}@example.org", ip: "10.1.0.#{i}", now: t0) }
    later = t0 + 2.hours
    3.times { throttle.allow?(email: "fresh@example.org", ip: "10.9.0.1", now: later) }
    throttle.allow?(email: "other@example.org", ip: "10.9.0.2", now: later)
    expect(throttle.size).to eq(8)

    expect(throttle.allow?(email: "fresh@example.org", ip: "10.9.0.1", now: later)).to be(false)
    expect(throttle.size).to eq(4)
  end

  it "has a process-wide default that reset! empties" do
    described_class.default.reset!
    described_class.default.allow?(email: "a@example.org", ip: "10.0.0.1")
    expect(described_class.default.size).to eq(2)

    described_class.default.reset!
    expect(described_class.default.size).to eq(0)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
