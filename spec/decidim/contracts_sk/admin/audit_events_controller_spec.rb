# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline, structural specs for the engine's admin audit-trail
# viewer controller (civora-org/civora-platform#92). Behavioural coverage
# (denied paths, org scoping, contract filter, dangling targets, paging)
# lives in spec/requests/admin/audit_events_spec.rb; this file pins only the
# class-level contract: the admin/public separation and the exact action
# surface (index only — the trail is append-only, so the viewer has no
# write or destroy surface).
# ---------------------------------------------------------------------------

require "spec_helper"

module Decidim
  module ContractsSk
    # The commands write exactly these action strings (transition events
    # via "contract.<event>", plus the redaction stamp, the amendment
    # publish and the two CRZ-import actions); the viewer's frozen label
    # mapping must cover every one of them, otherwise a row would fall
    # back to the humanized label.
    EXPECTED_AUDIT_ACTION_KEYS = %w[
      amendment.publish contract.approve contract.archive contract.publish
      contract.redaction_confirmed contract.reject contract.return
      contract.submit crz_import_create crz_import_update
    ].freeze

    RSpec.describe Admin::AuditEventsController do
      it "inherits from the engine's admin base controller" do
        expect(described_class.superclass).to eq(Admin::ApplicationController)
      end

      it "implements exactly the index action (read-only viewer)" do
        expect(described_class.public_instance_methods(false).map(&:to_s).sort)
          .to eq(%w[index])
      end

      it "does not sit on the engine's public base controller chain" do
        expect(described_class.ancestors)
          .not_to include(Decidim::ContractsSk::ApplicationController)
      end

      it "pins the audit action vocabulary actually written by the commands" do
        expect(described_class::ACTION_KEYS.keys.sort).to eq(EXPECTED_AUDIT_ACTION_KEYS)
      end

      it "derives the six lifecycle-action keys from the transition table, never hand-enumerated" do
        table_events = ContractLifecycle::TRANSITIONS.values.flat_map(&:keys).uniq.sort

        table_events.each do |event|
          expect(described_class::ACTION_KEYS)
            .to have_key("contract.#{event}"), "missing label mapping for contract.#{event}"
        end
      end
    end
  end
end
