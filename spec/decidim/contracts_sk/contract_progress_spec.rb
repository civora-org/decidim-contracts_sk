# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for ContractProgress, the five-step read model
# behind the contract page's "where am I in the process" indicator. Plain
# structs stand in for records, so no database is needed: the model reads
# only the lifecycle state, the source and the CRZ filing stamp.
# ---------------------------------------------------------------------------

require "spec_helper"

# Two related facts per example by design (a state and its flag, a table).
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Decidim::ContractsSk::ContractProgress do
  mirror_source = Decidim::ContractsSk::CrzImport::Mapper::SOURCE

  def progress(state, source: nil, filed: false)
    described_class.new(Struct.new(:state, :source, :crz_filed_at).new(state, source, filed ? Time.zone.now : nil))
  end

  def statuses(progress)
    progress.steps.to_h { |step| [step.key, step.status] }
  end

  it "has exactly the five steps a clerk thinks in, in order" do
    expect(described_class::STEPS).to eq(%i[draft review approved published filed])
  end

  {
    "draft" => %i[current upcoming upcoming upcoming upcoming],
    "returned" => %i[current upcoming upcoming upcoming upcoming],
    "in_review" => %i[done current upcoming upcoming upcoming],
    "approved" => %i[done done current upcoming upcoming],
    "published" => %i[done done done current upcoming],
    "archived" => %i[done done done done upcoming]
  }.each do |state, expected|
    it "puts a #{state} record on the right step" do
      expect(statuses(progress(state)).values).to eq(expected)
    end
  end

  it "completes every step once a published record's CRZ filing is confirmed" do
    expect(statuses(progress("published", filed: true)).values.uniq).to eq([:done])
  end

  it "stops a rejected record at the check" do
    expect(statuses(progress("rejected")).values).to eq(%i[done stopped upcoming upcoming upcoming])
    expect(progress("rejected")).to be_rejected
  end

  it "knows a returned draft is returned, without a step of its own" do
    expect(progress("returned")).to be_returned
    expect(progress("draft")).not_to be_returned
  end

  it "names the next-step sentence per state, one per lifecycle state plus the filed one" do
    keys = Decidim::ContractsSk::ContractLifecycle::STATES.map { |state| progress(state.to_s).next_key }

    expect(keys).to eq(%i[draft in_review returned approved rejected published archived])
    expect(progress("published", filed: true).next_key).to eq(:filed)
  end

  it "applies to editorial records only, never to CRZ mirrors" do
    expect(progress("published")).to be_applicable
    expect(progress("published", source: mirror_source)).not_to be_applicable
  end
end
# rubocop:enable RSpec/MultipleExpectations
