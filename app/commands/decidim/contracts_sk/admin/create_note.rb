# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Appends an internal review note to a contract (civora-org/
      # civora-platform#128).
      #
      # Notes are append-only: this is the only write path (no update, no
      # destroy command exists). The note and its audit row ("contract.
      # note_added", target = the contract; the body is deliberately NOT in
      # the audit trail, which carries identities and timestamps only) commit
      # atomically inside the contract's row lock — the repo-wide lock
      # discipline: with_lock reloads the row first, so a contract removed in
      # the meantime (e.g. a CRZ mirror absorbed by its filed record) can
      # never receive a note; the reload raises RecordNotFound, answered
      # :invalid.
      #
      # Tenancy: the controller's tenant-scoped lookup is the permission
      # boundary; this command re-checks, fail-closed and inside the lock,
      # that the author belongs to the contract's organization
      # (defense-in-depth, the CreateContract precedent). No lifecycle state
      # is consulted — role holders may annotate a record in any state, and
      # notes survive publication (they are never public).
      class CreateNote < Decidim::Command
        def initialize(form, contract, user:)
          super()
          @form = form
          @contract = contract
          @user = user
        end

        def call
          return broadcast(:invalid) unless form.valid?

          note = append_note
          return broadcast(:invalid) unless note

          broadcast(:ok, note)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
          broadcast(:invalid)
        end

        private

        attr_reader :form, :contract, :user

        # The note and its audit row, atomically inside the contract's row
        # lock; nil when the in-lock tenancy re-check refuses.
        def append_note
          contract.with_lock do
            return nil unless contract.decidim_organization_id == user.decidim_organization_id

            contract.notes.create!(author: user, body: form.body).tap { record_audit! }
          end
        end

        def record_audit!
          AuditEvent.create!(action: "contract.note_added", target: contract,
                             organization: contract.organization, actor: user)
        end
      end
    end
  end
end
