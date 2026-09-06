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
      # fail-closed, INSIDE the parent contract's row lock — the TOCTOU
      # doctrine of TransitionContract: the lock is the same row the
      # lifecycle commands lock, so a concurrent state change serializes
      # against this write, and with_lock reloads the contract first, so the
      # guard reads the in-database state: no document may be removed once
      # the record has left the editable states. Destroying the document
      # destroys its ActiveStorage attachment with it (the has_one_attached
      # wiring); the blob itself is purged through the host's queuing
      # backend. There is no audit row for document removal — the audit
      # trail tracks contract lifecycle transitions only.
      class DestroyDocument < Decidim::Command
        def initialize(document)
          super()
          @document = document
        end

        def call
          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            document.destroy!
          end

          broadcast(:ok)
        rescue ActiveRecord::RecordNotDestroyed
          broadcast(:invalid)
        end

        private

        attr_reader :document

        # The locked parent, loaded through the document's association (see
        # the class comment): with_lock's reload reads the in-database row
        # under the lock, so the guard decides on live state.
        def contract
          document.contract
        end
      end
    end
  end
end
