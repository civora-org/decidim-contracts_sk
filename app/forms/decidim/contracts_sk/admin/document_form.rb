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
      # before the command boundary; the file's CONTENT is not validated —
      # allowed kinds and size caps are deferred to
      # civora-org/civora-platform#64.
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

        attribute :title, :string
        attribute :kind, :string, default: "contract"

        attr_accessor :file

        validates :title, presence: true, length: { maximum: 255 }
        validates :kind, presence: true,
                         inclusion: { in: EDITOR_KINDS }
        validates :file, presence: true
      end
    end
  end
end
