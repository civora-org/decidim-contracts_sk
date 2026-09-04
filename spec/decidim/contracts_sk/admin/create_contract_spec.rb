# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for CreateContract (civora-org/civora-platform#58),
# run against the real migrations on an in-memory SQLite adapter (see
# spec/support/contracts_sk_db_helpers.rb; excluded from the default offline
# run).
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
RSpec.describe Decidim::ContractsSk::Admin::CreateContract, :db do
  before { migrate_engine_schema! }

  let(:form) do
    Decidim::ContractsSk::Admin::ContractForm.new(title: "Road reconstruction", reference: "ZP-2026-001")
  end

  it "creates a draft contract owned by the acting user's organization" do
    events = described_class.call(form, user: author, organization: organization)

    expect(events).to have_key(:ok)
    expect(events).not_to have_key(:invalid)

    record = events[:ok]
    expect(record.title).to eq("Road reconstruction")
    expect(record.reference).to eq("ZP-2026-001")
    expect(record.state).to eq("draft")
    expect(record.organization).to eq(organization)
    expect(record.author).to eq(author)
  end

  it "fails closed on a tenancy mismatch (user belongs to another organization)" do
    other_organization = Decidim::Organization.create!
    foreign_user = double(organization: other_organization)

    events = described_class.call(form, user: foreign_user, organization: organization)

    expect(events).to have_key(:invalid)
    expect(events).not_to have_key(:ok)
    expect(Decidim::ContractsSk::Contract.count).to eq(0)
  end

  it "skips the tenancy guard for seam objects without #organization (respond_to?-safe)" do
    # A bare Object carries no #organization, so the guard must skip (not
    # crash) — the permission layer stays the authorization authority. The
    # persistence seam is stubbed because AR's belongs_to typing rejects
    # non-AR author objects before the guard's contract could be observed.
    seam_user = Object.new
    record = Object.new # opaque identity token for the broadcast payload

    allow(Decidim::ContractsSk::Contract).to receive(:create!).and_return(record)

    events = described_class.call(form, user: seam_user, organization: organization)

    expect(events).to have_key(:ok)
    expect(events[:ok]).to eq(record)
    expect(Decidim::ContractsSk::Contract).to have_received(:create!).with(
      organization: organization,
      author: seam_user,
      title: "Road reconstruction",
      reference: "ZP-2026-001",
      subject_matter: nil,
      amount: nil,
      currency: "EUR",
      signed_on: nil,
      effective_from: nil,
      crz_url: nil
    )
  end

  it "passes the content fields through to the model (civora-org/civora-platform#75)" do
    content_form = Decidim::ContractsSk::Admin::ContractForm.new(
      title: "Road reconstruction",
      reference: "ZP-2026-001",
      subject_matter: "Supply and installation of road signage",
      amount: "1250.50",
      currency: "EUR",
      signed_on: "2026-09-01",
      effective_from: "2026-08-15",
      crz_url: "https://crz.gov.sk/record/123"
    )

    events = described_class.call(content_form, user: author, organization: organization)

    expect(events).to have_key(:ok)

    record = events[:ok]
    expect(record.subject_matter).to eq("Supply and installation of road signage")
    expect(record.amount).to eq(BigDecimal("1250.50"))
    expect(record.currency).to eq("EUR")
    expect(record.signed_on).to eq(Date.new(2026, 9, 1))
    expect(record.effective_from).to eq(Date.new(2026, 8, 15))
    expect(record.crz_url).to eq("https://crz.gov.sk/record/123")
    # The system field has no form path at all.
    expect(record.published_at).to be_nil
  end

  it "broadcasts :invalid without persisting when the model rejects the record (duplicate reference)" do
    Decidim::ContractsSk::Contract.create!(contract_attributes)

    events = described_class.call(form, user: author, organization: organization)

    expect(events).to have_key(:invalid)
    expect(events).not_to have_key(:ok)
    expect(Decidim::ContractsSk::Contract.count).to eq(1)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
