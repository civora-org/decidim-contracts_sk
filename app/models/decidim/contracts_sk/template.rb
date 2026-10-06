# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A contract template (civora-org/civora-platform#127): the defaults an
    # editor starts a new contract draft from (title pattern, subject matter,
    # currency and one object-party skeleton).
    #
    # A template only PREFILLS the draft form and seeds the new draft's
    # object party. It never creates, publishes or advances anything, and a
    # contract keeps no reference back to it: the values are copied when the
    # contract is created (CreateContractFromTemplate), so later edits or the
    # removal of a template never change an existing contract.
    #
    # Organization-scoped: every read path loads templates through
    # Template.where(organization: ...), and the name is unique per
    # organization. Only the object party is templated (the municipality);
    # the contractor is contract-specific and always entered on the contract.
    class Template < ApplicationRecord
      belongs_to :organization,
                 foreign_key: "decidim_organization_id",
                 class_name: "Decidim::Organization"

      # Explicit presence: the host's belongs_to-required default is not an
      # engine guarantee (the DB NOT NULL column is the last backstop).
      validates :organization, presence: true
      validates :name, presence: true,
                       length: { maximum: 255 },
                       uniqueness: { scope: :decidim_organization_id }
      validates :title_pattern, length: { maximum: 255 }, allow_nil: true
      validates :currency, presence: true,
                           inclusion: { in: Decidim::ContractsSk::Contract::SUPPORTED_CURRENCIES }

      # The skeleton mirrors the Party model's rules: a name is required as
      # soon as any other skeleton field is filled, the IČO is blank or
      # exactly 8 digits, and the strings are capped at 255.
      validates :object_party_name, presence: true, if: :party_details?
      validates :object_party_name, :object_party_address,
                length: { maximum: 255 }, allow_nil: true
      validates :object_party_ico, length: { is: 8 },
                                   format: { with: Decidim::ContractsSk::ICO_FORMAT },
                                   allow_blank: true

      # The attributes of the object party a new contract is seeded with, or
      # nil when the template carries no skeleton (no name).
      def party_skeleton
        return if object_party_name.blank?

        { role: "object", name: object_party_name,
          ico: object_party_ico.presence, address: object_party_address.presence }
      end

      private

      def party_details?
        object_party_ico.present? || object_party_address.present?
      end
    end
  end
end
