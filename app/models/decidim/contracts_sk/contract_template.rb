# frozen_string_literal: true

module Decidim
  module ContractsSk
    # One version of a contract template (civora-org/civora-platform#211): the
    # Word source file plus the field definitions the generator fills.
    #
    # Not to be confused with Template (#127), the draft-prefill defaults.
    #
    # Versioning: a lineage (organization + lineage_key) holds numbered
    # versions. A version is IMMUTABLE once any entry references it, so an
    # existing contract always regenerates against the exact template it was
    # written with; changes go into a new version. The guard allows only the
    # lifecycle `status` (and timestamps) to change on a used version, and
    # refuses replacing the attached file, destroying the version, and any
    # change to its fields (ContractTemplateField carries the same guard).
    #
    # Organization-scoped: every read path loads templates through
    # ContractTemplate.where(organization: ...).
    class ContractTemplate < ApplicationRecord
      LINEAGE_KEY_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
      STATUS_VALUES = %w[draft active archived].to_h { |status| [status, status] }.freeze

      # Attributes that may still change after an entry references the version.
      MUTABLE_WHEN_USED = %w[status updated_at].freeze

      belongs_to :organization,
                 foreign_key: "decidim_organization_id",
                 class_name: "Decidim::Organization"

      # No FK on purpose (a deleted user must not block the template history).
      belongs_to :created_by,
                 foreign_key: "decidim_created_by_id",
                 class_name: "Decidim::User",
                 optional: true

      # RESTRICT at the model level too: a used version cannot be deleted.
      has_many :entries,
               class_name: "Decidim::ContractsSk::ContractTemplateEntry",
               foreign_key: "contract_template_id",
               inverse_of: :contract_template,
               dependent: :restrict_with_error

      has_many :fields, -> { order(:position, :id) },
               class_name: "Decidim::ContractsSk::ContractTemplateField",
               foreign_key: "contract_template_id",
               inverse_of: :contract_template,
               dependent: :destroy

      has_one_attached :file

      enum :status, STATUS_VALUES, default: "draft", validate: true

      validates :organization, presence: true
      validates :lineage_key, presence: true
      validates :lineage_key, length: { maximum: 100 },
                              format: { with: LINEAGE_KEY_FORMAT },
                              allow_blank: true
      validates :version, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
      validates :version, uniqueness: { scope: %i[decidim_organization_id lineage_key] }
      validates :name, presence: true, length: { maximum: 255 }
      validates :source_filename, :reference_pattern, length: { maximum: 255 }, allow_nil: true
      validates :source_checksum, length: { maximum: 128 }, allow_nil: true

      validate :used_version_is_immutable, on: :update
      validate :created_by_belongs_to_organization

      # True once any entry references this version.
      def used?
        persisted? && entries.exists?
      end

      private

      def used_version_is_immutable
        return unless used?

        forbidden = changed - MUTABLE_WHEN_USED
        forbidden << "file" if attachment_changes.key?("file")
        return if forbidden.empty?

        errors.add(:base, :immutable_once_used)
      end

      def created_by_belongs_to_organization
        return if created_by.nil? || organization.nil?
        return if created_by.decidim_organization_id == decidim_organization_id

        errors.add(:created_by, :invalid)
      end
    end
  end
end
