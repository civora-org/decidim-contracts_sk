# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Spreadsheet bulk import of existing contracts as drafts
      # (civora-org/civora-platform#129): the upload form (#new), a stateless
      # dry run (#preview, writes nothing) and the import itself (#create).
      #
      # Every action is gated by the editor-only :import_file permission
      # before anything is read. The upload is size-capped before it is
      # parsed (SpreadsheetImport::MAX_BYTES), only the file's bytes and the
      # re-posted text are used, never a filename or a content type. The
      # import never trusts the preview: #create re-parses the posted text
      # and ImportContracts refuses unless every row validates, so a file is
      # imported whole or not at all. Rows land as drafts (see the command).
      class ContractImportsController < ApplicationController
        # The re-posted text is UTF-8 and may be larger than the Windows-1250
        # original, so it gets twice the upload byte budget.
        PAYLOAD_MAX_BYTES = SpreadsheetImport::MAX_BYTES * 2

        def new
          enforce_permission_to :import_file, :contract
        end

        def preview
          enforce_permission_to :import_file, :contract

          @preview = SpreadsheetImport::Preview.new(uploaded_bytes, organization: current_organization)
          return render(:new, status: :unprocessable_entity) if @preview.problems.any?

          render :preview
        end

        def create
          enforce_permission_to :import_file, :contract

          @preview = SpreadsheetImport::Preview.new(params[:payload].to_s, organization: current_organization,
                                                                           max_bytes: PAYLOAD_MAX_BYTES)

          ImportContracts.call(@preview, user: current_user, organization: current_organization) do
            on(:ok) { |contracts| import_succeeded(contracts) }
            on(:invalid) { import_failed }
          end
        end

        private

        # The upload's bytes, read at most one byte past the cap so the
        # reader can report "too large" without the whole file in memory.
        # Anything that is not an uploaded file (a plain string param) reads
        # as empty.
        def uploaded_bytes
          file = params[:file]
          return "" unless file.respond_to?(:read)

          file.read(SpreadsheetImport::MAX_BYTES + 1).to_s
        end

        def import_succeeded(contracts)
          flash[:notice] = t("decidim.contracts_sk.admin.contract_imports.create.success", count: contracts.size)
          redirect_to admin_contracts_path(state: "draft")
        end

        def import_failed
          flash.now[:alert] = t("decidim.contracts_sk.admin.contract_imports.create.invalid")
          return render(:new, status: :unprocessable_entity) if @preview.problems.any?

          render :preview, status: :unprocessable_entity
        end
      end
    end
  end
end
