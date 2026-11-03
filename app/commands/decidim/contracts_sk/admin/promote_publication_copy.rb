# frozen_string_literal: true

require "digest"

module Decidim
  module ContractsSk
    module Admin
      # Civora-org/civora-platform#211, P6: when a contract has a CURRENT
      # generated publication PDF, confirming the redaction makes it the
      # contract's publishable document: a Document of kind contract, the
      # same record a manual upload creates and the public page lists.
      #
      # Called by ConfirmRedaction INSIDE the contract's row lock, the same
      # lock regeneration takes. Only the current copy qualifies:
      # regeneration supersedes the old rows and removes what they had
      # promoted, so a superseded copy is never promoted. The stored SHA-256
      # is verified against the file first. Without a generated copy (a
      # manually prepared contract) nothing happens and manual uploads stay
      # as they are. Returns true when there is nothing to promote or the
      # copy was promoted, false when the copy is unusable (the
      # confirmation is then refused).
      class PromotePublicationCopy
        TITLE_KEY = "decidim.contracts_sk.admin.contracts.confirm_redaction.promoted_title"

        def self.call(contract, user:)
          new(contract, user).call
        end

        def initialize(contract, user)
          @contract = contract
          @user = user
        end

        def call
          return true if copy.nil? || copy.promoted_document_id.present?
          return false unless usable?

          promote!
          true
        end

        private

        attr_reader :contract, :user

        def copy
          @copy ||= contract.generated_documents.current
                            .where(variant: "publication", file_format: "pdf").order(:id).last
        end

        def usable?
          copy.file.attached? && (copy.checksum.blank? || copy.checksum == Digest::SHA256.hexdigest(copy.file.download))
        end

        def promote!
          document = contract.documents.build(title: I18n.t(TITLE_KEY), kind: "contract")
          document.attach_file!(copy.file.blob)
          copy.update!(promoted_document: document)
          AuditEvent.create!(action: "contract.publication_copy_promoted", target: contract,
                             organization: contract.organization, actor: user)
        end
      end
    end
  end
end
