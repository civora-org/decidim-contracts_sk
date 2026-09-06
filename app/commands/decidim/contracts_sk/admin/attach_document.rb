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
      # Editability is re-checked at execution time, fail-closed, INSIDE the
      # contract's row lock — the TOCTOU doctrine of TransitionContract: the
      # permission layer is checked when the request is admitted, but a stale
      # permission decision or a stale in-memory copy can never write into a
      # record that has left the editable states in the meantime. The lock is
      # the parent contract's row — the same row the lifecycle commands lock,
      # so a concurrent state change serializes against this write — and
      # with_lock reloads it first, so the guard reads the in-database state.
      # The form is validated before the lock (pure, no DB access), so a
      # rejection populates the form's errors for the controller's re-render.
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
          return broadcast(:invalid) unless form.valid?

          document = nil
          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            document = attach_document!
          end

          broadcast(:ok, document)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :contract

        # The lock's whole write: build through the contract's association
        # (tenancy is derived, never form-driven) and attach the file — runs
        # strictly after the reload, so the guard already saw the
        # in-database state.
        def attach_document!
          document = contract.documents.build(document_attributes)
          document.attach_file!(form.file)
          document
        end

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
