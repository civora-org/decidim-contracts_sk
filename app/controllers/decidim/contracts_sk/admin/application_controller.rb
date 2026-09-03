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

        def permission_class_chain
          [Decidim::ContractsSk::Permissions, *super]
        end
      end
    end
  end
end
