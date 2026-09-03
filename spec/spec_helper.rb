# frozen_string_literal: true

require "decidim/contracts_sk"

# Shared deterministic support for the :db groups (stand-ins, migration
# runner, connection juggling). Loaded before every spec file so the engine
# model requires inside the spec files find the Decidim::ApplicationRecord
# stand-in already defined.
require_relative "support/contracts_sk_db_helpers"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # DB-backed examples (tagged :db) stay out of the default offline run.
  # Opt in with CONTRACTS_SK_DB=1; those groups additionally need the sqlite3
  # gem and skip themselves with a clear message when it is absent.
  config.filter_run_excluding :db unless ENV["CONTRACTS_SK_DB"] == "1"
end
