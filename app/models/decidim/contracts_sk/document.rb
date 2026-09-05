# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A document attached to a contract record — catalogue copy, CRZ export,
    # annex or other supporting material.
    #
    # Storage is engine-side ActiveStorage on this model
    # (M02-05-A0, civora-org/civora-platform#73, Option A): a plain
    # `has_one_attached :file`, deliberately not Decidim::Attachment (the
    # engine stays self-contained; documents are contract-scoped engine
    # records, not attachable component resources). The macro is declared
    # unguarded — decidim-core parity: core declares `has_one_attached` on
    # its own models unguarded and declares no activestorage dependency
    # either, because every Decidim application runs ActiveStorage, and this
    # engine's runtime floor is decidim-core.
    #
    # The file_name/content_type/file_size columns are synced from the blob
    # at attach/replace time (#attach_file!) and stay the DISPLAY source of
    # truth — the public catalogue renders size/type without touching the
    # blob service. Content validation (allowed kinds, size caps) is deferred
    # to civora-org/civora-platform#64.
    #
    # Like Party, tenancy is derived through the contract's organization.
    class Document < ApplicationRecord
      # Stored-string kind vocabulary for the inclusion validator — frozen
      # so a captured validator reference cannot mutate the vocabulary.
      KINDS = %w[contract crz_export annex other].freeze

      # Symbol => stored String mapping for the Rails enum, mirroring
      # Contract's STATE_VALUES style.
      KIND_VALUES = KINDS.to_h { |kind| [kind, kind] }.freeze

      belongs_to :contract

      has_one_attached :file

      validates :kind, presence: true,
                       inclusion: { in: KINDS }
      validates :title, presence: true, length: { maximum: 255 }

      # Positional arguments: the Rails 7.2 enum API (the keyword form is
      # deprecated and removed in Rails 8). Column and enum agree on the
      # "contract" default.
      enum :kind, KIND_VALUES, default: "contract"

      # Attaches (or, when a file is already attached, replaces) the file and
      # syncs the display metadata columns from the freshly attached blob.
      #
      # For a persisted record ActiveStorage persists the blob and the
      # attachment row immediately; for a new record the change is scheduled
      # and lands with the record's own save, so both shapes collapse into
      # "attach, save if needed, then sync". The sync runs through #update!
      # (not #update_columns) so the write stays a normal, timestamped model
      # write; the synced values are system-derived (never user input), and
      # the metadata columns carry no validations of their own.
      def attach_file!(attachable)
        raise ArgumentError, "an attachable file is required" if attachable.blank?

        file.attach(attachable)
        save! unless persisted?
        sync_file_metadata!
        self
      end

      private

      def sync_file_metadata!
        update!(file_name: file.blob.filename.to_s,
                content_type: file.blob.content_type,
                file_size: file.blob.byte_size)
      end
    end
  end
end
