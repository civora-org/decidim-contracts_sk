# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Updates a party of a contract record (civora-org/civora-platform#76).
      #
      # The party is updated in place — the controller loads it from the
      # parent contract's parties association (the tenant scope), so the
      # record is contract-scoped by construction. Editability is re-checked
      # at execution time, fail-closed, through the party's contract: a
      # stale permission decision can never write into a contract that has
      # left the editable states in the meantime. Only the form's fields are
      # written — the parent contract is never re-assignable through this
      # command.
      class UpdateParty < Decidim::Command
        def initialize(form, party)
          super()
          @form = form
          @party = party
        end

        def call
          return broadcast(:invalid) unless party.contract.editable?
          return broadcast(:invalid) unless form.valid?

          party.update!(party_attributes)

          broadcast(:ok, party)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :party

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
