# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Pins the inertness of the Stage-1 dummy harness' chain members
# (spec/dummy/config/application.rb): DummyAdminPermissions /
# DummyPublicPermissions subclass the REAL pinned-gem DefaultPermissions so
# they quack as chain members for the harness' real NeedsPermission, but they
# must decide NOTHING — for every real scope (:admin, :public) #permissions
# has to return the action untouched, so the chain tail stays unset and the
# outcome remains entirely the engine's Permissions class' business
# (fail-closed downstream: allowed_to? rescues PermissionNotSetError to
# false).
#
# The public twin nests under the admin class (one top-level example group
# per file), which is also why the file is named after the admin class.
# ---------------------------------------------------------------------------

require "spec_helper"

# One top-level group per file (rubocop-rspec MultipleDescribes): the public
# twin nests under the admin class with a comment naming the pairing.
RSpec.describe DummyAdminPermissions do
  it "leaves admin-scope actions untouched (inert chain member)" do
    action = Decidim::PermissionAction.new(scope: :admin, action: :read, subject: :contract)

    described_class.new(nil, action, {}).permissions

    expect { action.allowed? }.to raise_error(Decidim::PermissionAction::PermissionNotSetError)
  end

  it "leaves public-scope actions untouched (inert chain member)" do
    action = Decidim::PermissionAction.new(scope: :public, action: :read, subject: :contract)

    described_class.new(nil, action, {}).permissions

    expect { action.allowed? }.to raise_error(Decidim::PermissionAction::PermissionNotSetError)
  end

  # The public stand-in's chain member, paired here so both inertness pins
  # live in one file.
  describe DummyPublicPermissions do
    it "leaves public-scope actions untouched (inert chain member)" do
      action = Decidim::PermissionAction.new(scope: :public, action: :read, subject: :contract)

      described_class.new(nil, action, {}).permissions

      expect { action.allowed? }.to raise_error(Decidim::PermissionAction::PermissionNotSetError)
    end

    it "leaves admin-scope actions untouched (inert chain member)" do
      action = Decidim::PermissionAction.new(scope: :admin, action: :create, subject: :contract)

      described_class.new(nil, action, {}).permissions

      expect { action.allowed? }.to raise_error(Decidim::PermissionAction::PermissionNotSetError)
    end
  end
end
