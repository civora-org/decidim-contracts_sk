# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the reviewer-decision-reason
# migration (civora-org/civora-platform#90), mirroring the pattern of the
# add_redaction_confirmation migration spec in this directory.
#
# The default run asserts the migration as text only — the suite must stay
# DB-less, so the file is never executed. The regexes pin the semantics that
# matter: the two nullable columns (reason string capped at 1000, decision
# datetime), no index, no default, and single `def change` reversibility.
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

RSpec.describe "db/migrate/*_add_review_decision_to_decidim_contracts_sk_contracts.rb" do
  subject(:migration_source) { File.read(migration_path) }

  # Fixed engine locations/identifiers as plain methods: they describe the
  # file surface, not per-example state. (engine_root comes from the shared
  # "contracts_sk db support" context in spec/support/.)
  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate",
                       "*_add_review_decision_to_decidim_contracts_sk_contracts.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "AddReviewDecisionToDecidimContractsSkContracts"
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

  # Stripped source lines, so the assertions below can pin per-line shapes
  # the way column_line does (a whole-source match with \A anchors would be
  # vacuous against multi-line text).
  def stripped_lines
    migration_source.lines.map(&:strip)
  end

  describe "columns" do
    it "adds exactly the review_reason and reviewed_at columns" do
      expect(column_line(:review_reason)).to be_present
      expect(column_line(:reviewed_at)).to be_present
      expect(stripped_lines.grep(/\Aadd_column\s/).size).to eq(2)
    end

    it "adds review_reason as a plain nullable string capped at 1000 characters" do
      expect(column_line(:review_reason)).to match(
        /\Aadd_column\s+:#{table_name},\s+:review_reason,\s+:string,\s+limit:\s+1000\s*$/
      )
    end

    it "adds reviewed_at as a plain nullable datetime" do
      expect(column_line(:reviewed_at)).to match(
        /\Aadd_column\s+:#{table_name},\s+:reviewed_at,\s+:datetime\s*$/
      )
    end

    it "attaches no default and no backfill (a fabricated judgment would defeat the gate)" do
      expect(column_line(:review_reason)).not_to match(/default/i)
      expect(column_line(:reviewed_at)).not_to match(/default/i)
      expect(migration_source).not_to match(/\b(change_column_default|update_all|execute)\b/)
    end

    it "adds no index (the decision is read per-record, never queried as a set)" do
      expect(stripped_lines.grep(/\Aadd_index\s/)).to be_empty
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

    it "adds the nullable decision columns and reverses cleanly" do
      base_migration_class.migrate(:up)
      insert_contract(reference: "ZP-2026-001")

      migration_class.migrate(:up)

      # Additive, no backfill: the pre-migration row reads both decision
      # columns as nil — it carries no reviewer judgment.
      contract = Decidim::ContractsSk::Contract.find_by!(reference: "ZP-2026-001")
      aggregate_failures do
        expect(contract.review_reason).to be_nil
        expect(contract.reviewed_at).to be_nil
      end

      reason_column = column_by_name("review_reason")
      aggregate_failures do
        expect(reason_column.type).to eq(:string)
        expect(reason_column.limit).to eq(1000)
        expect(reason_column.null).to be(true)
        expect(reason_column.default).to be_nil
      end

      reviewed_at_column = column_by_name("reviewed_at")
      aggregate_failures do
        expect(reviewed_at_column.type).to eq(:datetime)
        expect(reviewed_at_column.null).to be(true)
        expect(reviewed_at_column.default).to be_nil
      end

      migration_class.migrate(:down)
      aggregate_failures do
        expect(column_by_name("review_reason")).to be_nil
        expect(column_by_name("reviewed_at")).to be_nil
      end

      migration_class.migrate(:up)
      aggregate_failures do
        expect(column_by_name("review_reason")).to be_present
        expect(column_by_name("reviewed_at")).to be_present
      end
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
