# frozen_string_literal: true

# ---------------------------------------------------------------------------
# DB-backed specs for the Contract submitter scopes (civora-org/civora-platform
# #126). The central contract: the SET scope awaiting_review_by and the
# per-record four-eyes predicate (Decidim::ContractsSk.self_review_blocked?,
# #123) are twins — a record is in the reviewer's queue exactly when the
# predicate does not block :approve — in both modes of the
# allow_self_review seam. Opt in with CONTRACTS_SK_DB=1.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Contract, :db do
  let(:me) { Decidim::User.create!(organization: organization) }
  let(:other) { Decidim::User.create!(organization: organization) }
  let(:author) { other }

  before { migrate_engine_schema! }

  after { Decidim::ContractsSk.allow_self_review = false }

  def create_contract!(reference, overrides = {})
    described_class.create!(contract_attributes({ reference: reference }.merge(overrides)))
  end

  def references(scope)
    scope.pluck(:reference).sort
  end

  def seed!
    create_contract!("OWN", state: "in_review", decidim_submitted_by_id: me.id)
    create_contract!("THEIRS", state: "in_review", decidim_submitted_by_id: other.id)
    create_contract!("LEGACY", state: "in_review", decidim_submitted_by_id: nil)
    create_contract!("DRAFT-OWN", state: "draft", decidim_submitted_by_id: me.id)
    create_contract!("RET-OWN", state: "returned", decidim_submitted_by_id: me.id)
    create_contract!("RET-THEIRS", state: "returned", decidim_submitted_by_id: other.id)
    create_contract!("RET-LEGACY", state: "returned", decidim_submitted_by_id: nil)
  end

  describe ".submitted_by_user / .not_submitted_by_user" do
    before { seed! }

    it "selects the user's own submissions" do
      expect(references(described_class.submitted_by_user(me))).to eq(%w[DRAFT-OWN OWN RET-OWN])
    end

    it "selects everyone else's, keeping NULL stamps (no bare where.not)" do
      expect(references(described_class.not_submitted_by_user(me)))
        .to eq(%w[LEGACY RET-LEGACY RET-THEIRS THEIRS])
    end

    it "matches nothing for .submitted_by_user(nil) and everything for .not_submitted_by_user(nil)" do
      expect(described_class.submitted_by_user(nil)).to be_empty
      expect(described_class.not_submitted_by_user(nil).count).to eq(7)
    end
  end

  describe ".awaiting_review_by" do
    before { seed! }

    it "queues in_review records not submitted by the user, NULL stamps included" do
      expect(references(described_class.awaiting_review_by(me, allow_self: false))).to eq(%w[LEGACY THEIRS])
    end

    it "includes the user's own submissions when self review is allowed" do
      expect(references(described_class.awaiting_review_by(me, allow_self: true)))
        .to eq(%w[LEGACY OWN THEIRS])
    end

    it "defaults to the allow_self_review config seam" do
      expect(references(described_class.awaiting_review_by(me))).to eq(%w[LEGACY THEIRS])

      Decidim::ContractsSk.allow_self_review = true

      expect(references(described_class.awaiting_review_by(me))).to eq(%w[LEGACY OWN THEIRS])
    end

    it "composes on a tenant scope" do
      foreign = Decidim::Organization.create!
      create_contract!("FOREIGN", state: "in_review", organization: foreign, decidim_submitted_by_id: other.id)

      scope = described_class.where(organization: organization)

      expect(references(scope.awaiting_review_by(me, allow_self: false))).to eq(%w[LEGACY THEIRS])
    end

    # The twin-consistency contract, in both modes of the seam.
    [false, true].each do |allow_self|
      it "agrees with the per-record four-eyes predicate (allow_self_review: #{allow_self})" do
        Decidim::ContractsSk.allow_self_review = allow_self
        queue = described_class.awaiting_review_by(me, allow_self: allow_self)

        in_review = described_class.where(state: "in_review").to_a
        expect(in_review).not_to be_empty
        queued, excluded = in_review.partition { |contract| queue.exists?(contract.id) }

        expect(queued.map { |c| Decidim::ContractsSk.self_review_blocked?(c, me, :approve) }).to all(be(false))
        expect(excluded.map { |c| Decidim::ContractsSk.self_review_blocked?(c, me, :approve) }).to all(be(true))
        expect(excluded.map(&:reference)).to eq(allow_self ? [] : %w[OWN])
      end
    end
  end

  describe ".returned_to" do
    before { seed! }

    it "selects the returned records the user submitted, nothing else" do
      expect(references(described_class.returned_to(me))).to eq(%w[RET-OWN])
    end

    it "selects nothing for a nil user" do
      expect(described_class.returned_to(nil)).to be_empty
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
