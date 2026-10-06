# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Shared deterministic support for the engine's :db spec groups (extracted
# per D5 of M02-02-C, civora-org/civora-platform#57).
#
# Loaded from spec_helper.rb after the dummy-app boot, so the engine models
# (provided by the application autoloader) find the Decidim::ApplicationRecord
# stand-in already defined — the real one lives in decidim-core and cannot be
# required outside a full Decidim Rails app. The dummy is ActiveRecord-free by
# design, so these stand-ins are the :db groups' base for the foreseeable
# future (until Stage-2 real-Decidim fidelity). Guarded stand-ins for
# Decidim::Organization / Decidim::User follow the same rule (the contract and
# audit-event associations target them by class_name strings); they are inert
# in the structural (offline) groups, where no connection is ever opened.
#
# The :db-tagged groups exercise models and migrations against the REAL
# migrations on an in-memory SQLite adapter. They are excluded by default
# (see spec_helper.rb); opting in via CONTRACTS_SK_DB=1 requires the sqlite3
# gem, and each :db group skips with a clear message when it is absent.
# ---------------------------------------------------------------------------

require "logger"
require "fileutils"

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

      # The demo-seed rake task resolves its tenants through this
      # association (find_or_create_by!(organization: ...) → the FK), the
      # same shape the real Decidim::User carries. Optional so the plain
      # `Decidim::User.create!` author stand-ins keep working.
      belongs_to :organization, foreign_key: "decidim_organization_id", optional: true
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
  # first. After migrating, the engine models' memoized column metadata is
  # reset: migrations clear the connection's schema cache but NOT the
  # class-level attribute sets, so a partial-schema model access anywhere
  # earlier in the process (e.g. a single-migration spec touching the
  # model before the later migrations exist) would otherwise poison every
  # later :db example with a stale column set.
  def migrate_engine_schema!
    Dir.glob(File.join(engine_root, "db", "migrate", "*.rb")).sort.each do |path|
      require path
      snake_name = File.basename(path, ".rb").split("_", 2).last
      Object.const_get(snake_name.camelize).migrate(:up)
    end

    %w[Contract Party Document Amendment AuditEvent ContractLink UserRole Note].each do |model_name|
      klass = Decidim::ContractsSk.const_get(model_name)
      klass&.reset_column_information
    end
  end

  let(:organization) { Decidim::Organization.create! }
  # The author stand-in carries the shared organization: the real
  # Decidim::User always belongs to one, and the commands' tenancy guards
  # (CreateContract's user.organization == organization check) consult it —
  # a bare row would silently skip the guard the specs are meant to pin.
  let(:author) { Decidim::User.create!(organization: organization) }

  def contract_attributes(overrides = {})
    {
      organization: organization,
      author: author,
      title: "Road reconstruction",
      reference: "ZP-2026-001"
    }.merge(overrides)
  end

  # Creates the ActiveStorage tables (M02-05-A0, civora-org/civora-platform
  # #73). The engine attaches files through ActiveStorage but deliberately
  # ships NO storage-table migration — the host app owns that schema
  # (docs/contracts-domain-notes.md) — so the harness builds the tables from
  # the pinned activestorage gem's own migration, the same file a host app's
  # schema carries. Built for EVERY :db example: a contract destroy now
  # cascades into documents' attachments, so any group that destroys a
  # contract (not only the blob-backed ones) needs the tables present.
  def migrate_active_storage_schema!
    gem_path = Gem::Specification.find_by_name("activestorage").full_gem_path
    require File.join(gem_path, "db", "migrate", "20170806125915_create_active_storage_tables.rb")
    CreateActiveStorageTables.migrate(:up)
  end

  # The dummy app's ActiveStorage Disk service root (set inline in
  # spec/dummy/config/application.rb, git-ignored). Blob-backed :db groups
  # wipe it per example so runs stay hermetic.
  def active_storage_root
    File.join(engine_root, "spec", "dummy", "tmp", "storage")
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
    # foreign keys: the real tables live in a full Decidim app. Beyond the
    # timestamps-only shape the earlier groups needed, the columns mirror
    # what the demo-seed rake task writes (the seed-task spec runs the REAL
    # task against the stand-ins): Decidim stores organization names and
    # locale lists as JSON, and demo_user! fills the named user columns.
    ActiveRecord::Base.connection.create_table :decidim_organizations do |t|
      t.timestamps
      t.json :name
      t.string :host
      t.json :available_locales
      t.string :default_locale
      t.string :reference_prefix
      t.integer :tos_version
    end
    ActiveRecord::Base.connection.create_table :decidim_users do |t|
      t.timestamps
      t.bigint :decidim_organization_id
      t.string :email
      t.string :name
      t.string :nickname
      t.string :tos_agreement
      t.integer :accepted_tos_version
      t.string :password
      t.boolean :admin, default: false, null: false
      t.datetime :admin_terms_accepted_at
      t.datetime :confirmed_at
    end

    # The ActiveStorage tables a host app owns (see the helper's comment):
    # built fresh per example so every :db group can cascade a contract
    # destroy through the attachments, and the blob-backed groups can attach
    # for real.
    migrate_active_storage_schema!
  end

  config.after(:each, :db) do
    if ActiveRecord::Base.connected?
      # Clear the schema cache before disconnecting: re-establishing the
      # identical :memory: config can reuse the pool, whose schema cache
      # would otherwise leak a PARTIAL schema into the next example (a
      # standalone-migration spec that ran only some of the migrations
      # would poison every later model access — proven by the
      # add_amendment_lifecycle migration spec).
      ActiveRecord::Base.connection.schema_cache.clear!
      ActiveRecord::Base.connection_pool.disconnect!
    end
  end
end
