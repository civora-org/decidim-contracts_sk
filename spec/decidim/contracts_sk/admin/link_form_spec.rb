# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the editor-facing LinkForm
# (M01-87, civora-org/civora-platform#87).
#
# The form needs no database connection (the polymorphic target has no
# existence check at the form boundary — dangling targets are a legal
# state), so the whole file runs in the default offline suite. The examples
# pin that the target type is whitelisted against the config-time seam and
# the target id is an all-digits bigint-safe string, so a rejection
# surfaces on the form before the command boundary.
# ---------------------------------------------------------------------------

require "spec_helper"

# Each example asserts the decision AND its observable effect (validity plus
# the offending error key) by design.
# rubocop:disable RSpec/MultipleExpectations

RSpec.describe Decidim::ContractsSk::Admin::LinkForm do
  # The whitelist the examples exercise; restored afterwards (config-time
  # seam — no override may leak into later examples).
  around do |example|
    original = Decidim::ContractsSk.supported_link_target_types
    Decidim::ContractsSk.supported_link_target_types = ["Decidim::Accountability::Result"]
    example.run
    Decidim::ContractsSk.supported_link_target_types = original
  end

  def form_with(overrides = {})
    described_class.new({ target_type: "Decidim::Accountability::Result", target_id: "12" }.merge(overrides))
  end

  it "accepts a complete link form" do
    form = form_with

    expect(form).to be_valid
    expect(form.target_type).to eq("Decidim::Accountability::Result")
    expect(form.target_id).to eq("12")
  end

  it "requires a target type at all" do
    aggregate_failures do
      expect(form_with(target_type: nil)).not_to be_valid
      expect(form_with(target_type: "")).not_to be_valid
    end
  end

  it "rejects a target type outside the configured whitelist" do
    form = form_with(target_type: "Decidim::User")

    expect(form).not_to be_valid
    expect(form.errors[:target_type]).to be_present
  end

  it "reads the whitelist through the config seam at validation time (never captured)" do
    # A form built while a wider whitelist was configured re-validates
    # against the CURRENT setting — the validator holds a callable, not a
    # snapshot of the vocabulary.
    form = form_with(target_type: "Decidim::Budgets::Project")

    expect(form).not_to be_valid

    Decidim::ContractsSk.supported_link_target_types = ["Decidim::Budgets::Project"]

    expect(form).to be_valid
  end

  it "requires a target id" do
    aggregate_failures do
      expect(form_with(target_id: nil)).not_to be_valid
      expect(form_with(target_id: "")).not_to be_valid
    end
  end

  it "rejects a non-numeric target id" do
    form = form_with(target_id: "12abc")

    expect(form).not_to be_valid
    expect(form.errors[:target_id]).to be_present
  end

  it "rejects whitespace-padded or negative target ids" do
    aggregate_failures do
      expect(form_with(target_id: " 12")).not_to be_valid
      expect(form_with(target_id: "-12")).not_to be_valid
    end
  end

  it "caps the target id at 18 digits — always inside the bigint range" do
    expect(form_with(target_id: "9" * 18)).to be_valid

    form = form_with(target_id: "9" * 19)

    expect(form).not_to be_valid
    expect(form.errors[:target_id]).to be_present
  end
end

# rubocop:enable RSpec/MultipleExpectations
