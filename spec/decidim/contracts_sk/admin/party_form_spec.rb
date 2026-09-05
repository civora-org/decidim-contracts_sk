# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the editor-facing PartyForm
# (civora-org/civora-platform#76).
#
# The form needs no database connection (no uniqueness-backed validations —
# by design: multiple parties with the same role are legal), so the whole
# file runs in the default offline suite. The examples pin that the form's
# validations mirror the Party model's exactly, so a rejection surfaces on
# the form before the command boundary.
# ---------------------------------------------------------------------------

require "spec_helper"

# Each example asserts the decision AND its observable effect (validity plus
# the offending error key) by design.
# rubocop:disable RSpec/MultipleExpectations

RSpec.describe Decidim::ContractsSk::Admin::PartyForm do
  def form_with(overrides = {})
    described_class.new({ role: "object", name: "Obec Zelen" }.merge(overrides))
  end

  it "accepts a complete object-party form" do
    form = form_with(ico: "12345678", address: "Hlavná 1")

    expect(form).to be_valid
    expect(form.role).to eq("object")
  end

  it "accepts a complete contractor form" do
    expect(form_with(role: "contractor")).to be_valid
  end

  it "allows duplicate roles: two object-role forms are both valid" do
    # Multiple parties with the same role are legal by design (#76) — there
    # is deliberately no uniqueness validation on any axis.
    first = form_with
    second = form_with

    expect(first).to be_valid
    expect(second).to be_valid
  end

  it "requires a role at all" do
    aggregate_failures do
      expect(form_with(role: nil)).not_to be_valid
      expect(form_with(role: "")).not_to be_valid
    end
  end

  it "rejects a role outside the model's frozen vocabulary" do
    form = form_with(role: "bogus")

    expect(form).not_to be_valid
    expect(form.errors[:role]).to be_present
  end

  it "requires a name" do
    form = form_with(name: "")

    expect(form).not_to be_valid
    expect(form.errors[:name]).to be_present
  end

  it "caps the name at 255 characters" do
    expect(form_with(name: "a" * 255)).to be_valid

    form = form_with(name: "a" * 256)

    expect(form).not_to be_valid
    expect(form.errors[:name]).to be_present
  end

  it "accepts an exactly-8-digit ico" do
    expect(form_with(ico: "12345678")).to be_valid
  end

  it "rejects an ico that is not exactly 8 digits" do
    form = form_with(ico: "1234567")

    expect(form).not_to be_valid
    expect(form.errors[:ico]).to be_present
  end

  it "rejects overlong and non-digit icos alike" do
    aggregate_failures do
      expect(form_with(ico: "123456789")).not_to be_valid
      expect(form_with(ico: "1234567a")).not_to be_valid
    end
  end

  it "accepts a blank ico (the identifier is optional)" do
    aggregate_failures do
      expect(form_with(ico: nil)).to be_valid
      expect(form_with(ico: "")).to be_valid
    end
  end

  it "caps the address at 255 characters, with none being legal" do
    expect(form_with(address: nil)).to be_valid
    expect(form_with(address: "a" * 255)).to be_valid

    form = form_with(address: "a" * 256)

    expect(form).not_to be_valid
    expect(form.errors[:address]).to be_present
  end
end

# rubocop:enable RSpec/MultipleExpectations
