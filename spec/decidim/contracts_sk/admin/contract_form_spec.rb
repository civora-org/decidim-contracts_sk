# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the editor-facing ContractForm
# (civora-org/civora-platform#75, review round).
#
# The form needs no database connection (no uniqueness-backed validations),
# so the whole file runs in the default offline suite. The examples pin the
# boundary behaviour the :decimal attribute cast makes subtle: raw STRING
# params are inspected by the form's strict format guard BEFORE the cast can
# silently zero them (ActiveModel's :decimal type delegates to String#to_d,
# which returns 0 for garbage — "abc".to_d == 0, no exception), and the
# range cap mirrors the decimal(12,2) column so oversized values die as
# validation errors, not as ActiveRecord::RangeError (500) on PostgreSQL
# hosts.
# ---------------------------------------------------------------------------

require "spec_helper"

# Each example asserts the decision AND its observable effect (validity plus
# the typed value or the error key) by design.
# rubocop:disable RSpec/MultipleExpectations

RSpec.describe Decidim::ContractsSk::Admin::ContractForm do
  def form_with_amount(amount)
    described_class.new(title: "Road reconstruction", reference: "ZP-2026-001", amount: amount)
  end

  it "accepts dotted decimal strings" do
    form = form_with_amount("12.50")

    expect(form).to be_valid
    expect(form.amount).to eq(BigDecimal("12.50"))
  end

  it "accepts proper numerics without the string guard (spec/API compatibility)" do
    form = form_with_amount(12.5)

    expect(form).to be_valid
    expect(form.amount).to eq(BigDecimal("12.5"))
  end

  it "accepts the decimal(12,2) ceiling itself" do
    expect(form_with_amount(BigDecimal("9999999999.99"))).to be_valid
  end

  it "accepts a nil amount (the value may be unknown while drafting)" do
    expect(form_with_amount(nil)).to be_valid
  end

  it "rejects non-numeric strings instead of letting the cast zero them" do
    form = form_with_amount("abc")

    expect(form).not_to be_valid
    expect(form.errors[:amount]).to be_present
  end

  it "rejects comma decimals (the Slovak '12,50' habit, caught deliberately)" do
    form = form_with_amount("12,50")

    expect(form).not_to be_valid
    expect(form.errors[:amount]).to be_present
  end

  it "rejects scientific notation (the format guard stays strict)" do
    form = form_with_amount("1e5")

    expect(form).not_to be_valid
    expect(form.errors[:amount]).to be_present
  end

  it "rejects negative amounts" do
    form = form_with_amount("-5")

    expect(form).not_to be_valid
    expect(form.errors[:amount]).to be_present
  end

  it "rejects amounts beyond the decimal(12,2) column's ceiling" do
    form = form_with_amount(10_000_000_000)

    expect(form).not_to be_valid
    expect(form.errors[:amount]).to be_present
  end

  it "rejects over-ceiling strings too (raw input, same cap)" do
    form = form_with_amount("10000000000")

    expect(form).not_to be_valid
    expect(form.errors[:amount]).to be_present
  end
end

# rubocop:enable RSpec/MultipleExpectations
