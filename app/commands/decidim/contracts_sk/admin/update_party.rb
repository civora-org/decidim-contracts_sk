# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Updates a party of a contract record (civora-org/civora-platform#76).
      #
      # The party is updated in place — the controller loads it from the
      # parent contract's parties association (the tenant scope), so the
      # record is contract-scoped by construction. Editability is re-checked
      # at execution time, fail-closed, INSIDE the parent contract's row lock
      # — the TOCTOU doctrine of TransitionContract: the lock is the same row
      # the lifecycle commands lock, so a concurrent state change serializes
      # against this write, and with_lock reloads the contract first, so the
      # guard reads the in-database state rather than a possibly stale
      # in-memory copy. Only the form's fields are written — the parent
      # contract is never re-assignable through this command.
      class UpdateParty < Decidim::Command
        def initialize(form, party)
          super()
          @form = form
          @party = party
        end

        def call
          return broadcast(:invalid) unless form.valid?

          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            party.update!(party_attributes)
          end

          broadcast(:ok, party)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :party

        # The locked parent, loaded through the party's association (see the
        # class comment): with_lock's reload reads the in-database row under
        # the lock, so the guard decides on live state.
        def contract
          party.contract
        end

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
