# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the engine's first migration
# (M02-02-A, civora-org/civora-platform#55).
#
# The default run asserts the migration as text only — the suite must stay
# DB-less, so the file is never executed. The regexes are deliberately
# tolerant about option order and whitespace while pinning the semantics
# that matter: nullability, defaults, uniqueness, explicit index names, and
# reversibility (single `def change`, no `execute`, no `def up`/`def down`).
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

RSpec.describe "db/migrate/*_create_decidim_contracts_sk_contracts.rb" do
  subject(:migration_source) { File.read(migration_path) }

  # Fixed engine locations/identifiers as plain methods: they describe the
  # file surface, not per-example state, and keep the memoized-helper budget
  # for the specs that need it. (engine_root comes from the shared
  # "contracts_sk db support" context in spec/support/.)
  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_contracts.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "CreateDecidimContractsSkContracts"
  end

  def table_name
    :decidim_contracts_sk_contracts
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
        decidim_organization
        decidim_author
        title
        reference
        state
        source
        source_id
        imported_at
        import_status
      ].each do |column|
        expect(column_line(column)).to be_present, "missing column :#{column}"
      end

      expect(migration_source.lines.map(&:strip)).to include(match(/\At\.timestamps\b/))
    end

    it "makes the tenant and author references NOT NULL" do
      expect(column_line(:decidim_organization)).to match(/null:\s*false/)
      expect(column_line(:decidim_author)).to match(/null:\s*false/)
    end

    it "makes title and reference NOT NULL strings" do
      expect(column_line(:title)).to match(/\At\.string\s+:title,\s*null:\s*false\s*$/)
      expect(column_line(:reference)).to match(/\At\.string\s+:reference,\s*null:\s*false\s*$/)
    end

    it "pins state as NOT NULL defaulting to draft" do
      expect(column_line(:state)).to match(/\At\.string\s+:state,/)
      expect(column_line(:state)).to match(/null:\s*false/)
      expect(column_line(:state)).to match(/default:\s*"draft"/)
    end

    it "pins source as NOT NULL defaulting to editorial" do
      expect(column_line(:source)).to match(/\At\.string\s+:source,/)
      expect(column_line(:source)).to match(/null:\s*false/)
      expect(column_line(:source)).to match(/default:\s*"editorial"/)
    end

    it "keeps the provenance columns nullable" do
      expect(column_line(:source_id)).to match(/\At\.string\s+:source_id\s*$/)
      expect(column_line(:imported_at)).to match(/\At\.datetime\s+:imported_at\s*$/)
      expect(column_line(:import_status)).to match(/\At\.string\s+:import_status\s*$/)
    end
  end

  describe "indexes" do
    it "indexes the organization reference under an explicit name" do
      expect(column_line(:decidim_organization))
        .to match(/index:\s*\{\s*name:\s*"idx_contracts_sk_contracts_on_organization_id"\s*\}/)
    end

    it "indexes the author reference" do
      expect(column_line(:decidim_author)).to match(/index:\s*true/)
    end

    it "uniquely indexes (organization, reference) under an explicit name" do
      expect(add_index_line(:decidim_organization_id, :reference)).to be_present
      expect(migration_source).to match(/unique:\s*true/)
      expect(explicit_index_names)
        .to include("idx_contracts_sk_contracts_on_organization_id_and_reference")
    end

    it "indexes (organization, state) under an explicit name" do
      expect(add_index_line(:decidim_organization_id, :state)).to be_present
      expect(explicit_index_names)
        .to include("idx_contracts_sk_contracts_on_organization_id_and_state")
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

    it "migrates up, down, and up again with the expected columns" do
      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be(true)

      by_name = ActiveRecord::Base.connection.columns(table_name).index_by(&:name)
      expect(by_name.keys).to contain_exactly(
        "id", "decidim_organization_id", "decidim_author_id", "title", "reference",
        "state", "source", "source_id", "imported_at", "import_status", "created_at", "updated_at"
      )

      expect(by_name["state"].null).to be(false)
      expect(by_name["state"].default).to eq("draft")
      expect(by_name["source"].null).to be(false)
      expect(by_name["source"].default).to eq("editorial")

      %w[decidim_organization_id decidim_author_id title reference].each do |name|
        expect(by_name[name].null).to be(false), "#{name} must be NOT NULL"
      end

      %w[source_id imported_at import_status].each do |name|
        expect(by_name[name].null).to be(true), "#{name} must be nullable"
      end

      migration_class.migrate(:down)
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be(false)

      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(table_name)).to be(true)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
