# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for CreateParty (civora-org/civora-platform#76), run
# against the real migrations on an in-memory SQLite adapter (see
# spec/support/contracts_sk_db_helpers.rb; excluded from the default offline
# run).
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
#
# Synthetic data only (municipality/supplier names are fictional), no real PII.
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::CreateParty, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:form) do
    Decidim::ContractsSk::Admin::PartyForm.new(role: "object", name: "Obec Zelen", ico: "12345678")
  end

  it "creates a party through the parent contract's association, deriving the tenancy" do
    events = described_class.call(form, contract)

    expect(events).to have_key(:ok)

    party = events[:ok]
    expect(party).to be_persisted
    expect(party.reload.contract).to eq(contract)
    expect(party.role).to eq("object")
    expect(party.name).to eq("Obec Zelen")
    expect(party.ico).to eq("12345678")
  end

  it "persists multiple parties with the same role (no uniqueness by design)" do
    described_class.call(form, contract)
    events = described_class.call(form, contract)

    expect(events).to have_key(:ok)
    expect(contract.parties.where(role: "object").count).to eq(2)
  end

  it "writes no audit row on success (the audit trail tracks lifecycle transitions only)" do
    expect do
      events = described_class.call(form, contract)

      expect(events).to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::AuditEvent, :count)
  end

  it "broadcasts :invalid without persisting when the form is rejected (blank name)" do
    blank_form = Decidim::ContractsSk::Admin::PartyForm.new(role: "object", name: "")

    expect do
      events = described_class.call(blank_form, contract)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::Party, :count)
  end

  it "refuses a parent contract that has left the editable states, writing nothing (fail-closed re-check)" do
    contract.update!(state: "in_review")

    expect do
      events = described_class.call(form, contract)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::Party, :count)
  end

  describe "stale-object race (deterministic — no threads)" do
    it "refuses a copy of the contract loaded before it left the editable states, writing nothing" do
      # The stale copy models a request that loaded the parent contract
      # while it was still editable; the in-lock re-check must read the
      # reloaded, in-database state — not the request-start attributes.
      stale = Decidim::ContractsSk::Contract.find(contract.id)

      contract.update!(state: "in_review")

      expect do
        events = described_class.call(form, stale)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::Party, :count)

      contract.reload
      expect(contract.state).to eq("in_review")
      expect(contract.parties).to be_empty
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
