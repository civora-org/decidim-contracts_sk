# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for DestroyDocument (civora-org/civora-platform#73), run
# against the real migrations plus the ActiveStorage tables on an in-memory
# SQLite adapter (excluded from the default offline run).
#
# Destroying the document destroys its ActiveStorage attachment with it; the
# blob purge itself is enqueued (captured by the harness's :test queue
# adapter), never executed inline.
#
# Synthetic fixtures only (no real content, no PII).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::DestroyDocument, :db do
  before do
    migrate_engine_schema!
    FileUtils.rm_rf(active_storage_root)
  end

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:document) { Decidim::ContractsSk::Document.create!(contract: contract, title: "Signed contract scan") }

  def sample_fixture(name)
    File.expand_path("../../../fixtures/files/#{name}", __dir__)
  end

  it "removes the document and its attachment row" do
    document.attach_file!(Rack::Test::UploadedFile.new(sample_fixture("sample.pdf"), "application/pdf"))
    attachment_id = document.file_attachment.id

    expect do
      events = described_class.call(document)

      expect(events).to have_key(:ok)
    end.to change(Decidim::ContractsSk::Document, :count).by(-1)

    aggregate_failures do
      expect(Decidim::ContractsSk::Document.exists?(document.id)).to be(false)
      expect(ActiveStorage::Attachment.exists?(attachment_id)).to be(false)
    end
  end

  it "refuses a contract that has left the editable states (fail-closed re-check)" do
    document.attach_file!(Rack::Test::UploadedFile.new(sample_fixture("sample.pdf"), "application/pdf"))
    contract.update!(state: "in_review")

    expect do
      events = described_class.call(document)

      expect(events).to have_key(:invalid)
      expect(events).not_to have_key(:ok)
    end.not_to change(Decidim::ContractsSk::Document, :count)

    expect(Decidim::ContractsSk::Document.exists?(document.id)).to be(true)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
