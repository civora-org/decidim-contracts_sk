# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the editor-facing DocumentForm
# (civora-org/civora-platform#73).
#
# The form needs no database connection (its validations mirror the Document
# model's own, except the kind vocabulary, which is deliberately narrower —
# crz_export is reserved for the generated handoff artifact; the file
# presence check runs on the in-memory upload object),
# so the whole file runs in the default offline suite. The file's CONTENT is
# deliberately not validated — allowed kinds and size caps are deferred to
# civora-org/civora-platform#64.
#
# The uploaded files are the repo's synthetic fixtures (no real content,
# no PII).
# ---------------------------------------------------------------------------

require "spec_helper"

# Each example asserts the decision AND its observable effect (validity plus
# the offending error key) by design.
# rubocop:disable RSpec/MultipleExpectations

RSpec.describe Decidim::ContractsSk::Admin::DocumentForm do
  # The fixture lives at the engine root (this file sits at
  # spec/decidim/contracts_sk/admin/, four levels up is the engine root).
  def sample_fixture(name)
    File.expand_path("../../../fixtures/files/#{name}", __dir__)
  end

  def form_with(overrides = {})
    described_class.new(
      { title: "Signed contract scan", kind: "contract", file: sample_fixture("sample.pdf") }.merge(overrides)
    )
  end

  it "accepts a complete form" do
    form = form_with

    expect(form).to be_valid
    expect(form.title).to eq("Signed contract scan")
    expect(form.kind).to eq("contract")
  end

  it "defaults the kind to the model's column default" do
    form = described_class.new(title: "Scan", file: sample_fixture("sample.pdf"))

    expect(form.kind).to eq("contract")
    expect(form).to be_valid
  end

  it "accepts every kind of the form's editor vocabulary" do
    described_class::EDITOR_KINDS.each do |kind|
      expect(form_with(kind: kind)).to be_valid, "kind #{kind} must be legal"
    end
  end

  it "narrows the model's vocabulary exactly by the generated artifact's kind" do
    aggregate_failures do
      expect(described_class::EDITOR_KINDS)
        .to eq(Decidim::ContractsSk::Document::KINDS - %w[crz_export])
      # The model keeps the full vocabulary — generated artifacts land in
      # crz_export legitimately.
      expect(Decidim::ContractsSk::Document::KINDS).to include("crz_export")
    end
  end

  it "rejects the generated artifact's kind (upload cannot collide with the handoff)" do
    form = form_with(kind: "crz_export")

    expect(form).not_to be_valid
    expect(form.errors[:kind]).to be_present
  end

  it "requires a title" do
    aggregate_failures do
      expect(form_with(title: nil)).not_to be_valid
      expect(form_with(title: "")).not_to be_valid
    end
  end

  it "caps the title at 255 characters" do
    expect(form_with(title: "a" * 255)).to be_valid

    form = form_with(title: "a" * 256)

    expect(form).not_to be_valid
    expect(form.errors[:title]).to be_present
  end

  it "rejects a kind outside the model's frozen vocabulary" do
    form = form_with(kind: "bogus")

    expect(form).not_to be_valid
    expect(form.errors[:kind]).to be_present
  end

  it "requires a file" do
    aggregate_failures do
      expect(form_with(file: nil)).not_to be_valid
      expect(form_with(file: "")).not_to be_valid
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations
