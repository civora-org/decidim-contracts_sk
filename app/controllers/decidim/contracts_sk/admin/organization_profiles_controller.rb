# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # The organization's contract header (civora-org/civora-platform#211,
      # P6): the allowlisted values (IČO, name, seat, statutory
      # representative, ...) that document generation fills into every
      # contract made from a template. A singular resource: one header per
      # organization, always the current organization's own. Organization
      # admins only (the :organization_profile permission subject); the
      # header is the town's public identifiers, never personal data of
      # citizens.
      class OrganizationProfilesController < Admin::ApplicationController
        helper_method :header_keys, :header_label

        def show
          enforce_permission_to :read, :organization_profile

          @profile = profile
        end

        def new
          enforce_permission_to :create, :organization_profile

          return redirect_to(edit_admin_organization_profile_path) if profile

          @form = OrganizationProfileForm.new
        end

        def create
          enforce_permission_to :create, :organization_profile

          save(:new, :create)
        end

        def edit
          enforce_permission_to :update, :organization_profile

          return redirect_to(new_admin_organization_profile_path) unless profile

          @form = OrganizationProfileForm.for_profile(profile)
        end

        def update
          enforce_permission_to :update, :organization_profile

          save(:edit, :update)
        end

        def destroy
          enforce_permission_to :destroy, :organization_profile

          return redirect_to(admin_organization_profile_path) unless profile

          DestroyOrganizationProfile.call(profile, organization: current_organization, user: current_user) do
            on(:ok) { done(:destroyed) }
            on(:invalid) do
              flash[:alert] = t("decidim.contracts_sk.admin.organization_profiles.destroy.invalid")
              redirect_to admin_organization_profile_path
            end
          end
        end

        private

        def save(failure_view, action)
          @form = OrganizationProfileForm.new(form_params)
          SaveOrganizationProfile.call(@form, organization: current_organization, user: current_user) do
            on(:ok) { done(action == :create ? :created : :updated) }
            on(:invalid) do
              flash.now[:alert] = t("decidim.contracts_sk.admin.organization_profiles.#{action}.invalid")
              render failure_view, status: :unprocessable_entity
            end
          end
        end

        def done(outcome)
          flash[:notice] = t("decidim.contracts_sk.admin.organization_profiles.#{outcome}")
          redirect_to admin_organization_profile_path
        end

        def profile
          @profile ||= ContractOrganizationProfile.find_by(organization: current_organization)
        end

        def form_params
          raw = params[:organization_profile]
          raw = ActionController::Parameters.new unless raw.is_a?(ActionController::Parameters)
          raw.permit(*header_keys)
        end

        def header_keys
          ContractOrganizationProfile::HEADER_KEYS
        end

        def header_label(key)
          t(key, scope: "decidim.contracts_sk.admin.template_entries.header")
        end
      end
    end
  end
end
