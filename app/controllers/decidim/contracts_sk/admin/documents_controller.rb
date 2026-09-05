# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin management of a contract's documents
      # (civora-org/civora-platform#73), nested under the contracts admin.
      #
      # Every action loads the parent contract from the tenant scope first
      # (a contract of another organization is invisible — the scoped find
      # raises RecordNotFound → 404), then asks the permission layer with
      # the contract as context (its lifecycle state drives editability —
      # the decision needs only the parent), and only then the document
      # itself through the contract's documents association.
      #
      # There is deliberately no :index (the route set has none): the
      # documents themselves are listed on the contract's edit page, which
      # is also the PRG redirect target for every outcome here. The attach
      # page carries title/kind/file; the replace page swaps the file only —
      # its form's title/kind are pre-filled from the persisted record, so
      # the request cannot retouch the record's content fields.
      #
      # No request payload (and in particular no file content) is ever
      # logged: the engine writes no logger calls on this surface.
      class DocumentsController < Admin::ApplicationController
        def new
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :create, :document, contract: @contract

          @form = DocumentForm.new
        end

        def create
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :create, :document, contract: @contract

          @form = DocumentForm.new(form_params)

          AttachDocument.call(@form, @contract) do
            on(:ok) { create_succeeded }
            on(:invalid) { create_failed }
          end
        end

        def edit
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :update, :document, contract: @contract

          @document = @contract.documents.find(params[:id])

          # The edit request carries no document params — the form is built
          # purely from the persisted record.
          @form = DocumentForm.new(title: @document.title,
                                   kind: @document.kind)
        end

        def update
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :update, :document, contract: @contract

          @document = @contract.documents.find(params[:id])

          @form = replace_form

          ReplaceDocument.call(@form, @document) do
            on(:ok) { update_succeeded }
            on(:invalid) { update_failed }
          end
        end

        def destroy
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :destroy, :document, contract: @contract

          @document = @contract.documents.find(params[:id])

          DestroyDocument.call(@document) do
            on(:ok) { destroy_succeeded }
            on(:invalid) { destroy_failed }
          end
        end

        private

        # A replace swaps the file only: the form's title/kind mirror the
        # persisted record (they also satisfy the form's validations), and
        # only the file below comes from the request.
        def replace_form
          DocumentForm.new(form_params.merge(title: @document.title,
                                             kind: @document.kind))
        end

        # PRG on success: notice + back to the contract's edit page, where
        # the documents are listed (there is no document index route).
        def create_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.documents.create.success")
          redirect_to edit_admin_contract_path(@contract)
        end

        def update_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.documents.update.success")
          redirect_to edit_admin_contract_path(@contract)
        end

        # Failure re-renders the form with the command layer's error message
        # (flash.now so it survives only this render).
        def create_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.documents.create.error")
          render :new, status: :unprocessable_entity
        end

        def update_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.documents.update.error")
          render :edit, status: :unprocessable_entity
        end

        # Both outcomes are PRG redirects: a destroy failure means the row
        # changed under us, and there is no form to re-render — the
        # contract's edit page shows the truth.
        def destroy_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.documents.destroy.success")
          redirect_to edit_admin_contract_path(@contract)
        end

        def destroy_failed
          flash[:alert] = t("decidim.contracts_sk.admin.documents.destroy.error")
          redirect_to edit_admin_contract_path(@contract)
        end

        # Tenant-scoped record access: a contract of another organization is
        # invisible here (find raises RecordNotFound → 404), not merely
        # permission-denied. The documents are always reached through the
        # contract, so their tenancy is derived, never queried.
        def contracts_scope
          Contract.where(organization: current_organization)
        end

        # Only the document's own fields are admitted. On create all three
        # matter; on update the controller overrides title/kind from the
        # persisted record (a replace swaps the file only).
        def form_params
          params.require(:document).permit(:title, :kind, :file)
        end
      end
    end
  end
end
