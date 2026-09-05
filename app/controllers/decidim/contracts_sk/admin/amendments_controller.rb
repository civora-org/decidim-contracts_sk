# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin management of a contract's amendments (M02-05-B,
      # civora-org/civora-platform#65), nested under the contracts admin.
      #
      # Every action loads the parent contract from the tenant scope first
      # (a contract of another organization is invisible — the scoped find
      # raises RecordNotFound → 404). Member actions additionally load the
      # amendment itself BEFORE the permission check, because the decision
      # needs the amendment's draft state; index/new/create need only the
      # parent (create gates on the contract being published). Amendment
      # pages deliberately follow the parties pages' shape — dedicated
      # index/new/edit routes plus one explicit POST per publish event
      # (the lifecycle transition convention), no nested-form JS.
      class AmendmentsController < Admin::ApplicationController
        def index
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :read, :amendment, contract: @contract

          @amendments = @contract.amendments.order(version: :desc)
        end

        def new
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :create, :amendment, contract: @contract

          @form = AmendmentForm.new
        end

        def create
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :create, :amendment, contract: @contract

          @form = AmendmentForm.new(form_params)

          CreateAmendment.call(@form, @contract, user: current_user) do
            on(:ok) { create_succeeded }
            on(:invalid) { create_failed }
          end
        end

        def edit
          load_amendment

          enforce_permission_to :update, :amendment, contract: @contract, amendment: @amendment

          @form = AmendmentForm.new(summary: @amendment.summary)
        end

        def update
          load_amendment

          enforce_permission_to :update, :amendment, contract: @contract, amendment: @amendment

          @form = AmendmentForm.new(form_params)

          UpdateAmendment.call(@form, @amendment) do
            on(:ok) { update_succeeded }
            on(:invalid) { update_failed }
          end
        end

        # One explicit POST for the publish event. Both outcomes are PRG
        # redirects — a failure means the amendment's state changed under
        # us, and there is no form to re-render; the index shows the truth.
        def publish
          load_amendment

          enforce_permission_to :publish, :amendment, contract: @contract, amendment: @amendment

          PublishAmendment.call(@amendment, user: current_user) do
            on(:ok) { publish_succeeded }
            on(:invalid) { publish_failed }
          end
        end

        def destroy
          load_amendment

          enforce_permission_to :destroy, :amendment, contract: @contract, amendment: @amendment

          DestroyAmendment.call(@amendment) do
            on(:ok) { destroy_succeeded }
            on(:invalid) { destroy_failed }
          end
        end

        private

        # The member actions' shared preamble: tenant-scoped contract, then
        # the amendment through the contract's amendments association, so
        # the record is contract-scoped by construction.
        def load_amendment
          @contract = contracts_scope.find(params[:contract_id])
          @amendment = @contract.amendments.find(params[:id])
        end

        # PRG on success: notice + back to the contract's amendment index.
        def create_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.amendments.create.success")
          redirect_to admin_contract_amendments_path(@contract)
        end

        def update_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.amendments.update.success")
          redirect_to admin_contract_amendments_path(@contract)
        end

        # Failure re-renders the form with the command layer's error message
        # (flash.now so it survives only this render).
        def create_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.amendments.create.error")
          render :new, status: :unprocessable_entity
        end

        def update_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.amendments.update.error")
          render :edit, status: :unprocessable_entity
        end

        # Both publish outcomes are PRG redirects (see #publish).
        def publish_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.amendments.publish.success")
          redirect_to admin_contract_amendments_path(@contract)
        end

        def publish_failed
          flash[:alert] = t("decidim.contracts_sk.admin.amendments.publish.error")
          redirect_to admin_contract_amendments_path(@contract)
        end

        # Both outcomes are PRG redirects: a destroy failure means the row
        # changed under us, and there is no form to re-render — the index
        # shows the truth.
        def destroy_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.amendments.destroy.success")
          redirect_to admin_contract_amendments_path(@contract)
        end

        def destroy_failed
          flash[:alert] = t("decidim.contracts_sk.admin.amendments.destroy.error")
          redirect_to admin_contract_amendments_path(@contract)
        end

        # Tenant-scoped record access: a contract of another organization is
        # invisible here (find raises RecordNotFound → 404), not merely
        # permission-denied. The amendments are always reached through the
        # contract, so their tenancy is derived, never queried.
        def contracts_scope
          Contract.where(organization: current_organization)
        end

        # Only the amendment's own field is updatable through the form: a
        # draft carries its summary alone — the version is sequenced by the
        # command and the content snapshot is taken at publish time.
        def form_params
          params.require(:amendment).permit(:summary)
        end
      end
    end
  end
end
