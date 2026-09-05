# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Attaches a document (title, kind, file) to a contract record
      # (civora-org/civora-platform#73).
      #
      # Tenancy is derived through the parent contract — the document is
      # saved through the contract's documents association, so it can never
      # attach to a record outside the acting organization's tenant scope.
      # The controller's tenant-scoped lookup is the permission boundary;
      # this is defense-in-depth, not a permission decision of its own.
      #
      # Editability is re-checked at execution time, fail-closed: the
      # permission layer is checked when the request is admitted, but the
      # parent contract's state is re-verified here so a stale permission
      # decision can never write into a record that has left the editable
      # states in the meantime. The form is validated at this boundary
      # (before any persistence), so a rejection populates the form's errors
      # for the controller's re-render.
      #
      # The file is attached through Document#attach_file!, which syncs the
      # display metadata columns from the freshly created blob.
      class AttachDocument < Decidim::Command
        def initialize(form, contract)
          super()
          @form = form
          @contract = contract
        end

        def call
          return broadcast(:invalid) unless contract.editable?
          return broadcast(:invalid) unless form.valid?

          document = contract.documents.build(document_attributes)
          document.attach_file!(form.file)

          broadcast(:ok, document)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :contract

        # Only the form's fields are written — the parent contract (and with
        # it the tenancy) comes from the constructor, never from the form.
        def document_attributes
          {
            title: form.title,
            kind: form.kind
          }
        end
      end
    end
  end
end
