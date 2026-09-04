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
