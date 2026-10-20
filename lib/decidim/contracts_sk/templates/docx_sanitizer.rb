# frozen_string_literal: true

require "pathname"
require_relative "package"
require_relative "xml"

module Decidim
  module ContractsSk
    module Templates
      # Strips authorship and review residue from a .docx
      # (civora-org/civora-platform#211). Bytes in, bytes out.
      #
      # Removed or blanked:
      # - docProps/core.xml: creator, lastModifiedBy, title, subject, keywords,
      #   description, category, contentStatus, identifier (blanked, kept as
      #   empty elements so the package stays valid);
      # - docProps/app.xml: Company, Manager, HyperlinkBase, TitlesOfParts and
      #   HeadingPairs (the latter carry document titles);
      # - docProps/custom.xml, the thumbnail, customXml/*, comments parts and
      #   word/people.xml (author names), with their relationships and content
      #   types;
      # - tracked changes: insertions are accepted (unwrapped), deletions and
      #   formatting-change records are dropped, as is a deleted table row;
      # - comment anchors, w:customXml smart-tag wrappers (unwrapped), and
      #   hidden runs (w:vanish).
      #
      # Raises Package::Error or Xml::Malformed on input it cannot read.
      #
      # Known limits: a run that opens or closes a field is never removed even
      # when hidden (removing half a field corrupts it), and hidden text set by
      # a style in styles.xml is not touched (the redaction verifier still sees
      # it, because it scans every part).
      module DocxSanitizer
        CORE_BLANK = %w[
          dc:creator cp:lastModifiedBy dc:title dc:subject cp:keywords dc:description
          cp:category cp:contentStatus dc:identifier
        ].freeze
        APP_BLANK = %w[Company Manager HyperlinkBase].freeze
        APP_DROP = %w[TitlesOfParts HeadingPairs].freeze

        REMOVED_PART = %r{\A(?:
          docProps/custom\.xml |
          docProps/thumbnail\.\w+ |
          customXml/.* |
          word/people\.xml |
          word/comments\w*\.xml
        )\z}x

        CHANGE_RECORDS = %w[
          rPrChange pPrChange sectPrChange tblPrChange tblPrExChange tcPrChange trPrChange
          tblGridChange numberingChange cellIns cellDel cellMerge moveFromRangeStart
          moveFromRangeEnd moveToRangeStart moveToRangeEnd
        ].freeze
        COMMENT_ANCHORS = %w[commentRangeStart commentRangeEnd commentReference].freeze
        FIELD_MARKERS = %w[fldChar instrText fldSimple].freeze

        module_function

        def call(docx_bytes)
          entries = Package.read(docx_bytes)
          removed = entries.keys.grep(REMOVED_PART)
          kept = entries.reject { |name, _| removed.include?(name) }

          kept = kept.to_h { |name, data| [name, clean_part(name, data, removed)] }
          Package.write(kept)
        end

        def clean_part(name, data, removed)
          return data unless Xml.xml_part?(name)

          doc = Xml.parse(data) # raises Xml::Malformed: never emit a half-cleaned package
          case name
          when "docProps/core.xml" then blank_core(doc)
          when "docProps/app.xml" then blank_app(doc)
          when "[Content_Types].xml" then drop_overrides(doc, removed)
          when ->(n) { Xml.rels_part?(n) } then drop_relationships(doc, name, removed)
          when ->(n) { Xml.word_part?(n) } then clean_word_part(doc)
          else return data
          end
          Xml.serialize(doc)
        end

        def blank_core(doc)
          CORE_BLANK.each do |qualified|
            doc.xpath("//#{qualified}").each { |node| node.content = "" }
          end
        end

        def blank_app(doc)
          APP_BLANK.each { |tag| doc.xpath("//*[local-name()='#{tag}']").each { |node| node.content = "" } }
          APP_DROP.each { |tag| doc.xpath("//*[local-name()='#{tag}']").each(&:remove) }
        end

        def drop_overrides(doc, removed)
          doc.xpath("//ct:Override", Xml::NS).each do |node|
            node.remove if removed.include?(node["PartName"].to_s.delete_prefix("/"))
          end
        end

        def drop_relationships(doc, rels_name, removed)
          base = Pathname.new(rels_name).dirname.dirname
          doc.xpath("//rel:Relationship", Xml::NS).each do |rel|
            next if rel["TargetMode"].to_s.casecmp?("External")

            target = rel["Target"].to_s
            resolved = target.start_with?("/") ? target.delete_prefix("/") : base.join(target).cleanpath.to_s
            node_removed = removed.include?(resolved) || resolved.start_with?("customXml/")
            rel.remove if node_removed
          end
        end

        def clean_word_part(doc)
          drop_deleted_rows(doc)
          drop_by_name(doc, %w[del moveFrom])
          drop_by_name(doc, CHANGE_RECORDS)
          drop_by_name(doc, COMMENT_ANCHORS)
          unwrap(doc, %w[ins moveTo customXml])
          drop_by_name(doc, %w[delText delInstrText]) # orphans of removed deletions
          drop_hidden_runs(doc)
        end

        # A row marked deleted (w:trPr/w:del) disappears when changes are accepted.
        def drop_deleted_rows(doc)
          doc.xpath("//w:tr[w:trPr/w:del]", Xml::NS).each(&:remove)
        end

        def drop_by_name(doc, names)
          doc.xpath("//w:*[#{names.map { |n| "local-name()='#{n}'" }.join(" or ")}]", Xml::NS).each(&:remove)
        end

        # Replaces the element by its children (w:ins wrapping runs, a smart tag, ...).
        # A paragraph-mark w:ins inside w:rPr/w:trPr has no children and just goes.
        def unwrap(doc, names)
          doc.xpath("//w:*[#{names.map { |n| "local-name()='#{n}'" }.join(" or ")}]", Xml::NS).reverse_each do |node|
            node.children.each { |child| node.add_previous_sibling(child) }
            node.remove
          end
        end

        def drop_hidden_runs(doc)
          doc.xpath("//w:r[w:rPr/w:vanish]", Xml::NS).each do |run|
            vanish = run.at_xpath("w:rPr/w:vanish", Xml::NS)
            next if %w[0 false off].include?(Xml.wattr(vanish, "val").downcase)
            next if run.xpath(".//w:*", Xml::NS).any? { |n| FIELD_MARKERS.include?(n.name) }

            run.remove
          end
        end
      end
    end
  end
end
