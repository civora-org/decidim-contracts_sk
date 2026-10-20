# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Structural (offline) and runnable (:db) specs for the six contract-template
# migrations (civora-org/civora-platform#211, step P1). All are additive,
# single-`change` creates with no data step, so down (a drop) is the exact
# inverse. Timestamps are covered by migration_timestamps_spec.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "db/migrate/*_create_decidim_contracts_sk_contract_template_tables" do
  # In dependency order (parents first); down runs in reverse.
  migrations = {
    "contract_templates" => "CreateDecidimContractsSkContractTemplates",
    "contract_template_fields" => "CreateDecidimContractsSkContractTemplateFields",
    "contract_organization_profiles" => "CreateDecidimContractsSkContractOrganizationProfiles",
    "contract_template_entries" => "CreateDecidimContractsSkContractTemplateEntries",
    "generated_documents" => "CreateDecidimContractsSkGeneratedDocuments",
    "reference_counters" => "CreateDecidimContractsSkReferenceCounters"
  }.freeze

  def path_for(table)
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_#{table}.rb")).sole
  end

  describe "structure" do
    migrations.each_key do |table|
      it "#{table}: a single reversible `change`, no raw SQL, no data step" do
        source = File.read(path_for(table))
        code = source.lines.reject { |line| line.strip.start_with?("#") }.join

        expect(source).to match(/ActiveRecord::Migration\[7\.2\]/)
        expect(source.scan(/^\s*def (\w+)/).flatten).to eq(%w[change])
        expect(code).not_to match(/\bexecute\b|update_all|insert|reversible/)
        expect(source).to include("civora-org/civora-platform")
      end
    end

    it "runs the parents before the children (timestamp order)" do
      stamps = migrations.keys.map { |table| File.basename(path_for(table))[/\A\d+/].to_i }

      expect(stamps).to eq(stamps.sort)
      expect(stamps.uniq.size).to eq(stamps.size)
    end
  end

  describe "runnable migrations", :db do
    def prefixed(table)
      :"decidim_contracts_sk_#{table}"
    end

    it "migrates down and up again, table by table, with the intended constraints" do
      migrate_engine_schema!
      connection = ActiveRecord::Base.connection

      migrations.each_key { |table| expect(connection.table_exists?(prefixed(table))).to be(true) }

      migrations.to_a.reverse_each do |table, klass|
        Object.const_get(klass).migrate(:down)
        expect(connection.table_exists?(prefixed(table))).to be(false), "#{table} must drop"
      end
      migrations.each do |table, klass|
        Object.const_get(klass).migrate(:up)
        expect(connection.table_exists?(prefixed(table))).to be(true), "#{table} must come back"
      end

      unique = lambda do |table, columns|
        connection.indexes(prefixed(table)).any? { |index| index.unique && index.columns == columns }
      end
      expect(unique.call("contract_templates", %w[decidim_organization_id lineage_key version])).to be(true)
      expect(unique.call("contract_template_fields", %w[contract_template_id key])).to be(true)
      expect(unique.call("contract_organization_profiles", %w[decidim_organization_id])).to be(true)
      expect(unique.call("contract_template_entries", %w[contract_id])).to be(true)
      expect(unique.call("reference_counters", %w[decidim_organization_id scope_key])).to be(true)

      entries = connection.columns(prefixed("contract_template_entries")).index_by(&:name)
      expect(entries["personal_values"].type).to eq(:text)
      expect(entries["values"].null).to be(false)
      expect(connection.columns(prefixed("generated_documents")).map(&:name)).to include("promoted_document_id")
    end

    it "leaves the existing tables untouched" do
      migrate_engine_schema!
      connection = ActiveRecord::Base.connection

      expect(connection.columns(:decidim_contracts_sk_documents).map(&:name))
        .to contain_exactly("id", "contract_id", "title", "kind", "file_name", "content_type", "file_size",
                            "created_at", "updated_at")
      expect(connection.columns(:decidim_contracts_sk_contracts).map(&:name)).not_to include("template_entry_id")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
