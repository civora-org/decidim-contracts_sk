# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A file generated from a template entry (civora-org/civora-platform#211):
    # the internal working copy or the publication copy, as docx or pdf.
    #
    # ADMIN-ONLY by design and deliberately separate from the public Document
    # model: nothing here is ever rendered in the public catalogue. A
    # reviewer-confirmed publication PDF reaches the catalogue only when it is
    # promoted to a Document (`promoted_document`, set by a later step).
    #
    # Only one `current` file may exist per (entry, variant, file_format); a
    # regeneration marks the previous one `superseded` (done by the generator,
    # not here). Tenancy derives through the contract.
    class GeneratedDocument < ApplicationRecord
      VARIANT_VALUES = %w[internal publication].to_h { |variant| [variant, variant] }.freeze
      FILE_FORMAT_VALUES = %w[docx pdf].to_h { |format| [format, format] }.freeze
      STATUS_VALUES = %w[current superseded].to_h { |status| [status, status] }.freeze

      belongs_to :contract,
                 class_name: "Decidim::ContractsSk::Contract",
                 inverse_of: :generated_documents
      belongs_to :entry,
                 class_name: "Decidim::ContractsSk::ContractTemplateEntry",
                 inverse_of: :generated_documents

      # No FK on purpose (the `decidim_author_id` precedent).
      belongs_to :generated_by,
                 foreign_key: "decidim_generated_by_id",
                 class_name: "Decidim::User",
                 optional: true

      # The public Document this file was promoted to, if any.
      belongs_to :promoted_document,
                 class_name: "Decidim::ContractsSk::Document",
                 optional: true

      has_one_attached :file

      enum :variant, VARIANT_VALUES, validate: true
      enum :file_format, FILE_FORMAT_VALUES, validate: true
      enum :status, STATUS_VALUES, default: "current", validate: true

      validates :contract, :entry, presence: true
      validates :generated_at, presence: true
      validates :template_version, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
      validates :checksum, length: { maximum: 128 }, allow_nil: true
      validate :entry_belongs_to_contract
      validate :promoted_document_belongs_to_contract

      private

      def entry_belongs_to_contract
        return if entry.nil? || contract.nil?

        errors.add(:entry, :invalid) unless entry.contract_id == contract_id
      end

      def promoted_document_belongs_to_contract
        return if promoted_document.nil? || contract.nil?

        errors.add(:promoted_document, :invalid) unless promoted_document.contract_id == contract_id
      end
    end
  end
end
