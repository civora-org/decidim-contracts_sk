# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for GenerateCrzHandoff (M02-05-C,
# civora-org/civora-platform#74), run against the real migrations plus the
# ActiveStorage tables on an in-memory SQLite adapter (see
# spec/support/contracts_sk_db_helpers.rb; excluded from the default offline
# run).
#
# The PDF generation itself is real, not stubbed: Prawn is pure Ruby and
# the DejaVu font ships inside the gem, so the full generate-and-attach path
# runs offline and deterministically.
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::GenerateCrzHandoff, :db do
  before do
    migrate_engine_schema!
    FileUtils.rm_rf(active_storage_root)
  end

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

  it "creates exactly one crz_export document carrying a real PDF, with synced metadata" do
    events = described_class.call(contract, user: author)

    expect(events).to have_key(:ok)

    document = events[:ok]
    expect(document).to be_persisted
    aggregate_failures do
      expect(document.contract).to eq(contract)
      expect(document.title).to eq("CRZ handoff export")
      expect(document.kind).to eq("crz_export")
      expect(document.file_name).to eq("crz-handoff.pdf")
      expect(document.content_type).to eq("application/pdf")
      expect(document.file_size).to be > 0
      expect(document.file).to be_attached
      expect(document.file.download).to start_with("%PDF-")
    end
  end

  it "regenerates onto the SAME document row (no duplicates), swapping only the artifact" do
    first = described_class.call(contract, user: author)[:ok]
    first_attachment_id = first.file_attachment.id

    second = described_class.call(contract, user: author)[:ok]

    aggregate_failures do
      expect(second.id).to eq(first.id)
      expect(contract.documents.where(kind: "crz_export").count).to eq(1)
      expect(Decidim::ContractsSk::Document.count).to eq(1)
      expect(second.reload.title).to eq("CRZ handoff export")
      expect(second.file_attachment.id).not_to eq(first_attachment_id)
      expect(second.file.download).to start_with("%PDF-")
    end
  end

  it "refuses a contract that has left the editable states, writing nothing (fail-closed re-check)" do
    contract.update!(state: "in_review")

    expect do
      events = described_class.call(contract, user: author)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::Document, :count)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
