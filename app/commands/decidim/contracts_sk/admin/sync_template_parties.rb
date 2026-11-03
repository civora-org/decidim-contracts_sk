# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Creates or updates the two parties a contract written from a template
      # has (civora-org/civora-platform#211, follow-up): the municipality, from
      # the organization header profile, and the counterparty, from the fields
      # the template declares (ContractTemplateField#party_part).
      #
      # Idempotent: the parties are found by `template_slot` and updated in
      # place, so generating the documents again never duplicates them. A party
      # a person added by hand has no slot and is never read, changed or
      # deleted. When the value that justifies a party goes away (an emptied
      # name) the party it created is removed again.
      #
      # A natural-person counterparty is stored as Party::NATURAL_PERSON_NAME
      # only (see Templates::PartyValues); the typed values are not passed
      # through this class at all except to test that a name exists.
      #
      # Runs inside the caller's transaction and, on regeneration, inside the
      # contract's row lock (GenerateFromTemplate); it takes no lock of its own.
      # The unique (contract, slot) index makes a lost race fail loudly.
      class SyncTemplateParties
        def self.call(contract:, template:, form:, profile:, organization:)
          new(contract, template, form, profile, organization).call
        end

        def initialize(contract, template, form, profile, organization)
          @contract = contract
          @template = template
          @form = form
          @profile = profile
          @organization = organization
        end

        def call
          sync("municipality", Templates::PartyValues.municipality(profile, organization))
          sync("counterparty",
               Templates::PartyValues.counterparty(template, form.stored_values, form.stored_personal_values))
        end

        private

        attr_reader :contract, :template, :form, :profile, :organization

        def sync(slot, attributes)
          party = Party.find_by(contract_id: contract.id, template_slot: slot)
          return party&.destroy! unless attributes

          party ||= Party.new(contract: contract, template_slot: slot)
          party.update!(attributes)
        end
      end
    end
  end
end
