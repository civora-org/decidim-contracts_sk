# frozen_string_literal: true

module Decidim
  module ContractsSk
    # What an editor entered into a contract template's form for one contract
    # (civora-org/civora-platform#211). One entry per contract; it pins the
    # template VERSION it was written against, which makes that version
    # immutable (ContractTemplate guard).
    #
    # Two value stores, split by sensitivity:
    # - `values` (json): the non-personal field values, readable in SQL/logs;
    # - `personal_values` (text, Active Record Encryption): the values of
    #   personal-data fields (names, addresses, ID numbers of natural
    #   persons). Encrypted non-deterministically, so the column holds only
    #   ciphertext, and filtered from logs, `inspect` and error reports. The
    #   HOST must configure the encryption keys (docs/contract-templates.md);
    #   without them the first read or write of a non-nil value raises
    #   ActiveRecord::Encryption::Errors::Configuration.
    #
    # Tenancy derives through the contract and the template; both must belong
    # to the same organization. A personal field's value may live only in
    # `personal_values` and a non-personal one only in `values`.
    class ContractTemplateEntry < ApplicationRecord
      belongs_to :contract,
                 class_name: "Decidim::ContractsSk::Contract",
                 inverse_of: :template_entry
      belongs_to :contract_template,
                 class_name: "Decidim::ContractsSk::ContractTemplate",
                 inverse_of: :entries

      # No FK on purpose (the `decidim_author_id` precedent).
      belongs_to :created_by,
                 foreign_key: "decidim_created_by_id",
                 class_name: "Decidim::User",
                 optional: true

      has_many :generated_documents,
               class_name: "Decidim::ContractsSk::GeneratedDocument",
               foreign_key: "entry_id",
               inverse_of: :entry,
               dependent: :destroy

      # `serialize` first, then `encrypts`: Active Record encrypts the
      # serialized JSON text. type: Hash makes a missing value an empty hash.
      serialize :personal_values, type: Hash, coder: JSON
      encrypts :personal_values

      # Belt and braces: `encrypts` filters the attribute itself, but only
      # while the host leaves encryption.add_to_filter_parameters on (its
      # default); this keeps `inspect` safe either way.
      self.filter_attributes += [:personal_values]

      before_validation :pin_template_version, on: :create

      validates :contract, :contract_template, presence: true
      validates :contract_id, uniqueness: true
      validates :internal_number, length: { maximum: 100 }, allow_nil: true
      validate :values_are_hashes
      validate :template_in_contract_organization
      validate :template_version_matches
      validate :values_hold_no_personal_data
      validate :personal_values_hold_personal_fields
      validate :created_by_belongs_to_organization

      private

      def pin_template_version
        self.template_version ||= contract_template&.version
      end

      def values_are_hashes
        errors.add(:values, :invalid) unless values.is_a?(Hash)
        errors.add(:personal_values, :invalid) unless personal_values.is_a?(Hash)
      end

      def template_in_contract_organization
        return if contract.nil? || contract_template.nil?
        return if contract.decidim_organization_id == contract_template.decidim_organization_id

        errors.add(:contract_template, :invalid)
      end

      def template_version_matches
        return if contract_template.nil? || template_version == contract_template.version

        errors.add(:template_version, :invalid)
      end

      def values_hold_no_personal_data
        return unless values.is_a?(Hash)

        errors.add(:values, :contains_personal_data) if (key_names(values) & personal_field_keys).any?
      end

      def personal_values_hold_personal_fields
        return unless personal_values.is_a?(Hash)

        errors.add(:personal_values, :not_personal_fields) if (key_names(personal_values) - personal_field_keys).any?
      end

      def personal_field_keys
        return [] if contract_template.nil?

        contract_template.fields.select(&:personal_data).map(&:key)
      end

      def key_names(hash)
        hash.keys.map(&:to_s)
      end

      def created_by_belongs_to_organization
        return if created_by.nil? || contract.nil?
        return if created_by.decidim_organization_id == contract.decidim_organization_id

        errors.add(:created_by, :invalid)
      end
    end
  end
end
