# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin screens to list, grant and revoke the engine roles
      # (civora-org/civora-platform#112, parent #95): the role-holder list,
      # a user search, the grant and the revoke.
      #
      # Every action opens with enforce_permission_to on the :user_role
      # subject, BEFORE any record lookup - org admins with accepted admin
      # terms only (#111), so a refused user learns nothing about which ids
      # or users exist. The commands (GrantUserRole / RevokeUserRole) re-check
      # the actor inside their locks; this layer is request admission.
      #
      # Privacy: the picker never lists the organization's users. A grant
      # starts from a search (name, nickname or email, at least
      # MIN_QUERY_LENGTH characters, at most RESULT_LIMIT hits) that renders
      # name and nickname only - an email is matched against but never
      # printed, in line with Decidim's own admin, which keeps emails behind
      # an audited "show email" action. The search is a POST so an email
      # typed into it never lands in a URL, a log line or the browser
      # history. The grant carries the user's id, never an email: the
      # controller resolves the id inside the tenant scope and hands the
      # command the form it already expects.
      class UserRolesController < Admin::ApplicationController
        MIN_QUERY_LENGTH = 3
        MAX_QUERY_LENGTH = 100
        RESULT_LIMIT = 20

        helper_method :role_label

        def index
          enforce_permission_to :read, :user_role

          @holders = holders
        end

        def new
          enforce_permission_to :create, :user_role

          @query = ""
        end

        def search
          enforce_permission_to :create, :user_role

          @query = normalized_query
          if @query.length < MIN_QUERY_LENGTH
            flash.now[:alert] = t("decidim.contracts_sk.admin.user_roles.search.too_short", min: MIN_QUERY_LENGTH)
            render :new, status: :unprocessable_entity
          else
            @candidates = candidates(@query)
            @held_roles = held_roles(@candidates)
            render :new
          end
        end

        def create
          enforce_permission_to :create, :user_role

          user = grantable_user
          return grant_failed unless user

          form = UserRoleForm.new(email: user.email, role: params[:role].to_s)
          GrantUserRole.call(form, organization: current_organization, actor: current_user) do
            on(:ok) { grant_succeeded(user, form.role) }
            on(:invalid) { grant_failed }
          end
        end

        def destroy
          enforce_permission_to :destroy, :user_role

          user_role = roles_scope.includes(:user).find(params[:id])
          name = user_role.user.name
          role = user_role.role

          RevokeUserRole.call(user_role, actor: current_user) do
            on(:ok) { revoke_succeeded(name, role) }
            on(:invalid) { revoke_failed }
          end
        end

        private

        # The tenant scope for every role row: another organization's id is
        # invisible (find raises RecordNotFound -> 404).
        def roles_scope
          UserRole.where(decidim_organization_id: current_organization.id)
        end

        # Holders grouped per user, oldest grant first: [[user, [role rows]]].
        def holders
          roles_scope.includes(:user).order(:created_at, :id).group_by(&:user).to_a
        end

        # The search text: NUL bytes dropped (PostgreSQL rejects them in a
        # string literal), whitespace stripped, capped. Anything but a plain
        # string (an array or hash param) degrades to the empty query.
        def normalized_query
          raw = params[:q]
          return "" unless raw.is_a?(String)

          raw.delete("\0").strip.first(MAX_QUERY_LENGTH)
        end

        # Confirmed, available users of this organization whose name,
        # nickname or email contains the query (case-insensitive, LIKE
        # wildcards escaped). Bounded and deterministically ordered.
        def candidates(query)
          pattern = "%#{Decidim::User.sanitize_sql_like(query.downcase)}%"
          user_scope.where("LOWER(name) LIKE :p ESCAPE '\\' OR LOWER(nickname) LIKE :p ESCAPE '\\' " \
                           "OR LOWER(email) LIKE :p ESCAPE '\\'", p: pattern)
                    .order(:name, :id).limit(RESULT_LIMIT).to_a
        end

        # Users who may be granted a role: of this organization, not deleted,
        # blocked or managed, and email-confirmed.
        def user_scope
          Decidim::User.where(organization: current_organization).available.confirmed
        end

        # The user behind a grant click, from the tenant scope only; a foreign,
        # unconfirmed or unknown id yields nil.
        def grantable_user
          user_scope.find_by(id: params[:user_id].to_s)
        end

        # { user id => [role strings already held] } for the shown candidates.
        def held_roles(users)
          roles_scope.where(decidim_user_id: users.map(&:id)).group_by(&:decidim_user_id)
                     .transform_values { |rows| rows.map(&:role) }
        end

        def role_label(role)
          t(role, scope: "decidim.contracts_sk.admin.user_roles.roles")
        end

        def grant_succeeded(user, role)
          flash[:notice] = t("decidim.contracts_sk.admin.user_roles.create.success",
                             role: role_label(role), name: user.name)
          redirect_to admin_user_roles_path
        end

        # One generic failure for every refusal (unknown or unconfirmed user,
        # bad role, duplicate, in-lock guard): the screen never says which.
        def grant_failed
          flash[:alert] = t("decidim.contracts_sk.admin.user_roles.create.invalid")
          redirect_to new_admin_user_role_path
        end

        def revoke_succeeded(name, role)
          flash[:notice] = t("decidim.contracts_sk.admin.user_roles.destroy.success",
                             role: role_label(role), name: name)
          redirect_to admin_user_roles_path
        end

        def revoke_failed
          flash[:alert] = t("decidim.contracts_sk.admin.user_roles.destroy.invalid")
          redirect_to admin_user_roles_path
        end
      end
    end
  end
end
