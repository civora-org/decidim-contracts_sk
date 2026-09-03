# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, class-level specs for the engine's base controllers.
#
# No dummy Rails app is required: we boot only the ActionController pieces of
# Rails and load the engine controller files directly.
#
# The real Decidim::ApplicationController (from decidim-core) and the real
# Decidim::Admin::ApplicationController (from decidim-admin) cannot be
# required outside a full Decidim Rails app: they pull in the whole Decidim
# stack (NeedsOrganization, ForceAuthentication, Devise/Cells integrations,
# admin layout, admin permissions, ...). We therefore define MINIMAL
# STAND-INS for both classes below, BEFORE the engine controller files are
# loaded. The stand-ins carry no callbacks and no helpers of their own, so
# the callback and helper assertions reflect this engine's code only. Each
# stand-in also answers #permission_class_chain with a static sentinel so
# the engine controllers' delegation past their own permissions class can
# be asserted offline.
#
# Once a dummy-app harness exists, delete the stand-ins and the explicit
# requires and let the application autoloader provide the real classes
# instead.
# ---------------------------------------------------------------------------

require "spec_helper"

# Workaround for activesupport 6.1.x on Ruby >= 3.3: ActiveSupport references
# ::Logger, which is no longer a default gem. Must load before ActiveSupport.
require "logger"

require "action_controller/railtie"

# The engine controllers reference the engine's permissions class (via
# permission_class_chain), which subclasses the pinned gem's
# Decidim::DefaultPermissions — plain Ruby once its few ActiveSupport
# pieces are loaded, so the real files are required here by absolute path
# (resolved through RubyGems, no shelling out).
require "active_support/concern"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/module/delegation"

decidim_core = Gem::Specification.find_by_name("decidim-core").full_gem_path
require File.join(decidim_core, "app/helpers/concerns/decidim/user_role_checker.rb")
require File.join(decidim_core, "app/models/decidim/permission_action.rb")
require File.join(decidim_core, "app/permissions/decidim/default_permissions.rb")

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

engine_root = File.expand_path("../../..", __dir__)

require File.join(engine_root, "app/helpers/decidim/contracts_sk/application_helper.rb")
require File.join(engine_root, "app/permissions/decidim/contracts_sk/permissions.rb")
require File.join(engine_root, "app/controllers/decidim/contracts_sk/application_controller.rb")
require File.join(engine_root, "app/controllers/decidim/contracts_sk/admin/application_controller.rb")

# Nested in the Decidim::ContractsSk module namespace so the top-level
# describe names the public base controller while resolving relative
# constants (e.g. Admin::ApplicationController) inside the engine's scope.
module Decidim
  module ContractsSk
    RSpec.describe ApplicationController do
      # AC 1: the controller loads properly (the requires above would raise on
      # any class-definition error, so reaching an example proves it loaded).
      it "is defined as a class" do
        expect(described_class).to be_a(Class)
      end

      # AC 2: inherits Decidim authorization - direct subclass of
      # Decidim::ApplicationController.
      it "inherits directly from Decidim::ApplicationController" do
        expect(described_class.superclass).to eq(Decidim::ApplicationController)
      end

      # AC 3: helper methods available in views - the module is registered on
      # the controller's helpers.
      it "registers Decidim::ContractsSk::ApplicationHelper as a view helper" do
        expect(described_class._helpers)
          .to include(Decidim::ContractsSk::ApplicationHelper)
      end

      # AC 4 (Option A regression guard): the BASE controller must NOT require
      # authentication - no :authenticate_user! callback of any kind.
      it "does not declare an :authenticate_user! action callback" do
        callbacks = described_class._process_action_callbacks
                                   .select { |cb| cb.filter == :authenticate_user! }

        expect(callbacks).to be_empty
      end

      # AC 5 (M02-01-B): the engine's permissions class is consulted FIRST
      # for subject :contract actions; the rest of the Decidim chain follows.
      it "prepends Decidim::ContractsSk::Permissions to the inherited chain" do
        expect(described_class.new.permission_class_chain)
          .to eq([Decidim::ContractsSk::Permissions, :stand_in_public_chain])
      end

      describe Admin::ApplicationController do
        # AC 1: the admin controller loads properly as well.
        it "is defined as a class" do
          expect(described_class).to be_a(Class)
        end

        # AC 2: inherits Decidim's admin-level authorization machinery -
        # direct subclass of Decidim::Admin::ApplicationController.
        it "inherits directly from Decidim::Admin::ApplicationController" do
          expect(described_class.superclass)
            .to eq(Decidim::Admin::ApplicationController)
        end

        # AC 3 (hardening regression guard): the admin controller must NOT sit
        # on the engine's public base controller chain - admin and public
        # behaviour stay clearly separated.
        it "does not sit on the engine's public base controller chain" do
          expect(described_class.ancestors)
            .not_to include(Decidim::ContractsSk::ApplicationController)
        end

        # AC 4: the module's ApplicationHelper is registered on the admin
        # controller itself, now that the engine's public base is out of the
        # chain.
        it "registers Decidim::ContractsSk::ApplicationHelper as a view helper" do
          expect(described_class._helpers)
            .to include(Decidim::ContractsSk::ApplicationHelper)
        end

        # AC 5 (Option A regression guard): the ADMIN controller keeps the
        # :authenticate_user! floor - defense-in-depth under Decidim's
        # route-level admin enforcement (OrganizationDashboardConstraint).
        it "declares an :authenticate_user! before_action" do
          kinds = described_class._process_action_callbacks
                                 .select { |cb| cb.filter == :authenticate_user! }
                                 .map(&:kind)

          # An empty list fails contain_exactly, so the callback's presence
          # and its :before kind are both proven by the single expectation.
          expect(kinds).to contain_exactly(:before)
        end

        # AC 6 (M02-01-B): the admin base gets the engine permissions class
        # too - it does NOT inherit the public base controller, so it wires
        # its own chain, still delegating to its own (admin) superclass.
        it "prepends Decidim::ContractsSk::Permissions to the inherited chain" do
          expect(described_class.new.permission_class_chain)
            .to eq([Decidim::ContractsSk::Permissions, :stand_in_admin_chain])
        end
      end
    end
  end
end
