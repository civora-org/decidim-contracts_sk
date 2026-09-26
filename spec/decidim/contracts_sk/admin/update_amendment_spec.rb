# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for UpdateAmendment (M02-05-B,
# civora-org/civora-platform#65), run against the real migrations on an
# in-memory SQLite adapter (see spec/support/contracts_sk_db_helpers.rb;
# excluded from the default offline run).
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
#
# Synthetic data only (ZP-2026-00x references), no real PII.
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::UpdateAmendment, :db do
  before { migrate_engine_schema! }

  # The ADR-007 invariant (#91): amendment publication backstops on the
  # parent's redaction stamp, so this group's published parent carries it.
  let(:contract) do
    Decidim::ContractsSk::Contract
      .create!(contract_attributes(state: "published", redaction_confirmed_at: Time.current))
  end
  let(:form) { Decidim::ContractsSk::Admin::AmendmentForm.new(summary: "Retitled amendment") }

  def create_draft!
    Decidim::ContractsSk::Amendment.create!(contract: contract, version: 1,
                                            summary: "Extended delivery deadline",
                                            organization: organization, author: author)
  end

  def create_published!
    create_draft!.tap { |amendment| amendment.update!(state: "published") }
  end

  it "updates a draft's summary" do
    amendment = create_draft!

    events = described_class.call(form, amendment)

    expect(events).to have_key(:ok)
    expect(events[:ok]).to eq(amendment)
    expect(amendment.reload.summary).to eq("Retitled amendment")
  end

  it "broadcasts :invalid without persisting when the form is rejected (blank summary)" do
    amendment = create_draft!
    blank_form = Decidim::ContractsSk::Admin::AmendmentForm.new(summary: "")

    events = described_class.call(blank_form, amendment)

    expect(events).to have_key(:invalid)
    expect(events).not_to have_key(:ok)
    expect(amendment.reload.summary).to eq("Extended delivery deadline")
  end

  it "refuses a published amendment, leaving the row untouched (fail-closed re-check, ADR-006)" do
    amendment = create_published!

    events = described_class.call(form, amendment)

    expect(events).to have_key(:invalid)
    expect(events).not_to have_key(:ok)
    expect(amendment.reload.summary).to eq("Extended delivery deadline")
  end

  describe "stale-object race (deterministic — no threads)" do
    it "refuses a copy loaded before the amendment was published, leaving the row untouched" do
      # The stale copy models a request that loaded the row while it was
      # still a draft; the in-lock re-check must read the reloaded,
      # in-database state — not the request-start attributes.
      amendment = create_draft!
      stale = Decidim::ContractsSk::Amendment.find(amendment.id)

      events = Decidim::ContractsSk::Admin::PublishAmendment
               .call(Decidim::ContractsSk::Amendment.find(amendment.id), user: author)
      expect(events).to have_key(:ok)

      published_at = amendment.reload.published_at

      expect do
        events = described_class.call(form, stale)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      amendment.reload
      expect(amendment).to be_published
      expect(amendment.summary).to eq("Extended delivery deadline")
      expect(amendment.published_at).to eq(published_at)
      expect(amendment.content_snapshot).to be_present
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
