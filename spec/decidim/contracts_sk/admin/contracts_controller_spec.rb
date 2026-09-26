# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the engine's admin contracts
# controller (civora-org/civora-platform#58, #59). Behavioural coverage
# (denied paths, allowed paths, validation failures, transitions) lives in
# spec/requests/admin/; this file pins only the class-level contract: the
# admin/public separation and the exact action surface (the five CRUD actions
# plus the six lifecycle-transition actions, the CRZ-handoff pair, the
# single-record CRZ import and the ADR-007 redaction-confirmation POST —
# no show, no destroy).
# ---------------------------------------------------------------------------

require "spec_helper"

module Decidim
  module ContractsSk
    RSpec.describe Admin::ContractsController do
      it "inherits from the engine's admin base controller" do
        expect(described_class.superclass).to eq(Admin::ApplicationController)
      end

      it "implements exactly the CRUD + transition + CRZ-handoff + import + redaction actions (no show, no destroy)" do
        expect(described_class.public_instance_methods(false).map(&:to_s).sort)
          .to eq(%w[
                   approve archive confirm_redaction create download_crz_handoff edit
                   generate_crz_handoff import_crz index new publish reject return submit update
                 ])
      end

      it "does not sit on the engine's public base controller chain" do
        expect(described_class.ancestors)
          .not_to include(Decidim::ContractsSk::ApplicationController)
      end
    end
  end
end
