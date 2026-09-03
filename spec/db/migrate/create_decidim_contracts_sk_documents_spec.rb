# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the engine's documents
# migration (M02-02-B, civora-org/civora-platform#56).
#
# The default run asserts the migration as text only — the suite must stay
# DB-less, so the file is never executed. The regexes are deliberately
# tolerant about option order and whitespace while pinning the semantics
# that matter: nullability, defaults, the real FK onto the contracts table,
# the explicit index name, and reversibility (single `def change`, no
# `execute`, no `def up`/`def down`).
#
# The :db-tagged group additionally runs the migration up -> down -> up
# against an in-memory SQLite adapter. It stays excluded from the default
# run (see spec_helper.rb); opting in via CONTRACTS_SK_DB=1 requires the
# sqlite3 gem, and the group skips with a clear message when it is absent.
# ---------------------------------------------------------------------------

require "spec_helper"

require "active_record"
require "active_support/core_ext/string/inflections"

# Several structural examples deliberately hold several related expectations
# (per-column semantics) and exceed the default example-length budget.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe "db/migrate/*_create_decidim_contracts_sk_documents.rb" do
  subject(:migration_source) { File.read(migration_path) }

  # Fixed engine locations/identifiers as plain methods: they describe the
  # file surface, not per-example state, and keep the memoized-helper budget
  # for the specs that need it.
  def engine_root
    File.expand_path("../../..", __dir__)
  end

  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_documents.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "CreateDecidimContractsSkDocuments"
  end

  def table_name
    :decidim_contracts_sk_documents
  end

  # First migration line declaring a column of the given kind for `name`.
  # Tolerant about option order/whitespace so option reordering stays green;
  # the assertions below pin the semantics, not the formatting.
  def column_line(name)
    migration_source
      .lines
      .map(&:strip)
      .find { |line| line.match?(/\At\.(?:references|string|datetime|integer)\s+:#{name}\b/) }
  end

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
    it "declares the table with all expected columns" do
      expect(migration_source).to match(/create_table\s+:#{table_name}\b/)

      %i[
        contract
        title
        kind
        file_name
        content_type
        file_size
      ].each do |column|
        expect(column_line(column)).to be_present, "missing column :#{column}"
      end

      expect(migration_source.lines.map(&:strip)).to include(match(/\At\.timestamps\b/))
    end

    it "makes the contract reference NOT NULL with a real FK to the contracts table" do
      expect(column_line(:contract)).to match(/\At\.references\s+:contract,\s*null:\s*false/)
      expect(migration_source)
        .to match(/foreign_key:\s*\{\s*to_table:\s*:decidim_contracts_sk_contracts\s*\}/)
    end

    it "makes title NOT NULL" do
      expect(column_line(:title)).to match(/\At\.string\s+:title,\s*null:\s*false\s*$/)
    end

    it "pins kind as NOT NULL defaulting to contract" do
      expect(column_line(:kind)).to match(/\At\.string\s+:kind,/)
      expect(column_line(:kind)).to match(/null:\s*false/)
      expect(column_line(:kind)).to match(/default:\s*"contract"/)
    end

    it "keeps the file metadata columns nullable" do
      # Metadata only: validated upload handling arrives with M02-05-A.
      expect(column_line(:file_name)).to match(/\At\.string\s+:file_name\s*$/)
      expect(column_line(:content_type)).to match(/\At\.string\s+:content_type\s*$/)
      expect(column_line(:file_size)).to match(/\At\.integer\s+:file_size\s*$/)
    end
  end

  describe "indexes" do
    it "indexes the contract reference under an explicit name" do
      # Scans the whole source: the index option may wrap to its own line
      # under the references declaration.
      expect(migration_source)
        .to match(/index:\s*\{\s*name:\s*"idx_contracts_sk_documents_on_contract_id"\s*\}/)
      expect(explicit_index_names)
        .to include("idx_contracts_sk_documents_on_contract_id")
    end

    it "keeps every explicit index name within PostgreSQL's 63-byte limit" do
      expect(explicit_index_names).not_to be_empty

      explicit_index_names.each do |name|
        expect(name.length).to be <= 63, "index name exceeds 63 bytes: #{name}"
      end
    end
  end

  describe "reversibility proxy" do
    it "uses no raw SQL" do
      expect(migration_source).not_to match(/\bexecute\(/)
    end

    it "relies only on DSL that ActiveRecord can reverse" do
      migration_source.scan(/t\.\w+|add_index|create_table/).each do |call|
        expect(call).not_to match(/remove_|rename_/), "non-reversible-looking call: #{call}"
      end
    end
  end

  describe "runnable migration", :db do
    let(:migration_class) do
      require migration_path
      Object.const_get(migration_class_name)
    end

    before do
      begin
        require "sqlite3"
      rescue LoadError
        skip "sqlite3 gem is not available; add it locally to run the CONTRACTS_SK_DB=1 group"
      end

      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    end

    after do
      # Leave the shared process clean: the example above ends with the
      # table migrated up, and this spec file can run after other :db
      # groups (or share its pooled :memory: connection with them). Drop
      # the table and cut the connection so a later group's migrate(:up)
      # starts from an empty schema instead of "table already exists".
      if ActiveRecord::Base.connected?
        connection = ActiveRecord::Base.connection
        connection.drop_table(table_name) if connection.table_exists?(table_name)
        ActiveRecord::Base.connection_pool.disconnect!
      end
    end

    it "migrates up, down, and up again with the expected columns and the contracts FK" do
      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be(true)

      by_name = ActiveRecord::Base.connection.columns(table_name).index_by(&:name)
      expect(by_name.keys).to contain_exactly(
        "id", "contract_id", "title", "kind", "file_name", "content_type", "file_size", "created_at", "updated_at"
      )

      expect(by_name["kind"].null).to be(false)
      expect(by_name["kind"].default).to eq("contract")

      %w[contract_id title].each do |name|
        expect(by_name[name].null).to be(false), "#{name} must be NOT NULL"
      end

      %w[file_name content_type file_size].each do |name|
        expect(by_name[name].null).to be(true), "#{name} must be nullable"
      end

      foreign_keys = ActiveRecord::Base.connection.foreign_keys(table_name)
      contract_fk = foreign_keys.find { |fk| fk.from_table.to_s == table_name.to_s }
      expect(contract_fk).to be_present, "contract_id must carry a real FK constraint"
      expect(contract_fk.to_table).to eq("decidim_contracts_sk_contracts")

      migration_class.migrate(:down)
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be(false)

      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be(true)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
