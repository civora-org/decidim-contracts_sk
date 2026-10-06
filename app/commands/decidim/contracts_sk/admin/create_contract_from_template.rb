# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Creates a contract draft from a template (civora-org/civora-platform
      # #127). A template only seeds a draft: this command does exactly what
      # CreateContract does (same form, same attributes, lifecycle state on
      # the model's draft default, nothing published or advanced) plus two
      # copies and one audit row.
      #
      # Copy-on-create: the contract's own fields come from the submitted
      # FORM (the editor may have changed the prefill); the object party is
      # copied from the template's skeleton as a plain Party row. Nothing
      # links the contract to the template afterwards, so later template
      # edits or removal never change the contract.
      #
      # The template is locked and reloaded for the duration (the repo-wide
      # with_lock discipline): the skeleton is read from the post-lock
      # instance, so a stale copy loaded by the request can never seed an
      # outdated party, and a template removed in the meantime answers
      # :invalid. The in-lock tenancy re-check is fail-closed defense in
      # depth behind the controller's tenant-scoped lookup. The contract, its
      # party and the audit row ("contract.create_from_template", target =
      # the contract) commit atomically in the one transaction.
      class CreateContractFromTemplate < CreateContract
        def initialize(form, template, user:, organization:)
          super(form, user: user, organization: organization)
          @template = template
        end

        def call
          return broadcast(:invalid) unless tenancy_ok?
          return broadcast(:invalid) unless form.valid?

          contract = create_from_template
          return broadcast(:invalid) unless contract

          broadcast(:ok, contract)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound
          broadcast(:invalid)
        end

        private

        attr_reader :template

        # nil when the in-lock tenancy re-check refuses.
        def create_from_template
          template.with_lock do
            return nil unless template.decidim_organization_id == organization.id

            Contract.create!(contract_attributes).tap do |contract|
              skeleton = template.party_skeleton
              contract.parties.create!(skeleton) if skeleton
              record_audit!(contract)
            end
          end
        end

        def record_audit!(contract)
          AuditEvent.create!(action: "contract.create_from_template", target: contract,
                             organization: organization, actor: user)
        end
      end
    end
  end
end
