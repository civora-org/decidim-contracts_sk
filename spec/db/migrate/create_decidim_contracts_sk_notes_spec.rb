# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Structural (offline) and runnable (:db) specs for the internal review notes
# migration (civora-org/civora-platform#128): reversible single `change`, a
# real FK onto the contracts table, no author FK, append-only shape (no
# updated_at), and a timestamp later than the parallel UserRole migration.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "db/migrate/*_create_decidim_contracts_sk_notes.rb" do
  subject(:migration_source) { File.read(migration_path) }

  def migration_path
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_notes.rb")).sole
  end

  def table_name
    :decidim_contracts_sk_notes
  end

  describe "structure" do
    it "is a single reversible `change` with no raw SQL" do
      expect(migration_source).to match(/ActiveRecord::Migration\[7\.2\]/)
      expect(migration_source.scan(/^\s*def (\w+)/).flatten).to eq(%w[change])
      expect(migration_source).not_to include("execute")
    end

    it "carries a unique timestamp after the UserRole migration" do
      stamps = Dir.glob(File.join(engine_root, "db", "migrate", "*.rb")).map { |path| File.basename(path)[/\A\d+/] }
      own = File.basename(migration_path)[/\A\d+/]

      expect(own.to_i).to be > 20_261_006_000_001
      expect(stamps.uniq.size).to eq(stamps.size)
    end

    it "declares NOT NULL contract/author/body, a contract FK, and no updated_at" do
      expect(migration_source).to match(/t\.references :contract, null: false,\s+index: false,\s+foreign_key:/)
      expect(migration_source).to include("to_table: :decidim_contracts_sk_contracts")
      expect(migration_source).to match(/t\.references :decidim_author, null: false, index: false\n/)
      expect(migration_source).to match(/t\.text :body, null: false/)
      expect(migration_source).to match(/t\.datetime :created_at, null: false/)
      expect(migration_source).not_to include("t.timestamps")
    end
  end

  describe "runnable migration", :db do
    it "migrates up, down and up again with the expected columns, one FK and the thread index" do
      require migration_path
      migration_class = Object.const_get("CreateDecidimContractsSkNotes")

      migration_class.migrate(:up)
      connection = ActiveRecord::Base.connection
      expect(connection.table_exists?(table_name)).to be(true)

      by_name = connection.columns(table_name).index_by(&:name)
      expect(by_name.keys).to contain_exactly("id", "contract_id", "decidim_author_id", "body", "created_at")
      %w[contract_id decidim_author_id body created_at].each do |name|
        expect(by_name[name].null).to be(false), "#{name} must be NOT NULL"
      end

      expect(connection.foreign_keys(table_name).map(&:to_table)).to contain_exactly("decidim_contracts_sk_contracts")
      expect(connection.indexes(table_name).map(&:columns)).to contain_exactly(%w[contract_id id])

      migration_class.migrate(:down)
      expect(connection.table_exists?(table_name)).to be(false)

      migration_class.migrate(:up)
      expect(connection.table_exists?(table_name)).to be(true)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
