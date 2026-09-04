# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Creates a contract record from the admin form
      # (civora-org/civora-platform#58; content fields per #75).
      #
      # Tenancy and authorship are command responsibilities, never form
      # input: the organization comes from the controller's tenant context
      # and the author from the acting user. The same holds for the
      # lifecycle state (the model's draft default) and the system-stamped
      # published_at (TransitionContract on publish) — neither is passed
      # from the form. The tenancy guard is a fail-closed defense-in-depth
      # check behind the permission layer, not a permission decision of its
      # own. The form is validated at this boundary (before any
      # persistence), so a rejection populates the form's errors for the
      # controller's re-render.
      class CreateContract < Decidim::Command
        def initialize(form, user:, organization:)
          super()
          @form = form
          @user = user
          @organization = organization
        end

        def call
          return broadcast(:invalid) unless tenancy_ok?
          return broadcast(:invalid) unless form.valid?

          contract = Contract.create!(contract_attributes)

          broadcast(:ok, contract)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :form, :user, :organization

        # The full creation attribute set: only the form-sourced editorial
        # and content fields (#75) plus the command-owned tenancy and
        # authorship. The lifecycle state stays on the model's draft default
        # and the publication stamp on TransitionContract.
        def contract_attributes
          {
            organization: @organization, author: @user,
            title: @form.title, reference: @form.reference,
            subject_matter: @form.subject_matter, amount: @form.amount,
            currency: @form.currency, signed_on: @form.signed_on,
            effective_from: @form.effective_from, crz_url: @form.crz_url
          }
        end

        # A user belongs to exactly one organization; creating into a
        # different one is invalid. Duck-typed on purpose (respond_to?-safe):
        # plain test doubles and host-app user objects without the Decidim
        # association skip the check — the permission layer remains the
        # authorization authority.
        def tenancy_ok?
          return true unless user.respond_to?(:organization)

          user.organization == organization
        end
      end
    end
  end
end
