# frozen_string_literal: true

require "spec_helper"

# Offline spec for TransitionNotification.recipients and the
# notification_candidates seam (civora-org/civora-platform#94, M03-05-B /
# #105). Plain doubles only: no DB, no Decidim::User constant.
# The shared fixture set (seams, actors, contract) is the point of the file,
# so the helper-count and example-length budgets are waived here.
# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::TransitionNotification do
  person = Struct.new(:id)
  contract_class = Struct.new(:author, :organization)

  let(:organization) { Object.new }
  let(:author) { person.new(10) }
  let(:contract) { contract_class.new(author, organization) }
  let(:actor) { person.new(99) }
  let(:admin_reviewer) { person.new(1) }
  let(:admin_editor_only) { person.new(2) }
  let(:roles) { { 1 => [:reviewer], 2 => [:editor], 99 => [:reviewer] } }
  let(:candidates) { [admin_reviewer, admin_editor_only, actor] }

  around do |example|
    saved = [Decidim::ContractsSk.notification_candidates, Decidim::ContractsSk.role_resolver]
    example.run
  ensure
    Decidim::ContractsSk.notification_candidates, Decidim::ContractsSk.role_resolver = saved
  end

  before do
    Decidim::ContractsSk.notification_candidates = ->(_organization) { candidates }
    Decidim::ContractsSk.role_resolver = ->(candidate, _context) { roles.fetch(candidate.id, []) }
  end

  def recipients(event, **overrides)
    described_class.recipients(**{ event: event, contract: contract, actor: actor }.merge(overrides))
  end

  describe "submit" do
    it "notifies candidates holding the reviewer role, never the actor (four-eyes)" do
      expect(recipients(:submit)).to eq([admin_reviewer])
    end

    it "accepts String events" do
      expect(recipients("submit")).to eq([admin_reviewer])
    end

    it "asks the seam with the contract's organization" do
      received = nil
      Decidim::ContractsSk.notification_candidates = lambda do |org|
        received = org
        candidates
      end
      recipients(:submit)
      expect(received).to equal(organization)
    end

    it "still counts a reviewer whose resolver output carries foreign symbols" do
      roles[1] = %i[reviewer bogus]
      expect(recipients(:submit)).to eq([admin_reviewer])
    end

    it "ignores a user whose resolver output holds only foreign symbols" do
      roles[1] = [:bogus]
      expect(recipients(:submit)).to eq([])
    end

    it "does not notify a user the resolver grants nothing" do
      roles.delete(1)
      expect(recipients(:submit)).to eq([])
    end

    it "tolerates a nil resolver result" do
      Decidim::ContractsSk.role_resolver = ->(_candidate, _context) {}
      expect(recipients(:submit)).to eq([])
    end

    it "collapses duplicate candidates by id" do
      duplicate = person.new(1)
      allow(Decidim::ContractsSk).to receive(:notification_candidates)
        .and_return(->(_organization) { [admin_reviewer, duplicate, admin_reviewer] })
      expect(recipients(:submit)).to eq([admin_reviewer])
    end

    it "drops nil candidates" do
      Decidim::ContractsSk.notification_candidates = ->(_organization) { [nil, admin_reviewer] }
      expect(recipients(:submit)).to eq([admin_reviewer])
    end

    it "accepts a candidate collection that only responds to to_a" do
      reviewer = admin_reviewer
      relation_like = Object.new.tap { |collection| collection.define_singleton_method(:to_a) { [reviewer] } }
      Decidim::ContractsSk.notification_candidates = ->(_organization) { relation_like }
      expect(recipients(:submit)).to eq([admin_reviewer])
    end

    it "notifies everybody when no actor is given" do
      expect(recipients(:submit, actor: nil)).to eq([admin_reviewer, actor])
    end
  end

  %i[return approve reject publish].each do |event|
    describe event.to_s do
      it "notifies the contract's author" do
        expect(recipients(event)).to eq([author])
      end

      it "notifies nobody when the author is the actor" do
        expect(recipients(event, actor: author)).to eq([])
      end

      it "does not raise and notifies nobody when the author is nil" do
        contract.author = nil
        expect(recipients(event)).to eq([])
      end

      it "does not consult the candidates seam" do
        Decidim::ContractsSk.notification_candidates = ->(_organization) { raise "must not be called" }
        expect(recipients(event)).to eq([author])
      end
    end
  end

  describe "events that are not notified" do
    it "returns nobody for archive" do
      expect(recipients(:archive)).to eq([])
    end

    it "returns nobody for unknown events and nil" do
      expect([recipients(:bogus), recipients(nil)]).to eq([[], []])
    end
  end

  describe "no memoization across calls" do
    it "reads the seams afresh on every call" do
      first = recipients(:submit)
      Decidim::ContractsSk.notification_candidates = ->(_organization) { [admin_editor_only] }
      roles[2] = [:reviewer]
      expect([first, recipients(:submit)]).to eq([[admin_reviewer], [admin_editor_only]])
    end
  end

  # The default seam's query (admins plus stored reviewers) is DB-backed and
  # specced in spec/decidim/contracts_sk/contracts_sk_role_resolver_spec.rb.
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength
