# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Editor-facing form for a contract's documents
      # (civora-org/civora-platform#73).
      #
      # Deliberately narrow: only the document's title, kind and file are
      # exposed. The parent contract is never form input — the controller
      # loads it from the tenant scope and the command layer creates through
      # its documents association, so the tenancy cannot be influenced by a
      # form param (strong params in the controller mirror this allow-list).
      #
      # The file attribute is a plain accessor, not an ActiveModel::Attributes
      # cast: it carries an upload object (ActionDispatch::Http::UploadedFile
      # or Rack::Test::UploadedFile), and casting it as a string would destroy
      # it. Presence is validated here so a rejection surfaces on the form
      # before the command boundary; the file's CONTENT is also validated
      # here (civora-org/civora-platform#64) — against the client-declared
      # content type and the upload's byte size, with no magic-byte sniffing.
      #
      # On the replace path (ReplaceDocument) the controller pre-fills
      # title/kind from the persisted record — a replace swaps the file only,
      # so the request cannot retouch the record's content fields.
      #
      # The form's kind vocabulary is deliberately narrower than the model's:
      # crz_export is reserved for the generated CRZ-handoff artifact
      # (M02-05-C, civora-org/civora-platform#74), so the upload form can
      # neither offer nor accept it — an editor cannot upload into the
      # generated artifact's kind. The model's KINDS stay unchanged
      # (generated artifacts land there legitimately).
      class DocumentForm
        include ActiveModel::Model
        include ActiveModel::Attributes

        # The model's frozen KINDS minus the generated artifact's kind.
        EDITOR_KINDS = (Decidim::ContractsSk::Document::KINDS - ["crz_export"]).freeze

        # Upload guard constants live on the model — the form enforces, the
        # model owns (civora-org/civora-platform#64).
        ALLOWED_CONTENT_TYPES = Decidim::ContractsSk::Document::ALLOWED_CONTENT_TYPES
        MAX_FILE_SIZE = Decidim::ContractsSk::Document::MAX_FILE_SIZE

        attribute :title, :string
        attribute :kind, :string, default: "contract"

        attr_accessor :file

        validates :title, presence: true, length: { maximum: 255 }
        validates :kind, presence: true,
                         inclusion: { in: EDITOR_KINDS }
        validates :file, presence: true
        validate :file_must_be_allowed_upload

        private

        # Content validation (civora-org/civora-platform#64): an upload must
        # declare an allowed content type and fit the engine's size cap
        # (which floors it above zero). Checked against the upload object's
        # declared type and byte size — no magic-byte sniffing. Any present
        # value that is not an upload object (no content_type/size — e.g. a
        # bare path string) is rejected fail-closed.
        def file_must_be_allowed_upload
          return if file.blank?

          unless upload_object?
            errors.add(:file, :invalid)
            return
          end

          errors.add(:file, :invalid) unless allowed_content_type?
          errors.add(:file, :invalid) unless size_within_cap?
        end

        def upload_object?
          file.respond_to?(:content_type) && file.respond_to?(:size)
        end

        def allowed_content_type?
          ALLOWED_CONTENT_TYPES.include?(file.content_type.to_s)
        end

        def size_within_cap?
          size = file.size
          size.is_a?(Integer) && size.positive? && size <= MAX_FILE_SIZE
        end
      end
    end
  end
end
