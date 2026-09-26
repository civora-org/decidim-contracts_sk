# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin management of a contract's project/result links (M01-87,
      # civora-org/civora-platform#87), nested under the contracts admin.
      #
      # Every action loads the parent contract from the tenant scope first
      # (a contract of another organization is invisible — the scoped find
      # raises RecordNotFound → 404), then asks the permission layer with
      # the contract as context (its lifecycle state drives editability —
      # the decision needs only the parent), and only then the link itself
      # through the contract's links association.
      #
      # There are deliberately only two actions: links carry no editable
      # content, so the route set has no index/new/edit/update — the
      # contract's edit page is the hub: it lists the links (flagging the
      # dangling ones), hosts the plain add form, and is the PRG redirect
      # target for every outcome here.
      #
      # No request payload is ever logged: the engine writes no logger calls
      # on this surface.
      class LinksController < Admin::ApplicationController
        def create
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :create, :link, contract: @contract

          @form = LinkForm.new(form_params)

          CreateLink.call(@form, @contract) do
            on(:ok) { create_succeeded }
            on(:invalid) { create_failed }
          end
        end

        def destroy
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :destroy, :link, contract: @contract

          @link = @contract.links.find(params[:id])

          DestroyLink.call(@link) do
            on(:ok) { destroy_succeeded }
            on(:invalid) { destroy_failed }
          end
        end

        private

        # PRG on success: notice + back to the contract's edit page, where
        # the links are listed (there is no link index route).
        def create_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.links.create.success")
          redirect_to edit_admin_contract_path(@contract)
        end

        # Failure is a PRG redirect too: there is no dedicated form page to
        # re-render (the form lives on the contract's edit page, like the
        # document destroy rationale), so the edit page shows the truth —
        # with the command layer's alert.
        def create_failed
          flash[:alert] = t("decidim.contracts_sk.admin.links.create.error")
          redirect_to edit_admin_contract_path(@contract)
        end

        # Both outcomes are PRG redirects: a destroy failure means the row
        # changed under us, and there is no form to re-render — the
        # contract's edit page shows the truth.
        def destroy_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.links.destroy.success")
          redirect_to edit_admin_contract_path(@contract)
        end

        def destroy_failed
          flash[:alert] = t("decidim.contracts_sk.admin.links.destroy.error")
          redirect_to edit_admin_contract_path(@contract)
        end

        # Tenant-scoped record access: a contract of another organization is
        # invisible here (find raises RecordNotFound → 404), not merely
        # permission-denied. The links are always reached through the
        # contract, so their tenancy is derived, never queried.
        def contracts_scope
          Contract.where(organization: current_organization)
        end

        # Only the link's own fields are admitted. The parent contract is
        # never form-writable: it comes from the route and the tenant scope,
        # so a form param can never re-attach a link to a foreign contract.
        def form_params
          params.require(:link).permit(:target_type, :target_id)
        end
      end
    end
  end
end
