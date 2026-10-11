# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A link to an official attachment of a CRZ-mirrored contract
    # (civora-org/civora-platform#189). Link only: the row keeps metadata and
    # the CRZ file name; the file itself is never downloaded or stored.
    # Rows are replaced wholesale by the CRZ import and the attachments
    # backfill (the mirror is the source of truth), and die with the contract.
    class CrzAttachment < ApplicationRecord
      KINDS = %w[text scan].freeze

      belongs_to :contract

      validates :kind, inclusion: { in: KINDS }
      validates :title, length: { maximum: 255 }, allow_nil: true
      validate :file_name_allowlisted

      # The official file URL, or nil. Re-checks the allowlist on every call,
      # so a row that bypassed validation (raw SQL, update_column) still can
      # never put an arbitrary string into an href.
      def url
        CrzImport::AttachmentUrl.for(file_name)
      end

      # Upper-case extension of the file ("PDF"), nil when not allowlisted.
      def format_label
        url && File.extname(file_name).delete(".").upcase
      end

      private

      def file_name_allowlisted
        errors.add(:file_name, :invalid) unless CrzImport::AttachmentUrl.allowed?(file_name)
      end
    end
  end
end
