# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for ConfirmRedaction (ADR-007,
# civora-org/civora-platform#91), run against the real migrations on an
# in-memory SQLite adapter (see spec/support/contracts_sk_db_helpers.rb;
# excluded from the default offline run).
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
# The failure-injection example stubs the collaborator at its exact
# boundary (the audit table's create!) — never the command under test.
#
# Synthetic data only (ZP-2026-00x references), no real PII.
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::ConfirmRedaction, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

  it "stamps redaction_confirmed_at and broadcasts :ok with the record" do
    before = Time.current

    events = described_class.call(contract, user: author)

    expect(events).to have_key(:ok)
    expect(events[:ok]).to eq(contract)

    contract.reload
    expect(contract.redaction_confirmed_at).to be_present
    expect(contract.redaction_confirmed_at).to be >= before
  end

  it "stamps an approved record too — the confirmable window reaches the publish edge (#91 H-1)" do
    # The review round widened the CONFIRMATION window to include :approved
    # (a reviewer sign-off can arrive unstamped); editability itself is NOT
    # widened — the approved record still refuses content updates.
    approved = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "approved"))
    expect(approved).not_to be_editable

    expect { described_class.call(approved, user: author) }
      .to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

    approved.reload
    expect(approved.redaction_confirmed_at).to be_present
  end

  it "writes exactly one audit row with the pinned payload shape" do
    expect { described_class.call(contract, user: author) }
      .to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

    audit = Decidim::ContractsSk::AuditEvent.order(:id).last
    expect(audit.action).to eq("contract.redaction_confirmed")
    expect(audit.target_type).to eq("Decidim::ContractsSk::Contract")
    expect(audit.target_id).to eq(contract.id)
    expect(audit.organization).to eq(organization)
    expect(audit.actor).to eq(author)
    expect(audit.created_at).to be_present
  end

  it "rolls the stamp back when the audit write fails (atomicity)" do
    # The stamp UPDATE and the audit INSERT share the command's with_lock
    # transaction; injecting a failure at the audit boundary must leave an
    # unstamped record behind — no confirmation without its audit row, ever.
    allow(Decidim::ContractsSk::AuditEvent).to receive(:create!)
      .and_raise(ActiveRecord::RecordInvalid)

    events = described_class.call(contract, user: author)

    expect(events).to have_key(:invalid)
    expect(events).not_to have_key(:ok)

    contract.reload
    expect(contract.redaction_confirmed_at).to be_nil
    expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
  end

  describe "fail-closed guards (no mutation ever)" do
    it "refuses a record that has left the confirmable states" do
      # in_review sits between the editable states and approved: a record
      # under review can neither be edited nor gain the stamp.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

      expect do
        events = described_class.call(contract, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      contract.reload
      expect(contract.redaction_confirmed_at).to be_nil
    end

    it "refuses an already-stamped record (idempotency decision, #91 Gate-1)" do
      stamped = Decidim::ContractsSk::Contract.create!(contract_attributes)
      described_class.call(stamped, user: author)
      first_stamp = stamped.reload.redaction_confirmed_at

      expect do
        events = described_class.call(stamped, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      stamped.reload
      expect(stamped.redaction_confirmed_at).to eq(first_stamp)
    end
  end

  describe "stale-object race (deterministic — no threads)" do
    it "refuses a copy loaded before the record left the confirmable states, writing no stamp and no audit row" do
      # The stale copy models a request that loaded the record while it was
      # still confirmable; the row was then moved directly, bypassing the
      # command. The in-lock re-check (with_lock's reload) must see the
      # in-database state and refuse — the pre-lock permission decision
      # alone must never admit the write.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      stale = Decidim::ContractsSk::Contract.find(contract.id)

      contract.update!(state: "in_review")

      expect do
        events = described_class.call(stale, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      contract.reload
      expect(contract.state).to eq("in_review")
      expect(contract.redaction_confirmed_at).to be_nil
    end

    it "refuses a copy loaded before another request stamped the record" do
      # The second race shape: the row stayed editable, but the stamp
      # appeared between the request's load and its write. The in-lock
      # idempotency check reads the reloaded stamp and refuses — no second
      # stamp, no moved confirmation date, no second audit row.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      stale = Decidim::ContractsSk::Contract.find(contract.id)

      other = described_class.call(Decidim::ContractsSk::Contract.find(contract.id), user: author)
      expect(other).to have_key(:ok)
      first_stamp = contract.reload.redaction_confirmed_at

      expect do
        events = described_class.call(stale, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      contract.reload
      expect(contract.redaction_confirmed_at).to eq(first_stamp)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
