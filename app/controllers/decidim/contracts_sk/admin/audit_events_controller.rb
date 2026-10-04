# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Read-only admin audit-trail viewer (civora-org/civora-platform#92):
      # one org-level index over the append-only AuditEvent trail, written
      # by the admin commands and the CRZ import (exactly one row per
      # successful audited action). Nothing here ever writes — the model
      # itself is append-only (AuditEvent#readonly?), so the viewer exposes
      # index only.
      #
      # The list is scoped to the current organization (tenancy is stored
      # explicitly on the event, never derived through the polymorphic
      # target) under the same deterministic newest-first order as the
      # contracts index (INDEX_ORDER: created_at desc, id desc — a total
      # order, so pages never repeat or drop rows). An optional
      # ?contract_id= GET param narrows the list to one contract's events;
      # the contract is looked up through the tenant scope, so a foreign or
      # nonexistent id is an indistinguishable 404 (the contracts
      # controller's organization-scoped lookup discipline).
      #
      # index opens with enforce_permission_to before anything else; denial
      # is handled by the inherited Decidim::NeedsPermission machinery
      # (redirect + alert). The :audit_event/:read permission mirrors the
      # admin contracts index (:read :contract): any engine role.
      class AuditEventsController < Admin::ApplicationController
        # The action/actor/target/reason presentation helpers and the
        # action vocabulary (ACTION_KEYS, CONTRACT_TARGET_TYPE) live in the
        # concern shared with the admin dashboard's recent-activity block
        # (civora-org/civora-platform#126); AuditEventsController::ACTION_KEYS
        # still resolves through the include.
        include AuditEventPresentation

        def index
          enforce_permission_to :read, :audit_event

          @contract = filtered_contract

          # The page param reaches Kaminari only as a string: an array
          # (page[]=2) would raise inside Kaminari's Integer coercion (the
          # contracts index's guard, mirrored here).
          @audit_events = filtered_events.page(params[:page].to_s)
                                         .per(Decidim::ContractsSk::CONTRACTS_PER_PAGE)
        end

        private

        # The tenant scope under the deterministic order, narrowed by the
        # optional contract filter. Each filter leg is conditional — an
        # absent contract_id contributes no WHERE clause.
        def filtered_events
          scope = audit_events_scope.order(INDEX_ORDER)
          if filtered_contract
            scope.where(target_type: CONTRACT_TARGET_TYPE, target_id: filtered_contract.id)
          else
            scope
          end
        end

        # Tenancy is explicit on the event rows (decidim_organization_id);
        # it can never be derived through the polymorphic target.
        def audit_events_scope
          AuditEvent.where(organization: current_organization)
        end

        # The contract behind the optional ?contract_id= filter, loaded from
        # the tenant scope: another organization's contract (or a
        # nonexistent id) raises RecordNotFound → 404, exactly like the
        # contracts controller's tenant-scoped lookups. nil when no filter
        # is active.
        def filtered_contract
          return nil if params[:contract_id].blank?

          @filtered_contract ||= contracts_scope.find(params[:contract_id])
        end

        # Tenant-scoped contract access for the filter (see
        # ContractsController#contracts_scope).
        def contracts_scope
          Contract.where(organization: current_organization)
        end
      end
    end
  end
end
