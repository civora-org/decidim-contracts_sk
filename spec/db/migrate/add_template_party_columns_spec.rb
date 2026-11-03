# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Runnable (:db) spec for the two additive migrations of the contract parties
# from a template (civora-org/civora-platform#211): parties.template_slot with
# its unique index, and contract_template_fields.party_part. Both reversible.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "template party migrations", :db do
  def columns(table)
    ActiveRecord::Base.connection.columns(table).index_by(&:name)
  end

  def load_migration(suffix)
    path = Dir.glob(File.join(engine_root, "db", "migrate", "*_#{suffix}.rb")).sole
    require path
    suffix.camelize.constantize
  end

  it "adds a nullable template_slot with a unique (contract, slot) index, and reverses cleanly" do
    migrate_engine_schema!
    expect(columns(:decidim_contracts_sk_parties)["template_slot"]).to have_attributes(type: :string, null: true,
                                                                                       default: nil)
    index = ActiveRecord::Base.connection.indexes(:decidim_contracts_sk_parties).find { |i| i.columns == %w[contract_id template_slot] }
    expect(index).to have_attributes(unique: true)

    migration = load_migration("add_template_slot_to_decidim_contracts_sk_parties")
    migration.migrate(:down)
    expect(columns(:decidim_contracts_sk_parties)).not_to have_key("template_slot")
    migration.migrate(:up)
    expect(columns(:decidim_contracts_sk_parties)).to have_key("template_slot")
  end

  it "adds a nullable party_part and reverses cleanly" do
    migrate_engine_schema!
    table = :decidim_contracts_sk_contract_template_fields
    expect(columns(table)["party_part"]).to have_attributes(type: :string, null: true, default: nil)

    migration = load_migration("add_party_part_to_decidim_contracts_sk_contract_template_fields")
    migration.migrate(:down)
    expect(columns(table)).not_to have_key("party_part")
    migration.migrate(:up)
    expect(columns(table)).to have_key("party_part")
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
