# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Form behind granting an engine role to an existing user
      # (M03-06-D, civora-org/civora-platform#111, parent #95).
      #
      # Two fields only: the email of an EXISTING user of the current
      # organization and the role to grant. The organization and the actor
      # are never form input - the command receives them from the
      # controller (tenant and session), so no param can steer them.
      #
      # The role must come from the engine's frozen vocabulary
      # (ContractLifecycle::ROLES, the same source as UserRole::ROLES). The
      # email is normalized at the reader (stripped, downcased) so the
      # lookup is insensitive to padding and case; presence is validated on
      # the normalized value. Whether the email belongs to a user is a
      # lookup the command decides - the form stays pure and DB-free.
      class UserRoleForm
        include ActiveModel::Model
        include ActiveModel::Attributes

        ROLES = ContractLifecycle::ROLES.map(&:to_s).freeze

        attribute :email, :string
        attribute :role, :string

        validates :email, presence: true
        validates :role, inclusion: { in: ROLES }

        def email
          super.to_s.strip.downcase
        end

        def role
          super.to_s.strip
        end
      end
    end
  end
end
