# frozen_string_literal: true

require_relative "docx_filler"
require_relative "docx_sanitizer"
require_relative "publication_variant"
require_relative "redaction_verifier"
require_relative "pdf_converter"
require_relative "pdf_metadata"

module Decidim
  module ContractsSk
    module Templates
      # Produces the four documents of a contract from one template and one set
      # of values (civora-org/civora-platform#211). Pure: bytes in, bytes out, no
      # persistence, no Rails.
      #
      #   DocumentGenerator.call(template_bytes: docx, values: {...}, personal_keys: %w[kupujuci rodne_cislo])
      #   # => { internal_docx:, internal_pdf:, publication_docx:, publication_pdf: }
      #
      # Steps: fill, sanitize, convert (and blank the PDF metadata) for the
      # internal variant; the same for the publication variant, whose personal
      # values are the fixed block; then RedactionVerifier on the publication
      # docx and pdf. It FAILS CLOSED: a leak, or anything the verifier cannot
      # inspect, raises RedactionFailed and no document is returned.
      #
      # +personal_keys+ must not be empty (an empty list would publish the
      # internal variant). When the keys hold no non-blank value there is
      # nothing to hide and nothing to verify against, so the verifier is
      # skipped.
      module DocumentGenerator
        class Error < ContractsSk::Error; end

        # Carries what failed, never the personal values themselves.
        class RedactionFailed < Error
          attr_reader :leaks, :findings

          def initialize(leaks:, findings:)
            @leaks = leaks
            @findings = findings
            super(build_message)
          end

          private

          def build_message
            parts = leaks.map { |l| "#{l.kind} leak in #{l.location}" } + findings.map(&:message)
            "publication variant failed redaction verification: #{parts.join("; ")}"
          end
        end

        module_function

        def call(template_bytes:, values:, personal_keys:, converter: ContractsSk.pdf_converter)
          raise ArgumentError, "personal_keys must not be empty" if Array(personal_keys).empty?

          internal_docx, internal_pdf = render(template_bytes, values, converter)
          publication_values = PublicationVariant.values_for(values, personal_keys)
          publication_docx, publication_pdf = render(template_bytes, publication_values, converter)

          verify!(publication_docx, publication_pdf, PublicationVariant.personal_values(values, personal_keys))

          { internal_docx: internal_docx, internal_pdf: internal_pdf,
            publication_docx: publication_docx, publication_pdf: publication_pdf }
        end

        def render(template_bytes, values, converter)
          docx = DocxSanitizer.call(DocxFiller.call(template_bytes, values))
          pdf = PdfMetadata.blank(PdfConverter.validate!(converter.call(docx)))
          [docx, pdf]
        end

        def verify!(docx, pdf, personal_values)
          return if personal_values.empty?

          result = RedactionVerifier.call(docx_bytes: docx, pdf_bytes: pdf, personal_values: personal_values)
          return if result.ok?

          raise RedactionFailed.new(leaks: result.leaks, findings: result.errors)
        end
      end
    end
  end
end
