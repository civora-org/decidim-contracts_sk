# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # The shared actor check of the organization-header commands: an
      # organization admin (accepted admin terms) of the very organization
      # the header belongs to. Mirrors the :organization_profile permission
      # rule, re-checked in the commands as defense in depth.
      module OrganizationProfileActor
        module_function

        def ok?(user, organization)
          user.respond_to?(:admin?) && user.admin? && user.admin_terms_accepted? &&
            user.decidim_organization_id == organization.id
        end
      end
    end
  end
end
