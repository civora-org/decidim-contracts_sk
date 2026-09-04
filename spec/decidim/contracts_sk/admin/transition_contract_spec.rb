# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for TransitionContract (civora-org/civora-platform#59),
# run against the real migrations on an in-memory SQLite adapter (see
# spec/support/contracts_sk_db_helpers.rb; excluded from the default offline
# run).
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
# The two failure-injection examples stub the collaborators at their exact
# boundaries (the record's model transition; the audit table's create!) —
# never the command under test.
#
# Synthetic data only (ZP-2026-00x references), no real PII.
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::TransitionContract, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

  # Role control per group via the config-time seam; nested groups override
  # by redefining resolver_roles.
  let(:resolver_roles) { %i[editor] }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  describe "ok path" do
    it "broadcasts :ok with the record and persists the new state" do
      events = described_class.call(contract, event: :submit, user: author)

      expect(events).to have_key(:ok)
      expect(events[:ok]).to eq(contract)

      contract.reload
      expect(contract.state).to eq("in_review")
    end

    it "writes exactly one audit row with the pinned payload shape (D4)" do
      expect { described_class.call(contract, event: :submit, user: author) }
        .to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      audit = Decidim::ContractsSk::AuditEvent.order(:id).last
      expect(audit.action).to eq("contract.submit")
      expect(audit.target_type).to eq("Decidim::ContractsSk::Contract")
      expect(audit.target_id).to eq(contract.id)
      expect(audit.organization).to eq(organization)
      expect(audit.actor).to eq(author)
      expect(audit.created_at).to be_present
      expect(audit.updated_at).to be_present
    end
  end

  describe "publish stamp (civora-org/civora-platform#75)" do
    let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes(state: "approved")) }

    it "stamps published_at on publish, persisted with the state change" do
      before = Time.current

      events = described_class.call(contract, event: :publish, user: author)

      expect(events).to have_key(:ok)

      contract.reload
      expect(contract.state).to eq("published")
      expect(contract.published_at).to be_present
      expect(contract.published_at).to be >= before
    end

    it "stamps published_at even when the event arrives as a String" do
      # Symbol-fragility guard (#75 review round): the edge lookup, the
      # stamp check and the audit action all normalize the event, so a
      # future String caller gets the same transition AND the same stamp —
      # not a state change with the stamp silently skipped.
      events = described_class.call(contract, event: "publish", user: author)

      expect(events).to have_key(:ok)

      contract.reload
      expect(contract.state).to eq("published")
      expect(contract.published_at).to be_present

      audit = Decidim::ContractsSk::AuditEvent.order(:id).last
      expect(audit.action).to eq("contract.publish")
    end

    it "leaves published_at untouched on non-publish events" do
      draft = Decidim::ContractsSk::Contract.create!(contract_attributes)

      events = described_class.call(draft, event: :submit, user: author)

      expect(events).to have_key(:ok)

      draft.reload
      expect(draft.state).to eq("in_review")
      expect(draft.published_at).to be_nil
    end

    it "rolls the stamp back with the state when the audit write fails" do
      # The stamp is assigned inside the lock before the state write, so the
      # same transaction covers it: an audit failure must leave neither a
      # new state nor a publication stamp behind.
      allow(Decidim::ContractsSk::AuditEvent).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid)

      events = described_class.call(contract, event: :publish, user: author)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)

      contract.reload
      expect(contract.state).to eq("approved")
      expect(contract.published_at).to be_nil
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end
  end

  describe "invalid paths (no mutation ever)" do
    describe "role mismatch" do
      let(:resolver_roles) { %i[reviewer] }

      it "broadcasts :invalid without persisting (reviewer cannot submit)" do
        events = described_class.call(contract, event: :submit, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)

        contract.reload
        expect(contract.state).to eq("draft")
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end

    it "broadcasts :invalid without persisting on a non-edge event (approve on draft)" do
      events = described_class.call(contract, event: :approve, user: author)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)

      contract.reload
      expect(contract.state).to eq("draft")
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end

    it "broadcasts :invalid without persisting when the model rejects the edge inside the lock" do
      # Concurrency-loss injection: the edge was valid when the permission
      # layer admitted the request, but the row lock re-validation fails.
      # The stub raises before anything is written, so no rollback is even
      # needed — the pinned fact is the :invalid broadcast and zero writes.
      allow(contract).to receive(:transition_state!)
        .and_raise(Decidim::ContractsSk::ContractLifecycle::InvalidTransitionError)

      events = described_class.call(contract, event: :submit, user: author)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)

      contract.reload
      expect(contract.state).to eq("draft")
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end

    it "rolls the state change back when the audit write fails (atomicity)" do
      # The state UPDATE happens inside the same transaction as the audit
      # INSERT; injecting a failure at the audit boundary must roll the
      # state change back — no state without its audit row, ever.
      allow(Decidim::ContractsSk::AuditEvent).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid)

      events = described_class.call(contract, event: :submit, user: author)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)

      contract.reload
      expect(contract.state).to eq("draft")
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
