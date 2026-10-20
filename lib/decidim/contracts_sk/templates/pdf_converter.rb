# frozen_string_literal: true

require "stringio"
require "pdf/reader"

module Decidim
  module ContractsSk
    module Templates
      # The docx-to-PDF seam of the contract-template feature
      # (civora-org/civora-platform#211). A converter is any callable that takes
      # .docx bytes and returns PDF bytes; the host picks one with
      #
      #   Decidim::ContractsSk.pdf_converter = MyGotenbergAdapter.new
      #
      # and the default is LibreOfficeCli. Adapters raise the typed errors below.
      # Error messages never carry document content.
      module PdfConverter
        class Error < ContractsSk::Error; end

        # The converter did not finish within its time limit and was killed.
        class ConversionTimeout < Error; end

        # The converter ran but produced no usable PDF, or the input was refused.
        class ConversionFailed < Error; end

        # The converter itself is not installed or cannot be started.
        class ConverterUnavailable < Error; end

        module_function

        # soffice exits 0 even on garbage input, so the exit status proves
        # nothing: require the %PDF magic bytes, a parseable file and at least
        # one page. Raises ConversionFailed, returns the bytes otherwise.
        def validate!(pdf_bytes)
          bytes = pdf_bytes.to_s.b
          raise ConversionFailed, "converter produced no PDF output" if bytes.empty?
          raise ConversionFailed, "converter output does not start with %PDF" unless bytes.start_with?("%PDF")

          pages = PDF::Reader.new(StringIO.new(bytes)).page_count
          raise ConversionFailed, "converter output has no pages" unless pages.positive?

          bytes
        rescue ConversionFailed
          raise
        rescue StandardError => e
          # pdf-reader raises a zoo of errors on corrupt input, not all of them
          # PDF::Reader::*: treat every one as "not a readable PDF".
          raise ConversionFailed, "converter output is not a readable PDF (#{e.class.name.split("::").last})"
        end
      end
    end
  end
end
