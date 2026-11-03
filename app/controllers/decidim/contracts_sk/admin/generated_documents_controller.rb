# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Download of a file generated from a contract template
      # (civora-org/civora-platform#211). Admin-only: no public route serves
      # these files, and no public page links them.
      #
      # The contract is loaded from the organization's scope first (another
      # tenant's contract is a 404), the permission is checked against it, and
      # the file is found through the contract's own documents: only the
      # CURRENT, downloadable ones (see GeneratedDocument.downloadable), so a
      # superseded file or the publication Word intermediate answers 404.
      # The response is an attachment, never cached.
      class GeneratedDocumentsController < Admin::ApplicationController
        def show
          @contract = Contract.where(organization: current_organization).find(params[:contract_id])

          enforce_permission_to :read, :generated_document, contract: @contract

          send_document(@contract.generated_documents.current.downloadable.find(params[:id]))
        end

        private

        def send_document(document)
          response.headers["Cache-Control"] = "no-store"
          send_data document.file.download, filename: document.file.filename.to_s,
                                            type: document.file.content_type, disposition: "attachment"
        end
      end
    end
  end
end
