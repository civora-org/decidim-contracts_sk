# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Structural + :db specs for the agreed-effectiveness-date migration
# (civora-org/civora-platform#202): one nullable date column, reversible,
# existing rows untouched.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "db/migrate/*_add_agreed_effective_on_to_decidim_contracts_sk_contracts.rb" do
  subject(:migration_source) { File.read(migration_path) }

  def migration_files
    Dir.glob(File.join(engine_root, "db", "migrate",
                       "*_add_agreed_effective_on_to_decidim_contracts_sk_contracts.rb"))
  end

  def migration_path
    migration_files.first
  end

  def migration_class_name
    "AddAgreedEffectiveOnToDecidimContractsSkContracts"
  end

  it "has exactly one migration file whose class name matches, dated no later than now" do
    expect(migration_files.size).to eq(1)
    timestamp, snake_name = File.basename(migration_path, ".rb").split("_", 2)

    expect(snake_name.camelize).to eq(migration_class_name)
    expect(timestamp).to match(/\A\d{14}\z/)
    expect(timestamp.to_i).to be <= Time.now.utc.strftime("%Y%m%d%H%M%S").to_i
  end

  it "is a single reversible add_column of one nullable date, without default or index" do
    expect(migration_source).to match(/class\s+#{migration_class_name}\s*<\s*ActiveRecord::Migration\[7\.2\]\s*$/)
    expect(migration_source.scan(/\bdef\s+change\b/).size).to eq(1)
    expect(migration_source.lines.map(&:strip).grep(/\Aadd_column\s/))
      .to eq(["add_column :decidim_contracts_sk_contracts, :agreed_effective_on, :date"])
    expect(migration_source).not_to match(/\b(default:|add_index|execute|update_all)\b/)
  end

  describe "runnable migration", :db do
    it "adds a nullable date, keeps existing rows NULL and reverses cleanly" do
      migrate_engine_schema!
      record = Decidim::ContractsSk::Contract.create!(contract_attributes)
      column = ActiveRecord::Base.connection.columns(:decidim_contracts_sk_contracts)
                                 .find { |c| c.name == "agreed_effective_on" }

      expect(column.type).to eq(:date)
      expect(column.null).to be(true)
      expect(record.reload.agreed_effective_on).to be_nil

      Object.const_get(migration_class_name).migrate(:down)
      expect(ActiveRecord::Base.connection.column_exists?(:decidim_contracts_sk_contracts, :agreed_effective_on))
        .to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
