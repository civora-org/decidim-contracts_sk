# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for CreateLink (M01-87, civora-org/civora-platform#87),
# run against the real migrations on an in-memory SQLite adapter (see
# spec/support/contracts_sk_db_helpers.rb; excluded from the default offline
# run).
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
#
# The link whitelist seam is swapped for the duration of the group and
# restored afterwards (config-time only).
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::CreateLink, :db do
  before do
    migrate_engine_schema!
    Decidim::ContractsSk.supported_link_target_types = ["Decidim::Accountability::Result"]
  end

  after do
    Decidim::ContractsSk.supported_link_target_types = []
  end

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:form) do
    Decidim::ContractsSk::Admin::LinkForm.new(target_type: "Decidim::Accountability::Result", target_id: "12")
  end

  it "creates a link through the parent contract's association, deriving the tenancy" do
    events = described_class.call(form, contract)

    expect(events).to have_key(:ok)

    link = events[:ok]
    expect(link).to be_persisted
    expect(link.reload.contract).to eq(contract)
    expect(link.target_type).to eq("Decidim::Accountability::Result")
    expect(link.target_id).to eq(12)
  end

  it "writes no audit row on success (the audit trail tracks lifecycle transitions only)" do
    expect do
      events = described_class.call(form, contract)

      expect(events).to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::AuditEvent, :count)
  end

  it "broadcasts :invalid without persisting when the form is rejected (unsupported target type)" do
    foreign_form = Decidim::ContractsSk::Admin::LinkForm.new(target_type: "Decidim::User", target_id: "12")

    expect do
      events = described_class.call(foreign_form, contract)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::ContractLink, :count)
  end

  it "broadcasts :invalid without persisting on a duplicate (contract, target) pair" do
    described_class.call(form, contract)

    expect do
      events = described_class.call(form, contract)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::ContractLink, :count)
  end

  it "degrades a DB uniqueness-backstop collision to :invalid without persisting (RecordNotUnique rescue)" do
    # The model-level uniqueness validation catches ordinary duplicates
    # (the example above); this pins the DB backstop's failure mode: a
    # concurrent create that slips past the validation's read collides
    # with the unique composite index at INSERT time and must degrade to
    # :invalid, never a 500. Simulated by raising straight from the
    # association write (deterministic, no threads) — the row lock, the
    # in-lock editability re-check and the command's rescue path stay real.
    links = instance_double(ActiveRecord::Associations::CollectionProxy)
    allow(links).to receive(:create!)
      .and_raise(ActiveRecord::RecordNotUnique, "idx_contracts_sk_contract_links_on_contract_and_target")
    allow(contract).to receive(:links).and_return(links)

    expect do
      events = described_class.call(form, contract)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::ContractLink, :count)
  end

  it "refuses a parent contract that has left the editable states, writing nothing (fail-closed re-check)" do
    contract.update!(state: "in_review")

    expect do
      events = described_class.call(form, contract)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::ContractLink, :count)
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
      end.not_to change(Decidim::ContractsSk::ContractLink, :count)

      contract.reload
      expect(contract.state).to eq("in_review")
      expect(contract.links).to be_empty
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
