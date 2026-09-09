# frozen_string_literal: true

# Stage-1 dummy-app harness (civora-org/civora-platform#61, #45 item 2): the
# spec suite boots the minimal AR-free Rails app under spec/dummy, which
# mounts the engine at "/" and provides the engine's real classes (plus the
# stand-in Decidim application controllers it needs) — so no spec file loads
# the engine or its classes by hand anymore.
#
# Route note (M02-05-A0, #73): the dummy's routes — including the engine
# mount AND ActiveStorage's application-level routes/URL helpers — are drawn
# by the routes reloader execute at the end of spec/dummy/config/application.rb.
# Deliberately NO `require_relative "dummy/config/routes"` here anymore: a
# second `DummyApp.routes.draw` would CLEAR the route table and wipe the
# ActiveStorage registrations.
require_relative "dummy/config/application"

require "rspec/rails"

# Shared deterministic support for the :db groups (stand-ins, migration
# runner, connection juggling). Loaded before every spec file so the
# autoloaded engine models find the Decidim::ApplicationRecord stand-in
# already defined (the dummy is AR-free on purpose; the real one lives in
# decidim-core and cannot be required outside a full Decidim app).
require_relative "support/contracts_sk_db_helpers"
require_relative "support/demo_data"
require_relative "support/crz_import_payloads"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Spec type follows the directory layout (spec/requests → :request, ...).
  config.infer_spec_type_from_file_location!

  # DB-backed examples (tagged :db) stay out of the default offline run.
  # Opt in with CONTRACTS_SK_DB=1; those groups additionally need the sqlite3
  # gem and skip themselves with a clear message when it is absent.
  config.filter_run_excluding :db unless ENV["CONTRACTS_SK_DB"] == "1"
end
