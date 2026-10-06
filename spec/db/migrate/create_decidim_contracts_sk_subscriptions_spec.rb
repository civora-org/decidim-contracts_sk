# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Structural (offline) and runnable (:db) specs for the e-mail alert
# subscriptions migration (civora-org/civora-platform#121): reversible single
# `change`, a timestamp at or after 20261013000010, and above all the exact
# column list: this is the engine's first table of resident personal data, so
# the spec pins that nothing beyond the approved minimum is ever stored (no
# IP, no user agent, no user reference, no raw token).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe "db/migrate/*_create_decidim_contracts_sk_subscriptions.rb" do
  subject(:migration_source) { File.read(migration_path) }

  def migration_path
    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_subscriptions.rb")).sole
  end

  def table_name
    :decidim_contracts_sk_subscriptions
  end

  describe "structure" do
    it "is a single reversible `change` with no raw SQL" do
      expect(migration_source).to match(/ActiveRecord::Migration\[7\.2\]/)
      expect(migration_source.scan(/^\s*def (\w+)/).flatten).to eq(%w[change])
      expect(migration_source).not_to include("execute")
    end

    it "carries a unique timestamp of 20261013000010 or later" do
      stamps = Dir.glob(File.join(engine_root, "db", "migrate", "*.rb")).map { |path| File.basename(path)[/\A\d+/] }
      own = File.basename(migration_path)[/\A\d+/]

      expect(own.to_i).to be >= 20_261_013_000_010
      expect(stamps.uniq.size).to eq(stamps.size)
    end
  end

  describe "runnable migration", :db do
    it "migrates up, down and up again with exactly the approved columns and both indexes" do
      require migration_path
      migration_class = Object.const_get("CreateDecidimContractsSkSubscriptions")

      migration_class.migrate(:up)
      connection = ActiveRecord::Base.connection
      expect(connection.table_exists?(table_name)).to be(true)

      by_name = connection.columns(table_name).index_by(&:name)
      # The whole data-minimisation decision: this list, and nothing else.
      expect(by_name.keys).to contain_exactly(
        "id", "decidim_organization_id", "email", "filter_params", "locale",
        "confirmed_at", "last_notified_at", "token_digest", "created_at", "updated_at"
      )
      %w[decidim_organization_id email filter_params locale token_digest].each do |name|
        expect(by_name[name].null).to be(false), "#{name} must be NOT NULL"
      end
      %w[confirmed_at last_notified_at].each do |name|
        expect(by_name[name].null).to be(true), "#{name} must be nullable"
      end

      indexes = connection.indexes(table_name).to_h { |index| [index.columns, index] }
      expect(indexes.fetch(["token_digest"]).unique).to be(true)
      expect(indexes.fetch(%w[decidim_organization_id email]).unique).to be(false)

      migration_class.migrate(:down)
      expect(connection.table_exists?(table_name)).to be(false)

      migration_class.migrate(:up)
      expect(connection.table_exists?(table_name)).to be(true)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
