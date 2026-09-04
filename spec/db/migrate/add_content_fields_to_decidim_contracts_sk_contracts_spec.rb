# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the contract content fields
# migration (M02-02-D, civora-org/civora-platform#75), mirroring the
# pattern of the create-table migration specs in this directory.
#
# The default run asserts the migration as text only — the suite must stay
# DB-less, so the file is never executed. The regexes pin the semantics that
# matter: the seven additive columns, the amount precision/scale, the D1
# currency NOT NULL + "EUR" default, nullable content columns, single
# `def change` reversibility, and the D3 backfill living in the up arm of a
# reversible block.
#
# The :db-tagged group runs the migration against seeded pre-migration rows
# on an in-memory SQLite adapter (up -> down -> up, plus the D3 backfill and
# the column defaults applied to existing rows). It stays excluded from the
# default run (see spec_helper.rb); opting in via CONTRACTS_SK_DB=1 requires
# the sqlite3 gem, and the group skips with a clear message when it is
# absent.
#
# Seeding note: the rows are inserted with raw SQL on purpose. The migration
# must work against arbitrary pre-existing rows, and a model-level insert
# would couple the test to the CURRENT model validations (which include the
# currency column the migration has not added yet).
# ---------------------------------------------------------------------------

require "spec_helper"

# Several structural examples deliberately hold several related expectations
# (per-column semantics) and exceed the default example-length budget.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe "db/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb" do
  subject(:migration_source) { File.read(migration_path) }

  # Fixed engine locations/identifiers as plain methods: they describe the
  # file surface, not per-example state. (engine_root comes from the shared
  # "contracts_sk db support" context in spec/support/.)
  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate", "*_add_content_fields_to_decidim_contracts_sk_contracts.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "AddContentFieldsToDecidimContractsSkContracts"
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
    it "adds exactly the seven content columns" do
      %i[
        subject_matter
        amount
        currency
        signed_on
        effective_from
        published_at
        crz_url
      ].each do |column|
        expect(column_line(column)).to be_present, "missing add_column for :#{column}"
      end
    end

    it "pins the amount as decimal(12,2)" do
      expect(column_line(:amount)).to match(/:decimal/)
      expect(column_line(:amount)).to match(/precision:\s*12/)
      expect(column_line(:amount)).to match(/scale:\s*2/)
    end

    it "pins currency as NOT NULL defaulting to EUR (D1)" do
      expect(column_line(:currency)).to match(/:string/)
      expect(column_line(:currency)).to match(/limit:\s*3/)
      expect(column_line(:currency)).to match(/null:\s*false/)
      expect(column_line(:currency)).to match(/default:\s*"EUR"/)
    end

    it "keeps the remaining content columns nullable" do
      expect(column_line(:subject_matter)).to match(/:text\s*$/)
      expect(column_line(:signed_on)).to match(/:date\s*$/)
      expect(column_line(:effective_from)).to match(/:date\s*$/)
      expect(column_line(:published_at)).to match(/:datetime\s*$/)
      expect(column_line(:crz_url)).to match(/:string\s*$/)
    end
  end

  describe "published_at backfill (D3)" do
    it "backfills published rows from updated_at inside the up arm of a reversible block" do
      expect(migration_source).to match(/reversible do \|dir\|/)
      expect(migration_source).to match(/dir\.up do/)

      body = migration_source.lines.map(&:strip)
      expect(body).to include(match(/SET\s+published_at\s*=\s*updated_at/))
      expect(body).to include(match(/WHERE\s+state\s*=\s*'published'/))
    end

    it "guards the backfill against re-stamping (idempotent WHERE clause)" do
      expect(migration_source.lines.map(&:strip)).to include(match(/published_at IS NULL/))
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

    def column_names
      ActiveRecord::Base.connection.columns(table_name).map(&:name)
    end

    def column_by_name(name)
      ActiveRecord::Base.connection.columns(table_name).find { |column| column.name == name }
    end

    # Raw-SQL seeding on purpose (see the file header): the migration must
    # serve arbitrary pre-migration rows, with deterministic timestamps.
    def insert_contract(reference:, state:, updated_at:)
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO decidim_contracts_sk_contracts
          (decidim_organization_id, decidim_author_id, title, reference, state,
           source, created_at, updated_at)
        VALUES
          (#{organization.id}, #{author.id}, 'Road reconstruction', '#{reference}',
           '#{state}', 'editorial', '2026-09-01 08:00:00.000000', '#{updated_at}')
      SQL
    end

    it "adds the columns, backfills published rows, and reverses cleanly" do
      base_migration_class.migrate(:up)

      insert_contract(reference: "ZP-2026-001", state: "published", updated_at: "2026-09-02 12:30:00.000000")
      insert_contract(reference: "ZP-2026-002", state: "draft", updated_at: "2026-09-02 09:00:00.000000")

      migration_class.migrate(:up)

      published = Decidim::ContractsSk::Contract.find_by!(reference: "ZP-2026-001")
      draft = Decidim::ContractsSk::Contract.find_by!(reference: "ZP-2026-002")

      # D3 backfill: the published row carries its updated_at as the
      # publication stamp; the draft row stays unstamped.
      expect(published.reload.published_at).to eq(published.reload.updated_at)
      expect(draft.reload.published_at).to be_nil

      # The D1 default applies to pre-migration rows too.
      expect(published.currency).to eq("EUR")

      expect(column_by_name("subject_matter").type).to eq(:text)
      expect(column_by_name("amount").precision).to eq(12)
      expect(column_by_name("amount").scale).to eq(2)
      expect(column_by_name("currency").limit).to eq(3)
      expect(column_by_name("currency").null).to be(false)
      expect(column_by_name("currency").default).to eq("EUR")

      %w[subject_matter amount signed_on effective_from published_at crz_url].each do |name|
        expect(column_by_name(name).null).to be(true), "#{name} must be nullable"
      end

      migration_class.migrate(:down)
      expect(column_names)
        .not_to include(*%w[subject_matter amount currency signed_on effective_from published_at crz_url])

      migration_class.migrate(:up)
      expect(column_names).to include(*%w[subject_matter amount currency signed_on effective_from published_at crz_url])
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
