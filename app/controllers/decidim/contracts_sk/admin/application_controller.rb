# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Base controller for the admin namespace of the ContractsSk module.
      #
      # Inherits Decidim's admin application controller for admin-level
      # authorization machinery (permission scope :admin, admin layout,
      # admin helpers) instead of only checking that a user is signed in.
      # Individual actions must still call enforce_permission_to to
      # enforce permissions.
      #
      # authenticate_user! is kept as a defense-in-depth floor: Decidim
      # enforces admin login at the route level (OrganizationDashboardConstraint),
      # which only applies when the engine is mounted inside that constraint.
      class ApplicationController < ::Decidim::Admin::ApplicationController
        helper Decidim::ContractsSk::ApplicationHelper

        before_action :authenticate_user!
        before_action :require_second_factor!

        # Optional second-factor guard (civora-org/civora-platform#165,
        # ADR-010): a no-op unless the host assigns
        # Decidim::ContractsSk.second_factor_satisfied. Admin-only: public
        # and in-space controllers do not inherit this class.
        def require_second_factor!
          return if Decidim::ContractsSk.second_factor_satisfied.call(current_user, session)

          flash[:alert] = I18n.t("decidim.contracts_sk.admin.second_factor.required")
          redirect_to Decidim::ContractsSk.second_factor_redirect_path.call(self)
        end

        def permission_class_chain
          [Decidim::ContractsSk::Permissions, *super]
        end

        # Refusal landing (civora-org/civora-platform#161, D1 of the #108
        # spike). Decidim's admin base redirects every refusal to
        # decidim_admin.root_path (/admin), which is a 404 for a non-admin
        # engine-role holder (Decidim's dashboard constraint). Engine role
        # holders land on the engine admin root (open to any role), everyone
        # else on the public catalogue; the "not authorized" flash is
        # unchanged. A referer, when present, still wins (NeedsPermission).
        def user_has_no_permission_path
          if Decidim::ContractsSk::Menu.holds_engine_role?(current_user, current_organization)
            admin_root_path
          else
            contracts_path
          end
        end

        def user_not_authorized_path
          user_has_no_permission_path
        end
      end
    end
  end
end
