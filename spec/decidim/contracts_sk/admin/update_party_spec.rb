# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for UpdateParty (civora-org/civora-platform#76), run
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
RSpec.describe Decidim::ContractsSk::Admin::UpdateParty, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:party) { contract.parties.create!(role: "object", name: "Obec Zelen") }
  let(:form) do
    Decidim::ContractsSk::Admin::PartyForm.new(role: "contractor", name: "Zeleň a.s.",
                                               ico: "12345678", address: "Hlavná 1")
  end

  it "updates the party's content fields" do
    events = described_class.call(form, party)

    expect(events).to have_key(:ok)
    expect(events[:ok]).to eq(party)

    party.reload
    expect(party.role).to eq("contractor")
    expect(party.name).to eq("Zeleň a.s.")
    expect(party.ico).to eq("12345678")
    expect(party.address).to eq("Hlavná 1")
  end

  it "writes only the form's fields — the parent contract is never re-assignable" do
    other_contract = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-777"))

    events = described_class.call(form, party)

    expect(events).to have_key(:ok)

    party.reload
    expect(party.contract).to eq(contract)
    expect(other_contract.reload.parties).to be_empty
  end

  it "broadcasts :invalid without writing when the form is rejected (blank name)" do
    blank_form = Decidim::ContractsSk::Admin::PartyForm.new(role: "object", name: "")

    events = described_class.call(blank_form, party)

    expect(events).to have_key(:invalid)
    party.reload
    expect(party.name).to eq("Obec Zelen")
  end

  it "refuses a parent contract that has left the editable states, writing nothing (fail-closed re-check)" do
    contract.update!(state: "in_review")

    events = described_class.call(form, party)

    expect(events).to have_key(:invalid)
    party.reload
    expect(party.role).to eq("object")
    expect(party.name).to eq("Obec Zelen")
  end

  describe "stale-object race (deterministic — no threads)" do
    it "refuses a party copy loaded before its contract left the editable states, writing nothing" do
      # The stale party models a controller that loaded the child through
      # the request-start contract copy (association + inverse_of), so the
      # child's `contract` is the stale in-memory row, still editable. The
      # in-lock re-check must read the contract's reloaded, in-database
      # state — not the request-start attributes.
      parent = Decidim::ContractsSk::Contract.find(contract.id)
      stale = parent.parties.find(party.id)

      contract.update!(state: "in_review")

      expect do
        events = described_class.call(form, stale)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      party.reload
      expect(party.role).to eq("object")
      expect(party.name).to eq("Obec Zelen")
      expect(contract.reload.state).to eq("in_review")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
