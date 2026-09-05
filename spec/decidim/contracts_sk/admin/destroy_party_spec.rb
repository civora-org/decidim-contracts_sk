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

# rubocop:disable RSpec/MultipleExpectations
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
end
# rubocop:enable RSpec/MultipleExpectations
