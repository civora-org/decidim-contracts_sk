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
      # at execution time, fail-closed, INSIDE the parent contract's row lock
      # — the TOCTOU doctrine of TransitionContract: the lock is the same row
      # the lifecycle commands lock, so a concurrent state change serializes
      # against this write, and with_lock reloads the contract first, so the
      # guard reads the in-database state rather than a possibly stale
      # in-memory copy.
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
          return broadcast(:invalid) unless form.valid?

          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            document.attach_file!(form.file)
          end

          broadcast(:ok, document)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :document

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
