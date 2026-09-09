# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the import-provenance
# hardening migration (civora-org/civora-platform#85), mirroring the pattern
# of the create-table migration specs in this directory.
#
# The default run asserts the migration as text only — the suite must stay
# DB-less, so the file is never executed. The regexes pin the semantics that
# matter: the nullable checksum column, the composite (organization, source,
# source_id) index under its explicit 63-byte-safe name, and single
# `def change` reversibility.
#
# The :db-tagged group runs the migration up -> down -> up against the
# base contracts table on an in-memory SQLite adapter. It stays excluded
# from the default run (see spec_helper.rb); opting in via CONTRACTS_SK_DB=1
# requires the sqlite3 gem, and the group skips with a clear message when it
# is absent.
#
# Seeding note: the row is inserted with raw SQL on purpose (the
# content-fields spec precedent) — the model's current validations exceed
# the columns this example's migrations create, so a model-level insert
# would couple the test to migrations it does not run.
# ---------------------------------------------------------------------------

require "spec_helper"

# Several structural examples deliberately hold several related expectations
# (per-column semantics) and exceed the default example-length budget.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe "db/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb" do
  subject(:migration_source) { File.read(migration_path) }

  # Fixed engine locations/identifiers as plain methods: they describe the
  # file surface, not per-example state. (engine_root comes from the shared
  # "contracts_sk db support" context in spec/support/.)
  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate", "*_add_import_provenance_to_decidim_contracts_sk_contracts.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "AddImportProvenanceToDecidimContractsSkContracts"
  end

  def base_migration_path
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_contracts.rb")).first
  end

  def table_name
    :decidim_contracts_sk_contracts
  end

  # First migration line declaring the given column, tolerant about option
  # order/whitespace so option reordering stays green; the assertions below
  # pin the semantics, not the formatting.
  def column_line(name)
    migration_source
      .lines
      .map(&:strip)
      .find { |line| line.match?(/\Aadd_column\s+:#{table_name},\s+:#{name}\b/) }
  end

  # The add_index line covering the given columns (in order), tolerant about
  # symbol-array spelling ([:a, :b] vs %i[a b]).
  def add_index_line(*columns)
    pattern = columns.map { |column| Regexp.escape(column.to_s) }.join(".*")
    migration_source.lines.map(&:strip).find do |line|
      line.match?(/\Aadd_index\s+:#{table_name}.*#{pattern}/)
    end
  end

  # Explicit index names across the whole source: the name option may sit on
  # a wrapped continuation line, so it cannot be pinned to the add_index
  # line itself.
  def explicit_index_names
    migration_source.scan(/name:\s*"([^"]+)"/).flatten
  end

  describe "file surface" do
    it "has exactly one matching migration file" do
      expect(migration_files.size).to eq(1)
    end

    it "keeps the class name in sync with the file name" do
      basename = File.basename(migration_path, ".rb")
      timestamp, snake_name = basename.split("_", 2)

      expect(timestamp).to match(/\A\d{14}\z/)
      expect(snake_name.camelize).to eq(migration_class_name)
      expect(migration_source).to match(/\A#\s+frozen_string_literal: true\s*$/)
    end
  end

  describe "class shape" do
    it "subclasses ActiveRecord::Migration[7.2]" do
      expect(migration_source)
        .to match(/class\s+#{migration_class_name}\s*<\s*ActiveRecord::Migration\[7\.2\]\s*$/)
    end

    it "defines exactly one `def change` and no up/down split" do
      expect(migration_source.scan(/\bdef\s+change\b/).size).to eq(1)
      expect(migration_source).not_to match(/\bdef\s+up\b/)
      expect(migration_source).not_to match(/\bdef\s+down\b/)
    end
  end

  describe "columns" do
    it "adds the checksum column as a nullable string" do
      expect(column_line(:checksum)).to match(/\Aadd_column\s+:#{table_name},\s+:checksum,\s+:string\s*$/)
    end
  end

  describe "indexes" do
    it "indexes (organization, source, source_id) under an explicit name" do
      expect(add_index_line(:decidim_organization_id, :source, :source_id)).to be_present
      expect(explicit_index_names)
        .to include("idx_contracts_sk_contracts_on_organization_id_and_source_id")
    end

    it "keeps every explicit index name within PostgreSQL's 63-byte limit" do
      expect(explicit_index_names).not_to be_empty

      explicit_index_names.each do |name|
        expect(name.length).to be <= 63, "index name exceeds 63 bytes: #{name}"
      end
    end
  end

  describe "runnable migration", :db do
    let(:migration_class) do
      require migration_path
      Object.const_get(migration_class_name)
    end

    let(:base_migration_class) do
      require base_migration_path
      Object.const_get("CreateDecidimContractsSkContracts")
    end

    def column_by_name(name)
      ActiveRecord::Base.connection.columns(table_name).find { |column| column.name == name }
    end

    def index_by_name(name)
      ActiveRecord::Base.connection.indexes(table_name).find { |index| index.name == name }
    end

    # Raw-SQL seeding on purpose (see the file header): the model's current
    # validations exceed the columns this example's migrations create.
    def insert_contract(reference:)
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO decidim_contracts_sk_contracts
          (decidim_organization_id, decidim_author_id, title, reference, state,
           source, created_at, updated_at)
        VALUES
          (#{organization.id}, #{author.id}, 'Road reconstruction', '#{reference}',
           'draft', 'editorial', '2026-09-01 08:00:00.000000', '2026-09-01 08:00:00.000000')
      SQL
    end

    it "adds the checksum column and the composite index, and reverses cleanly" do
      base_migration_class.migrate(:up)
      insert_contract(reference: "ZP-2026-001")

      migration_class.migrate(:up)

      # Additive, no backfill: the pre-migration row reads checksum as nil.
      expect(Decidim::ContractsSk::Contract.find_by!(reference: "ZP-2026-001").checksum).to be_nil

      checksum = column_by_name("checksum")
      expect(checksum.type).to eq(:string)
      expect(checksum.null).to be(true)

      index = index_by_name("idx_contracts_sk_contracts_on_organization_id_and_source_id")
      expect(index.columns).to eq(%w[decidim_organization_id source source_id])

      migration_class.migrate(:down)
      expect(column_by_name("checksum")).to be_nil
      expect(index_by_name("idx_contracts_sk_contracts_on_organization_id_and_source_id")).to be_nil

      migration_class.migrate(:up)
      expect(column_by_name("checksum")).to be_present
      expect(index_by_name("idx_contracts_sk_contracts_on_organization_id_and_source_id")).to be_present
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
