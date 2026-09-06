# frozen_string_literal: true

require "stringio"

module Decidim
  module ContractsSk
    module Admin
      # Generates (or regenerates) the manual CRZ-handoff PDF for a contract
      # record and stores it as the record's single crz_export Document
      # (M02-05-C, civora-org/civora-platform#74; ADR-002).
      #
      # Regenerate-and-replace: exactly one crz_export document exists per
      # contract. The first generation creates it; every further generation
      # replaces the ATTACHMENT on the same row (fixed, locale-driven title)
      # — never a second crz_export record. The file is attached through
      # Document#attach_file!, which swaps the blob and re-syncs the display
      # metadata columns, exactly like the #73 upload wiring.
      #
      # The PDF bytes come from CrzHandoffPdf (pure Ruby, Slovak-only
      # content) and are handed to ActiveStorage as an in-memory IO — no
      # disk temp files.
      #
      # Editability is re-checked at execution time, fail-closed, INSIDE the
      # contract's row lock — the TOCTOU doctrine of TransitionContract: the
      # permission layer is checked when the request is admitted, but a stale
      # permission decision or a stale in-memory copy can never write into a
      # record that has left the editable states in the meantime. with_lock
      # reloads the row first, so both the guard and the PDF's content read
      # the in-database state — the artifact is serialized from the row as it
      # stands under the lock, never from the request-start copy.
      #
      # No AuditEvent is written: the audit trail is scoped to lifecycle
      # transitions ("exactly one row per successful transition", #57/#59),
      # and the document commands this command mirrors (#73) audit nothing.
      #
      # The acting user is accepted per the approved command signature and
      # kept for future attribution needs (audit/notifications); it takes no
      # part in today's write.
      class GenerateCrzHandoff < Decidim::Command
        # Fixed artifact identity: the regenerated export always presents
        # the same filename and content type, whatever the record's title.
        FILENAME = "crz-handoff.pdf"
        CONTENT_TYPE = "application/pdf"

        def initialize(contract, user: nil)
          super()
          @contract = contract
          @user = user
        end

        def call
          document = nil
          contract.with_lock do
            return broadcast(:invalid) unless contract.editable?

            document = existing_document || contract.documents.build(kind: "crz_export")
            document.title = document_title
            document.attach_file!(pdf_attachable)
          end

          broadcast(:ok, document)
        rescue ActiveRecord::RecordInvalid
          broadcast(:invalid)
        end

        private

        attr_reader :contract, :user

        # The single existing handoff document, or nil. Scoped through the
        # contract's association, so tenancy is derived, never queried.
        def existing_document
          contract.documents.find_by(kind: "crz_export")
        end

        # Locale-driven fixed title: resolved in the acting admin's UI
        # locale at generation time; the persisted value becomes the display
        # title in the admin list and the public catalogue.
        def document_title
          I18n.t("decidim.contracts_sk.admin.crz_handoff.document_title")
        end

        def pdf_attachable
          {
            io: StringIO.new(CrzHandoffPdf.new(contract).render),
            filename: FILENAME,
            content_type: CONTENT_TYPE
          }
        end
      end
    end
  end
end
