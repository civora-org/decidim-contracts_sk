# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Shared deterministic support for the engine's :db spec groups (extracted
# per D5 of M02-02-C, civora-org/civora-platform#57).
#
# Loaded from spec_helper.rb BEFORE any spec file runs, so the engine model
# requires inside the spec files find the Decidim::ApplicationRecord stand-in
# already defined — the real one lives in decidim-core and cannot be required
# outside a full Rails app. Guarded stand-ins for Decidim::Organization /
# Decidim::User follow the same rule (the contract and audit-event
# associations target them by class_name strings); they are inert in the
# structural (offline) groups, where no connection is ever opened.
#
# The :db-tagged groups exercise models and migrations against the REAL
# migrations on an in-memory SQLite adapter. They are excluded by default
# (see spec_helper.rb); opting in via CONTRACTS_SK_DB=1 requires the sqlite3
# gem, and each :db group skips with a clear message when it is absent.
#
# Once a dummy-app harness exists, delete the stand-ins and the per-file
# explicit requires and let the application autoloader provide the real
# classes instead.
# ---------------------------------------------------------------------------

# Workaround for activesupport 6.1.x on Ruby >= 3.3: ActiveSupport references
# ::Logger, which is no longer a default gem. Must load before ActiveSupport.
require "logger"

require "active_record"
require "active_support/concern"
require "active_support/core_ext/string/inflections"

# Minimal stand-in for decidim-core's Decidim::ApplicationRecord.
unless defined?(Decidim::ApplicationRecord)
  module Decidim
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end

# Minimal stand-ins for the association targets: the engine models reference
# them by class_name strings, but offline nothing else defines them.
unless defined?(Decidim::Organization)
  module Decidim
    Organization = Class.new(ActiveRecord::Base) do
      self.table_name = "decidim_organizations"
    end
  end
end

unless defined?(Decidim::User)
  module Decidim
    User = Class.new(ActiveRecord::Base) do
      self.table_name = "decidim_users"
    end
  end
end

RSpec.shared_context "contracts_sk db support" do
  # Fixed engine location as a plain method, not a let: the migration
  # directory is a deterministic engine identifier, not per-example state.
  def engine_root
    File.expand_path("../..", __dir__)
  end

  # Migrates the engine schema all the way up, in filename (= timestamp)
  # order: child tables carry real FK constraints, so parents must come
  # first.
  def migrate_engine_schema!
    Dir.glob(File.join(engine_root, "db", "migrate", "*.rb")).sort.each do |path|
      require path
      snake_name = File.basename(path, ".rb").split("_", 2).last
      Object.const_get(snake_name.camelize).migrate(:up)
    end
  end

  let(:organization) { Decidim::Organization.create! }
  let(:author) { Decidim::User.create! }

  def contract_attributes(overrides = {})
    {
      organization: organization,
      author: author,
      title: "Road reconstruction",
      reference: "ZP-2026-001"
    }.merge(overrides)
  end
end

RSpec.configure do |config|
  config.include_context "contracts_sk db support"

  # Connection juggling around every :db example: a fresh, empty in-memory
  # SQLite database per example makes the groups order-independent — an
  # identical :memory: config would otherwise reuse a live pool (and its
  # schema) left behind by a previous group in the same process.
  config.before(:each, :db) do
    begin
      require "sqlite3"
    rescue LoadError
      skip "sqlite3 gem is not available; add it locally to run the CONTRACTS_SK_DB=1 group"
    end

    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

    # Stand-in tenants/authors for the engine's prefixed organization/user
    # foreign keys: the real tables live in a full Decidim app.
    ActiveRecord::Base.connection.create_table(:decidim_organizations, &:timestamps)
    ActiveRecord::Base.connection.create_table(:decidim_users, &:timestamps)
  end

  config.after(:each, :db) do
    ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
  end
end
