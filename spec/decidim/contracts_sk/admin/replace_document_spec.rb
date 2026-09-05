# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for ReplaceDocument (civora-org/civora-platform#73), run
# against the real migrations plus the ActiveStorage tables on an in-memory
# SQLite adapter (excluded from the default offline run).
#
# A replace swaps the FILE only — the controller pre-fills the form's
# title/kind from the persisted record — so the examples pin that the
# record's content fields survive an execution untouched.
#
# Synthetic fixtures only (no real content, no PII).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::ReplaceDocument, :db do
  before do
    migrate_engine_schema!
    FileUtils.rm_rf(active_storage_root)
  end

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:document) do
    Decidim::ContractsSk::Document.create!(contract: contract, title: "Signed contract scan", kind: "annex")
  end

  def sample_fixture(name)
    File.expand_path("../../../fixtures/files/#{name}", __dir__)
  end

  def form_with(overrides = {})
    Decidim::ContractsSk::Admin::DocumentForm.new(
      { title: document.title, kind: document.kind,
        file: Rack::Test::UploadedFile.new(sample_fixture("sample.pdf"), "application/pdf") }.merge(overrides)
    )
  end

  it "swaps the file and re-syncs the metadata columns, keeping the content fields" do
    document.attach_file!(Rack::Test::UploadedFile.new(sample_fixture("sample-notes.txt"), "text/plain"))

    events = described_class.call(form_with, document)

    expect(events).to have_key(:ok)

    document.reload
    aggregate_failures do
      # The file (and with it the metadata) is the only thing that changed.
      expect(document.file_name).to eq("sample.pdf")
      expect(document.content_type).to eq("application/pdf")
      expect(document.file_size).to eq(File.size(sample_fixture("sample.pdf")))
      expect(document.title).to eq("Signed contract scan")
      expect(document.kind).to eq("annex")
      expect(document.file).to be_attached
    end
  end

  it "broadcasts :invalid without changing anything when the form is rejected (no file)" do
    document.attach_file!(Rack::Test::UploadedFile.new(sample_fixture("sample.pdf"), "application/pdf"))
    old_blob_id = document.file.blob.id

    events = described_class.call(form_with(file: nil), document)

    aggregate_failures do
      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
      expect(document.reload.file_name).to eq("sample.pdf")
      expect(document.file.blob.id).to eq(old_blob_id)
    end
  end

  it "refuses a contract that has left the editable states (fail-closed re-check)" do
    contract.update!(state: "published")

    events = described_class.call(form_with, document)

    aggregate_failures do
      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
      expect(document.reload.file_name).to be_nil
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
