# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for AttachDocument (civora-org/civora-platform#73), run
# against the real migrations plus the ActiveStorage tables on an in-memory
# SQLite adapter (see spec/support/contracts_sk_db_helpers.rb; excluded from
# the default offline run).
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
#
# The uploaded fixtures are the repo's synthetic files (PDF-shaped/text
# bytes, no real content, no PII).
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::AttachDocument, :db do
  before do
    migrate_engine_schema!
    FileUtils.rm_rf(active_storage_root)
  end

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

  def sample_fixture(name)
    File.expand_path("../../../fixtures/files/#{name}", __dir__)
  end

  def form_with(overrides = {})
    Decidim::ContractsSk::Admin::DocumentForm.new(
      { title: "Signed contract scan", kind: "contract",
        file: Rack::Test::UploadedFile.new(sample_fixture("sample.pdf"), "application/pdf") }.merge(overrides)
    )
  end

  it "creates a document through the parent contract's association and syncs the metadata columns" do
    events = described_class.call(form_with, contract)

    expect(events).to have_key(:ok)

    document = events[:ok]
    expect(document).to be_persisted
    expect(document.reload.contract).to eq(contract)
    expect(document.title).to eq("Signed contract scan")
    expect(document.kind).to eq("contract")
    expect(document.file_name).to eq("sample.pdf")
    expect(document.content_type).to eq("application/pdf")
    expect(document.file_size).to eq(File.size(sample_fixture("sample.pdf")))
    expect(document.file).to be_attached
  end

  it "broadcasts :invalid without persisting when the form is rejected (blank title)" do
    blank_form = form_with(title: "")

    expect do
      events = described_class.call(blank_form, contract)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::Document, :count)
  end

  it "refuses a parent contract that has left the editable states, writing nothing (fail-closed re-check)" do
    contract.update!(state: "in_review")

    expect do
      events = described_class.call(form_with, contract)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::Document, :count)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
