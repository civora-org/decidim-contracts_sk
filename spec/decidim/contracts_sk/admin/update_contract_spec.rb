# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for UpdateContract (civora-org/civora-platform#58), run
# against the real migrations on an in-memory SQLite adapter (see
# spec/support/contracts_sk_db_helpers.rb; excluded from the default offline
# run).
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
RSpec.describe Decidim::ContractsSk::Admin::UpdateContract, :db do
  before { migrate_engine_schema! }

  let(:form) do
    Decidim::ContractsSk::Admin::ContractForm.new(title: "Road reconstruction II", reference: "ZP-2026-002")
  end

  it "updates the editorial identity fields of a draft contract" do
    contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

    events = described_class.call(form, contract)

    expect(events).to have_key(:ok)
    expect(events[:ok]).to eq(contract)

    contract.reload
    expect(contract.title).to eq("Road reconstruction II")
    expect(contract.reference).to eq("ZP-2026-002")
    expect(contract.state).to eq("draft")
  end

  it "updates the content fields of a draft contract (civora-org/civora-platform#75)" do
    contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
    content_form = Decidim::ContractsSk::Admin::ContractForm.new(
      title: "Road reconstruction II",
      reference: "ZP-2026-002",
      subject_matter: "Revised scope: signage and barrier-free access",
      amount: "98000.40",
      currency: "EUR",
      signed_on: "2026-09-01",
      effective_from: "2026-08-15",
      crz_url: "https://crz.gov.sk/record/123"
    )

    events = described_class.call(content_form, contract)

    expect(events).to have_key(:ok)

    contract.reload
    expect(contract.subject_matter).to eq("Revised scope: signage and barrier-free access")
    expect(contract.amount).to eq(BigDecimal("98000.40"))
    expect(contract.currency).to eq("EUR")
    expect(contract.signed_on).to eq(Date.new(2026, 9, 1))
    expect(contract.effective_from).to eq(Date.new(2026, 8, 15))
    expect(contract.crz_url).to eq("https://crz.gov.sk/record/123")
    expect(contract.published_at).to be_nil
  end

  it "refuses a record that has left the editable states, writing nothing (fail-closed re-check)" do
    contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

    events = described_class.call(form, contract)

    expect(events).to have_key(:invalid)
    expect(events).not_to have_key(:ok)

    contract.reload
    expect(contract.title).to eq("Road reconstruction")
    expect(contract.reference).to eq("ZP-2026-001")
    expect(contract.state).to eq("in_review")
  end

  it "broadcasts :invalid without persisting when the model rejects the record (blank title)" do
    contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
    blank_form = Decidim::ContractsSk::Admin::ContractForm.new(title: "", reference: "ZP-2026-002")

    events = described_class.call(blank_form, contract)

    expect(events).to have_key(:invalid)
    contract.reload
    expect(contract.title).to eq("Road reconstruction")
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
