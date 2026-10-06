# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the engine's user roles
# migration (M03-06-B, civora-org/civora-platform#109).
#
# The default run asserts the migration as text only (the suite stays
# DB-less). The :db group additionally runs it up -> down -> up on an
# in-memory SQLite adapter (opt in via CONTRACTS_SK_DB=1).
# ---------------------------------------------------------------------------

require "spec_helper"

# Structural examples hold several related expectations per column.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe "db/migrate/*_create_decidim_contracts_sk_user_roles.rb" do
  subject(:migration_source) { File.read(migration_path) }

  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_user_roles.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "CreateDecidimContractsSkUserRoles"
  end

  def table_name
    :decidim_contracts_sk_user_roles
  end

  def column_line(name)
    migration_source
      .lines
      .map(&:strip)
      .find { |line| line.match?(/\At\.(?:references|string|datetime)\s+:#{name}\b/) }
  end

  def explicit_index_names
    migration_source.scan(/name:\s*"([^"]+)"/).flatten
  end

  describe "file surface" do
    it "has exactly one matching migration file, newer than the previous newest" do
      expect(migration_files.size).to eq(1)
      expect(File.basename(migration_path).split("_").first).to be > "20261003000002"
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
    it "declares the table with the user, organization, role and timestamps" do
      expect(migration_source).to match(/create_table\s+:#{table_name}\b/)

      %i[decidim_user decidim_organization role].each do |column|
        expect(column_line(column)).to be_present, "missing column :#{column}"
      end
      expect(migration_source.lines.map(&:strip)).to include(match(/\At\.timestamps\b/))
    end

    it "makes user, organization and role NOT NULL" do
      %i[decidim_user decidim_organization role].each do |column|
        expect(column_line(column)).to match(/null:\s*false/), ":#{column} must be NOT NULL"
      end
    end

    it "puts real FKs on the user and organization references" do
      expect(migration_source).to match(/foreign_key:\s*\{\s*to_table:\s*:decidim_users\s*\}/)
      expect(migration_source).to match(/foreign_key:\s*\{\s*to_table:\s*:decidim_organizations\s*\}/)
    end
  end

  describe "indexes" do
    it "uniquely indexes (user, organization, role) under the issue-specified name" do
      expect(migration_source).to match(
        /add_index\s+:#{table_name},\s*%i\[decidim_user_id decidim_organization_id role\]/
      )
      expect(migration_source).to match(/unique:\s*true/)
      expect(explicit_index_names).to include("index_decidim_contracts_sk_user_roles_unique")
    end

    it "keeps every explicit index name within PostgreSQL's 63-byte limit" do
      expect(explicit_index_names).not_to be_empty

      explicit_index_names.each do |name|
        expect(name.length).to be <= 63, "index name exceeds 63 bytes: #{name}"
      end
    end
  end

  describe "reversibility proxy" do
    it "uses no raw SQL and no non-reversible DSL" do
      expect(migration_source).not_to match(/\bexecute\(/)
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

    it "migrates up, down, and up again with the expected columns, FKs and unique index" do
      migration_class.migrate(:up)
      connection = ActiveRecord::Base.connection
      expect(connection.table_exists?(table_name)).to be(true)

      by_name = connection.columns(table_name).index_by(&:name)
      expect(by_name.keys).to contain_exactly(
        "id", "decidim_user_id", "decidim_organization_id", "role", "created_at", "updated_at"
      )
      expect(by_name["role"].type).to eq(:string)
      %w[decidim_user_id decidim_organization_id role created_at updated_at].each do |name|
        expect(by_name[name].null).to be(false), "#{name} must be NOT NULL"
      end

      expect(connection.foreign_keys(table_name).map(&:to_table))
        .to contain_exactly("decidim_users", "decidim_organizations")

      indexes = connection.indexes(table_name).index_by(&:name)
      expect(indexes.keys).to contain_exactly(
        "index_decidim_contracts_sk_user_roles_unique",
        "idx_contracts_sk_user_roles_on_organization_id"
      )
      unique = indexes["index_decidim_contracts_sk_user_roles_unique"]
      expect(unique.columns).to eq(%w[decidim_user_id decidim_organization_id role])
      expect(unique.unique).to be(true)
      expect(indexes["idx_contracts_sk_user_roles_on_organization_id"].columns)
        .to eq(%w[decidim_organization_id])

      migration_class.migrate(:down)
      expect(connection.table_exists?(table_name)).to be(false)

      migration_class.migrate(:up)
      expect(connection.table_exists?(table_name)).to be(true)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
