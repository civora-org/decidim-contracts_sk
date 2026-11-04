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
      # A per-word needle is dropped when that word also occurs in +public_texts+
      # (strings the caller knows are public: the template's own text, the
      # non-personal values such as the town header), because a town word in a
      # buyer's address is not a leak when the town name is printed anyway. The
      # whole-value and rodné číslo needles are never exempted. Without
      # +public_texts+ nothing is exempted (fail closed).
      #
      # Word boundaries: apart from digit needles (rodné číslo, a purely numeric
      # value), which stay substring matches, a needle matches only when the
      # character before it is not a letter or digit and the letters right after
      # it are empty or a Slovak case ending (CASE_ENDINGS). So the first name
      # "Jana" is not found in the public surname "Janas" or "Evanjelická" for
      # "Eva", while "Novák" is still found in "Novákovi" and "Novákom".
      # Limits: a personal word that is also an inflected form of a public word
      # ("Jana" in a public "Jana") cannot be told apart
      # (a single-word value is never exempted by +public_texts+); a word glued to
      # a letter before it ("dňaJana") and a hyphenated line break
      # ("Testo-vací") are not matched.
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

        # Slovak case endings that may follow a personal word and still count as
        # that word ("Novák" -> "Novákovi", "Jana" -> "Janou"). Folded, no diacritics.
        CASE_ENDINGS = %w[
          a e i o u y m
          om ou ov ia ie iu im ym ej ho mu mi
          ovi ova ovu ove ovo ach ami eho emu ich ych
          ovej ovou ovym ovych ovia
        ].to_set.freeze

        INERT_EXTENSIONS = %w[.png .jpg .jpeg .gif .bmp .tif .tiff .emf .wmf .svg .odttf .fntdata].freeze

        module_function

        def call(docx_bytes:, personal_values:, pdf_bytes: nil, public_texts: [])
          errors = []
          leaks = []
          candidates = build_candidates(personal_values, errors, public_words(public_texts))
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

        # Normalised words of the given public strings.
        def public_words(public_texts)
          Array(public_texts).flat_map { |t| split_words(t.to_s).map { |w| normalize(w) } }.to_set
        end

        def split_words(text)
          text.split(/[[:space:],;]+/).map { |w| w.gsub(/\A[[:punct:]]+|[[:punct:]]+\z/, "") }
        end

        # Paragraph and element texts of the docx body, headers and footers: the
        # words a template prints by itself. Unreadable input yields nothing,
        # so nothing is exempted.
        def docx_public_texts(docx_bytes)
          Package.read(docx_bytes).flat_map do |name, data|
            next [] unless name.match?(%r{\Aword/(document|header\d*|footer\d*)\.xml\z})

            xml_segments(Xml.parse(data))
          end
        rescue StandardError
          []
        end

        # [[value_index, kind, normalised_needle], ...]
        def build_candidates(personal_values, errors, public_words = Set.new)
          values = Array(personal_values).map(&:to_s).reject { |v| v.strip.empty? }
          if values.empty?
            errors << Finding.new(code: :no_personal_values,
                                  message: "no personal values to verify against")
          end

          values.each_with_index.flat_map do |value, index|
            needles = [[:value, normalize(value)]]
            needles.concat(rodne_cislo_variants(value))
            needles.concat(word_needles(value, public_words))
            needles.uniq.reject { |_, needle| needle.empty? }.map { |kind, needle| [index, kind, needle] }
          end
        end

        def rodne_cislo_variants(value)
          match = RODNE_CISLO.match(value.strip)
          return [] unless match

          [[:value, "#{match[1]}#{match[2]}"], [:value, "#{match[1]}/#{match[2]}"]]
        end

        def word_needles(value, public_words = Set.new)
          words = split_words(value)
          return [] if words.length < 2

          words.map { |w| normalize(w) }
               .select { |w| w.length >= MIN_WORD && !COMMON_WORDS.include?(w) && !public_words.include?(w) }
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
          folded = segments.map { |s| fold(s) }
          candidates.each do |index, kind, needle|
            leaks << Leak.new(location: location, kind: kind, value_index: index) if folded.any? do |f|
              found?(f, needle)
            end
          end
        end

        # [spaced, stripped, map]: +spaced+ is the folded text with whitespace
        # kept (word boundaries), +stripped+ is the same without whitespace (what
        # the needles are written in), +map+ gives each stripped index its index
        # in +spaced+.
        def fold(text)
          spaced = text.to_s.scrub.unicode_normalize(:nfkd).gsub(/\p{Mn}|\p{Cf}/, "").downcase
          stripped = +""
          map = []
          spaced.each_char.with_index do |ch, i|
            next if ch.match?(/[[:space:]]/)

            stripped << ch
            map << i
          end
          [spaced, stripped, map]
        end

        # Digit needles (rodné číslo, a numeric value) match as substrings, as
        # before: a number inside a longer digit run still counts. Every other
        # needle must stand on word boundaries (see the module comment).
        def found?(folded, needle)
          spaced, stripped, map = folded
          return stripped.include?(needle) if needle.match?(%r{\A[\d/]+\z})

          from = 0
          while (i = stripped.index(needle, from))
            return true if whole_word?(spaced, map[i], map[i + needle.length - 1])

            from = i + 1
          end
          false
        end

        def whole_word?(spaced, first, last)
          return false if first.positive? && spaced[first - 1].match?(/[\p{L}\p{N}]/)

          tail = spaced[(last + 1)..][/\A\p{L}*/]
          tail.empty? || CASE_ENDINGS.include?(tail)
        end
      end
    end
  end
end
