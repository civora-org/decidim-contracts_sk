# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Structural (offline) and runnable (:db) spec for the group_label migration
# (civora-org/civora-platform#211, P6): one nullable string column, reversible,
# no data step. Timestamps are covered by migration_timestamps_spec.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "db/migrate/*_add_group_label_to_decidim_contracts_sk_contract_template_fields" do
  def path
    pattern = "*_add_group_label_to_decidim_contracts_sk_contract_template_fields.rb"
    Dir.glob(File.join(engine_root, "db", "migrate", pattern)).sole
  end

  it "is a single reversible `change` adding one column, with no raw SQL and no data step" do
    source = File.read(path)
    code = source.lines.reject { |line| line.strip.start_with?("#") }.join

    expect(source).to match(/ActiveRecord::Migration\[7\.2\]/)
    expect(source.scan(/^\s*def (\w+)/).flatten).to eq(%w[change])
    expect(code).to match(/add_column :decidim_contracts_sk_contract_template_fields, :group_label, :string\s*$/)
    expect(code).not_to match(/\bexecute\b|update_all|insert|reversible|null: false|default:/)
    expect(source).to include("civora-org/civora-platform")
  end

  context "when run", :db do
    def columns
      ActiveRecord::Base.connection.columns(:decidim_contracts_sk_contract_template_fields).index_by(&:name)
    end

    it "adds a nullable string column and removes it again on down" do
      migrate_engine_schema!
      expect(columns["group_label"]).to have_attributes(type: :string, null: true, default: nil)

      require path
      AddGroupLabelToDecidimContractsSkContractTemplateFields.migrate(:down)
      expect(columns).not_to have_key("group_label")
      AddGroupLabelToDecidimContractsSkContractTemplateFields.migrate(:up)
      expect(columns).to have_key("group_label")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
