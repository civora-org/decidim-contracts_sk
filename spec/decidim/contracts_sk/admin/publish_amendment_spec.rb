# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for PublishAmendment (M02-05-B,
# civora-org/civora-platform#65), run against the real migrations on an
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
RSpec.describe Decidim::ContractsSk::Admin::PublishAmendment, :db do
  before { migrate_engine_schema! }

  let(:contract) do
    Decidim::ContractsSk::Contract.create!(contract_attributes(state: "published").tap do |attrs|
      attrs[:subject_matter] = "Supply and installation of road signage"
      attrs[:amount] = BigDecimal("1250.50")
      attrs[:signed_on] = Date.new(2026, 9, 1)
      attrs[:effective_from] = Date.new(2026, 8, 15)
      attrs[:crz_url] = "https://crz.gov.sk/record/123"
    end)
  end

  # The draft under test, created through the creation command exactly as
  # the admin surface does (version sequenced there).
  let!(:amendment) do
    Decidim::ContractsSk::Admin::CreateAmendment
      .call(Decidim::ContractsSk::Admin::AmendmentForm.new(summary: "Extended delivery deadline"),
            contract, user: author)[:ok]
  end

  # The frozen snapshot the publish must write: the contract's pre-publish
  # content fields, normalized to display-ready scalars.
  let(:expected_snapshot) do
    {
      "subject_matter" => "Supply and installation of road signage",
      "amount" => "1250.5",
      "currency" => "EUR",
      "signed_on" => "2026-09-01",
      "effective_from" => "2026-08-15",
      "crz_url" => "https://crz.gov.sk/record/123"
    }
  end

  it "publishes the draft, freezing the contract's current content fields as the snapshot" do
    before = Time.current

    events = described_class.call(amendment, user: author)

    expect(events).to have_key(:ok)

    amendment.reload
    expect(amendment).to be_published
    expect(amendment.published_at).to be_present
    expect(amendment.published_at).to be >= before
    expect(amendment.content_snapshot).to eq(expected_snapshot)

    # The live fields stay the current version (ADR-006): the record itself
    # is untouched by publishing a version of it.
    expect(contract.reload.subject_matter).to eq("Supply and installation of road signage")
  end

  it "keeps the version sequenced at creation time" do
    events = described_class.call(amendment, user: author)

    expect(events).to have_key(:ok)
    expect(amendment.reload.version).to eq(1)
  end

  it "writes exactly one audit row with the pinned payload shape" do
    expect { described_class.call(amendment, user: author) }
      .to change(Decidim::ContractsSk::AuditEvent, :count).by(1)

    audit = Decidim::ContractsSk::AuditEvent.order(:id).last
    expect(audit.action).to eq("amendment.publish")
    expect(audit.target_type).to eq("Decidim::ContractsSk::Amendment")
    expect(audit.target_id).to eq(amendment.id)
    expect(audit.organization).to eq(organization)
    expect(audit.actor).to eq(author)
    expect(audit.created_at).to be_present
  end

  it "rolls the publication back when the audit write fails (atomicity)" do
    # The snapshot/state/stamp and the audit INSERT share one transaction;
    # injecting a failure at the audit boundary must leave an untouched
    # draft behind — no publication without its audit row, ever.
    allow(Decidim::ContractsSk::AuditEvent).to receive(:create!)
      .and_raise(ActiveRecord::RecordInvalid)

    events = described_class.call(amendment, user: author)

    expect(events).to have_key(:invalid)
    expect(events).not_to have_key(:ok)

    amendment.reload
    expect(amendment).to be_draft
    expect(amendment.published_at).to be_nil
    expect(amendment.content_snapshot).to be_nil
    expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
  end

  describe "fail-closed re-checks (no mutation ever)" do
    it "refuses an amendment that is already published" do
      described_class.call(amendment, user: author)
      published_at = amendment.reload.published_at

      expect do
        events = described_class.call(amendment, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      amendment.reload
      expect(amendment.published_at).to eq(published_at)
      expect(amendment.content_snapshot).to eq(expected_snapshot)
    end

    it "refuses to publish when the parent contract has left the published state" do
      contract.archive!(by_role: :editor)

      events = described_class.call(amendment, user: author)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)

      amendment.reload
      expect(amendment).to be_draft
      expect(amendment.published_at).to be_nil
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end
  end

  describe "stale-object race (deterministic — no threads)" do
    it "refuses a copy loaded before the publication, leaving the published row untouched" do
      # The stale copy models a request that loaded the row while it was
      # still a draft; the in-lock re-check must read the reloaded,
      # in-database state — not the request-start attributes.
      stale = Decidim::ContractsSk::Amendment.find(amendment.id)

      events = described_class.call(Decidim::ContractsSk::Amendment.find(amendment.id),
                                    user: author)
      expect(events).to have_key(:ok)

      published_at = amendment.reload.published_at

      expect do
        events = described_class.call(stale, user: author)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      amendment.reload
      expect(amendment).to be_published
      expect(amendment.published_at).to eq(published_at)
      expect(amendment.content_snapshot).to eq(expected_snapshot)
    end

    it "freezes the contract content as it stands under the lock, not the request-start copy" do
      # The command's view of the parent is the association-loaded
      # instance; mutating the row through a fresh instance models a write
      # that lands between the request's load and its publish. The
      # in-lock reload must serialize the CURRENT content.
      stale_contract = amendment.contract
      expect(stale_contract.subject_matter).to eq("Supply and installation of road signage")

      Decidim::ContractsSk::Contract.find(contract.id)
                                    .update!(subject_matter: "Amended scope of works")

      events = described_class.call(amendment, user: author)

      expect(events).to have_key(:ok)
      expect(amendment.reload.content_snapshot["subject_matter"]).to eq("Amended scope of works")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
