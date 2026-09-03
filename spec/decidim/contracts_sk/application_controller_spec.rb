# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, class-level specs for the engine's base controllers.
#
# Classes come from the Stage-1 dummy harness (spec/dummy): the stand-in
# Decidim::ApplicationController / Decidim::Admin::ApplicationController live
# in the dummy boot and answer #permission_class_chain with static sentinels
# (:stand_in_public_chain / :stand_in_admin_chain), so the delegation past
# this engine's own permissions class stays assertable offline. The engine
# classes themselves are provided by the dummy's autoloader.
# ---------------------------------------------------------------------------

require "spec_helper"

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
