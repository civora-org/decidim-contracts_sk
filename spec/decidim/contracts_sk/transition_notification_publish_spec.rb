# frozen_string_literal: true

require "spec_helper"

# Offline spec for TransitionNotification.publish (civora-org/civora-platform
# #94, M03-05-C / #106). The dummy has neither Decidim::EventsManager nor the
# event class loaded, so both are stubbed at their exact boundary; recipients
# are real (plain structs, no DB).
# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe Decidim::ContractsSk::TransitionNotification do
  person = Struct.new(:id)
  contract_class = Struct.new(:author, :organization, :review_reason)

  let(:events_manager) { Class.new { def self.publish(**); end } }
  let(:author) { person.new(10) }
  let(:actor) { person.new(99) }
  let(:reviewer) { person.new(1) }
  let(:contract) { contract_class.new(author, Object.new, "Doplňte prílohu.") }

  around do |example|
    saved = [Decidim::ContractsSk.notification_candidates, Decidim::ContractsSk.role_resolver]
    example.run
  ensure
    Decidim::ContractsSk.notification_candidates, Decidim::ContractsSk.role_resolver = saved
  end

  before do
    stub_const("Decidim::EventsManager", events_manager)
    allow(events_manager).to receive(:publish)
    # stub_const would first READ the constant and so trigger the engine's
    # autoload of the real event class, which needs decidim-core. const_set
    # replaces the pending autoload without loading it (undone in `after`;
    # no offline example needs the real class).
    Decidim::ContractsSk.const_set(:ContractTransitionEvent, Class.new)
    Decidim::ContractsSk.notification_candidates = ->(_organization) { [reviewer, actor] }
    Decidim::ContractsSk.role_resolver = ->(_candidate, _context) { [:reviewer] }
  end

  after { Decidim::ContractsSk.send(:remove_const, :ContractTransitionEvent) } # rubocop:disable RSpec/RemoveConst

  def publish(event, **overrides)
    described_class.publish(**{ event: event, contract: contract, actor: actor }.merge(overrides))
  end

  it "publishes submit once, to the eligible reviewers only, with no extra" do
    publish(:submit)

    expect(events_manager).to have_received(:publish).once.with(
      event: "decidim.events.contracts_sk.contract_submitted",
      event_class: Decidim::ContractsSk::ContractTransitionEvent,
      resource: contract,
      affected_users: [reviewer],
      extra: {}
    )
  end

  %i[return reject].each do |event|
    it "carries the stored reviewer reason on #{event}" do
      publish(event)

      expect(events_manager).to have_received(:publish).once.with(
        hash_including(affected_users: [author], extra: { reason: "Doplňte prílohu." })
      )
    end
  end

  %i[approve publish].each do |event|
    it "carries no reason on #{event}" do
      publish(event)

      expect(events_manager).to have_received(:publish).once.with(
        hash_including(affected_users: [author], extra: {})
      )
    end
  end

  it "accepts String events" do
    publish("return")

    expect(events_manager).to have_received(:publish).with(hash_including(extra: { reason: "Doplňte prílohu." }))
  end

  it "does not publish when there are no recipients" do
    publish(:approve, actor: author)

    expect(events_manager).not_to have_received(:publish)
  end

  it "does not publish for archive" do
    publish(:archive)

    expect(events_manager).not_to have_received(:publish)
  end

  it "does not publish for an unknown event or nil" do
    publish(:bogus)
    publish(nil)

    expect(events_manager).not_to have_received(:publish)
  end

  it "returns nil when it publishes" do
    expect(publish(:submit)).to be_nil
  end

  describe "fail-soft" do
    let(:secret) { "secret.person@example.org" }
    let(:logger) { instance_spy(Logger) }

    before do
      allow(Rails).to receive(:logger).and_return(logger)
      allow(events_manager).to receive(:publish).and_raise(ArgumentError, secret)
    end

    it "swallows a StandardError and returns nil" do
      expect { publish(:submit) }.not_to raise_error
      expect(publish(:submit)).to be_nil
    end

    it "logs the error class only, never the message or recipients" do
      publish(:submit)

      expect(logger).to have_received(:warn)
        .with("[decidim-contracts_sk] transition notification failed: ArgumentError")
      expect(logger).not_to have_received(:warn).with(a_string_including(secret))
    end

    it "also swallows a failure while resolving recipients" do
      Decidim::ContractsSk.notification_candidates = ->(_organization) { raise IOError, secret }

      expect(publish(:submit)).to be_nil
      expect(logger).to have_received(:warn).with(a_string_including("IOError"))
    end

    it "does not swallow exceptions that are not StandardErrors" do
      allow(events_manager).to receive(:publish).and_raise(NoMemoryError)

      expect { publish(:submit) }.to raise_error(NoMemoryError)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength, RSpec/MultipleExpectations
