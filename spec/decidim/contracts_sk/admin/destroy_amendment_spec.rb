# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for DestroyAmendment (M02-05-B,
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
RSpec.describe Decidim::ContractsSk::Admin::DestroyAmendment, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes(state: "published")) }

  def create_draft!
    Decidim::ContractsSk::Amendment.create!(contract: contract, version: 1,
                                            summary: "Extended delivery deadline",
                                            organization: organization, author: author)
  end

  def create_published!
    create_draft!.tap { |amendment| amendment.update!(state: "published") }
  end

  it "removes a draft amendment" do
    amendment = create_draft!

    events = described_class.call(amendment)

    expect(events).to have_key(:ok)
    expect(Decidim::ContractsSk::Amendment.exists?(amendment.id)).to be(false)
  end

  it "refuses a published amendment, leaving the row in place (fail-closed re-check, ADR-006)" do
    amendment = create_published!

    events = described_class.call(amendment)

    expect(events).to have_key(:invalid)
    expect(events).not_to have_key(:ok)
    expect(Decidim::ContractsSk::Amendment.exists?(amendment.id)).to be(true)
  end

  describe "stale-object race (deterministic — no threads)" do
    it "refuses a copy loaded before the amendment was published, leaving the row in place" do
      # The stale copy models a request that loaded the row while it was
      # still a draft; the in-lock re-check must read the reloaded,
      # in-database state — not the request-start attributes.
      amendment = create_draft!
      stale = Decidim::ContractsSk::Amendment.find(amendment.id)

      events = Decidim::ContractsSk::Admin::PublishAmendment
               .call(Decidim::ContractsSk::Amendment.find(amendment.id), user: author)
      expect(events).to have_key(:ok)

      expect do
        events = described_class.call(stale)

        expect(events).to have_key(:invalid)
        expect(events).not_to have_key(:ok)
      end.not_to change(Decidim::ContractsSk::AuditEvent, :count)

      amendment.reload
      expect(amendment).to be_published
      expect(amendment.published_at).to be_present
      expect(amendment.content_snapshot).to be_present
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
