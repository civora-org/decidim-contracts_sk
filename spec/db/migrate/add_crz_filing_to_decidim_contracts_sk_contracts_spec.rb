# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic structural + :db specs for the CRZ filing-confirmation
# migration (civora-org/civora-platform#125), mirroring the review-decision
# migration spec: the default run reads the migration as text only; the
# :db group (CONTRACTS_SK_DB=1) runs up -> down -> up on in-memory SQLite.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "db/migrate/*_add_crz_filing_to_decidim_contracts_sk_contracts.rb" do
  subject(:migration_source) { File.read(migration_path) }

  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate",
                       "*_add_crz_filing_to_decidim_contracts_sk_contracts.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "AddCrzFilingToDecidimContractsSkContracts"
  end

  def base_migration_path
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_contracts.rb")).first
  end

  def table_name
    :decidim_contracts_sk_contracts
  end

  def stripped_lines
    migration_source.lines.map(&:strip)
  end

  def column_line(name)
    stripped_lines.find { |line| line.match?(/\Aadd_column\s+:#{table_name},\s+:#{name}\b/) }
  end

  describe "file surface and class shape" do
    it "has exactly one migration file whose class name matches" do
      expect(migration_files.size).to eq(1)
      timestamp, snake_name = File.basename(migration_path, ".rb").split("_", 2)

      expect(timestamp).to match(/\A\d{14}\z/)
      expect(snake_name.camelize).to eq(migration_class_name)
      expect(migration_source).to match(/\A#\s+frozen_string_literal: true\s*$/)
    end

    it "is a single reversible `def change` on ActiveRecord::Migration[7.2]" do
      expect(migration_source)
        .to match(/class\s+#{migration_class_name}\s*<\s*ActiveRecord::Migration\[7\.2\]\s*$/)
      expect(migration_source.scan(/\bdef\s+change\b/).size).to eq(1)
      expect(migration_source).not_to match(/\bdef\s+(up|down)\b/)
    end
  end

  describe "columns" do
    it "adds exactly the three nullable system columns, with no default, backfill or index" do
      expect(stripped_lines.grep(/\Aadd_column\s/).size).to eq(3)
      expect(column_line(:crz_filed_at)).to match(/:datetime\s*$/)
      expect(column_line(:crz_published_on)).to match(/:date\s*$/)
      expect(column_line(:crz_filing_reason)).to match(/:string,\s+limit:\s+1000\s*$/)
      expect(migration_source).not_to match(/\bdefault:/)
      expect(migration_source).not_to match(/\b(change_column_default|update_all|execute|add_index)\b/)
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

    it "adds the nullable columns, leaves existing rows unfiled and reverses cleanly" do
      base_migration_class.migrate(:up)
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO decidim_contracts_sk_contracts
          (decidim_organization_id, decidim_author_id, title, reference, state,
           source, created_at, updated_at)
        VALUES
          (#{organization.id}, #{author.id}, 'Road reconstruction', 'ZP-2026-001', 'draft',
           'editorial', '2026-09-01 08:00:00.000000', '2026-09-01 08:00:00.000000')
      SQL

      migration_class.migrate(:up)

      row = ActiveRecord::Base.connection.select_one("SELECT * FROM decidim_contracts_sk_contracts")
      expect(row.values_at("crz_filed_at", "crz_published_on", "crz_filing_reason")).to eq([nil, nil, nil])

      expect(column_by_name("crz_filed_at").type).to eq(:datetime)
      expect(column_by_name("crz_published_on").type).to eq(:date)
      expect(column_by_name("crz_filing_reason").limit).to eq(1000)
      %w[crz_filed_at crz_published_on crz_filing_reason].each do |name|
        expect(column_by_name(name).null).to be(true)
        expect(column_by_name(name).default).to be_nil
      end

      migration_class.migrate(:down)
      expect(%w[crz_filed_at crz_published_on crz_filing_reason].map { |n| column_by_name(n) }).to all(be_nil)

      migration_class.migrate(:up)
      expect(column_by_name("crz_filed_at")).to be_present
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
