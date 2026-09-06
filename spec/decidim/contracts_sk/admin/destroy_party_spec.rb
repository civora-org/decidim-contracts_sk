# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for DestroyParty (civora-org/civora-platform#76), run
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
RSpec.describe Decidim::ContractsSk::Admin::DestroyParty, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:party) { contract.parties.create!(role: "contractor", name: "Zeleň a.s.") }

  it "removes the party row" do
    events = described_class.call(party)

    expect(events).to have_key(:ok)
    expect(Decidim::ContractsSk::Party.exists?(party.id)).to be(false)
  end

  it "refuses a parent contract that has left the editable states, removing nothing (fail-closed re-check)" do
    contract.update!(state: "in_review")

    events = described_class.call(party)

    expect(events).to have_key(:invalid)
    expect(events).not_to have_key(:ok)
    expect(Decidim::ContractsSk::Party.exists?(party.id)).to be(true)
  end

  describe "stale-object race (deterministic — no threads)" do
    it "refuses a party copy loaded before its contract left the editable states, removing nothing" do
      # The stale party models a controller that loaded the child through
      # the request-start contract copy (association + inverse_of), so the
      # child's `contract` is the stale in-memory row, still editable. The
      # in-lock re-check must read the contract's reloaded, in-database
      # state — not the request-start attributes.
      parent = Decidim::ContractsSk::Contract.find(contract.id)
      stale = parent.parties.find(party.id)

      contract.update!(state: "in_review")

      expect do
        events = described_class.call(stale)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::Party, :count)

      expect(Decidim::ContractsSk::Party.exists?(party.id)).to be(true)
      expect(contract.reload.state).to eq("in_review")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
