# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin management of a contract's parties
      # (civora-org/civora-platform#76), nested under the contracts admin.
      #
      # Every action loads the parent contract from the tenant scope first
      # (a contract of another organization is invisible — the scoped find
      # raises RecordNotFound → 404), then asks the permission layer with
      # the contract as context (its lifecycle state drives editability —
      # the decision needs only the parent), and only then the party itself
      # through the contract's parties association.
      # Party pages deliberately follow the contracts pages' shape —
      # dedicated index/new/edit routes, no nested-form JS.
      class PartiesController < Admin::ApplicationController
        def index
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :read, :party, contract: @contract

          @parties = @contract.parties.order(:id)
        end

        def new
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :create, :party, contract: @contract

          @form = PartyForm.new
        end

        def create
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :create, :party, contract: @contract

          @form = PartyForm.new(form_params)

          CreateParty.call(@form, @contract) do
            on(:ok) { create_succeeded }
            on(:invalid) { create_failed }
          end
        end

        def edit
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :update, :party, contract: @contract

          @party = @contract.parties.find(params[:id])

          @form = PartyForm.new(role: @party.role,
                                name: @party.name,
                                ico: @party.ico,
                                address: @party.address)
        end

        def update
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :update, :party, contract: @contract

          @party = @contract.parties.find(params[:id])

          @form = PartyForm.new(form_params)

          UpdateParty.call(@form, @party) do
            on(:ok) { update_succeeded }
            on(:invalid) { update_failed }
          end
        end

        def destroy
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :destroy, :party, contract: @contract

          @party = @contract.parties.find(params[:id])

          DestroyParty.call(@party) do
            on(:ok) { destroy_succeeded }
            on(:invalid) { destroy_failed }
          end
        end

        private

        # PRG on success: notice + back to the contract's party index.
        def create_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.parties.create.success")
          redirect_to admin_contract_parties_path(@contract)
        end

        def update_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.parties.update.success")
          redirect_to admin_contract_parties_path(@contract)
        end

        # Failure re-renders the form with the command layer's error message
        # (flash.now so it survives only this render).
        def create_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.parties.create.error")
          render :new, status: :unprocessable_entity
        end

        def update_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.parties.update.error")
          render :edit, status: :unprocessable_entity
        end

        # Both outcomes are PRG redirects: a destroy failure means the row
        # changed under us, and there is no form to re-render — the index
        # shows the truth.
        def destroy_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.parties.destroy.success")
          redirect_to admin_contract_parties_path(@contract)
        end

        def destroy_failed
          flash[:alert] = t("decidim.contracts_sk.admin.parties.destroy.error")
          redirect_to admin_contract_parties_path(@contract)
        end

        # Tenant-scoped record access: a contract of another organization is
        # invisible here (find raises RecordNotFound → 404), not merely
        # permission-denied. The parties are always reached through the
        # contract, so their tenancy is derived, never queried.
        def contracts_scope
          Contract.where(organization: current_organization)
        end

        # Only the party's content fields are updatable through the form.
        # The parent contract is never form-writable: it comes from the
        # route and the tenant scope, so a form param can never re-attach a
        # party to a foreign contract.
        def form_params
          params.require(:party).permit(:role, :name, :ico, :address)
        end
      end
    end
  end
end
