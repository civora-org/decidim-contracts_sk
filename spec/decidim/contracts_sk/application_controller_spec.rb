# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, class-level specs for the engine's base controllers.
#
# No dummy Rails app is required: we boot only the ActionController pieces of
# Rails and load the engine controller files directly.
#
# The real Decidim::ApplicationController (from decidim-core) cannot be
# required outside a full Decidim Rails app: it inherits DecidimController
# and includes ~20 app-coupled concerns (NeedsOrganization, ForceAuthentication,
# Devise/Cells integrations, ...). We therefore define a MINIMAL STAND-IN for
# Decidim::ApplicationController below, BEFORE the engine controller files are
# loaded. The stand-in carries no callbacks of its own, so the callback
# assertions (AC4) reflect this engine's code only.
#
# Once a dummy-app harness exists, delete the stub and the explicit requires
# and let the application autoloader provide the real classes instead.
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
require File.join(engine_root, "app/controllers/decidim/contracts_sk/admin/application_controller.rb")

RSpec.describe Decidim::ContractsSk::ApplicationController do
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

  # AC 3: helper methods available in views - the module is registered on the
  # controller's helpers.
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
end

RSpec.describe Decidim::ContractsSk::Admin::ApplicationController do
  # AC 1: the admin controller loads properly as well.
  it "is defined as a class" do
    expect(described_class).to be_a(Class)
  end

  # AC 2: the inheritance chain must be exactly
  # Admin::ApplicationController < ContractsSk::ApplicationController <
  # Decidim::ApplicationController. Neither class includes modules, so the
  # first three ancestors are the class chain itself.
  it "sits on top of the exact expected inheritance chain" do
    expect(described_class.ancestors.first(3)).to eq(
      [
        Decidim::ContractsSk::Admin::ApplicationController,
        Decidim::ContractsSk::ApplicationController,
        Decidim::ApplicationController
      ]
    )
  end

  # AC 3: the helper registered on the base controller stays available in
  # admin views through inheritance.
  it "inherits the ApplicationHelper registration from the base controller" do
    expect(described_class._helpers)
      .to include(Decidim::ContractsSk::ApplicationHelper)
  end

  # AC 4 (Option A regression guard): the ADMIN controller MUST authenticate
  # - an :authenticate_user! before_action must be declared.
  it "declares an :authenticate_user! before_action" do
    callback = described_class._process_action_callbacks
                              .find { |cb| cb.filter == :authenticate_user! }

    expect(callback).not_to be_nil
    expect(callback.kind).to eq(:before)
  end
end
