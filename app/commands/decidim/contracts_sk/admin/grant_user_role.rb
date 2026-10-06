# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Grants an engine role to an existing user of the organization
      # (M03-06-D, civora-org/civora-platform#111, parent #95).
      #
      # The role row and its audit row ("user_role.grant_<role>", target =
      # the affected Decidim::User, actor = the acting admin; no JSON
      # payload, no email or name anywhere) commit atomically in one
      # transaction.
      #
      # Authority is re-checked at execution time, fail-closed, INSIDE the
      # transaction - the repo-wide lock discipline (TransitionContract).
      # The controller's permission check is only request admission; here
      # the actor and the target user rows are locked together (ascending
      # id, so two admins granting to each other cannot deadlock) and read
      # back fresh: an actor demoted or un-accepted, or a target blocked,
      # deleted or moved, after admission can never produce a grant. The
      # actor must be an organization admin with accepted terms of THIS
      # organization - the same rule as the :user_role permission.
      #
      # A grant the user already holds is :invalid and writes nothing (no
      # role row, no audit row): UserRole's scoped uniqueness validation
      # raises inside the transaction, and the unique index backstops a
      # concurrent duplicate that slips past it (RecordNotUnique); both are
      # rescued the same way. An unknown email, or one
      # of another organization, yields the one generic form error - never
      # more detail about which case it was.
      class GrantUserRole < Decidim::Command
        def initialize(form, organization:, actor:)
          super()
          @form = form
          @organization = organization
          @actor = actor
        end

        def call
          return broadcast(:invalid) unless form.valid?

          user = lookup_user
          return reject_unknown_email unless user

          user_role = grant(user)
          return broadcast(:invalid) unless user_role

          broadcast(:ok, user_role)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::RecordNotFound
          broadcast(:invalid)
        end

        private

        attr_reader :form, :organization, :actor

        # The unlocked lookup that finds the row to lock: an available user
        # of this organization with this email (the issue's exact scope).
        def lookup_user
          Decidim::User.where(organization: organization).available.find_by(email: form.email)
        end

        def reject_unknown_email
          form.errors.add(:email, I18n.t("decidim.contracts_sk.admin.user_roles.form.unknown_email"))
          broadcast(:invalid)
        end

        # The role and audit rows, atomically, under the user locks; nil
        # when an in-lock guard refuses (nothing written).
        def grant(user)
          UserRole.transaction do
            locked = lock_users(user)
            next unless actor_authorized?(locked) && target_eligible?(locked, user)

            UserRole.create!(user: user, organization: organization, role: form.role).tap do
              AuditEvent.create!(action: "user_role.grant_#{form.role}", target: user,
                                 organization: organization, actor: actor)
            end
          end
        end

        # Both rows, FOR UPDATE, in ascending id order (see the class comment).
        def lock_users(user)
          ids = [actor&.id, user.id].compact.uniq
          Decidim::User.where(id: ids).order(:id).lock.index_by(&:id)
        end

        # Fresh, locked state of the actor: an organization admin with
        # accepted terms of this organization.
        def actor_authorized?(locked)
          fresh = actor && locked[actor.id]
          return false unless fresh

          fresh.decidim_organization_id == organization.id && fresh.admin? && fresh.admin_terms_accepted?
        end

        # Fresh, locked state of the target: still of this organization and
        # still available (not deleted, blocked or managed).
        def target_eligible?(locked, user)
          fresh = locked[user.id]
          return false unless fresh

          fresh.decidim_organization_id == organization.id &&
            fresh.deleted_at.nil? && !fresh.blocked? && !fresh.managed?
        end
      end
    end
  end
end
