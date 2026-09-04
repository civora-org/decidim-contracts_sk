# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the engine's admin contracts
# controller (civora-org/civora-platform#58). Behavioural coverage (denied
# paths, allowed paths, validation failures) lives in
# spec/requests/admin/contracts_spec.rb; this file pins only the class-level
# contract: the admin/public separation and the exact action surface
# (create/edit only — no show, no destroy).
# ---------------------------------------------------------------------------

require "spec_helper"

module Decidim
  module ContractsSk
    RSpec.describe Admin::ContractsController do
      it "inherits from the engine's admin base controller" do
        expect(described_class.superclass).to eq(Admin::ApplicationController)
      end

      it "implements exactly the five admin CRUD actions (no show, no destroy)" do
        expect(described_class.public_instance_methods(false).map(&:to_s).sort)
          .to eq(%w[create edit index new update])
      end

      it "does not sit on the engine's public base controller chain" do
        expect(described_class.ancestors)
          .not_to include(Decidim::ContractsSk::ApplicationController)
      end
    end
  end
end
