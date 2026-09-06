# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Updates the editorial identity and content fields of a contract
      # record (civora-org/civora-platform#58; content fields per #75).
      #
      # Re-checks editability at execution time, fail-closed, INSIDE the row
      # lock — the TOCTOU doctrine of TransitionContract: the permission
      # layer's admission decision is request-start state, so a stale one can
      # never write to a record that has left the editable states in the
      # meantime. with_lock reloads the row first, so the guard reads the
      # in-database state, not whatever the caller's copy held at request
      # start. Nothing is assigned to the record before the lock (with_lock
      # raises on unpersisted changes). The form is validated before the lock
      # (pure, no DB access), so a rejection populates the form's errors for
      # the controller's re-render. Only the form's fields are written —
      # state, provenance, organization, author and the system-stamped
      # published_at are untouchable through this command.
      class UpdateContract < Decidim::Command
        def initialize(form, contract)
          super()
          @form = form
          @contract = contract
        end

        def call
          return broadcast(:invalid) unless form.valid?

          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            contract.update!(update_attributes)
          end

          broadcast(:ok, contract)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :contract

        # Only the form's fields are written — state, provenance,
        # organization, author and the system-stamped published_at are
        # untouchable through this command.
        def update_attributes
          {
            title: form.title, reference: form.reference,
            subject_matter: form.subject_matter, amount: form.amount,
            currency: form.currency, signed_on: form.signed_on,
            effective_from: form.effective_from, crz_url: form.crz_url
          }
        end
      end
    end
  end
end
