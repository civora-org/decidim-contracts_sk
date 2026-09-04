# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin CRUD for contract records — create and edit only
      # (civora-org/civora-platform#58).
      #
      # index/new/create open with enforce_permission_to before anything
      # else; edit/update load the record first, so the permission check can
      # see the record's lifecycle state. Denial is handled by the inherited
      # Decidim::NeedsPermission machinery (redirect + alert). The lifecycle
      # state is never written from here: creation lands on
      # the model's draft default, updates go through UpdateContract, and
      # transitions belong to the dedicated transition milestone
      # (civora-org/civora-platform#60).
      class ContractsController < Admin::ApplicationController
        def index
          enforce_permission_to :read, :contract

          @contracts = contracts_scope
        end

        def new
          enforce_permission_to :create, :contract

          @form = ContractForm.new
        end

        def create
          enforce_permission_to :create, :contract

          @form = ContractForm.new(form_params)

          CreateContract.call(@form, user: current_user, organization: current_organization) do
            on(:ok) { create_succeeded }
            on(:invalid) { create_failed }
          end
        end

        def edit
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :update, :contract, contract: @contract

          @form = ContractForm.new(title: @contract.title, reference: @contract.reference)
        end

        def update
          @contract = contracts_scope.find(params[:id])

          enforce_permission_to :update, :contract, contract: @contract

          @form = ContractForm.new(form_params)

          UpdateContract.call(@form, @contract) do
            on(:ok) { update_succeeded }
            on(:invalid) { update_failed }
          end
        end

        private

        # PRG on success: notice + back to the admin index.
        def create_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.contracts.create.success")
          redirect_to admin_contracts_path
        end

        def update_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.contracts.update.success")
          redirect_to admin_contracts_path
        end

        # Failure re-renders the form with the command layer's error message
        # (flash.now so it survives only this render).
        def create_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.contracts.create.error")
          render :new, status: :unprocessable_entity
        end

        def update_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.contracts.update.error")
          render :edit, status: :unprocessable_entity
        end

        # Tenant-scoped record access: a contract of another organization is
        # invisible here (find raises RecordNotFound → 404), not merely
        # permission-denied.
        def contracts_scope
          Contract.where(organization: current_organization)
        end

        # Only the editorial identity fields are updatable through the form.
        # state, provenance, organization and author are deliberately absent:
        # adding them here would bypass the command layer's ownership rules.
        def form_params
          params.require(:contract).permit(:title, :reference)
        end
      end
    end
  end
end
