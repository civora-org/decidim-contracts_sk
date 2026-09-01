# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, class-level specs for the public contracts
# scaffold controller.
#
# No dummy Rails app is required: we boot only the ActionController pieces
# of Rails and load the engine controller files directly.
#
# The real Decidim::ApplicationController (from decidim-core) cannot be
# required outside a full Decidim Rails app: it pulls in the whole Decidim
# stack (NeedsOrganization, ForceAuthentication, Devise/Cells integrations,
# ...). We therefore define a MINIMAL STAND-IN for it below, BEFORE the
# engine controller files are loaded. The stand-in carries no callbacks
# and no helpers of its own, so the inheritance assertion reflects this
# engine's code only.
#
# The scaffold renders localized placeholders; response behaviour is a
# host-app concern (verified against the civora host app), so these specs
# stay structural: class identity, inheritance, and the action surface.
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

# Minimal stand-in for decidim-core's Decidim::ApplicationController.
unless defined?(Decidim::ApplicationController)
  module Decidim
    class ApplicationController < ActionController::Base
    end
  end
end

engine_root = File.expand_path("../../..", __dir__)

require File.join(engine_root, "app/helpers/decidim/contracts_sk/application_helper.rb")
require File.join(engine_root, "app/controllers/decidim/contracts_sk/application_controller.rb")
require File.join(engine_root, "app/controllers/decidim/contracts_sk/contracts_controller.rb")

# Nested in the Decidim::ContractsSk module namespace so the top-level
# describe names the scaffold controller while resolving relative
# constants inside the engine's scope.
module Decidim
  module ContractsSk
    RSpec.describe ContractsController do
      # AC 1: the controller loads properly (the requires above would raise
      # on any class-definition error, so reaching an example proves it
      # loaded) and is the engine's public ContractsController.
      it "is defined as a class" do
        expect(described_class).to be_a(Class)
      end

      it "is Decidim::ContractsSk::ContractsController" do
        expect(described_class.name)
          .to eq("Decidim::ContractsSk::ContractsController")
      end

      # AC 2: sits on the engine's public base controller chain - admin and
      # public behaviour stay clearly separated.
      it "inherits from Decidim::ContractsSk::ApplicationController" do
        expect(described_class.superclass)
          .to eq(Decidim::ContractsSk::ApplicationController)
      end

      # AC 3: the public catalogue action surface is present - the scaffold
      # answers #index and #show, matching the engine's public routes.
      it "defines :index and :show as public instance methods" do
        expect(described_class.public_instance_methods)
          .to include(:index, :show)
      end
    end
  end
end
