# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for DestroyLink (M01-87, civora-org/civora-platform#87),
# run against the real migrations on an in-memory SQLite adapter (see
# spec/support/contracts_sk_db_helpers.rb; excluded from the default offline
# run).
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::DestroyLink, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:link) do
    contract.links.create!(target_type: "Decidim::Accountability::Result", target_id: 12)
  end

  it "removes the link" do
    events = described_class.call(link)

    expect(events).to have_key(:ok)
    expect(Decidim::ContractsSk::ContractLink.exists?(link.id)).to be(false)
  end

  it "writes no audit row on success (the audit trail tracks lifecycle transitions only)" do
    expect do
      events = described_class.call(link)

      expect(events).to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::AuditEvent, :count)
  end

  it "refuses a parent contract that has left the editable states, removing nothing (fail-closed re-check)" do
    # Materialize the row before the assertion: the command must be the
    # only thing the change matcher observes.
    link = contract.links.create!(target_type: "Decidim::Accountability::Result", target_id: 12)
    contract.update!(state: "in_review")

    expect do
      events = described_class.call(link)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::ContractLink, :count)
  end

  describe "stale-object race (deterministic — no threads)" do
    it "refuses when the parent copy was loaded before it left the editable states, removing nothing" do
      # The stale copy models a request that loaded the parent contract
      # while it was still editable; the in-lock re-check must read the
      # reloaded, in-database state — not the request-start attributes.
      stale = Decidim::ContractsSk::Contract.find(contract.id)
      link = stale.links.create!(target_type: "Decidim::Accountability::Result", target_id: 12)

      contract.update!(state: "in_review")

      expect do
        events = described_class.call(link)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::ContractLink, :count)

      contract.reload
      expect(contract.state).to eq("in_review")
      expect(contract.links).not_to be_empty
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
