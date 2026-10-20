# frozen_string_literal: true

require_relative "package"
require_relative "xml"

module Decidim
  module ContractsSk
    module Templates
      # Static safety and shape check of an uploaded .docx template
      # (civora-org/civora-platform#211). Pure: bytes in, Result out, nothing
      # is written or executed.
      #
      # Errors block the template; warnings are shown to the author.
      #
      #   result = TemplateLinter.call(bytes)
      #   result.ok?            # no errors
      #   result.errors         # [Finding(code:, message:, part:)]
      #   result.warnings
      #   result.merge_fields   # ["cislo_zmluvy", "p.nazov", ...] (sablon "=" stripped)
      #   result.control_fields # ["priloha:if", "polozky:each(p)", ...]
      module TemplateLinter
        Finding = Struct.new(:code, :message, :part, keyword_init: true)

        Result = Struct.new(:errors, :warnings, :merge_fields, :control_fields, keyword_init: true) do
          def ok?
            errors.empty?
          end

          def error_codes
            errors.map(&:code)
          end

          def warning_codes
            warnings.map(&:code)
          end
        end

        ALLOWED_FIELDS = %w[MERGEFIELD PAGE NUMPAGES].freeze

        # sablon's own pattern (sablon-0.4.3 lib/sablon/parser/mail_merge.rb): a
        # field that does not match is silently left unfilled, so it is an error.
        SABLON_MERGEFIELD = /\A\s*MERGEFIELD\s+([^ ]+)\s+\\\*\s+MERGEFORMAT\s*\z/

        EMBEDDED_RELATIONSHIP_TYPES = %w[oleObject package activeXControl vbaProject].freeze
        EMBEDDED_PART = %r{\A(?:word/embeddings/|word/activeX/|.*oleObject\d*\.bin\z)}i
        REVISION_ELEMENTS = %w[ins del moveFrom moveTo].freeze
        COMMENT_ELEMENTS = %w[commentReference commentRangeStart commentRangeEnd].freeze

        module_function

        def call(docx_bytes)
          ctx = { errors: [], warnings: [], merge_fields: [], control_fields: [] }
          entries = Package.read(docx_bytes)
          lint_package(entries, ctx)
          build_result(ctx)
        rescue Package::Error => e
          ctx = { errors: [Finding.new(code: e.code, message: e.message)], warnings: [], merge_fields: [],
                  control_fields: [] }
          build_result(ctx)
        end

        def build_result(ctx)
          Result.new(errors: ctx[:errors].uniq, warnings: ctx[:warnings].uniq,
                     merge_fields: ctx[:merge_fields].uniq, control_fields: ctx[:control_fields].uniq)
        end

        def lint_package(entries, ctx)
          unless entries.key?("word/document.xml")
            add_error(ctx, :not_a_docx, "word/document.xml is missing")
            return
          end

          lint_entry_names(entries, ctx)
          lint_content_types(entries, ctx)

          entries.each do |name, data|
            next unless Xml.xml_part?(name)

            if Xml.doctype?(data)
              add_error(ctx, :doctype, "DOCTYPE declarations are not allowed", name)
              next
            end

            doc = begin
              Xml.parse(data)
            rescue Xml::Malformed
              add_error(ctx, :malformed_xml, "part is not well-formed XML", name)
              next
            end

            lint_relationships(doc, name, ctx) if Xml.rels_part?(name)
            lint_word_part(doc, name, ctx) if Xml.word_part?(name)
            lint_hidden_text(doc, name, ctx) if Xml.word_part?(name) || name == "word/styles.xml"
          end
        end

        def lint_entry_names(entries, ctx)
          entries.each_key do |name|
            add_error(ctx, :macros, "VBA project present", name) if /vbaProject/i.match?(name)
            add_error(ctx, :ole_embedding, "embedded object present", name) if EMBEDDED_PART.match?(name)
            add_warning(ctx, :embedded_media, "embedded media present", name) if name.start_with?("word/media/")
            add_warning(ctx, :comments, "comments present", name) if name == "word/comments.xml"
          end
        end

        # A macro-enabled document (.docm) announces itself in the content types.
        def lint_content_types(entries, ctx)
          types = entries["[Content_Types].xml"]
          return add_error(ctx, :not_a_docx, "[Content_Types].xml is missing") unless types

          return unless /macroEnabled|vbaProject/i.match?(types)

          add_error(ctx, :macros, "macro-enabled content type",
                    "[Content_Types].xml")
        end

        def lint_relationships(doc, part, ctx)
          doc.xpath("//rel:Relationship", Xml::NS).each do |rel|
            if rel["TargetMode"].to_s.casecmp?("External")
              add_error(ctx, :external_relationship, "external relationship (#{rel["Type"].to_s.split("/").last})",
                        part)
            end
            type = rel["Type"].to_s.split("/").last
            if EMBEDDED_RELATIONSHIP_TYPES.include?(type)
              add_error(ctx, :ole_embedding, "embedded object relationship (#{type})",
                        part)
            end
            add_error(ctx, :alt_chunk, "altChunk relationship", part) if type == "aFChunk"
          end
        end

        def lint_word_part(doc, part, ctx)
          doc.xpath("//*[local-name()='altChunk']").each { add_error(ctx, :alt_chunk, "altChunk element", part) }
          doc.xpath("//*[local-name()='OLEObject']").each { add_error(ctx, :ole_embedding, "OLE object element", part) }

          if doc.xpath("//w:*[#{local_name_in(REVISION_ELEMENTS)}]", Xml::NS).any?
            add_warning(ctx, :tracked_changes, "tracked changes present", part)
          end
          if doc.xpath("//w:*[#{local_name_in(COMMENT_ELEMENTS)}]", Xml::NS).any?
            add_warning(ctx, :comments, "comments present", part)
          end

          each_field(doc) { |instruction| lint_field(instruction, part, ctx) }
        end

        def lint_hidden_text(doc, part, ctx)
          hidden = doc.xpath("//w:vanish", Xml::NS).any? { |node| !%w[0 false off].include?(Xml.wattr(node, "val").downcase) }
          add_warning(ctx, :hidden_text, "hidden text present", part) if hidden
        end

        def lint_field(instruction, part, ctx)
          type = instruction.strip[/\A[A-Za-z]+/].to_s.upcase
          return if type.empty?

          unless ALLOWED_FIELDS.include?(type)
            add_error(ctx, :disallowed_field, "field type #{type} is not allowed", part)
            return
          end
          return unless type == "MERGEFIELD"

          lint_merge_field(instruction, part, ctx)
        end

        def lint_merge_field(instruction, part, ctx)
          name = instruction.strip.split(/\s+/)[1].to_s
          if name.casecmp?("FORMULA")
            add_error(ctx, :mangled_field, "MERGEFIELD FORMULA: the field was mangled by a LibreOffice save", part)
          elsif (match = SABLON_MERGEFIELD.match(instruction))
            expression = match[1]
            if expression.include?(":")
              ctx[:control_fields] << expression
            elsif expression.start_with?("=")
              ctx[:merge_fields] << expression.delete_prefix("=")
            else
              add_error(ctx, :unsupported_merge_field, "merge field names must be written =name", part)
            end
          else
            add_error(ctx, :unsupported_merge_field, "merge field must read: MERGEFIELD =name \\* MERGEFORMAT", part)
          end
        end

        # Yields the full instruction of every field in document order. A complex
        # field's instruction may be split over several instrText runs.
        def each_field(doc, &block)
          stack = []
          doc.xpath("//w:fldChar | //w:instrText | //w:fldSimple", Xml::NS).each do |node|
            case node.name
            when "fldSimple"
              yield Xml.wattr(node, "instr")
            when "instrText"
              stack.empty? ? yield(node.text) : stack.last << node.text
            else
              apply_fld_char(node, stack, &block)
            end
          end
          stack.each(&block)
        end

        def apply_fld_char(node, stack)
          case Xml.wattr(node, "fldCharType")
          when "begin" then stack.push(+"")
          when "end" then yield stack.pop.to_s unless stack.empty?
          end
        end

        def local_name_in(names)
          names.map { |n| "local-name()='#{n}'" }.join(" or ")
        end

        def add_error(ctx, code, message, part = nil)
          ctx[:errors] << Finding.new(code: code, message: message, part: part)
        end

        def add_warning(ctx, code, message, part = nil)
          ctx[:warnings] << Finding.new(code: code, message: message, part: part)
        end
      end
    end
  end
end
