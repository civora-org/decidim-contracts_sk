# frozen_string_literal: true

module Decidim
  module ContractsSk
    # An organization-scoped grant of one engine role (editor or reviewer) to
    # a Decidim user (M03-06-B, civora-org/civora-platform#109, parent #95).
    #
    # Nothing reads this model yet: the resolver union and the grant
    # commands are separate sub-issues. The row stores only the user
    # reference, the organization and the role — no personal data.
    #
    # The role vocabulary is ContractLifecycle::ROLES, stored as strings. No
    # has_many is added to Decidim core models (never patch Decidim core).
    class UserRole < ApplicationRecord
      ROLES = ContractLifecycle::ROLES.map(&:to_s).freeze

      # optional: false is explicit so presence does not depend on the host's
      # belongs_to_required_by_default setting.
      belongs_to :user, foreign_key: "decidim_user_id", class_name: "Decidim::User", optional: false
      belongs_to :organization, foreign_key: "decidim_organization_id",
                                class_name: "Decidim::Organization", optional: false

      validates :role, inclusion: { in: ROLES }

      # Mirrors the migration's unique index
      # index_decidim_contracts_sk_user_roles_unique: one grant per
      # (user, organization, role). The DB index is the backstop for
      # concurrent creates; a user may still hold both roles.
      validates :role, uniqueness: { scope: %i[decidim_user_id decidim_organization_id] }

      validate :user_belongs_to_organization

      private

      # No cross-tenant grants: the user must belong to the organization the
      # role is granted in.
      def user_belongs_to_organization
        return if user.nil? || organization.nil?
        return if user.decidim_organization_id == decidim_organization_id

        errors.add(:user, :invalid)
      end
    end
  end
end
