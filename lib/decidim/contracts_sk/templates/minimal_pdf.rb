# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Templates
      # A tiny, deterministic, single-page PDF writer (no dependency): the
      # output of the Fake converter and the fixture builder of the metadata
      # specs. Text is ASCII-folded Helvetica; uncompressed, so bytes are stable.
      module MinimalPdf
        module_function

        # +lines+: Array of Strings. +info+: Hash of Info-dictionary strings
        # (Title, Author, ...), or a String used verbatim as the dictionary
        # body (for hand-crafted edge cases). +pages+ and +extra_trailer+ let a
        # spec build deliberately odd files. +xmp+ (a String) adds an XMP
        # metadata stream referenced from the catalog; pass
        # { body: String, filter: "FlateDecode" } to mark it compressed (/Filter)
        # so a spec can exercise the fail-closed path.
        # Returns binary PDF bytes.
        def build(lines:, info: {}, pages: 1, extra_trailer: "", xmp: nil)
          xmp_id = (info.empty? ? 6 : 7) if xmp
          xmp_body, xmp_filter = xmp.is_a?(Hash) ? xmp.values_at(:body, :filter) : [xmp, nil]
          metadata = xmp_id ? " /Metadata #{xmp_id} 0 R" : ""
          objects = [
            "<< /Type /Catalog /Pages 2 0 R#{metadata} >>",
            pages_dictionary(pages),
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R " \
            "/Resources << /Font << /F1 5 0 R >> >> >>",
            stream(content(lines)),
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
          ]
          objects << info_dictionary(info) unless info.empty?
          info_id = info.empty? ? nil : objects.length
          objects << xmp_stream(xmp_body, xmp_filter) if xmp
          assemble(objects, info_id: info_id, extra_trailer: extra_trailer)
        end

        def xmp_stream(xmp, filter)
          flt = filter ? " /Filter /#{filter}" : ""
          dict = "/Type /Metadata /Subtype /XML#{flt} /Length #{xmp.bytesize}"
          "<< #{dict} >>\nstream\n#{xmp}\nendstream"
        end

        def content(lines)
          lines.each_with_index.map do |line, i|
            "BT /F1 10 Tf 40 #{800 - (i * 14)} Td (#{escape(line)}) Tj ET"
          end.join("\n")
        end

        def stream(data) = "<< /Length #{data.bytesize} >>\nstream\n#{data}\nendstream"

        def pages_dictionary(pages)
          kids = pages.positive? ? "[3 0 R]" : "[]"
          "<< /Type /Pages /Kids #{kids} /Count #{pages} >>"
        end

        def info_dictionary(info)
          return "<< #{info} >>" if info.is_a?(String)

          "<< #{info.map { |k, v| "/#{k} (#{escape(v)})" }.join(" ")} >>"
        end

        def escape(text)
          ascii = text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").gsub(/[^\x20-\x7e]/, "?")
          ascii.gsub(/[\\()]/) { |c| "\\#{c}" }
        end

        def assemble(objects, info_id:, extra_trailer:)
          out = "%PDF-1.4\n".b
          offsets = objects.each_with_index.map do |body, i|
            offset = out.bytesize
            out << "#{i + 1} 0 obj\n#{body}\nendobj\n".b
            offset
          end
          xref = out.bytesize
          out << "xref\n0 #{objects.length + 1}\n0000000000 65535 f \n".b
          offsets.each { |o| out << format("%010d 00000 n \n", o).b }
          trailer = "/Size #{objects.length + 1} /Root 1 0 R"
          trailer += " /Info #{info_id} 0 R" if info_id
          trailer += " #{extra_trailer}" unless extra_trailer.empty?
          out << "trailer\n<< #{trailer} >>\nstartxref\n#{xref}\n%%EOF\n".b
        end
      end
    end
  end
end
