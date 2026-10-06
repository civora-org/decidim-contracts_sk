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

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
RSpec.describe Decidim::ContractsSk::Admin::TransitionContract, :db do
  before do
    migrate_engine_schema!
    # The command only HANDS OFF to the notification layer (#94, M03-05-C);
    # the notification group below pins the hand-off, the publish spec
    # pins the layer itself.
    allow(Decidim::ContractsSk::TransitionNotification).to receive(:publish)
  end

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
    # The ADR-007 gate (#91) makes the redaction stamp a precondition of
    # the publish edge, so this group's contracts carry it — the gate
    # itself is pinned in the dedicated group below.
    let(:contract) do
      Decidim::ContractsSk::Contract
        .create!(contract_attributes(state: "approved", redaction_confirmed_at: Time.current))
    end

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

  describe "redaction confirmation gate (ADR-007, civora-org/civora-platform#91)" do
    let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes(state: "approved")) }

    it "refuses publish without the stamp, writing no state, no publication stamp and no audit row" do
      expect do
        events = described_class.call(contract, event: :publish, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("approved")
        expect(contract.published_at).to be_nil
        expect(contract.redaction_confirmed_at).to be_nil
      end
    end

    it "rides a :redaction_gate payload on the refusal, absent from every other :invalid" do
      # The UI's dedicated-flash channel (#91 review round): the EventRecorder
      # stores broadcast args, so the gate refusal carries :redaction_gate
      # while ordinary :invalid broadcasts (bad role, invalid edge) carry
      # none — no new outcome symbol, no reason leaked beyond the
      # already-public gate.
      gate_refusal = described_class.call(contract, event: :publish, user: author)
      expect(gate_refusal[:invalid]).to eq(:redaction_gate)

      unstamped_draft = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-002"))
      plain_refusal = described_class.call(unstamped_draft, event: :archive, user: author)
      expect(plain_refusal).to have_key(:invalid)
      # The recorder keeps argless broadcasts as [] — the point is that no
      # :redaction_gate payload rides a plain refusal.
      expect(plain_refusal[:invalid]).not_to eq(:redaction_gate)
    end

    it "publishes the same record once the stamp is present" do
      contract.update!(redaction_confirmed_at: Time.current)

      events = described_class.call(contract, event: :publish, user: author)

      expect(events).to have_key(:ok)

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("published")
        expect(contract.published_at).to be_present
      end
    end

    it "lets non-publish events through unstamped records (the gate is publish-only)" do
      draft = Decidim::ContractsSk::Contract.create!(contract_attributes)

      events = described_class.call(draft, event: :submit, user: author)

      expect(events).to have_key(:ok)

      draft.reload
      expect(draft.state).to eq("in_review")
    end

    it "refuses a copy loaded before the stamp was cleared, writing nothing (in-lock re-check, no threads)" do
      # The stale copy models a request that loaded the record WITH the
      # stamp; the stamp was then cleared by a direct write, bypassing the
      # command layer. The in-lock reload must re-read the in-database
      # stamp — the request-start copy's attribute must never satisfy the
      # gate.
      contract = Decidim::ContractsSk::Contract
                 .create!(contract_attributes(state: "approved", redaction_confirmed_at: Time.current))
      stale = Decidim::ContractsSk::Contract.find(contract.id)
      expect(stale.redaction_confirmed_at).to be_present

      contract.update!(redaction_confirmed_at: nil)

      expect do
        events = described_class.call(stale, event: :publish, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("approved")
        expect(contract.published_at).to be_nil
      end
    end
  end

  describe "reviewer decision reason (civora-org/civora-platform#90)" do
    let(:resolver_roles) { %i[reviewer] }
    let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review")) }

    it "requires a reason on return, writing no state, no decision stamps and no audit row without one" do
      expect do
        events = described_class.call(contract, event: :return, user: author)

        expect(events).to have_key(:invalid)
        expect(events[:invalid]).to eq(described_class::REASON_REQUIRED)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("in_review")
        expect(contract.review_reason).to be_nil
        expect(contract.reviewed_at).to be_nil
      end
    end

    it "treats a whitespace-only reason as missing" do
      events = described_class.call(contract, event: :return, user: author, reason: "   \n\t ")

      expect(events).to have_key(:invalid)
      expect(events[:invalid]).to eq(described_class::REASON_REQUIRED)
    end

    it "refuses an over-cap reason with the :reason_rejected payload, writing nothing" do
      expect do
        events = described_class.call(contract, event: :return, user: author, reason: "x" * 1001)

        expect(events).to have_key(:invalid)
        expect(events[:invalid]).to eq(described_class::REASON_REJECTED)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      contract.reload
      aggregate_failures do
        expect(contract.state).to eq("in_review")
        expect(contract.review_reason).to be_nil
        expect(contract.reviewed_at).to be_nil
      end
    end

    it "persists the stripped reason, the decision timestamp, the state and the audit row atomically" do
      before = Time.current

      events = described_class.call(contract, event: :return, user: author,
                                              reason: "  Missing cost breakdown in the annex.  ")

      expect(events).to have_key(:ok)

      contract.reload
      audit = Decidim::ContractsSk::AuditEvent.order(:id).last
      aggregate_failures do
        expect(contract.state).to eq("returned")
        expect(contract.review_reason).to eq("Missing cost breakdown in the annex.")
        expect(contract.reviewed_at).to be_present
        expect(contract.reviewed_at).to be >= before
        expect(audit.action).to eq("contract.return")
        expect(audit.target).to eq(contract)
      end
    end

    it "accepts a reason exactly at the cap (the boundary is inclusive)" do
      events = described_class.call(contract, event: :return, user: author,
                                              reason: "x" * described_class::MAX_REASON_LENGTH)

      expect(events).to have_key(:ok)

      contract.reload
      expect(contract.review_reason.length).to eq(described_class::MAX_REASON_LENGTH)
    end

    it "rejects with a reason onto the terminal state (same decision plumbing)" do
      events = described_class.call(contract, event: :reject, user: author,
                                              reason: "Duplicate of ZP-2026-001.")

      expect(events).to have_key(:ok)

      contract.reload
      audit = Decidim::ContractsSk::AuditEvent.order(:id).last
      aggregate_failures do
        expect(contract.state).to eq("rejected")
        expect(contract.review_reason).to eq("Duplicate of ZP-2026-001.")
        expect(audit.action).to eq("contract.reject")
      end
    end

    describe "fail-closed vocabulary (non-judgment events take no reason)" do
      let(:resolver_roles) { %i[editor] }

      it "refuses submit carrying a reason" do
        draft = Decidim::ContractsSk::Contract.create!(contract_attributes)

        expect do
          events = described_class.call(draft, event: :submit, user: author, reason: "Not my call.")

          expect(events).to have_key(:invalid)
          expect(events[:invalid]).to eq(described_class::REASON_REJECTED)
          expect(events).not_to have_key(:ok)
        end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

        draft.reload
        aggregate_failures do
          expect(draft.state).to eq("draft")
          expect(draft.review_reason).to be_nil
        end
      end

      it "refuses publish carrying a reason — before the redaction gate is even reached" do
        # The guard order pinned: the reason shape is a request precondition
        # (evaluated before the lock), so the refusal carries REASON_REJECTED
        # even on a record the redaction gate would also refuse — the request
        # never takes the row lock.
        contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "approved"))

        expect do
          events = described_class.call(contract, event: :publish, user: author, reason: "x")

          expect(events).to have_key(:invalid)
          expect(events[:invalid]).to eq(described_class::REASON_REJECTED)
          expect(events[:invalid]).not_to eq(described_class::REDACTION_GATE_REASON)
        end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

        contract.reload
        expect(contract.state).to eq("approved")
      end

      it "refuses archive carrying a reason" do
        contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "published"))

        expect do
          events = described_class.call(contract, event: :archive, user: author, reason: "x")

          expect(events).to have_key(:invalid)
          expect(events[:invalid]).to eq(described_class::REASON_REJECTED)
        end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

        contract.reload
        expect(contract.state).to eq("published")
      end
    end

    describe "resubmit clears the stale decision" do
      let(:resolver_roles) { %i[editor] }

      it "clears review_reason and reviewed_at from returned, atomically with the state" do
        # The command's own clearing act: the nil assignments ride the same
        # lock and the same state-write UPDATE, so a resubmit either fully
        # happened (state + cleared decision + audit row) or did not happen.
        returned = Decidim::ContractsSk::Contract.create!(
          contract_attributes(state: "returned", review_reason: "Fix the annex.", reviewed_at: Time.current)
        )

        events = described_class.call(returned, event: :submit, user: author)

        expect(events).to have_key(:ok)

        returned.reload
        audit = Decidim::ContractsSk::AuditEvent.order(:id).last
        aggregate_failures do
          expect(returned.state).to eq("in_review")
          expect(returned.review_reason).to be_nil
          expect(returned.reviewed_at).to be_nil
          expect(audit.action).to eq("contract.submit")
        end
      end

      it "clears nothing on submit from draft (the columns are already nil — a no-op)" do
        contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

        events = described_class.call(contract, event: :submit, user: author)

        expect(events).to have_key(:ok)

        contract.reload
        aggregate_failures do
          expect(contract.state).to eq("in_review")
          expect(contract.review_reason).to be_nil
          expect(contract.reviewed_at).to be_nil
        end
      end
    end

    describe "stale-object race with a reason (deterministic — no threads)" do
      it "refuses a stale copy's return, persisting no decision" do
        # The stale copy models a request admitted while the return edge
        # still existed (in_review); the row was then moved directly,
        # bypassing the command. The in-lock re-validation must fail the
        # edge — the reason must never be written onto the moved row.
        contract = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))
        stale = Decidim::ContractsSk::Contract.find(contract.id)

        contract.update!(state: "returned")

        expect do
          events = described_class.call(stale, event: :return, user: author, reason: "Late decision.")

          expect(events).to have_key(:invalid)
          expect(events).not_to have_key(:ok)
        end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

        contract.reload
        aggregate_failures do
          expect(contract.state).to eq("returned")
          expect(contract.review_reason).to be_nil
          expect(contract.reviewed_at).to be_nil
        end
      end
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

  describe "stale-object race (deterministic — no threads)" do
    it "refuses a copy loaded before the record left its state, writing no state and no audit row" do
      # The stale copy models a request that loaded the record while the
      # submit edge still existed (draft); the row was then moved directly,
      # bypassing the command. The in-lock re-validation (transition_state!
      # against the reloaded row) must fail the edge — the pre-lock role
      # resolution alone must never admit the write.
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)
      stale = Decidim::ContractsSk::Contract.find(contract.id)

      contract.update!(state: "in_review")

      expect do
        events = described_class.call(stale, event: :submit, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      contract.reload
      expect(contract.state).to eq("in_review")
    end
  end

  describe "four-eyes (civora-org/civora-platform#123)" do
    # The default resolver gives org admins both roles; model that here so
    # only the per-person rule can refuse.
    let(:resolver_roles) { %i[editor reviewer] }
    let(:reviewer_user) { Decidim::User.create!(organization: organization) }
    let(:third_user) { Decidim::User.create!(organization: organization) }
    let(:in_review) do
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(state: "in_review", decidim_submitted_by_id: author.id)
      )
    end

    def audit_actions
      Decidim::ContractsSk::AuditEvent.order(:id).pluck(:action)
    end

    def reason_for(event)
      %i[return reject].include?(event) ? "A reason." : nil
    end

    around do |example|
      original = Decidim::ContractsSk.allow_self_review
      example.run
      Decidim::ContractsSk.allow_self_review = original
    end

    describe "the submit stamp" do
      it "stamps the acting user as the submitter" do
        described_class.call(contract, event: :submit, user: author)

        expect(contract.reload.decidim_submitted_by_id).to eq(author.id)
        expect(contract.submitted_by).to eq(author)
      end

      it "overwrites the stamp when someone else resubmits from returned" do
        returned = Decidim::ContractsSk::Contract
                   .create!(contract_attributes(state: "returned", decidim_submitted_by_id: author.id))

        events = described_class.call(returned, event: :submit, user: reviewer_user)

        expect(events).to have_key(:ok)
        expect(returned.reload.decidim_submitted_by_id).to eq(reviewer_user.id)
      end
    end

    describe "the submitter judging their own submission" do
      %i[return approve reject].each do |event|
        it "refuses #{event} with :self_review and writes nothing" do
          expect do
            events = described_class.call(in_review, event: event, user: author, reason: reason_for(event))

            expect(events).to have_key(:invalid)
            expect(events[:invalid]).to eq(described_class::SELF_REVIEW_REASON)
            expect(events).not_to have_key(:ok)
          end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

          in_review.reload
          aggregate_failures do
            expect(in_review.state).to eq("in_review")
            expect(in_review.review_reason).to be_nil
            expect(in_review.reviewed_at).to be_nil
          end
        end
      end

      it "refuses a String event the same way" do
        events = described_class.call(in_review, event: "approve", user: author)

        expect(events[:invalid]).to eq(described_class::SELF_REVIEW_REASON)
      end

      it "re-checks inside the lock: a stale copy loaded before the stamp is refused (no threads)" do
        contract = Decidim::ContractsSk::Contract
                   .create!(contract_attributes(state: "in_review", decidim_submitted_by_id: reviewer_user.id))
        stale = Decidim::ContractsSk::Contract.find(contract.id)
        expect(stale.decidim_submitted_by_id).to eq(reviewer_user.id)

        # The row changes behind the stale copy: the acting user becomes the
        # submitter (e.g. a resubmit that landed after request admission).
        contract.update_column(:decidim_submitted_by_id, author.id)

        expect do
          events = described_class.call(stale, event: :approve, user: author)

          expect(events[:invalid]).to eq(described_class::SELF_REVIEW_REASON)
        end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

        expect(contract.reload.state).to eq("in_review")
      end
    end

    describe "a stale judgment against a record that left review" do
      it "gets the generic :invalid refusal, not :self_review" do
        approved = Decidim::ContractsSk::Contract
                   .create!(contract_attributes(state: "in_review", decidim_submitted_by_id: author.id))
        stale = Decidim::ContractsSk::Contract.find(approved.id)
        approved.update!(state: "approved")

        events = described_class.call(stale, event: :reject, user: author, reason: "Late.")

        expect(events).to have_key(:invalid)
        expect(events[:invalid]).not_to eq(described_class::SELF_REVIEW_REASON)
        expect(approved.reload.state).to eq("approved")
      end
    end

    describe "another reviewer" do
      it "may approve, with the plain contract.approve audit action" do
        events = described_class.call(in_review, event: :approve, user: reviewer_user)

        expect(events).to have_key(:ok)
        expect(in_review.reload.state).to eq("approved")
        expect(audit_actions).to eq(["contract.approve"])
      end

      it "may return and reject with a reason" do
        returned = described_class.call(in_review, event: :return, user: reviewer_user, reason: "Fix it.")
        expect(returned).to have_key(:ok)

        other = Decidim::ContractsSk::Contract
                .create!(contract_attributes(reference: "ZP-2026-002", state: "in_review",
                                             decidim_submitted_by_id: author.id))
        rejected = described_class.call(other, event: :reject, user: reviewer_user, reason: "No.")
        expect(rejected).to have_key(:ok)
      end
    end

    describe "resubmission by someone else" do
      it "changes who is blocked: A submits, B returns, C resubmits, then A may approve and C may not" do
        expect(described_class.call(contract, event: :submit, user: author)).to have_key(:ok)
        expect(described_class.call(contract, event: :return, user: reviewer_user, reason: "Redo."))
          .to have_key(:ok)
        expect(described_class.call(contract, event: :submit, user: third_user)).to have_key(:ok)

        expect(described_class.call(contract, event: :approve, user: third_user)[:invalid])
          .to eq(described_class::SELF_REVIEW_REASON)
        expect(described_class.call(contract, event: :approve, user: author)).to have_key(:ok)
        expect(contract.reload.state).to eq("approved")
      end
    end

    describe "legacy records" do
      it "does not block a record with no submitter stamp" do
        legacy = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review"))

        events = described_class.call(legacy, event: :approve, user: author)

        expect(events).to have_key(:ok)
        expect(audit_actions).to eq(["contract.approve"])
      end
    end

    describe "with allow_self_review enabled" do
      before { Decidim::ContractsSk.allow_self_review = true }

      %i[return approve reject].each do |event|
        it "lets the submitter #{event} and audits it as contract.#{event}_self" do
          events = described_class.call(in_review, event: event, user: author, reason: reason_for(event))

          expect(events).to have_key(:ok)
          expect(in_review.reload.state).not_to eq("in_review")
          expect(audit_actions).to eq(["contract.#{event}_self"])
        end
      end

      it "keeps the plain contract.approve action for a non-submitter" do
        events = described_class.call(in_review, event: :approve, user: reviewer_user)

        expect(events).to have_key(:ok)
        expect(audit_actions).to eq(["contract.approve"])
      end

      it "audits the submit itself as plain contract.submit" do
        described_class.call(contract, event: :submit, user: author)

        expect(audit_actions).to eq(["contract.submit"])
      end
    end
  end

  describe "workflow notifications (civora-org/civora-platform#94, M03-05-C)" do
    let(:notifier) { Decidim::ContractsSk::TransitionNotification }
    let(:resolver_roles) { %i[editor reviewer] }
    let(:reviewer_user) { Decidim::User.create!(organization: organization) }
    let(:in_review) do
      Decidim::ContractsSk::Contract
        .create!(contract_attributes(state: "in_review", decidim_submitted_by_id: author.id))
    end
    let(:approved) do
      Decidim::ContractsSk::Contract
        .create!(contract_attributes(state: "approved", redaction_confirmed_at: Time.current))
    end

    def expect_published_once(event, record, actor)
      expect(notifier).to have_received(:publish).once.with(event: event, contract: record, actor: actor)
    end

    it "publishes submit with the acting user after the transition" do
      described_class.call(contract, event: :submit, user: author)

      expect_published_once(:submit, contract, author)
    end

    %i[return reject].each do |event|
      it "publishes #{event} with the stored reason already on the record" do
        stored = nil
        allow(notifier).to receive(:publish) { |contract:, **| stored = contract.reload.review_reason }

        described_class.call(in_review, event: event, user: reviewer_user, reason: "Doplňte prílohu.")

        expect(stored).to eq("Doplňte prílohu.")
        expect_published_once(event, in_review, reviewer_user)
      end
    end

    it "publishes approve" do
      described_class.call(in_review, event: :approve, user: reviewer_user)

      expect_published_once(:approve, in_review, reviewer_user)
    end

    it "publishes publish" do
      described_class.call(approved, event: :publish, user: author)

      expect_published_once(:publish, approved, author)
    end

    it "publishes only once the new state is committed and visible to other connections' reads" do
      state_at_publish = nil
      allow(notifier).to receive(:publish) { |contract:, **| state_at_publish = contract.class.find(contract.id).state }

      described_class.call(contract, event: :submit, user: author)

      expect(state_at_publish).to eq("in_review")
    end

    it "publishes nothing when the role does not match" do
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { [:reviewer] }

      described_class.call(contract, event: :submit, user: author)

      expect(notifier).not_to have_received(:publish)
    end

    it "publishes nothing when the redaction gate refuses" do
      gated = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "approved"))

      described_class.call(gated, event: :publish, user: author)

      expect(notifier).not_to have_received(:publish)
    end

    it "publishes nothing on a missing or refused reason" do
      described_class.call(in_review, event: :return, user: reviewer_user)
      described_class.call(in_review, event: :approve, user: reviewer_user, reason: "not allowed here")

      expect(notifier).not_to have_received(:publish)
    end

    it "publishes nothing on an invalid edge" do
      described_class.call(contract, event: :approve, user: author)

      expect(notifier).not_to have_received(:publish)
    end

    it "publishes nothing when the four-eyes rule refuses" do
      described_class.call(in_review, event: :approve, user: author)

      expect(notifier).not_to have_received(:publish)
    end

    it "publishes nothing when the audit write fails inside the lock" do
      allow(Decidim::ContractsSk::AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      described_class.call(contract, event: :submit, user: author)

      expect(notifier).not_to have_received(:publish)
    end

    it "publishes nothing when the model rejects the edge inside the lock" do
      allow(contract).to receive(:transition_state!).and_raise(Decidim::ContractsSk::ContractLifecycle::InvalidTransitionError)

      described_class.call(contract, event: :submit, user: author)

      expect(notifier).not_to have_received(:publish)
    end

    describe "inside an outer transaction" do
      it "waits for the outermost commit" do
        contract # created before the transaction opens
        ActiveRecord::Base.transaction do
          described_class.call(contract, event: :submit, user: author)
          expect(notifier).not_to have_received(:publish)
        end

        expect_published_once(:submit, contract, author)
      end

      it "publishes nothing when the outer transaction rolls back, though the command broadcast :ok" do
        contract # created before the transaction opens
        events = nil
        ActiveRecord::Base.transaction do
          events = described_class.call(contract, event: :submit, user: author)
          raise ActiveRecord::Rollback
        end

        expect(events).to have_key(:ok)
        expect(notifier).not_to have_received(:publish)
        expect(contract.reload.state).to eq("draft")
      end
    end

    describe "fail-soft end to end (real publisher, failing events manager)" do
      let(:manager) { Class.new { def self.publish(**) = raise(IOError, "secret.person@example.org") } }
      let(:logger) { instance_spy(Logger) }

      before do
        allow(notifier).to receive(:publish).and_call_original
        stub_const("Decidim::EventsManager", manager)
        Decidim::ContractsSk.const_set(:ContractTransitionEvent, Class.new)
        allow(Rails).to receive(:logger).and_return(logger)
        Decidim::ContractsSk.notification_candidates = ->(_organization) { [reviewer_user] }
      end

      around do |example|
        saved = Decidim::ContractsSk.notification_candidates
        example.run
      ensure
        Decidim::ContractsSk.notification_candidates = saved
      end

      after do
        Decidim::ContractsSk.send(:remove_const, :ContractTransitionEvent) # rubocop:disable RSpec/RemoveConst
      end

      it "keeps the :ok broadcast and the committed state, and logs the class only" do
        events = described_class.call(contract, event: :submit, user: author)

        expect(events).to have_key(:ok)
        expect(contract.reload.state).to eq("in_review")
        expect(logger).to have_received(:warn).with("[decidim-contracts_sk] transition notification failed: IOError")
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
