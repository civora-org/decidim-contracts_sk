# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Config-seam and predicate spec for Decidim::ContractsSk.allow_self_review
# (the four-eyes rule, civora-org/civora-platform#123).
#
# Pure Ruby, offline: the predicates are duck-typed on the record's
# decidim_submitted_by_id and the user's id, so plain structs stand in for
# both. The truth table pins every axis: judgment vs non-judgment event,
# submitter vs other vs nil user, stamped vs legacy-nil record, and the
# config seam.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Decidim::ContractsSk do
  let(:stamped) { Struct.new(:decidim_submitted_by_id).new(7) }
  let(:legacy) { Struct.new(:decidim_submitted_by_id).new(nil) }
  let(:submitter) { Struct.new(:id).new(7) }
  let(:other) { Struct.new(:id).new(8) }

  after { described_class.allow_self_review = false }

  describe "allow_self_review config seam (civora-org/civora-platform#123)" do
    it "defaults to false (the four-eyes rule is on)" do
      expect(described_class.allow_self_review).to be(false)
    end

    it "accepts an explicit opt-out assignment" do
      described_class.allow_self_review = true

      expect(described_class.allow_self_review).to be(true)
    end
  end

  describe "JUDGMENT_EVENTS" do
    it "is the frozen reviewer-decision vocabulary" do
      expect(described_class::JUDGMENT_EVENTS).to eq(%i[return approve reject])
      expect(described_class::JUDGMENT_EVENTS).to be_frozen
    end
  end

  describe ".self_review?" do
    it "is true for the submitter on each judgment event, Symbol or String" do
      %i[return approve reject].each do |event|
        expect(described_class.self_review?(stamped, submitter, event)).to be(true)
        expect(described_class.self_review?(stamped, submitter, event.to_s)).to be(true)
      end
    end

    it "is false for the submitter on non-judgment events" do
      %i[submit publish archive].each do |event|
        expect(described_class.self_review?(stamped, submitter, event)).to be(false)
      end
    end

    it "is false for another user" do
      expect(described_class.self_review?(stamped, other, :approve)).to be(false)
    end

    it "is false for a legacy record with no submitter stamp" do
      expect(described_class.self_review?(legacy, submitter, :approve)).to be(false)
    end

    it "is nil-safe for a nil user, nil contract and nil event" do
      expect(described_class.self_review?(stamped, nil, :approve)).to be(false)
      expect(described_class.self_review?(nil, submitter, :approve)).to be(false)
      expect(described_class.self_review?(stamped, submitter, nil)).to be(false)
    end

    it "is false for objects that do not carry the stamp reader (state-only doubles)" do
      expect(described_class.self_review?(Struct.new(:state).new("in_review"), submitter, :approve)).to be(false)
    end
  end

  describe ".self_review_blocked?" do
    it "blocks a self review while the seam is off" do
      expect(described_class.self_review_blocked?(stamped, submitter, :approve)).to be(true)
    end

    it "does not block a self review once the seam is on" do
      described_class.allow_self_review = true

      expect(described_class.self_review_blocked?(stamped, submitter, :approve)).to be(false)
    end

    it "never blocks a non-self review" do
      expect(described_class.self_review_blocked?(stamped, other, :approve)).to be(false)
      expect(described_class.self_review_blocked?(legacy, submitter, :approve)).to be(false)
      expect(described_class.self_review_blocked?(stamped, submitter, :publish)).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
