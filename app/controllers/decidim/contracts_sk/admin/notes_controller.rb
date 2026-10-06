# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Admin internal review notes on a contract (civora-org/civora-platform
      # #128), nested under the contracts admin: the thread page (index) and
      # the append (create). There is deliberately no edit/update/destroy —
      # notes are append-only.
      #
      # Every action loads the parent contract from the tenant scope first (a
      # contract of another organization is invisible: RecordNotFound → 404),
      # then asks the permission layer. Any engine role holder may read and
      # add (the reviewer cannot reach the contract's edit page, so this page
      # is their entry). The edit page embeds the same thread partial.
      #
      # No note body is ever logged: the engine writes no logger calls here.
      class NotesController < Admin::ApplicationController
        def index
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :read, :note, contract: @contract

          @form = NoteForm.new
          load_notes
        end

        def create
          @contract = contracts_scope.find(params[:contract_id])

          enforce_permission_to :create, :note, contract: @contract

          @form = NoteForm.new(form_params)

          CreateNote.call(@form, @contract, user: current_user) do
            on(:ok) { create_succeeded }
            on(:invalid) { create_failed }
          end
        end

        private

        def create_succeeded
          flash[:notice] = t("decidim.contracts_sk.admin.notes.create.success")
          redirect_to admin_contract_notes_path(@contract)
        end

        # Re-renders the thread page with the typed text kept, so a rejected
        # note (blank, over the cap, record gone from under us) is not lost.
        def create_failed
          load_notes
          flash.now[:alert] = t("decidim.contracts_sk.admin.notes.create.error")
          render :index, status: :unprocessable_entity
        end

        def load_notes
          @notes = @contract.notes.includes(:author).order(:id)
        end

        def contracts_scope
          Contract.where(organization: current_organization)
        end

        # Only the body is admitted; contract and author never come from
        # params.
        def form_params
          params.permit(note: [:body]).fetch(:note, {})
        end
      end
    end
  end
end
