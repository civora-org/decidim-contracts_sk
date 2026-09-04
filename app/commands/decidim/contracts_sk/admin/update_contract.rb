# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Updates the editorial identity fields of a contract record
      # (civora-org/civora-platform#58).
      #
      # Re-checks editability at execution time, fail-closed: the permission
      # layer is checked when the request is admitted, but the record's state
      # is re-verified here so a stale permission decision can never write to
      # a record that has left the editable states in the meantime. The form
      # is validated at this boundary (before any persistence), so a
      # rejection populates the form's errors for the controller's re-render.
      # Only the form's fields are written — state, provenance, organization
      # and author are untouchable through this command.
      class UpdateContract < Decidim::Command
        def initialize(form, contract)
          super()
          @form = form
          @contract = contract
        end

        def call
          return broadcast(:invalid) unless contract.editable?
          return broadcast(:invalid) unless form.valid?

          contract.update!(title: form.title, reference: form.reference)

          broadcast(:ok, contract)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :contract
      end
    end
  end
end
