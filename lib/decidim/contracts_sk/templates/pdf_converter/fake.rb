# frozen_string_literal: true

require "zip"
require "stringio"
require_relative "../pdf_converter"
require_relative "../minimal_pdf"

module Decidim
  module ContractsSk
    module Templates
      module PdfConverter
        # Spec adapter: no LibreOffice, no processes. Returns a tiny, valid,
        # deterministic PDF whose text is the ASCII-folded text of the docx's
        # body paragraphs, so a leak in the docx also shows in the "PDF" and the
        # redaction verifier has something real to read. Its Info dictionary
        # carries marker strings, so the metadata sanitizer has work to do.
        class Fake
          INFO = { "Title" => "Fake title", "Author" => "Fake author",
                   "Creator" => "Fake creator", "Producer" => "Fake producer" }.freeze
          ENTITIES = { "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => '"', "&apos;" => "'" }.freeze

          def call(docx_bytes)
            lines = paragraphs(docx_bytes.to_s.b)
            lines = ["(empty document)"] if lines.empty?
            MinimalPdf.build(lines: lines, info: INFO)
          end

          private

          def paragraphs(bytes)
            xml = nil
            Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
              xml = zip.find_entry("word/document.xml")&.get_input_stream&.read
            end
            return [] unless xml

            lines = xml.force_encoding(Encoding::UTF_8).scan(%r{<w:p[ >].*?</w:p>}m).map do |para|
              para.scan(%r{<w:t[^>]*>([^<]*)</w:t>}).flatten.join.gsub(/&(?:amp|lt|gt|quot|apos);/, ENTITIES)
            end
            lines.reject { |line| line.strip.empty? }
          rescue Zip::Error
            []
          end
        end
      end
    end
  end
end
