# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the source_id unique-index
# migration (civora-org/civora-platform#86 review fold-in), mirroring the
# pattern of the import-provenance migration spec in this directory.
#
# The default run asserts the migration as text only — the suite must stay
# DB-less, so the file is never executed. The :db-tagged group runs the
# migration up -> down -> up against the base contracts table on an
# in-memory SQLite adapter and pins the two behaviours that matter:
# the NULL exemption (editorial rows never collide) and the duplicate
# rejection (the create-race backstop).
# ---------------------------------------------------------------------------

require "spec_helper"

# Several structural examples deliberately hold several related expectations
# (per-column semantics) and exceed the default example-length budget.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe "db/migrate/*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb" do
  subject(:migration_source) { File.read(migration_path) }

  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate",
                       "*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "AddSourceIdUniqueIndexToDecidimContractsSkContracts"
  end

  def base_migration_path
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_contracts.rb")).first
  end

  def table_name
    :decidim_contracts_sk_contracts
  end

  def index_line
    migration_source.lines.map(&:strip).find do |line|
      line.match?(/\Aadd_index\s+:#{table_name}/)
    end
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
        .to match(/class\s+#{migration_class_name}\s+<\s+ActiveRecord::Migration\[7\.2\]\s*$/)
    end

    it "defines exactly one `def change` and no up/down split" do
      expect(migration_source.scan(/\bdef\s+change\b/).size).to eq(1)
      expect(migration_source).not_to match(/\bdef\s+up\b/)
      expect(migration_source).not_to match(/\bdef\s+down\b/)
    end
  end

  describe "index" do
    it "uniquely indexes (organization, source_id) under the explicit unique name" do
      expect(index_line).to be_present
      expect(migration_source).to match(/%i\[decidim_organization_id source_id\]/)
      expect(migration_source).to match(/name:\s*"idx_contracts_sk_contracts_on_org_and_source_id_unique"/)
      expect(migration_source).to match(/unique:\s*true/)
    end

    it "keeps the index name within PostgreSQL's 63-byte limit" do
      name = migration_source[/name:\s*"([^"]+)"/, 1]

      expect(name).to eq("idx_contracts_sk_contracts_on_org_and_source_id_unique")
      expect(name.length).to be <= 63
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

    def index_by_name(name)
      ActiveRecord::Base.connection.indexes(table_name).find { |index| index.name == name }
    end

    # Raw-SQL inserts on purpose (the import-provenance spec precedent):
    # this example runs only the base migration, whose columns predate the
    # model's current validations.
    def insert_contract(reference:, source_id:)
      null_marker = source_id.nil? ? "NULL" : "'#{source_id}'"

      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO decidim_contracts_sk_contracts
          (decidim_organization_id, decidim_author_id, title, reference, state,
           source, source_id, created_at, updated_at)
        VALUES
          (#{organization.id}, #{author.id}, 'Road reconstruction', '#{reference}',
           'draft', 'editorial', #{null_marker}, '2026-09-01 08:00:00.000000',
           '2026-09-01 08:00:00.000000')
      SQL
    end

    it "creates the unique index, exempts NULL source_ids and rejects duplicates" do
      base_migration_class.migrate(:up)
      insert_contract(reference: "ZP-2026-001", source_id: "2142424")
      # The NULL exemption: editorial rows never collide, no matter how many.
      insert_contract(reference: "ZP-2026-002", source_id: nil)
      insert_contract(reference: "ZP-2026-003", source_id: nil)

      migration_class.migrate(:up)

      index = index_by_name("idx_contracts_sk_contracts_on_org_and_source_id_unique")
      aggregate_failures do
        expect(index).to be_present
        expect(index.unique).to be(true)
        expect(index.columns).to eq(%w[decidim_organization_id source_id])
      end

      # The backstop: a second mirror row for the same (organization,
      # source_id) raises at the database level — the upsert command
      # translates this into the update/collision reroute.
      expect do
        insert_contract(reference: "ZP-2026-004", source_id: "2142424")
      end.to raise_error(ActiveRecord::RecordNotUnique)

      # Different organization, same source_id: legal (mirrors are
      # per-organization records).
      other_org = Decidim::Organization.create!
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO decidim_contracts_sk_contracts
          (decidim_organization_id, decidim_author_id, title, reference, state,
           source, source_id, created_at, updated_at)
        VALUES
          (#{other_org.id}, #{author.id}, 'Road reconstruction', 'ZP-2026-005',
           'draft', 'crz', '2142424', '2026-09-01 08:00:00.000000',
           '2026-09-01 08:00:00.000000')
      SQL

      migration_class.migrate(:down)
      expect(index_by_name("idx_contracts_sk_contracts_on_org_and_source_id_unique")).to be_nil

      migration_class.migrate(:up)
      expect(index_by_name("idx_contracts_sk_contracts_on_org_and_source_id_unique")).to be_present
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
