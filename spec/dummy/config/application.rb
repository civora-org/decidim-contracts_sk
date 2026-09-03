# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Stage-1 dummy-app harness (civora-org/civora-platform#61, #45 item 2).
#
# A minimal, ActiveRecord-free Rails app that exists only to host the engine
# in specs: it mounts Decidim::ContractsSk::Engine at "/" (see routes.rb),
# so request specs run against real routes and every spec file can rely on
# the engine's real classes instead of per-file stand-ins.
#
# This is NOT a Decidim application: the real decidim-core
# Decidim::ApplicationController and decidim-admin
# Decidim::Admin::ApplicationController cannot be required outside a full
# Decidim app (they pull in NeedsOrganization, ForceAuthentication,
# Devise/Cells integrations, the admin layout, ...). Minimal stand-ins for
# both are therefore defined here, before the engine is required. The
# stand-ins carry no callbacks and no helpers of their own, so the
# class-level assertions reflect this engine's code only, and each answers
# #permission_class_chain with the same static sentinel the retired per-spec
# stand-ins used (:stand_in_public_chain / :stand_in_admin_chain). Real
# Decidim fidelity arrives with the Stage-2 harness.
# ---------------------------------------------------------------------------

require "logger"

require "rails"
require "action_controller/railtie"

# Minimal stand-in for decidim-core's Decidim::ApplicationController.
unless defined?(Decidim::ApplicationController)
  module Decidim
    class ApplicationController < ActionController::Base
      def permission_class_chain
        [:stand_in_public_chain]
      end
    end
  end
end

# Minimal stand-in for decidim-admin's Decidim::Admin::ApplicationController.
unless defined?(Decidim::Admin::ApplicationController)
  module Decidim
    module Admin
      class ApplicationController < ActionController::Base
        def permission_class_chain
          [:stand_in_admin_chain]
        end
      end
    end
  end
end

# The engine's Permissions class subclasses the pinned gem's
# Decidim::DefaultPermissions — plain Ruby once its few ActiveSupport pieces
# are loaded, so the real files are required by absolute path (resolved
# through RubyGems, no shelling out).
require "active_support/concern"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/module/delegation"

decidim_core = Gem::Specification.find_by_name("decidim-core").full_gem_path
require File.join(decidim_core, "app/helpers/concerns/decidim/user_role_checker.rb")
require File.join(decidim_core, "app/models/decidim/permission_action.rb")
require File.join(decidim_core, "app/permissions/decidim/default_permissions.rb")

# Rails is defined from here on, so the engine's conditional engine require
# fires and the full engine (lifecycle, role resolver, Engine class) loads.
require "decidim/contracts_sk"

# Minimal AR-free Rails application hosting the engine for specs.
class DummyApp < Rails::Application
  config.root = File.expand_path("..", __dir__)
  config.eager_load = false
  config.secret_key_base = "0" * 128
  config.logger = Logger.new(IO::NULL)
  config.hosts.clear
  config.action_dispatch.show_exceptions = :rescuable
  config.cache_store = :null_store
end

DummyApp.initialize!

# Post-initialize draw of the dummy routes (mounts the engine at "/").
# RouteSet#draw clears the table first, so this stays idempotent even though
# the routes reloader has already evaluated this file during initialize!.
require_relative "routes"
