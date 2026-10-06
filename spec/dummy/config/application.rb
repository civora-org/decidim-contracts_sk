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
# ActiveStorage rides along since M02-05-A0 (civora-org/civora-platform#73):
# the engine's Document model declares `has_one_attached :file` unguarded —
# decidim-core parity, since every Decidim app runs ActiveStorage — so the
# harness boots the real ActiveStorage engine for the model to load at all.
# ActiveRecord is loadable in this harness either way (the shared :db support
# requires it in every run); the dummy stays DB-free because nothing queries.
require "active_storage/engine"
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

# The Decidim form builder (host-form parity for the admin form renders).
# A real Decidim host points ActionView::Base.default_form_builder at
# Decidim::FormBuilder through decidim-core's `decidim_core.default_form_builder`
# initializer — which never runs here, because this harness requires
# pin-point files instead of the decidim-core engine. Without it, form_with
# yields the plain Rails builder, so the engine views render differently
# than in any host (the Decidim builder consumes the `label:`/`label_options:`
# field options; the Rails builder would leak them onto the input). The
# requires below are the builder's dependency chain, in order; the assignment
# mirrors the host initializer (decidim-core engine.rb).
require File.join(decidim_core, "lib/decidim/map")
require File.join(decidim_core, "lib/decidim/map/utility")
require File.join(decidim_core, "lib/decidim/map/frontend")
require File.join(decidim_core, "lib/decidim/map/autocomplete")
require File.join(decidim_core, "lib/decidim/legacy_form_builder")
require File.join(decidim_core, "lib/decidim/translatable_attributes")
require File.join(decidim_core, "app/validators/translatable_presence_validator")
require File.join(decidim_core, "lib/decidim/tooltip_helper")
require File.join(decidim_core, "lib/decidim/form_builder")

# The Decidim menu registry (civora-org/civora-platform#86c): the engine's
# navigation initializer calls Decidim.menu at boot, so the harness must
# provide the menu machinery before the engine is required. The three
# classes are pure Ruby with zero dependencies — required here by absolute
# path from the pinned gem, like every Decidim class above:
#
#   * Decidim::MenuRegistry (menu_registry.rb) — the global named registry
#   * Decidim::MenuItem      (menu_item.rb)      — the item value object
#   * Decidim::Menu          (menu.rb)           — the per-render DSL
#
# Decidim.menu itself (the module method delegating to MenuRegistry) is
# defined inside lib/decidim/core.rb — a file whose first line requires the
# full decidim-core engine, so it cannot be required pin-point. The mirror
# below is verbatim the pinned gem's method body (decidim-core 0.31.7,
# lib/decidim/core.rb:984-986); every class under it stays real.
require File.join(decidim_core, "lib/decidim/menu_registry")
require File.join(decidim_core, "lib/decidim/menu_item")
require File.join(decidim_core, "lib/decidim/menu")

module Decidim
  class << self
    # Verbatim mirror of decidim-core 0.31.7 lib/decidim/core.rb:984-986.
    def menu(name, &)
      MenuRegistry.register(name.to_sym, &)
    end
  end
end

# Pagination parity for the paginated index listings (#86b): a real Decidim
# host loads Kaminari through decidim-core's gem dependency (a normal app's
# Bundler.require picks up the railties), which teaches ActiveRecord
# relations `.page`/`.per` — the engine's controllers paginate through it.
# The require registers Kaminari's lazy AR hook (and its railtie, since
# Rails is defined above), so the extension lands whether ActiveRecord::Base
# is already loaded or loads later; it must run before initialize! so the
# railtie's config initializer is seen.
require "kaminari/activerecord"

# The REAL Decidim::MetaTagsHelper (civora-org/civora-platform#122): a host
# gets it through Decidim::ApplicationController's `helper`, and the engine's
# public views register their titles/descriptions through it. The harness
# layout (spec/dummy/app/views/layouts/application.html.erb) renders the
# values the way decidim-core's _head partial does. Only the image lookup is
# stubbed: MetaImageUrlResolver queries content blocks, which need a full
# Decidim schema.
require File.join(decidim_core, "app/helpers/decidim/meta_tags_helper")

module DummyMetaTagsHelper
  include Decidim::MetaTagsHelper

  def resolve_meta_image_url(_resource)
    nil
  end
end

# Inert chain members: DefaultPermissions' base target_scope ("") matches no
# real scope (:admin / :public), so #permissions returns the action untouched
# — exactly what a chain member that decides nothing must do.
class DummyAdminPermissions < Decidim::DefaultPermissions; end
class DummyPublicPermissions < Decidim::DefaultPermissions; end

# Minimal stand-in for decidim-core's Decidim::ApplicationController.
unless defined?(Decidim::ApplicationController)
  module Decidim
    class ApplicationController < ActionController::Base
      helper DummyMetaTagsHelper
      # The harness layout renders the head (see its header comment).
      layout "application"

      # Devise-ish seam (stubbed; overridden per-example in specs): a real
      # host provides current_organization via Decidim::NeedsOrganization,
      # and the engine's public catalogue reads it for its tenant scope.
      # Mirrors the admin stand-in below: nil by default, stubbed
      # per-example with allow_any_instance_of.
      def current_organization
        nil
      end

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
  # :none on purpose (M02-05-A0, #73): the harness must RE-RAISE exceptions
  # out of the request, never render error pages — the suite's not-found
  # specs pin the ActiveRecord::RecordNotFound raise itself. Under the
  # previous :rescuable setting that held only while active_record/railtie
  # was absent (RecordNotFound was not a registered rescue response); with
  # ActiveStorage pulling the AR railtie in, :rescuable started RENDERING
  # it as a 404 page. Rails 7.2 note: `false` would NOT restore the raise —
  # ExceptionWrapper#show? treats false as "unset" (renders all); only
  # :none re-raises everything.
  config.action_dispatch.show_exceptions = :none
  config.cache_store = :null_store

  # Host-form parity (see the builder requires above): same default builder
  # as any Decidim host, so request specs exercise the forms exactly as they
  # render in production.
  config.action_view.default_form_builder = "Decidim::FormBuilder"

  # ActiveStorage service wiring (M02-05-A0, #73): configured inline so no
  # storage.yml file is introduced — the `active_storage.services`
  # initializer reads `service_configurations` before falling back to the
  # file. The Disk root lives under the git-ignored dummy tmp dir; the
  # blob-backed :db groups wipe it per example for hermeticity. The queue
  # adapter is pinned to :test so attachment/blob purge cascades
  # (`purge_later`) are captured, never executed on background threads —
  # background threads would race the per-example DB disconnect.
  config.active_job.queue_adapter = :test
  config.active_storage.service = :test
  config.active_storage.service_configurations = {
    test: { service: "Disk", root: File.expand_path("../tmp/storage", __dir__) }
  }.freeze
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

# Route loading happens post-initialize, deliberately (M02-05-A0, #73): a
# bare `initialize!` on this minimal app does not execute the routes
# reloader, so nothing is drawn until it runs. `execute` loads every
# registered route file into its own target set — the dummy mount (its own
# file draws into DummyApp.routes), the engine's routes (drawn into the
# isolated engine set) and ActiveStorage's /rails/active_storage endpoints
# plus the `direct :rails_blob` URL helpers, which the gem's routes file
# draws into the APPLICATION route set (the engine's public view needs the
# latter for its download links). Replacing this with a plain
# `DummyApp.routes.draw { mount ... }` would clear the app set and wipe the
# ActiveStorage registrations.
Rails.application.routes_reloader.execute
