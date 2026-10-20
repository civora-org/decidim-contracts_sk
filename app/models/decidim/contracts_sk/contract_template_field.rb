# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A merge field of a contract template version (civora-org/civora-platform
    # #211): the key the Word MERGEFIELD uses, how the form labels and types
    # it, and whether its value is personal data.
    #
    # `personal_data` is forced on for the `person` type (a person field is
    # always stored encrypted and redacted in the publication copy); other
    # types may opt in. Like the template it belongs to, a field is frozen
    # once an entry references that template version.
    class ContractTemplateField < ApplicationRecord
      FIELD_TYPES = %w[text long_text date money number person org_header].freeze
      FIELD_TYPE_VALUES = FIELD_TYPES.to_h { |type| [type, type] }.freeze

      # ASCII snake_case: the key is a MERGEFIELD name and a JSON key.
      KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
      MAX_KEY_LENGTH = 64

      belongs_to :contract_template,
                 class_name: "Decidim::ContractsSk::ContractTemplate",
                 inverse_of: :fields

      enum :field_type, FIELD_TYPE_VALUES, default: "text", validate: true

      before_validation :force_personal_data_for_person

      validates :contract_template, presence: true
      validates :key, presence: true
      validates :key, length: { maximum: MAX_KEY_LENGTH },
                      format: { with: KEY_FORMAT },
                      uniqueness: { scope: :contract_template_id },
                      allow_blank: true
      validates :label, presence: true, length: { maximum: 255 }
      validates :group_key, length: { maximum: MAX_KEY_LENGTH },
                            format: { with: KEY_FORMAT },
                            allow_blank: true
      validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

      validate :template_not_used
      before_destroy :ensure_template_not_used, prepend: true

      private

      def force_personal_data_for_person
        self.personal_data = true if person?
      end

      # A used template version is frozen, fields included. Checked on every
      # write; for an update the check reads the (possibly different) stored
      # template too, so moving a field out of a used version is refused.
      def template_not_used
        return unless contract_template&.persisted? && contract_template.used?

        errors.add(:base, :template_used)
      end

      def ensure_template_not_used
        # The template's own destroy never gets here for a used version: its
        # `entries` restrict check is declared first and refuses it.
        return unless contract_template&.used?

        errors.add(:base, :template_used)
        throw :abort
      end
    end
  end
end
