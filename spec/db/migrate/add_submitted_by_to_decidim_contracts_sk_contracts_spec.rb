# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic structural + :db specs for the four-eyes submitter-stamp
# migration (civora-org/civora-platform#123), mirroring the pattern of the
# add_review_decision migration spec in this directory.
#
# The default run asserts the migration as text only — the suite must stay
# DB-less, so the file is never executed. The regexes pin the semantics that
# matter: one nullable reference column named decidim_submitted_by_id, no
# index and no foreign key (the decidim_author_id precedent), the audit-trail
# backfill inside a reversible up direction, and single `def change`
# reversibility.
#
# The :db-tagged group runs the migration up -> down -> up against the
# contracts and audit tables on an in-memory SQLite adapter, and proves the
# backfill picks the actor of the MOST RECENT contract.submit audit row per
# contract. It stays excluded from the default run (see spec_helper.rb);
# opting in via CONTRACTS_SK_DB=1 requires the sqlite3 gem.
#
# Seeding note: rows are inserted with raw SQL on purpose (the precedent) —
# the model's current validations exceed the columns this example's
# migrations create.
# ---------------------------------------------------------------------------

require "spec_helper"

# Several examples deliberately hold several related expectations and exceed
# the default example-length budget.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe "db/migrate/*_add_submitted_by_to_decidim_contracts_sk_contracts.rb" do
  subject(:migration_source) { File.read(migration_path) }

  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate",
                       "*_add_submitted_by_to_decidim_contracts_sk_contracts.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "AddSubmittedByToDecidimContractsSkContracts"
  end

  def migration_path_for(suffix)
    Dir.glob(File.join(engine_root, "db", "migrate", "*_#{suffix}.rb")).first
  end

  def table_name
    :decidim_contracts_sk_contracts
  end

  def stripped_lines
    migration_source.lines.map(&:strip)
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

    it "sorts after every earlier engine migration" do
      timestamps = Dir.glob(File.join(engine_root, "db", "migrate", "*.rb"))
                      .map { |path| File.basename(path).split("_", 2).first }.sort

      expect(timestamps.last).to eq(File.basename(migration_path).split("_", 2).first)
    end
  end

  describe "class shape" do
    it "subclasses ActiveRecord::Migration[7.2]" do
      expect(migration_source)
        .to match(/class\s+#{migration_class_name}\s*<\s*ActiveRecord::Migration\[7\.2\]\s*$/)
    end

    it "defines exactly one `def change` and no up/down split at the method level" do
      expect(migration_source.scan(/\bdef\s+change\b/).size).to eq(1)
      expect(migration_source).not_to match(/\bdef\s+up\b/)
      expect(migration_source).not_to match(/\bdef\s+down\b/)
    end

    it "runs the backfill only in the up direction of a reversible block" do
      expect(migration_source).to match(/\breversible\s+do\s*\|dir\|/)
      expect(migration_source).to match(/\bdir\.up\s+do\b/)
      expect(migration_source).not_to match(/\bdir\.down\b/)
    end
  end

  describe "column" do
    it "adds exactly one nullable reference column, decidim_submitted_by" do
      references = stripped_lines.grep(/\Aadd_reference\s/)

      expect(references.size).to eq(1)
      expect(references.first).to match(/\Aadd_reference\s+:#{table_name},\s+:decidim_submitted_by\b/)
      expect(references.first).to match(/null:\s+true/)
      expect(stripped_lines.grep(/\Aadd_column\s/)).to be_empty
    end

    it "attaches no default and no foreign key (the decidim_author_id precedent)" do
      reference = stripped_lines.find { |line| line.start_with?("add_reference") }

      expect(reference).not_to match(/default/i)
      expect(reference).not_to match(/foreign_key/)
      expect(migration_source).not_to match(/\badd_foreign_key\b/)
    end

    it "adds no index (the stamp is read per-record, never queried as a set)" do
      reference = stripped_lines.find { |line| line.start_with?("add_reference") }

      expect(reference).to match(/index:\s+false/)
      expect(stripped_lines.grep(/\Aadd_index\s/)).to be_empty
    end
  end

  describe "backfill SQL" do
    it "reads the latest contract.submit audit row's actor per contract, deterministically" do
      sql = migration_source.gsub(/\s+/, " ")

      expect(sql).to include("SET decidim_submitted_by_id = (")
      expect(sql).to include("audit.action = 'contract.submit'")
      expect(sql).to include("audit.target_type = 'Decidim::ContractsSk::Contract'")
      expect(sql).to include("audit.target_id = decidim_contracts_sk_contracts.id")
      expect(sql).to include("ORDER BY audit.created_at DESC, audit.id DESC LIMIT 1")
      expect(sql).to match(/\) WHERE EXISTS \( SELECT 1 FROM decidim_contracts_sk_audit_events audit/)
    end
  end

  describe "runnable migration", :db do
    let(:migration_class) do
      require migration_path
      Object.const_get(migration_class_name)
    end

    def prerequisite_migrations!
      %w[create_decidim_contracts_sk_contracts create_decidim_contracts_sk_audit_events].each do |suffix|
        path = migration_path_for(suffix)
        require path
        Object.const_get(suffix.camelize).migrate(:up)
      end
    end

    def column_by_name(name)
      ActiveRecord::Base.connection.columns(table_name).find { |column| column.name == name }
    end

    def sql_value(sql)
      ActiveRecord::Base.connection.select_value(sql)
    end

    def insert_contract(reference:)
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO decidim_contracts_sk_contracts
          (decidim_organization_id, decidim_author_id, title, reference, state,
           source, created_at, updated_at)
        VALUES
          (#{organization.id}, #{author.id}, 'Road reconstruction', '#{reference}',
           'in_review', 'editorial', '2026-09-01 08:00:00.000000', '2026-09-01 08:00:00.000000')
      SQL
      sql_value("SELECT id FROM decidim_contracts_sk_contracts WHERE reference = '#{reference}'")
    end

    def insert_audit(contract_id:, user:, action:, at:)
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO decidim_contracts_sk_audit_events
          (decidim_organization_id, decidim_user_id, target_type, target_id, action,
           created_at, updated_at)
        VALUES
          (#{organization.id}, #{user.id}, 'Decidim::ContractsSk::Contract', #{contract_id},
           '#{action}', '#{at}', '#{at}')
      SQL
    end

    def submitted_by_of(contract_id)
      sql_value("SELECT decidim_submitted_by_id FROM decidim_contracts_sk_contracts WHERE id = #{contract_id}")
    end

    it "adds the nullable bigint column without index or FK and reverses cleanly" do
      prerequisite_migrations!
      insert_contract(reference: "ZP-2026-001")

      migration_class.migrate(:up)

      column = column_by_name("decidim_submitted_by_id")
      aggregate_failures do
        expect(column.type).to eq(:integer).or eq(:bigint)
        expect(column.null).to be(true)
        expect(column.default).to be_nil
        expect(ActiveRecord::Base.connection.foreign_keys(table_name).map(&:column))
          .not_to include("decidim_submitted_by_id")
        expect(ActiveRecord::Base.connection.indexes(table_name).flat_map(&:columns))
          .not_to include("decidim_submitted_by_id")
      end

      migration_class.migrate(:down)
      expect(column_by_name("decidim_submitted_by_id")).to be_nil

      migration_class.migrate(:up)
      expect(column_by_name("decidim_submitted_by_id")).to be_present
    end

    it "backfills each contract with the actor of its most recent contract.submit audit row" do
      prerequisite_migrations!
      user_a = Decidim::User.create!(organization: organization)
      user_b = Decidim::User.create!(organization: organization)
      user_c = Decidim::User.create!(organization: organization)
      first_id = insert_contract(reference: "ZP-2026-001")
      second_id = insert_contract(reference: "ZP-2026-002")
      third_id = insert_contract(reference: "ZP-2026-003")

      # Contract 1: an older submit by A, a newer submit by B, and a newer
      # NON-submit row by C that must be ignored.
      insert_audit(contract_id: first_id, user: user_a, action: "contract.submit",
                   at: "2026-09-02 09:00:00.000000")
      insert_audit(contract_id: first_id, user: user_b, action: "contract.submit",
                   at: "2026-09-03 09:00:00.000000")
      insert_audit(contract_id: first_id, user: user_c, action: "contract.return",
                   at: "2026-09-04 09:00:00.000000")
      # Contract 2: no audit rows at all. Contract 3: only a non-submit row.
      insert_audit(contract_id: third_id, user: user_c, action: "contract.approve",
                   at: "2026-09-04 09:00:00.000000")

      migration_class.migrate(:up)

      aggregate_failures do
        expect(submitted_by_of(first_id)).to eq(user_b.id)
        expect(submitted_by_of(second_id)).to be_nil
        expect(submitted_by_of(third_id)).to be_nil
      end
    end

    it "breaks a created_at tie on the highest audit id" do
      prerequisite_migrations!
      user_a = Decidim::User.create!(organization: organization)
      user_b = Decidim::User.create!(organization: organization)
      contract_id = insert_contract(reference: "ZP-2026-001")
      insert_audit(contract_id: contract_id, user: user_a, action: "contract.submit",
                   at: "2026-09-02 09:00:00.000000")
      insert_audit(contract_id: contract_id, user: user_b, action: "contract.submit",
                   at: "2026-09-02 09:00:00.000000")

      migration_class.migrate(:up)

      expect(submitted_by_of(contract_id)).to eq(user_b.id)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
