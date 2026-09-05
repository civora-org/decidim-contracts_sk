# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Updates a draft amendment's summary (M02-05-B,
      # civora-org/civora-platform#65).
      #
      # The amendment is contract-scoped by construction (the controller
      # loads it from the parent contract's amendments association, the
      # tenant scope). Draft-only is re-checked at execution time,
      # fail-closed, INSIDE the row lock — the TOCTOU doctrine of
      # TransitionContract: a published amendment is immutable (ADR-006),
      # so a stale permission decision or a stale in-memory copy can never
      # retouch it. with_lock reloads the row first, so the guard reads the
      # in-database state, not whatever the caller's copy held at request
      # start; the model's readonly? guard backs this up. The form is
      # validated before the lock (pure, no DB access); only the form's
      # field is written — the parent contract is never re-assignable
      # through this command.
      class UpdateAmendment < Decidim::Command
        def initialize(form, amendment)
          super()
          @form = form
          @amendment = amendment
        end

        def call
          return broadcast(:invalid) unless form.valid?

          amendment.with_lock do
            return broadcast(:invalid) unless amendment.draft?

            amendment.update!(summary: form.summary)
          end

          broadcast(:ok, amendment)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :amendment
      end
    end
  end
end
