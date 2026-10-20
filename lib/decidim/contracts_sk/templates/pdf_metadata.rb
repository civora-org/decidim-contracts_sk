# frozen_string_literal: true

require "stringio"
require "pdf/reader"

module Decidim
  module ContractsSk
    module Templates
      # Blanks the descriptive strings of a PDF's Info dictionary (Title,
      # Author, Subject, Keywords, Creator, Producer) for
      # civora-org/civora-platform#211. LibreOffice copies the document title
      # into the PDF and names itself as Creator and Producer.
      #
      # How: pdf-reader only reads, and the writers (hexapdf is AGPL, prawn and
      # origami cannot edit an existing file) are out of scope, so this
      # overwrites the string bytes IN PLACE with spaces of the same length.
      # Nothing moves, so every xref offset stays valid, and the old text is
      # gone from the file (an appended replacement Info object would leave it
      # recoverable). The result is re-read with pdf-reader to prove the file is
      # still valid and the strings are blank.
      #
      # It FAILS CLOSED (raises Error) on anything it cannot rewrite safely: an
      # encrypted or unreadable file, an incremental update (/Prev), XMP
      # metadata, an Info object it cannot find as plain bytes (inside an object
      # stream), an indirect string value. LibreOffice's PDF export is none of
      # these. Dates and other keys are left alone.
      module PdfMetadata
        class Error < ContractsSk::Error; end

        KEYS = %w[Title Author Subject Keywords Creator Producer].freeze
        KEY_PATTERN = %r{/(?:#{KEYS.join("|")})(?![A-Za-z0-9#])[ \t\r\n]*}n

        module_function

        def blank(pdf_bytes)
          bytes = pdf_bytes.to_s.b
          reader = PDF::Reader.new(StringIO.new(bytes))
          ref = info_reference(reader)
          return bytes unless ref

          pages = reader.page_count
          blanked = blank_object(bytes, ref)
          verify!(blanked, pages)
          blanked
        rescue Error
          raise
        rescue StandardError => e
          raise Error, "cannot sanitize PDF metadata (#{e.class.name.split("::").last})"
        end

        def info_reference(reader)
          trailer = reader.objects.trailer
          raise Error, "incremental PDF updates are not supported" if trailer.key?(:Prev)
          raise Error, "PDF carries XMP metadata" unless reader.metadata.to_s.strip.empty?

          ref = trailer[:Info]
          return nil if ref.nil?
          raise Error, "Info dictionary is not an indirect object" unless ref.is_a?(PDF::Reader::Reference)

          ref
        end

        def blank_object(bytes, ref)
          header = /(?<!\d)#{ref.id}[ \t\r\n]+#{ref.gen}[ \t\r\n]+obj(?![A-Za-z])/n
          out = bytes.dup
          found = false
          pos = 0
          while (match = header.match(out, pos))
            body_start = match.end(0)
            body_end = out.index("endobj", body_start) or raise Error, "unterminated Info object"
            blank_range(out, body_start, body_end)
            found = true
            pos = body_end
          end
          raise Error, "Info object not found as plain bytes" unless found

          out
        end

        # Walks the dictionary text; after each handled value it resumes behind
        # it, so a "/Title" inside a string value is never taken for a key.
        def blank_range(out, from, to)
          pos = from
          while (match = KEY_PATTERN.match(out, pos)) && match.begin(0) < to
            value_at = match.end(0)
            pos = blank_value(out, value_at)
          end
        end

        def blank_value(out, at)
          case out.getbyte(at)
          when 0x28 then blank_literal(out, at)
          when 0x3c then blank_hex(out, at)
          when 0x30..0x39 then raise Error, "Info string is an indirect reference"
          else at
          end
        end

        def blank_literal(out, open)
          depth = 0
          i = open
          while i < out.bytesize
            case out.getbyte(i)
            when 0x5c then i += 1
            when 0x28 then depth += 1
            when 0x29
              depth -= 1
              if depth.zero?
                out[(open + 1)...i] = " " * (i - open - 1)
                return i + 1
              end
            end
            i += 1
          end
          raise Error, "unterminated string in Info"
        end

        # "<" is a hex string unless it opens a dictionary ("<<").
        def blank_hex(out, open)
          return open + 2 if out.getbyte(open + 1) == 0x3c

          close = out.index(">", open) or raise Error, "unterminated hex string in Info"
          width = close - open - 1
          out[(open + 1)...close] = ("20" * ((width + 1) / 2))[0, width]
          close + 1
        end

        def verify!(blanked, pages)
          reader = PDF::Reader.new(StringIO.new(blanked))
          raise Error, "PDF changed while blanking metadata" unless reader.page_count == pages

          leftovers = reader.info.to_h.slice(*KEYS.map(&:to_sym)).values.reject { |v| v.to_s.strip.empty? }
          raise Error, "Info strings are not blank after sanitizing" unless leftovers.empty?
        end
      end
    end
  end
end
