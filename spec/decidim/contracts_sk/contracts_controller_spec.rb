# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, class-level specs for the public contracts
# catalogue controller.
#
# Classes come from the Stage-1 dummy harness (spec/dummy): the engine
# classes are provided by the dummy's autoloader, and the stand-in
# Decidim::ApplicationController lives in the dummy boot.
#
# These specs stay structural: class identity, inheritance, and the action
# surface. Request-level behaviour — the published-only scoping, rendering
# and not-found semantics (civora-org/civora-platform#62, #63) — is covered
# by spec/requests/contracts_spec.rb against the dummy routes.
# ---------------------------------------------------------------------------

require "spec_helper"

# Nested in the Decidim::ContractsSk module namespace so the top-level
# describe names the catalogue controller while resolving relative
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

      # AC 3: the public catalogue action surface is present - the controller
      # answers #index and #show, matching the engine's public routes.
      it "defines :index and :show as public instance methods" do
        expect(described_class.public_instance_methods)
          .to include(:index, :show)
      end
    end
  end
end
