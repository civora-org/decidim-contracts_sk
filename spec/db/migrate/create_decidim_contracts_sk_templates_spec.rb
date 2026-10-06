# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Structural (offline) and runnable (:db) specs for the contract templates
# migration (civora-org/civora-platform#127): reversible single `change`, a
# timestamp at or after 20261011000001, the columns the copy-on-create
# semantics rely on, and the absence of any link back from contracts.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "db/migrate/*_create_decidim_contracts_sk_templates.rb" do
  subject(:migration_source) { File.read(migration_path) }

  def migration_path
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_templates.rb")).sole
  end

  def table_name
    :decidim_contracts_sk_templates
  end

  describe "structure" do
    it "is a single reversible `change` with no raw SQL" do
      expect(migration_source).to match(/ActiveRecord::Migration\[7\.2\]/)
      expect(migration_source.scan(/^\s*def (\w+)/).flatten).to eq(%w[change])
      expect(migration_source).not_to include("execute")
    end

    it "carries a unique timestamp of 20261011000001 or later" do
      stamps = Dir.glob(File.join(engine_root, "db", "migrate", "*.rb")).map { |path| File.basename(path)[/\A\d+/] }
      own = File.basename(migration_path)[/\A\d+/]

      expect(own.to_i).to be >= 20_261_011_000_001
      expect(stamps.uniq.size).to eq(stamps.size)
    end
  end

  describe "runnable migration", :db do
    it "migrates up, down and up again with the expected columns and the unique name index" do
      require migration_path
      migration_class = Object.const_get("CreateDecidimContractsSkTemplates")

      migration_class.migrate(:up)
      connection = ActiveRecord::Base.connection
      expect(connection.table_exists?(table_name)).to be(true)

      by_name = connection.columns(table_name).index_by(&:name)
      expect(by_name.keys).to contain_exactly(
        "id", "decidim_organization_id", "name", "title_pattern", "subject_matter", "currency",
        "object_party_name", "object_party_ico", "object_party_address", "created_at", "updated_at"
      )
      %w[decidim_organization_id name currency].each do |name|
        expect(by_name[name].null).to be(false), "#{name} must be NOT NULL"
      end
      expect(by_name["currency"].default).to eq("EUR")

      unique = connection.indexes(table_name).sole
      expect(unique.columns).to eq(%w[decidim_organization_id name])
      expect(unique.unique).to be(true)

      # Copy-on-create: no foreign key out of the table (the contracts
      # side is pinned in template_spec: no template column on contracts).
      expect(connection.foreign_keys(table_name)).to be_empty

      migration_class.migrate(:down)
      expect(connection.table_exists?(table_name)).to be(false)

      migration_class.migrate(:up)
      expect(connection.table_exists?(table_name)).to be(true)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
