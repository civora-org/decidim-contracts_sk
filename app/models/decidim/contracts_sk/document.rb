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
    # blob service. Every synced name passes through .sanitize_filename,
    # the single choke point covering attach, replace and the generated
    # CRZ handoff alike (civora-org/civora-platform#64).
    #
    # Like Party, tenancy is derived through the contract's organization.
    class Document < ApplicationRecord
      # Stored-string kind vocabulary for the inclusion validator — frozen
      # so a captured validator reference cannot mutate the vocabulary.
      KINDS = %w[contract crz_export annex other].freeze

      # Symbol => stored String mapping for the Rails enum, mirroring
      # Contract's STATE_VALUES style.
      KIND_VALUES = KINDS.to_h { |kind| [kind, kind] }.freeze

      # Upload guard (civora-org/civora-platform#64), enforced at the form
      # boundary: the allowlist is checked against the CLIENT-DECLARED
      # content type (no magic-byte sniffing — ActiveStorage sniffs the
      # bytes separately when it stores the blob).
      ALLOWED_CONTENT_TYPES = %w[application/pdf text/plain image/png image/jpeg].freeze

      # Upload size cap — an engine constant, deliberately not
      # host-configurable (civora-org/civora-platform#64).
      MAX_FILE_SIZE = 10.megabytes

      # Stored-name ceiling: the file_name column is a string (255), so the
      # sanitizer never produces a value the row cannot hold.
      MAX_FILE_NAME_LENGTH = 255

      # Fallback base name for uploads whose name is lost entirely to
      # sanitization (a pure-unicode name, "..", an empty string). The
      # literal is already frozen by the magic comment above.
      FALLBACK_FILE_NAME = "document"

      belongs_to :contract

      has_one_attached :file

      validates :kind, presence: true,
                       inclusion: { in: KINDS }
      validates :title, presence: true, length: { maximum: 255 }

      # Positional arguments: the Rails 7.2 enum API (the keyword form is
      # deprecated and removed in Rails 8). Column and enum agree on the
      # "contract" default.
      enum :kind, KIND_VALUES, default: "contract"

      # Pure filename sanitizer — the single choke point for every stored
      # display name (civora-org/civora-platform#64): strips directory
      # components (both separator styles), control characters and anything
      # outside [A-Za-z0-9._-], collapses repeated separators, and caps the
      # length at MAX_FILE_NAME_LENGTH. When no name survives (only dots or
      # separators, e.g. "..", or a bare extension like "ččč.pdf"), it falls
      # back to FALLBACK_FILE_NAME, preserving a derivable ASCII extension.
      # Display-only by contract: the stored name never feeds paths or
      # headers (downloads use the blob's own ActiveStorage-sanitized name).
      # Class-level and pure so specs can unit-test it directly.
      def self.sanitize_filename(raw)
        basename = raw.to_s.split(%r{[\\/]}).last.to_s
        cleaned = strip_to_safe_charset(basename)

        ext = cleaned[/\.[A-Za-z0-9]+\z/].to_s
        stem = cleaned[0...(cleaned.length - ext.length)].to_s
        return FALLBACK_FILE_NAME + ext if stem.delete("._-").empty?

        cleaned[0, MAX_FILE_NAME_LENGTH]
      end

      # Charset-level pass shared by .sanitize_filename: drops control
      # characters, keeps only [A-Za-z0-9._-] and collapses separator runs.
      def self.strip_to_safe_charset(basename)
        basename.gsub(/[[:cntrl:]]/, "")
                .gsub(/[^A-Za-z0-9._-]/, "")
                .gsub(/([._-])\1+/, "\\1")
      end

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
        update!(file_name: self.class.sanitize_filename(file.blob.filename.to_s),
                content_type: file.blob.content_type,
                file_size: file.blob.byte_size)
      end
    end
  end
end
