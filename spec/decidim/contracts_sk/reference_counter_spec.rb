# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for ReferenceCounter (civora-org/civora-platform#211, step P1): the
# per-organization sequence behind internal contract numbers. Deterministic:
# the race is simulated with a stale pre-loaded object, never with threads.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::ReferenceCounter, :db do
  before { migrate_engine_schema! }

  def row_count
    described_class.where(organization: organization).count
  end

  describe ".next!" do
    it "creates the counter on first use and counts up from 1" do
      expect(row_count).to eq(0)

      expect(described_class.next!(organization, "zmluvy:2026")).to eq(1)
      expect(described_class.next!(organization, "zmluvy:2026")).to eq(2)
      expect(described_class.next!(organization, "zmluvy:2026")).to eq(3)
      expect(row_count).to eq(1)
    end

    it "keeps sequences of different scope keys independent (a new year starts at 1)" do
      expect(described_class.next!(organization, described_class.scope_key_for("zmluvy", 2026))).to eq(1)
      expect(described_class.next!(organization, described_class.scope_key_for("zmluvy", 2026))).to eq(2)
      expect(described_class.next!(organization, described_class.scope_key_for("zmluvy", 2027))).to eq(1)
      expect(described_class.next!(organization, described_class.scope_key_for("objednavky", 2026))).to eq(1)
      expect(row_count).to eq(3)
    end

    it "keeps organizations independent (tenancy)" do
      other = Decidim::Organization.create!

      expect(described_class.next!(organization, "zmluvy:2026")).to eq(1)
      expect(described_class.next!(organization, "zmluvy:2026")).to eq(2)
      expect(described_class.next!(other, "zmluvy:2026")).to eq(1)
    end

    it "reuses the row a concurrent request created between the read and the create" do
      winner = described_class.create!(organization: organization, scope_key: "zmluvy:2026", last_value: 4)
      # Simulates the lost race: the first lookup (before the create) finds
      # nothing, and the create then hits the unique index.
      allow(described_class).to receive(:find_by).and_return(nil)
      allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

      expect(described_class.next!(organization, "zmluvy:2026")).to eq(5)
      expect(winner.reload.last_value).to eq(5)
      expect(row_count).to eq(1)
    end
  end

  describe "#next!" do
    it "hands out a fresh number to a stale pre-loaded instance (increments under with_lock)" do
      stale = described_class.create!(organization: organization, scope_key: "zmluvy:2026")
      # Another request increments the same row after `stale` was loaded.
      described_class.find(stale.id).next!
      described_class.find(stale.id).next!
      expect(stale.last_value).to eq(0)

      expect(stale.next!).to eq(3)
      expect(described_class.find(stale.id).last_value).to eq(3)
    end

    it "never repeats a number across two instances of the same row" do
      first = described_class.create!(organization: organization, scope_key: "zmluvy:2026")
      second = described_class.find(first.id)

      expect([first.next!, second.next!, first.next!]).to eq([1, 2, 3])
    end

    it "locks the row while it increments" do
      counter = described_class.create!(organization: organization, scope_key: "zmluvy:2026")
      allow(counter).to receive(:with_lock).and_call_original

      counter.next!

      expect(counter).to have_received(:with_lock).once
    end
  end

  describe "validations" do
    def build_counter(overrides = {})
      described_class.new({ organization: organization, scope_key: "zmluvy:2026" }.merge(overrides))
    end

    it "is valid with an organization and a scope key, starting at 0" do
      expect(build_counter).to be_valid
      expect(build_counter.last_value).to eq(0)
    end

    it "requires an organization and a well-formed scope key" do
      expect(build_counter(organization: nil)).not_to be_valid
      expect(build_counter(scope_key: nil)).not_to be_valid
      expect(build_counter(scope_key: "Zmluvy 2026")).not_to be_valid
      expect(build_counter(scope_key: "a" * 101)).not_to be_valid
    end

    it "does not accept a negative value" do
      expect(build_counter(last_value: -1)).not_to be_valid
    end

    it "keeps (organization, scope_key) unique, in the model and in the database" do
      build_counter.save!

      duplicate = build_counter
      expect(duplicate).not_to be_valid
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(build_counter(organization: Decidim::Organization.create!)).to be_valid
    end
  end

  describe ".scope_key_for" do
    it "joins a base and a year" do
      expect(described_class.scope_key_for("zmluvy", 2026)).to eq("zmluvy:2026")
      expect(described_class.scope_key_for("zmluvy", "2027")).to eq("zmluvy:2027")
    end

    it "refuses a non-numeric year" do
      expect { described_class.scope_key_for("zmluvy", "last year") }.to raise_error(ArgumentError)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
