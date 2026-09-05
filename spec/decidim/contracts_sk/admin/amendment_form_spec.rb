# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the editor-facing AmendmentForm
# (M02-05-B, civora-org/civora-platform#65).
#
# The form needs no database connection (a draft amendment carries only its
# summary — the version is sequenced by the command and the content snapshot
# is taken at publish time), so the whole file runs in the default offline
# suite. The examples pin that the form's validation mirrors the Amendment
# model's summary validation exactly, so a rejection surfaces on the form
# before the command boundary.
# ---------------------------------------------------------------------------

require "spec_helper"

# Each example asserts the decision AND its observable effect (validity plus
# the offending error key) by design.
# rubocop:disable RSpec/MultipleExpectations

RSpec.describe Decidim::ContractsSk::Admin::AmendmentForm do
  def form_with(overrides = {})
    described_class.new({ summary: "Extended delivery deadline" }.merge(overrides))
  end

  it "accepts a complete amendment form" do
    form = form_with

    expect(form).to be_valid
    expect(form.summary).to eq("Extended delivery deadline")
  end

  it "rejects a blank summary" do
    form = form_with(summary: "")

    expect(form).not_to be_valid
    expect(form.errors[:summary]).to be_present
  end

  it "rejects a missing summary" do
    expect(form_with(summary: nil)).not_to be_valid
  end

  it "caps the summary at 255 characters" do
    expect(form_with(summary: "a" * 255)).to be_valid

    form = form_with(summary: "a" * 256)

    expect(form).not_to be_valid
    expect(form.errors[:summary]).to be_present
  end
end

# rubocop:enable RSpec/MultipleExpectations
