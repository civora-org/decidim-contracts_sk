# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Removes a document from a contract record
      # (civora-org/civora-platform#73).
      #
      # Like ReplaceDocument, the document is contract-scoped by construction
      # (the controller loads it from the parent contract's documents
      # association) and editability is re-checked at execution time,
      # fail-closed through the document's contract: no document may be
      # removed once the record has left the editable states. Destroying the
      # document destroys its ActiveStorage attachment with it (the
      # has_one_attached wiring); the blob itself is purged through the
      # host's queuing backend. There is no audit row for document removal —
      # the audit trail tracks contract lifecycle transitions only.
      class DestroyDocument < Decidim::Command
        def initialize(document)
          super()
          @document = document
        end

        def call
          return broadcast(:invalid) unless document.contract.editable?

          document.destroy!

          broadcast(:ok)
        rescue ActiveRecord::RecordNotDestroyed
          broadcast(:invalid)
        end

        private

        attr_reader :document
      end
    end
  end
end
