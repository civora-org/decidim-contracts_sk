# frozen_string_literal: true

require "pdf/reader"
require_relative "package"
require_relative "xml"

module Decidim
  module ContractsSk
    module Templates
      # Proves that a publication document does not contain personal values
      # (civora-org/civora-platform#211). It FAILS CLOSED: anything it cannot
      # inspect (an unreadable package, an encrypted PDF, a PDF without
      # extractable text, a part it cannot read, an empty value list) is an
      # error, never a pass.
      #
      #   result = RedactionVerifier.call(docx_bytes: docx, pdf_bytes: pdf,
      #                                   personal_values: ["Ján Novák", "800101/1234"])
      #   result.ok?     # true only with no leaks and no errors
      #   result.leaks   # [Leak(location:, kind:, value_index:)]
      #   result.errors  # [Finding(code:, message:)]
      #
      # A Leak never carries the value itself (logs stay free of personal data);
      # value_index points into the personal_values the caller passed.
      #
      # Matching, on text normalised by dropping whitespace, invisible format
      # characters and diacritics and by downcasing:
      # - the whole value;
      # - a rodné číslo (6 digits, optional slash, 3-4 digits) with and without
      #   the slash;
      # - each word of a multi-word value that has at least 4 normalised
      #   characters and is not a common word (street, town, state words).
      #
      # Searched: every XML part of the docx (body, headers, footers,
      # footnotes, endnotes, comments, docProps, customXml, relationships; text
      # and attribute values, paragraph by paragraph so a value split across
      # runs is still found) and, when given, the PDF's page text, Info
      # dictionary and XMP metadata.
      #
      # Known limit: text drawn as an image or with a font that has no Unicode
      # map cannot be read; a PDF whose pages yield no text at all is rejected,
      # a partly unreadable one is not detected.
      module RedactionVerifier
        Leak = Struct.new(:location, :kind, :value_index, keyword_init: true)
        Finding = Struct.new(:code, :message, keyword_init: true)

        Result = Struct.new(:leaks, :errors, keyword_init: true) do
          def ok?
            leaks.empty? && errors.empty?
          end
        end

        MIN_WORD = 4
        RODNE_CISLO = %r{\A(\d{6})/?(\d{3,4})\z}

        # Compared after normalisation (diacritics stripped, lowercase).
        COMMON_WORDS = %w[
          ulica ulice namestie mesto obec okres kraj slovensko slovenska slovenskej republika
          cislo adresa sidlo bydlisko trvale bytom narodnej
        ].to_set.freeze

        INERT_EXTENSIONS = %w[.png .jpg .jpeg .gif .bmp .tif .tiff .emf .wmf .svg .odttf .fntdata].freeze

        module_function

        def call(docx_bytes:, personal_values:, pdf_bytes: nil)
          errors = []
          leaks = []
          candidates = build_candidates(personal_values, errors)
          return Result.new(leaks: leaks, errors: errors) if errors.any?

          scan_docx(docx_bytes, candidates, leaks, errors)
          scan_pdf(pdf_bytes, candidates, leaks, errors) if pdf_bytes
          Result.new(leaks: leaks.uniq, errors: errors)
        rescue StandardError => e
          Result.new(leaks: [],
                     errors: [Finding.new(code: :verifier_failed,
                                          message: "verification aborted: #{e.class}")])
        end

        # Lowercase, no diacritics, no whitespace or invisible format characters.
        def normalize(text)
          text.to_s.scrub.unicode_normalize(:nfkd).gsub(/\p{Mn}|\p{Cf}|[[:space:]]/, "").downcase
        end

        # [[value_index, kind, normalised_needle], ...]
        def build_candidates(personal_values, errors)
          values = Array(personal_values).map(&:to_s).reject { |v| v.strip.empty? }
          if values.empty?
            errors << Finding.new(code: :no_personal_values,
                                  message: "no personal values to verify against")
          end

          values.each_with_index.flat_map do |value, index|
            needles = [[:value, normalize(value)]]
            needles.concat(rodne_cislo_variants(value))
            needles.concat(word_needles(value))
            needles.uniq.reject { |_, needle| needle.empty? }.map { |kind, needle| [index, kind, needle] }
          end
        end

        def rodne_cislo_variants(value)
          match = RODNE_CISLO.match(value.strip)
          return [] unless match

          [[:value, "#{match[1]}#{match[2]}"], [:value, "#{match[1]}/#{match[2]}"]]
        end

        def word_needles(value)
          words = value.split(/[[:space:],;]+/).map { |w| w.gsub(/\A[[:punct:]]+|[[:punct:]]+\z/, "") }
          return [] if words.length < 2

          words.map { |w| normalize(w) }
               .select { |w| w.length >= MIN_WORD && !COMMON_WORDS.include?(w) }
               .map { |w| [:word, w] }
        end

        def scan_docx(docx_bytes, candidates, leaks, errors)
          entries = Package.read(docx_bytes)
          unless entries.key?("word/document.xml")
            errors << Finding.new(code: :not_a_docx, message: "word/document.xml is missing")
            return
          end

          entries.each do |name, data|
            segments = docx_segments(name, data, errors)
            check(segments, candidates, "docx:#{name}", leaks)
          end
        rescue Package::Error => e
          errors << Finding.new(code: e.code, message: "docx unreadable: #{e.message}")
        end

        def docx_segments(name, data, errors)
          ext = File.extname(name).downcase
          return [] if INERT_EXTENSIONS.include?(ext)

          unless Xml.xml_part?(name)
            errors << Finding.new(code: :unscannable_part, message: "cannot inspect #{name}")
            return []
          end

          xml_segments(Xml.parse(data))
        rescue Xml::Malformed
          errors << Finding.new(code: :malformed_xml, message: "#{name} is not well-formed XML")
          []
        end

        # Paragraph texts (so a value split over runs is whole again), the text
        # of every other element, and every attribute value.
        def xml_segments(doc)
          segments = doc.xpath("//*[local-name()='p']").map(&:text)
          segments.concat(doc.xpath("//*[not(*)]").map(&:text))
          segments.concat(doc.xpath("//@*").map(&:value))
          segments.concat(doc.xpath("//comment()").map(&:text))
          segments.reject { |s| s.strip.empty? }
        end

        def scan_pdf(pdf_bytes, candidates, leaks, errors)
          reader = PDF::Reader.new(StringIO.new(pdf_bytes.b))
          pages = reader.pages.map(&:text)
          if pages.all? { |t| t.strip.empty? }
            errors << Finding.new(code: :pdf_no_text, message: "PDF has no extractable text, cannot verify")
            return
          end

          pages.each_with_index { |text, i| check([text], candidates, "pdf:page #{i + 1}", leaks) }
          check([pages.join], candidates, "pdf:text", leaks)
          check(reader.info.to_h.values.map(&:to_s), candidates, "pdf:info", leaks)
          check([reader.metadata.to_s], candidates, "pdf:metadata", leaks)
        rescue StandardError => e
          # pdf-reader raises a zoo of errors (malformed, encrypted, unsupported
          # features) and some non-PDF::Reader ones on corrupt input: fail closed on all.
          errors << Finding.new(code: :pdf_unreadable, message: "PDF unreadable: #{e.class}")
        end

        def check(segments, candidates, location, leaks)
          normalized = segments.map { |s| normalize(s) }
          candidates.each do |index, kind, needle|
            leaks << Leak.new(location: location, kind: kind, value_index: index) if normalized.any? do |s|
              s.include?(needle)
            end
          end
        end
      end
    end
  end
end
