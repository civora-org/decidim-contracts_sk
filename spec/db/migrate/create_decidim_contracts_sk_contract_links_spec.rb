# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the engine's contract links
# migration (M01-87, civora-org/civora-platform#87).
#
# The default run asserts the migration as text only — the suite must stay
# DB-less, so the file is never executed. The regexes are deliberately
# tolerant about option order and whitespace while pinning the semantics
# that matter: nullability, the real FK onto the contracts table, the
# polymorphic target with no FK (AuditEvent precedent), the suppressed
# single-column indexes, the unique composite index under its explicit
# engine-convention name, and reversibility (single `def change`, no
# `execute`, no `def up`/`def down`).
#
# The :db-tagged group additionally runs the migration up -> down -> up
# against an in-memory SQLite adapter. It stays excluded from the default
# run (see spec_helper.rb); opting in via CONTRACTS_SK_DB=1 requires the
# sqlite3 gem, and the group skips with a clear message when it is absent.
# ---------------------------------------------------------------------------

require "spec_helper"

# Several structural examples deliberately hold several related expectations
# (per-column semantics) and exceed the default example-length budget.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe "db/migrate/*_create_decidim_contracts_sk_contract_links.rb" do
  subject(:migration_source) { File.read(migration_path) }

  # Fixed engine locations/identifiers as plain methods: they describe the
  # file surface, not per-example state, and keep the memoized-helper budget
  # for the specs that need it. (engine_root comes from the shared
  # "contracts_sk db support" context in spec/support/.)
  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_contract_links.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "CreateDecidimContractsSkContractLinks"
  end

  def table_name
    :decidim_contracts_sk_contract_links
  end

  # First migration line declaring a column of the given kind for `name`.
  # Tolerant about option order/whitespace so option reordering stays green;
  # the assertions below pin the semantics, not the formatting.
  def column_line(name)
    migration_source
      .lines
      .map(&:strip)
      .find { |line| line.match?(/\At\.(?:references|string|datetime)\s+:#{name}\b/) }
  end

  # The add_index line covering the given columns (in order), tolerant about
  # symbol-array spelling ([:a, :b] vs %i[a b]).
  def add_index_line(*columns)
    pattern = columns.map { |column| Regexp.escape(column.to_s) }.join(".*")
    migration_source.lines.map(&:strip).find do |line|
      line.match?(/\Aadd_index\s+:#{table_name}.*#{pattern}/)
    end
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
        target
      ].each do |column|
        expect(column_line(column)).to be_present, "missing column :#{column}"
      end

      expect(migration_source.lines.map(&:strip)).to include(match(/\At\.timestamps\b/))
    end

    it "makes the contract reference NOT NULL and suppresses its single-column index" do
      # The unique composite (contract_id, target_type, target_id) index
      # covers plain contract_id lookups, so the default index on the
      # references line is redundant.
      expect(column_line(:contract))
        .to match(/\At\.references\s+:contract,\s*null:\s*false,\s*index:\s*false/)
    end

    it "puts a real FK on the contract reference, targeting the contracts table" do
      expect(migration_source)
        .to match(/foreign_key:\s*\{\s*to_table:\s*:decidim_contracts_sk_contracts\s*\}/)
    end

    it "makes the target a NOT NULL polymorphic reference with no index of its own" do
      # Scans the whole source: the polymorphic and index options may wrap to
      # their own lines under the references declaration. The target carries
      # no FK on purpose (the AuditEvent precedent) and no single-column
      # index — the composite unique index covers the engine's lookups.
      expect(column_line(:target)).to match(/\At\.references\s+:target,/)
      expect(migration_source).to match(/polymorphic:\s*true/)
      expect(column_line(:target)).to match(/null:\s*false/)
      expect(column_line(:target)).to match(/index:\s*false/)
      expect(migration_source).not_to match(/foreign_key:\s*\{\s*to_table:\s*:target/)
    end
  end

  describe "indexes" do
    it "uniquely indexes (contract_id, target_type, target_id) under an explicit name" do
      # The columns sit on the add_index line; the unique flag may wrap to a
      # continuation line, so it is asserted against the whole source.
      expect(add_index_line(:contract_id, :target_type, :target_id)).to be_present
      expect(migration_source).to match(/unique:\s*true/)
      expect(explicit_index_names)
        .to include("idx_contracts_sk_contract_links_on_contract_and_target")
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

    it "migrates up, down, and up again with the expected columns, FK and unique index" do
      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be(true)

      by_name = ActiveRecord::Base.connection.columns(table_name).index_by(&:name)
      expect(by_name.keys).to contain_exactly(
        "id", "contract_id", "target_type", "target_id", "created_at", "updated_at"
      )

      # The polymorphic reference derives the type column as a string — the
      # structural regex above cannot prove the derived type.
      expect(by_name["target_type"].type).to eq(:string)

      %w[contract_id target_type target_id].each do |name|
        expect(by_name[name].null).to be(false), "#{name} must be NOT NULL"
      end

      # Exactly one FK: the contract. The polymorphic target deliberately
      # carries none (a link may dangle after its target's deletion).
      foreign_keys = ActiveRecord::Base.connection.foreign_keys(table_name)
      expect(foreign_keys.map(&:to_table)).to contain_exactly("decidim_contracts_sk_contracts")

      indexes = ActiveRecord::Base.connection.indexes(table_name)
      expect(indexes.map(&:name)).to contain_exactly(
        "idx_contracts_sk_contract_links_on_contract_and_target"
      )

      composite = indexes.find do |index|
        index.name == "idx_contracts_sk_contract_links_on_contract_and_target"
      end
      expect(composite.columns).to eq(%w[contract_id target_type target_id])
      expect(composite.unique).to be(true)

      migration_class.migrate(:down)
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be(false)

      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be(true)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
