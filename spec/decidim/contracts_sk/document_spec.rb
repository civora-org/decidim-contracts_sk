# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's Document model
# (M02-02-B, civora-org/civora-platform#56).
#
# The default run asserts class-level structure only (inheritance, table
# name, associations, frozen vocabulary, validators, enum wiring) — none of
# it touches a DB connection. The Decidim::ApplicationRecord /
# Decidim::Organization / Decidim::User stand-ins live in
# spec/support/contracts_sk_db_helpers.rb, loaded from spec_helper.rb before
# any spec file: the real ones live in decidim-core and cannot be required
# outside a full Rails app.
#
# The :db-tagged group exercises the model against the REAL migrations on an
# in-memory SQLite adapter. It is excluded by default (see spec_helper.rb);
# opting in via CONTRACTS_SK_DB=1 requires the sqlite3 gem, and the group
# skips with a clear message when it is absent.
#
# The model class is provided by the Stage-1 dummy harness (spec/dummy); the
# Decidim::ApplicationRecord / Decidim::Organization / Decidim::User
# stand-ins it builds on live in spec/support/contracts_sk_db_helpers.rb
# (the dummy is AR-free by design).
# ---------------------------------------------------------------------------

require "spec_helper"
require "tmpdir"

# The structural groups assert several related class-level facts per example
# and the :db group walks several scenarios, exceeding the default budgets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe Decidim::ContractsSk::Document do
  describe "class structure" do
    it "inherits from the engine's ApplicationRecord" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
    end

    it "maps to the prefixed documents table" do
      expect(described_class.table_name).to eq("decidim_contracts_sk_documents")
    end
  end

  describe "associations" do
    it "belongs to the contract it hangs off" do
      reflection = described_class.reflect_on_association(:contract)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("contract_id")
      expect(reflection.klass).to eq(Decidim::ContractsSk::Contract)
    end

    it "carries the engine-side ActiveStorage attachment (civora-org/civora-platform#73)" do
      reflection = described_class.reflect_on_attachment(:file)

      aggregate_failures do
        # `has_one_attached :file` builds this attachment reflection and the
        # has_one :file_attachment association behind it; Option A keeps the
        # storage on the engine model, not on Decidim::Attachment.
        expect(reflection).not_to be_nil
        expect(reflection.macro).to eq(:has_one_attached)
        expect(reflection.options[:dependent]).to eq(:purge_later)
        attachment = described_class.reflect_on_association(:file_attachment)

        expect(attachment.macro).to eq(:has_one)
        expect(attachment.options[:class_name]).to eq("ActiveStorage::Attachment")
        # Destroying the document destroys the attachment row with it (the
        # blob purge itself goes through the host's queuing backend).
        expect(attachment.options[:dependent]).to eq(:destroy)
      end
    end
  end

  describe "kind vocabulary" do
    it "exposes the approved kind vocabulary as frozen strings" do
      expect(described_class::KINDS).to eq(%w[contract crz_export annex other])
      expect(described_class::KINDS).to all(be_a(String)) # a Symbol list silently invalidates every record
      expect(described_class::KINDS).to be_frozen
    end

    it "derives KIND_VALUES from KINDS, never hand-enumerated" do
      expect(described_class::KIND_VALUES)
        .to eq(described_class::KINDS.to_h { |kind| [kind, kind] })
      expect(described_class::KIND_VALUES).to be_frozen
    end
  end

  describe "upload guard constants (civora-org/civora-platform#64)" do
    it "exposes the frozen content-type allowlist" do
      aggregate_failures do
        expect(described_class::ALLOWED_CONTENT_TYPES)
          .to eq(%w[application/pdf text/plain image/png image/jpeg])
        expect(described_class::ALLOWED_CONTENT_TYPES).to be_frozen
      end
    end

    it "caps uploads at 10 megabytes" do
      expect(described_class::MAX_FILE_SIZE).to eq(10 * 1024 * 1024)
    end
  end

  describe "filename sanitization (civora-org/civora-platform#64)" do
    def sanitized(raw)
      described_class.sanitize_filename(raw)
    end

    it "strips directory components from both separator styles" do
      aggregate_failures do
        expect(sanitized("../../etc/passwd")).to eq("passwd")
        expect(sanitized("..\\windows\\system32\\evil.exe")).to eq("evil.exe")
        expect(sanitized("a/b\\c/d.txt")).to eq("d.txt")
      end
    end

    it "strips control characters" do
      aggregate_failures do
        expect(sanitized("na\u0000me\u0001.pdf")).to eq("name.pdf")
        expect(sanitized("report\t\n.pdf")).to eq("report.pdf")
      end
    end

    it "keeps only [A-Za-z0-9._-] and collapses repeated separators" do
      aggregate_failures do
        expect(sanitized("my__file--v2.pdf")).to eq("my_file-v2.pdf")
        # Unicode (diacritics, homoglyphs) is dropped with the rest.
        expect(sanitized("zmluva č. 4.pdf")).to eq("zmluva.4.pdf")
        expect(sanitized("\u0441\u043empany.pdf")).to eq("mpany.pdf") # Cyrillic с, о
      end
    end

    it "leaves normal names unchanged" do
      aggregate_failures do
        expect(sanitized("sample.pdf")).to eq("sample.pdf")
        expect(sanitized("sample-notes.txt")).to eq("sample-notes.txt")
        # The generated handoff artifact's fixed name survives verbatim.
        expect(sanitized("crz-handoff.pdf")).to eq("crz-handoff.pdf")
      end
    end

    it "falls back to a stable name when every character is lost" do
      aggregate_failures do
        expect(sanitized("..")).to eq("document")
        expect(sanitized("...")).to eq("document")
        expect(sanitized("ččč")).to eq("document")
        expect(sanitized("")).to eq("document")
        expect(sanitized(nil)).to eq("document")
      end
    end

    it "falls back with the extension preserved when only the extension survives" do
      aggregate_failures do
        expect(sanitized("ččč.pdf")).to eq("document.pdf")
        expect(sanitized(".pdf")).to eq("document.pdf")
        expect(sanitized("..pdf")).to eq("document.pdf")
      end
    end

    it "caps the length at MAX_FILE_NAME_LENGTH" do
      expect(sanitized("a" * 300)).to eq("a" * described_class::MAX_FILE_NAME_LENGTH)
    end
  end

  describe "validations" do
    it "requires a kind within the frozen vocabulary" do
      validators = described_class.validators_on(:kind)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      inclusion = validators.find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }
      expect(inclusion.options[:in]).to eq(%w[contract crz_export annex other])
      expect(inclusion.options[:in]).to all(be_a(String))
      expect(inclusion.options[:in]).to be_frozen # a mutable vocabulary could be corrupted through the validator
    end

    it "requires a title of at most 255 characters" do
      validators = described_class.validators_on(:title)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      expect(validators.find { |v| v.is_a?(ActiveModel::Validations::LengthValidator) }.options[:maximum]).to eq(255)
    end
  end

  describe "kind enum" do
    it "exposes kinds equal to KIND_VALUES" do
      # Rails stores enum values in a HashWithIndifferentAccess, so the
      # equality contract holds against the stringified mapping.
      expect(described_class.kinds).to eq(described_class::KIND_VALUES.stringify_keys)
      expect(described_class.kinds.keys).to contain_exactly("contract", "crz_export", "annex", "other")
    end

    it "defines a predicate, a bang setter and both scopes for every kind" do
      described_class::KINDS.each do |kind|
        expect(described_class.method_defined?(:"#{kind}?")).to be(true)
        expect(described_class.method_defined?(:"#{kind}!")).to be(true)
        expect(described_class.respond_to?(kind)).to be(true)
        expect(described_class.respond_to?(:"not_#{kind}")).to be(true)
      end
    end

    # The "contract" default itself is behaviour: the migration spec pins the
    # column default structurally, and the :db group exercises it on a live
    # schema (Model.new needs the schema in Rails 7.2, so it cannot run here).
  end

  describe "database behaviour", :db do
    before do
      migrate_engine_schema!
      # Since M02-05-A0 (#73) a document destroy cascades into its
      # ActiveStorage attachment (contract destroy included), so this group
      # needs the host-owned storage tables too.
    end

    let(:contract) do
      Decidim::ContractsSk::Contract.create!(contract_attributes)
    end

    def document_attributes(overrides = {})
      {
        contract: contract,
        title: "Signed contract scan"
      }.merge(overrides)
    end

    it "defaults the kind to contract on new and persisted records" do
      document = described_class.new(document_attributes)

      expect(document.kind).to eq("contract")

      document.save!
      expect(document.reload.kind).to eq("contract")
    end

    it "persists a document attached to a real contract" do
      document = described_class.create!(document_attributes(kind: "annex", file_name: "priloha-1.pdf"))

      expect(document).to be_persisted
      expect(document.reload.contract).to eq(contract)
      expect(document.reload).to be_annex
    end

    it "raises InvalidForeignKey when the contract reference points nowhere" do
      # Bypasses the belongs_to presence validation: this example exists to
      # pin the DB-level FK constraint onto the contracts table.
      expect do
        described_class.new(title: "Orphan scan", contract_id: 987_654).save!(validate: false)
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "raises NotNullViolation when title is written as NULL below the validation layer" do
      expect do
        described_class.new(document_attributes(title: nil)).save!(validate: false)
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "destroys documents with their contract" do
      document = described_class.create!(document_attributes)

      contract.destroy

      expect(described_class.exists?(document.id)).to be(false)
    end

    it "raises ArgumentError when an unknown value is assigned through the enum layer" do
      document = described_class.new(document_attributes)

      # Rails 7.2 enums validate at assignment, so bogus input never even
      # reaches the model's inclusion validation.
      expect { document.kind = "bogus" }.to raise_error(ArgumentError)
    end

    it "is invalid when the column holds a kind no enum assignment could produce" do
      # The inclusion validator's real job: guarding against DB corruption.
      # A raw SQL write bypasses the enum; on read the unknown string
      # deserializes to nil, and presence + inclusion invalidate the record.
      document = described_class.create!(document_attributes)
      ActiveRecord::Base.connection.execute(
        "UPDATE decidim_contracts_sk_documents SET kind = 'bogus' WHERE id = #{document.id}"
      )

      expect(document.reload.kind).to be_nil
      expect(document).not_to be_valid
      expect(document.errors[:kind]).to be_present
    end
  end

  # Blob-backed behaviour (civora-org/civora-platform#73): real uploads
  # against the ActiveStorage tables a host app owns, built here from the
  # pinned gem's own migration; the Disk service root is wiped per example.
  # Synthetic PDF-shaped bytes only — no real content, no PII.
  describe "file attachment behaviour (civora-org/civora-platform#73)", :db do
    before do
      migrate_engine_schema!
      FileUtils.rm_rf(active_storage_root)
    end

    let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

    def document_attributes(overrides = {})
      {
        contract: contract,
        title: "Signed contract scan"
      }.merge(overrides)
    end

    def sample_fixture(name)
      File.join(engine_root, "spec", "fixtures", "files", name)
    end

    def upload(name, content_type)
      Rack::Test::UploadedFile.new(sample_fixture(name), content_type)
    end

    # A real file on disk whose NAME is the hostile part (POSIX-legal, so no
    # fixture file is committed with a hostile name); the directory is left
    # to the OS temp cleaner — the upload reads lazily from the path.
    def hostile_upload(name, content_type: "application/pdf")
      path = File.join(Dir.mktmpdir, name)
      File.binwrite(path, "%PDF-hostile")
      Rack::Test::UploadedFile.new(path, content_type)
    end

    it "attaches a file and syncs the metadata columns from the blob" do
      document = described_class.create!(document_attributes(kind: "contract"))

      document.attach_file!(upload("sample.pdf", "application/pdf"))

      blob = document.file.reload.blob
      aggregate_failures do
        expect(document.file).to be_attached
        expect(document.reload.file_name).to eq("sample.pdf")
        expect(document.reload.content_type).to eq("application/pdf")
        expect(document.reload.file_size).to eq(File.size(sample_fixture("sample.pdf")))
        expect(document.reload.file_size).to eq(blob.byte_size)
      end
    end

    it "sniffs the content type from the bytes when the client sends a generic type" do
      document = described_class.create!(document_attributes)

      document.attach_file!(upload("sample.pdf", "application/octet-stream"))

      expect(document.reload.content_type).to eq("application/pdf")
    end

    it "persists a sanitized file_name for a hostile upload name (civora-org/civora-platform#64)" do
      document = described_class.create!(document_attributes)

      document.attach_file!(hostile_upload("zmluva č. 4.pdf"))

      expect(document.reload.file_name).to eq("zmluva.4.pdf")
    end

    it "strips control characters ActiveStorage leaves in place (civora-org/civora-platform#64)" do
      document = described_class.create!(document_attributes)

      document.attach_file!(hostile_upload("na\u0001me.pdf"))

      expect(document.reload.file_name).to eq("name.pdf")
    end

    it "replaces the file and re-syncs the metadata columns from the new blob" do
      document = described_class.create!(document_attributes)
      document.attach_file!(upload("sample.pdf", "application/pdf"))

      document.attach_file!(upload("sample-notes.txt", "text/plain"))

      aggregate_failures do
        expect(document.reload.file_name).to eq("sample-notes.txt")
        expect(document.reload.content_type).to eq("text/plain")
        expect(document.reload.file_size).to eq(File.size(sample_fixture("sample-notes.txt")))
        # Exactly one attachment survives the replace, pointing at the new
        # blob — the old attachment row is destroyed with the swap.
        attachments = ActiveStorage::Attachment.where(record: document, name: "file")

        expect(attachments.count).to eq(1)
        expect(attachments.sole.blob_id).to eq(document.file.reload.blob.id)
      end
    end

    it "refuses to attach a blank file" do
      document = described_class.create!(document_attributes)

      expect { document.attach_file!(nil) }.to raise_error(ArgumentError)

      expect(document.reload.file).not_to be_attached
      expect(document.reload.file_name).to be_nil
    end

    it "destroys the attachment row with the document" do
      document = described_class.create!(document_attributes)
      document.attach_file!(upload("sample.pdf", "application/pdf"))
      attachment_id = document.file_attachment.id

      document.destroy!

      aggregate_failures do
        expect(ActiveStorage::Attachment.exists?(attachment_id)).to be(false)
        expect(described_class.exists?(document.id)).to be(false)
      end
    end

    it "destroys documents (and their attachments) with the contract" do
      document = described_class.create!(document_attributes)
      document.attach_file!(upload("sample.pdf", "application/pdf"))

      contract.destroy!

      aggregate_failures do
        expect(described_class.exists?(document.id)).to be(false)
        expect(ActiveStorage::Attachment.exists?(document.file_attachment.id)).to be(false)
      end
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
