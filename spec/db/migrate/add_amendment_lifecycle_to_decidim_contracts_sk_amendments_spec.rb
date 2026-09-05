# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the amendment lifecycle
# migration (M02-05-B, civora-org/civora-platform#65), mirroring the
# pattern of the content-fields migration spec in this directory.
#
# The default run asserts the migration as text only — the suite must stay
# DB-less, so the file is never executed. The regexes pin the semantics
# that matter: the five additive columns, the state NOT NULL + "draft"
# default (the correct semantic for pre-lifecycle rows — nothing was
# published before #65), the nullable system/tenancy/snapshot columns, the
# real FKs onto organizations/users, and single `def change`
# reversibility.
#
# The :db-tagged group runs the migration against seeded pre-migration rows
# on an in-memory SQLite adapter (up -> down -> up, plus the column default
# applied to existing rows). It stays excluded from the default run (see
# spec_helper.rb); opting in via CONTRACTS_SK_DB=1 requires the sqlite3
# gem, and the group skips with a clear message when it is absent.
#
# Seeding note: the row is inserted with raw SQL on purpose (the
# content-fields spec's rationale): the migration must work against
# arbitrary pre-existing rows, and a model-level insert would couple the
# test to the CURRENT model validations (which include the very columns
# the migration has not added yet).
# ---------------------------------------------------------------------------

require "spec_helper"

# Several structural examples deliberately hold several related expectations
# (per-column semantics) and the raw-SQL seeders span heredoc lines, exceeding
# the default budgets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, Metrics/MethodLength

RSpec.describe "db/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb" do
  subject(:migration_source) { File.read(migration_path) }

  # Fixed engine locations/identifiers as plain methods: they describe the
  # file surface, not per-example state. (engine_root comes from the shared
  # "contracts_sk db support" context in spec/support/.)
  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate",
                       "*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "AddAmendmentLifecycleToDecidimContractsSkAmendments"
  end

  def base_migration_path
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_amendments.rb")).first
  end

  def table_name
    :decidim_contracts_sk_amendments
  end

  # First migration line adding the given column, tolerant about option
  # order/whitespace so option reordering stays green; the assertions below
  # pin the semantics, not the formatting.
  def column_line(name)
    migration_source
      .lines
      .map(&:strip)
      .find { |line| line.match?(/\Aadd_column\s+:#{table_name},\s+:#{name}\b/) }
  end

  # The FULL add_reference declaration for the given reference: the call
  # spans multiple lines (type/foreign_key/index options), so the block is
  # joined from its first line up to (and including) the line that closes
  # the call (the first not ending in a trailing comma).
  def reference_block(name)
    lines = migration_source.lines.map(&:strip)
    start = lines.index { |line| line.match?(/\Aadd_reference\s+:#{table_name},\s+:#{name},/) }
    return "" unless start

    block = []
    lines[start..].each do |line|
      block << line
      break unless line.end_with?(",")
    end
    block.join(" ")
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
    it "adds exactly the five lifecycle columns" do
      %i[
        state
        published_at
        content_snapshot
      ].each do |column|
        expect(column_line(column)).to be_present, "missing add_column for :#{column}"
      end

      %i[decidim_organization decidim_author].each do |reference|
        expect(reference_block(reference)).to be_present, "missing add_reference for :#{reference}"
      end
    end

    it "pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)" do
      expect(column_line(:state)).to match(/:string/)
      expect(column_line(:state)).to match(/null:\s*false/)
      expect(column_line(:state)).to match(/default:\s*"draft"/)
    end

    it "keeps the system, tenancy and snapshot columns nullable" do
      expect(column_line(:published_at)).to match(/:datetime\s*$/)
      expect(column_line(:content_snapshot)).to match(/:json\s*$/)
      expect(reference_block(:decidim_organization)).not_to match(/null:\s*false/)
      expect(reference_block(:decidim_author)).not_to match(/null:\s*false/)
    end

    it "puts real FKs on the tenancy and actor references" do
      expect(reference_block(:decidim_organization))
        .to match(/foreign_key:\s*\{\s*to_table:\s*:decidim_organizations\s*\}/)
      expect(reference_block(:decidim_author))
        .to match(/foreign_key:\s*\{\s*to_table:\s*:decidim_users\s*\}/)
    end

    it "keeps every explicit index name within PostgreSQL's 63-byte limit" do
      names = migration_source.scan(/name:\s*"([^"]+)"/).flatten

      expect(names).to include("idx_contracts_sk_amendments_on_organization_id")
      names.each { |name| expect(name.length).to be <= 63, "index name exceeds 63 bytes: #{name}" }
    end
  end

  describe "reversibility proxy" do
    it "uses no raw SQL" do
      expect(migration_source).not_to match(/\bexecute\(/)
    end
  end

  describe "runnable migration", :db do
    let(:migration_class) do
      require migration_path
      Object.const_get(migration_class_name)
    end

    let(:base_migration_class) do
      require base_migration_path
      Object.const_get("CreateDecidimContractsSkAmendments")
    end

    def column_names
      ActiveRecord::Base.connection.columns(table_name).map(&:name)
    end

    def column_by_name(name)
      ActiveRecord::Base.connection.columns(table_name).find { |column| column.name == name }
    end

    # Raw-SQL seeding on purpose (see the file header): the contract row is
    # inserted while the contracts table still has only its BASE columns —
    # instantiating the model here would couple the test to the CURRENT
    # model attribute set (which includes the content columns this example
    # deliberately does not migrate).
    def insert_contract!
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO decidim_contracts_sk_contracts
          (decidim_organization_id, decidim_author_id, title, reference, state,
           source, created_at, updated_at)
        VALUES
          (#{organization.id}, #{author.id}, 'Road reconstruction', 'ZP-2026-001',
           'draft', 'editorial', '2026-09-01 08:00:00.000000', '2026-09-01 08:00:00.000000')
      SQL
      ActiveRecord::Base.connection.select_value(
        "SELECT id FROM decidim_contracts_sk_contracts ORDER BY id DESC LIMIT 1"
      )
    end

    # Raw-SQL seeding on purpose (see the file header): a pre-migration row
    # with deterministic timestamps.
    def insert_amendment!(contract_id)
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO decidim_contracts_sk_amendments
          (contract_id, version, summary, created_at, updated_at)
        VALUES
          (#{contract_id}, 1, 'Pre-lifecycle revision', '2026-09-01 08:00:00.000000', '2026-09-01 08:00:00.000000')
      SQL
    end

    it "adds the columns, defaults pre-lifecycle rows to draft, and reverses cleanly" do
      # The amendments table's FK targets the contracts table: build the
      # base the same way the content-fields spec does — run the real
      # contracts migration first, then the amendments one.
      contracts_path = Dir.glob(File.join(engine_root, "db", "migrate",
                                          "*_create_decidim_contracts_sk_contracts.rb")).first
      require contracts_path
      Object.const_get("CreateDecidimContractsSkContracts").migrate(:up)
      base_migration_class.migrate(:up)

      contract_id = insert_contract!
      insert_amendment!(contract_id)

      migration_class.migrate(:up)

      amendment = Decidim::ContractsSk::Amendment.find_by!(contract_id: contract_id)

      # The state default applies to pre-migration rows too — the correct
      # semantic: nothing was ever published before #65.
      expect(amendment.reload.state).to eq("draft")
      expect(amendment.published_at).to be_nil
      expect(amendment.content_snapshot).to be_nil
      expect(amendment.decidim_organization_id).to be_nil
      expect(amendment.decidim_author_id).to be_nil

      expect(column_by_name("state").type).to eq(:string)
      expect(column_by_name("state").null).to be(false)
      expect(column_by_name("state").default).to eq("draft")
      expect(column_by_name("published_at").type).to eq(:datetime)
      expect(column_by_name("content_snapshot").type).to eq(:json)
      %w[decidim_organization_id decidim_author_id].each do |name|
        expect(column_by_name(name).type).to eq(:integer)
        expect(column_by_name(name).null).to be(true), "#{name} must be nullable"
      end

      foreign_keys = ActiveRecord::Base.connection.foreign_keys(table_name)
      expect(foreign_keys.map(&:to_table)).to contain_exactly(
        "decidim_contracts_sk_contracts", "decidim_organizations", "decidim_users"
      )

      migration_class.migrate(:down)
      expect(column_names)
        .not_to include("state", "published_at", "decidim_organization_id", "decidim_author_id", "content_snapshot")

      migration_class.migrate(:up)
      expect(column_names).to include("state", "published_at", "decidim_organization_id", "decidim_author_id",
                                      "content_snapshot")
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, Metrics/MethodLength
