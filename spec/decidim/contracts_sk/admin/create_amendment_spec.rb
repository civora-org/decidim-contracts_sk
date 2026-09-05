# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for CreateAmendment (M02-05-B,
# civora-org/civora-platform#65), run against the real migrations on an
# in-memory SQLite adapter (see spec/support/contracts_sk_db_helpers.rb;
# excluded from the default offline run).
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
#
# Synthetic data only (ZP-2026-00x references), no real PII.
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::CreateAmendment, :db do
  before { migrate_engine_schema! }

  # Amendments are seeded onto published contracts only (ADR-006) — the
  # happy-path group's contract.
  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes(state: "published")) }
  let(:form) { Decidim::ContractsSk::Admin::AmendmentForm.new(summary: "Extended delivery deadline") }

  it "creates a draft amendment through the parent contract's association, deriving the tenancy" do
    events = described_class.call(form, contract, user: author)

    expect(events).to have_key(:ok)

    amendment = events[:ok]
    expect(amendment).to be_persisted
    expect(amendment.reload.contract).to eq(contract)
    expect(amendment).to be_draft
    expect(amendment.summary).to eq("Extended delivery deadline")
    expect(amendment.organization).to eq(organization)
    expect(amendment.author).to eq(author)

    # A draft carries no publication facts yet.
    expect(amendment.published_at).to be_nil
    expect(amendment.content_snapshot).to be_nil
  end

  it "sequences the version per contract: first 1, then 2" do
    first = described_class.call(form, contract, user: author)[:ok]
    second = described_class.call(form, contract, user: author)[:ok]

    expect(first.reload.version).to eq(1)
    expect(second.reload.version).to eq(2)
  end

  it "broadcasts :invalid without persisting when the form is rejected (blank summary)" do
    blank_form = Decidim::ContractsSk::Admin::AmendmentForm.new(summary: "")

    expect do
      events = described_class.call(blank_form, contract, user: author)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::Amendment, :count)
  end

  it "refuses a parent contract that is not published, writing nothing (fail-closed re-check)" do
    draft = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-002"))
    in_review = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-003",
                                                                           state: "in_review"))

    aggregate_failures do
      [draft, in_review].each do |unpublished|
        events = described_class.call(form, unpublished, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end
    end

    expect(Decidim::ContractsSk::Amendment.count).to eq(0)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
