# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin CRUD for contract templates (civora-org/civora-platform#127):
      # organization-level, so a flat resource (no parent record). Every
      # action asks the :template permission (editor only) before touching
      # anything; records are loaded from the organization's scope, so a
      # template of another organization is invisible (RecordNotFound -> 404),
      # not merely permission-denied.
      #
      # A template is only a prefill. Nothing here creates, publishes or
      # advances a contract; starting a draft from a template is the
      # contracts#new/#create flow (?template_id=).
      class TemplatesController < Admin::ApplicationController
        # The fields the form (and so the strong params) admit. The
        # organization never comes from params.
        TEMPLATE_FIELDS = %i[name title_pattern subject_matter currency
                             object_party_name object_party_ico object_party_address].freeze

        def index
          enforce_permission_to :read, :template

          @templates = templates_scope.order(:name, :id)
        end

        def new
          enforce_permission_to :create, :template

          @form = TemplateForm.new
        end

        def create
          enforce_permission_to :create, :template

          @form = TemplateForm.new(form_params)

          CreateTemplate.call(@form, organization: current_organization) do
            on(:ok) { create_succeeded }
            on(:invalid) { create_failed }
          end
        end

        def edit
          enforce_permission_to :update, :template

          @template = templates_scope.find(params[:id])
          @form = TemplateForm.new(@template.slice(*TEMPLATE_FIELDS))
        end

        def update
          enforce_permission_to :update, :template

          @template = templates_scope.find(params[:id])
          @form = TemplateForm.new(form_params)

          UpdateTemplate.call(@form, @template) do
            on(:ok) { update_succeeded }
            on(:invalid) { update_failed }
          end
        end

        def destroy
          enforce_permission_to :destroy, :template

          @template = templates_scope.find(params[:id])

          DestroyTemplate.call(@template) do
            on(:ok) { destroy_succeeded }
            on(:invalid) { destroy_failed }
          end
        end

        private

        def create_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.templates.create.success")
          redirect_to admin_templates_path
        end

        def update_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.templates.update.success")
          redirect_to admin_templates_path
        end

        def create_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.templates.create.error")
          render :new, status: :unprocessable_entity
        end

        def update_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.templates.update.error")
          render :edit, status: :unprocessable_entity
        end

        def destroy_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.templates.destroy.success")
          redirect_to admin_templates_path
        end

        # A destroy failure means the row changed under us; there is no form
        # to re-render, so the index shows the truth.
        def destroy_failed
          flash[:alert] = t("decidim.contracts_sk.admin.templates.destroy.error")
          redirect_to admin_templates_path
        end

        def templates_scope
          Template.where(organization: current_organization)
        end

        # permit-then-fetch (the notes precedent): a malformed param (a
        # scalar instead of a hash) yields an empty form and a 422, never a
        # 500.
        def form_params
          params.permit(template: TEMPLATE_FIELDS).fetch(:template, {})
        end
      end
    end
  end
end
