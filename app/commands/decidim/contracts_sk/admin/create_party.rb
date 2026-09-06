# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Adds a party to a contract record (civora-org/civora-platform#76).
      #
      # Tenancy is derived through the parent contract — the party is saved
      # through the contract's parties association, so it can never attach
      # to a record outside the acting organization's tenant scope. The
      # controller's tenant-scoped lookup is the permission boundary; this
      # is defense-in-depth, not a permission decision of its own.
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
      class CreateParty < Decidim::Command
        def initialize(form, contract)
          super()
          @form = form
          @contract = contract
        end

        def call
          return broadcast(:invalid) unless form.valid?

          party = nil
          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            party = contract.parties.create!(party_attributes)
          end

          broadcast(:ok, party)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :contract

        # Only the form's fields are written — the parent contract (and with
        # it the tenancy) comes from the constructor, never from the form.
        def party_attributes
          {
            role: form.role,
            name: form.name,
            ico: form.ico,
            address: form.address
          }
        end
      end
    end
  end
end
