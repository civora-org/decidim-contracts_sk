# frozen_string_literal: true

require "nokogiri"

module Decidim
  module ContractsSk
    module Templates
      # Shared OOXML knowledge for the template services.
      module Xml
        NS = {
          "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
          "r" => "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
          "rel" => "http://schemas.openxmlformats.org/package/2006/relationships",
          "ct" => "http://schemas.openxmlformats.org/package/2006/content-types"
        }.freeze

        # Parts holding WordprocessingML text (body, headers, footers, notes, comments).
        WORD_PART = %r{\Aword/(?:document|header\d*|footer\d*|footnotes|endnotes|comments\w*)\.xml\z}

        module_function

        class Malformed < StandardError; end

        # Parses a part strictly (no error recovery), with network access off
        # and entities left unexpanded. Raises Malformed on bad XML or an empty
        # document. The linter rejects DOCTYPE declarations before any other
        # service reads a part.
        def parse(bytes)
          doc = Nokogiri::XML(bytes.dup.force_encoding(Encoding::UTF_8)) { |config| config.nonet.strict }
          raise Malformed, "no root element" if doc.root.nil?

          doc
        rescue Nokogiri::XML::SyntaxError => e
          raise Malformed, e.message
        end

        def serialize(doc)
          doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
        end

        def doctype?(bytes)
          bytes.b.match?(/<!DOCTYPE/i)
        end

        # Value of a w:-namespaced attribute ("" when absent).
        def wattr(node, name)
          node.attribute_with_ns(name, NS["w"])&.value.to_s
        end

        def word_part?(name)
          WORD_PART.match?(name)
        end

        def rels_part?(name)
          name.end_with?(".rels")
        end

        def xml_part?(name)
          name.end_with?(".xml", ".rels")
        end
      end
    end
  end
end
