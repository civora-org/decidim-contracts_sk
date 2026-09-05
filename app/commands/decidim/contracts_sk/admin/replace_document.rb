# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Replaces a document's file on a contract record
      # (civora-org/civora-platform#73).
      #
      # The document is updated in place — the controller loads it from the
      # parent contract's documents association (the tenant scope), so the
      # record is contract-scoped by construction. Editability is re-checked
      # at execution time, fail-closed, through the document's contract: a
      # stale permission decision can never write into a contract that has
      # left the editable states in the meantime.
      #
      # A replace swaps the FILE only: the controller builds the form with
      # the persisted record's title/kind, so the request cannot retouch
      # those fields through this command. The new file is attached through
      # Document#attach_file!, which swaps the underlying blob/attachment and
      # re-syncs the display metadata columns from the new blob.
      class ReplaceDocument < Decidim::Command
        def initialize(form, document)
          super()
          @form = form
          @document = document
        end

        def call
          return broadcast(:invalid) unless document.contract.editable?
          return broadcast(:invalid) unless form.valid?

          document.attach_file!(form.file)

          broadcast(:ok, document)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :document
      end
    end
  end
end
