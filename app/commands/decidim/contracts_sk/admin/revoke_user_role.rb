# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Revokes a stored engine role (M03-06-D, civora-org/civora-platform
      # #111, parent #95).
      #
      # The audit row ("user_role.revoke_<role>", target = the affected
      # Decidim::User - the UserRole row is deleted, so it cannot be the
      # target; actor = the acting admin; no payload, no email or name) and
      # the deletion commit atomically in one transaction.
      #
      # Same discipline as GrantUserRole: the actor and the affected user
      # are locked together (ascending id) and the actor's authority is
      # re-read fresh inside the lock - an organization admin with accepted
      # terms of the role's organization. The role row is then locked and
      # reloaded (lock!): a row already revoked by a concurrent request, or
      # a stale in-memory copy of it, raises RecordNotFound and is answered
      # :invalid with NO audit row - a revoke is never written twice.
      #
      # The role's organization must be the actor's own (another
      # organization's row is refused). Self-revocation by an admin is
      # allowed on purpose (#95 Gate-1: the admin default keeps every admin
      # holding both roles, so no lockout exists to guard against).
      class RevokeUserRole < Decidim::Command
        def initialize(user_role, actor:)
          super()
          @user_role = user_role
          @actor = actor
        end

        def call
          revoke
          broadcast(:ok)
        rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordInvalid, Refused
          broadcast(:invalid)
        end

        private

        attr_reader :user_role, :actor

        # Raised inside the transaction when an in-lock guard refuses, so
        # the transaction unwinds and #call answers :invalid.
        Refused = Class.new(StandardError)

        def revoke
          UserRole.transaction do
            locked = lock_users
            raise Refused unless actor_authorized?(locked)

            user_role.lock!
            AuditEvent.create!(action: "user_role.revoke_#{user_role.role}", target: user_role.user,
                               organization: user_role.organization, actor: actor)
            user_role.destroy!
          end
        end

        def lock_users
          ids = [actor&.id, user_role.decidim_user_id].compact.uniq
          Decidim::User.where(id: ids).order(:id).lock.index_by(&:id)
        end

        def actor_authorized?(locked)
          fresh = actor && locked[actor.id]
          return false unless fresh

          fresh.decidim_organization_id == user_role.decidim_organization_id &&
            fresh.admin? && fresh.admin_terms_accepted?
        end
      end
    end
  end
end
