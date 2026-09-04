# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Stage-1 dummy-app harness (civora-org/civora-platform#61, #45 item 2;
# admin permission surface grown for the admin CRUD milestone, #58).
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
# both are therefore defined here, before the engine is required.
#
# The ADMIN stand-in includes the REAL pinned-gem Decidim::NeedsPermission,
# so enforce_permission_to / allowed_to? / the ActionForbidden rescue behave
# exactly as in a host app. Only the Devise-ish seam is stubbed to safe
# defaults (current_user / current_organization return nil, authenticate_user!
# redirects with the DISTINCT literal flash key :dummy_authentication_required)
# — request specs override the seam per-example via allow_any_instance_of and
# can thereby tell an authentication bounce from a permission denial.
#
# The chain sentinels of the earlier harness (:stand_in_public_chain /
# :stand_in_admin_chain) are replaced by inert permission classes:
# NeedsPermission#allowed_to? calls .new(...).permissions on every chain
# member, so the members must quack like DefaultPermissions. The Dummy*
# subclasses of the real DefaultPermissions are pinned as inert by
# spec/decidim/contracts_sk/dummy_permissions_spec.rb.
#
# register_permissions is deliberately NOT called: the class method (from
# the RegistersPermissions concern that rides along with NeedsPermission)
# resolves Decidim.permissions_registry, which only exists in a full
# decidim-core load; the stand-ins answer #permission_class_chain directly.
# ---------------------------------------------------------------------------

require "logger"

require "rails"
require "action_controller/railtie"
require "i18n"
require "wisper"

require "active_support/concern"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/module/delegation"

# The pinned gem is the ground truth for every Decidim class the harness or
# the engine touches; its files are required by absolute path (resolved
# through RubyGems, no shelling out) in dependency order. NeedsPermission
# needs RegistersPermissions (its include), DefaultPermissions needs
# UserRoleChecker; decidim/command.rb includes Wisper::Publisher (required
# above) and Decidim::Command.call builds a Decidim::EventRecorder.
decidim_core = Gem::Specification.find_by_name("decidim-core").full_gem_path
require File.join(decidim_core, "app/helpers/concerns/decidim/user_role_checker.rb")
require File.join(decidim_core, "app/models/decidim/permission_action.rb")
require File.join(decidim_core, "app/permissions/decidim/default_permissions.rb")
require File.join(decidim_core, "app/controllers/concerns/decidim/registers_permissions.rb")
require File.join(decidim_core, "app/controllers/concerns/decidim/needs_permission.rb")
require File.join(decidim_core, "lib/decidim/command.rb")
require File.join(decidim_core, "lib/decidim/event_recorder.rb")

# Inert chain members: DefaultPermissions' base target_scope ("") matches no
# real scope (:admin / :public), so #permissions returns the action untouched
# — exactly what a chain member that decides nothing must do.
class DummyAdminPermissions < Decidim::DefaultPermissions; end
class DummyPublicPermissions < Decidim::DefaultPermissions; end

# Minimal stand-in for decidim-core's Decidim::ApplicationController.
unless defined?(Decidim::ApplicationController)
  module Decidim
    class ApplicationController < ActionController::Base
      def permission_class_chain
        [DummyPublicPermissions]
      end
    end
  end
end

# Minimal stand-in for decidim-admin's Decidim::Admin::ApplicationController:
# real NeedsPermission machinery over a stubbed Devise-ish seam.
unless defined?(Decidim::Admin::ApplicationController)
  module Decidim
    module Admin
      class ApplicationController < ActionController::Base
        include Decidim::NeedsPermission

        # --- Devise-ish seam (stubbed; overridden per-example in specs) ---
        def current_user
          nil
        end

        def user_signed_in?
          false
        end

        def current_organization
          nil
        end

        # Method only, deliberately: the ENGINE's admin base owns the
        # before_action declaration (pinned by application_controller_spec.rb),
        # so exactly one callback exists on it. Devise semantics: signed-in
        # visitors pass through; everyone else is bounced with the DISTINCT
        # literal flash key (:dummy_authentication_required), so request specs
        # can tell an authentication bounce from a permission denial
        # (NeedsPermission's handler uses :alert).
        def authenticate_user!
          return if user_signed_in?

          flash[:dummy_authentication_required] = "Dummy harness: sign-in required"
          redirect_to "/"
        end

        # --- NeedsPermission overrides ---
        def user_has_no_permission_path
          "/"
        end

        def permission_class_chain
          [DummyAdminPermissions]
        end

        def permission_scope
          :admin
        end
      end
    end
  end
end

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

# NeedsPermission's denial handler translates
# decidim.core.actions.unauthorized — a key shipped by decidim-core's own
# locale files, which are not on this harness's load path. Stub it through
# the live backend AFTER boot (no later code reloads I18n in the one-shot
# spec process).
I18n.backend.store_translations(
  :en,
  decidim: { core: { actions: { unauthorized: "You are not authorized to perform this action." } } }
)

# Post-initialize draw of the dummy routes (mounts the engine at "/").
# RouteSet#draw clears the table first, so this stays idempotent even though
# the routes reloader has already evaluated this file during initialize!.
require_relative "routes"
