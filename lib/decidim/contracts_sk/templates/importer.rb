# frozen_string_literal: true

require "digest"
require "yaml"
require_relative "template_linter"
require_relative "docx_sanitizer"
require_relative "template_fields"

module Decidim
  module ContractsSk
    module Templates
      # Loads a fields-ready .docx as an ACTIVE contract template of one
      # organization (civora-org/civora-platform#211). It is what the rake task
      # `decidim_contracts_sk:templates:import` runs, so the pilot templates can
      # be loaded by hand until there is an upload screen.
      #
      #   Importer.call(organization: org, path: "kupna.docx", lineage_key: "kupna-zmluva", name: "Kúpna zmluva")
      #
      # Steps: lint (any error refuses the file), refuse control fields (the form
      # has no loops or optional blocks yet), sanitize, create the next version
      # of the lineage with one field per merge field, archive the older active
      # versions of the lineage, activate. All in one transaction.
      #
      # Field types are guessed from the key:
      #   org_ico, org_nazov, ...        org_header   (filled from the profile)
      #   datum_x, x_datum               date
      #   cena_x, x_cena, suma_x, x_suma money
      #   x_slovom, x_words              text (spelled out from the money field)
      #   everything else                text
      # A sidecar `<path>.fields.yml` refines it (unknown keys are an error, so
      # a typo cannot silently drop a setting):
      #
      #   person: [kupujuci_meno, kupujuci_rc]     personal data, hidden in the publication copy
      #   required: [predmet, suma_celkom]         or  required: all
      #   types:  { vymera: number }
      #   labels: { kupujuci_meno: "Kupujúci - meno" }
      #   groups: { kupujuci_meno: kupujuci }
      #
      # Output names fields and counts only, never any document content.
      module Importer
        class Error < ContractsSk::Error; end

        SIDECAR_KEYS = %w[person required types labels groups].freeze
        FIELD_KEY = /\A[a-z][a-z0-9_]{0,63}\z/
        TYPE_VALUES = %w[text long_text date money number person].freeze
        DOCX_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

        Result = Struct.new(:template, :fields, :warnings, keyword_init: true)

        module_function

        def call(organization:, path:, lineage_key:, name:)
          bytes = read(path)
          sidecar = load_sidecar("#{path}.fields.yml")
          lint = lint!(bytes)
          keys = field_keys!(lint)
          check_sidecar!(sidecar, keys)
          definitions = keys.each_with_index.map { |key, position| definition(key, position, sidecar) }

          meta = { organization: organization, lineage_key: lineage_key, name: name, path: path }
          template = persist(meta, bytes, definitions)
          Result.new(template: template, fields: template.fields.to_a, warnings: lint.warnings)
        end

        def read(path)
          raise Error, "file not found: #{path}" unless File.file?(path.to_s)
          raise Error, "not a .docx file: #{path}" unless File.extname(path.to_s).casecmp(".docx").zero?

          File.binread(path)
        end

        def load_sidecar(path)
          return {} unless File.file?(path)

          data = YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
          raise Error, "#{path}: the sidecar must be a mapping" unless data.is_a?(Hash)

          data.transform_keys(&:to_s)
        rescue Psych::Exception => e
          raise Error, "#{path}: not valid YAML (#{e.class.name.split("::").last})"
        end

        def lint!(bytes)
          lint = TemplateLinter.call(bytes)
          unless lint.ok?
            reasons = lint.errors.map { |e| "  - #{e.code}: #{e.message}" }.join("\n")
            raise Error, "the template is refused:\n#{reasons}"
          end
          if lint.control_fields.any?
            raise Error, "control fields are not supported by the form yet: #{lint.control_fields.uniq.join(", ")}"
          end

          lint
        end

        def field_keys!(lint)
          keys = lint.merge_fields.uniq
          raise Error, "the template has no merge fields" if keys.empty?

          bad = keys.grep_v(FIELD_KEY)
          raise Error, "merge field names must be lowercase ASCII snake_case: #{bad.join(", ")}" if bad.any?

          keys
        end

        def check_sidecar!(sidecar, keys)
          unknown = sidecar.keys - SIDECAR_KEYS
          raise Error, "unknown sidecar settings: #{unknown.join(", ")}" if unknown.any?

          mentioned = Array(sidecar["person"]) + Array(sidecar["required"]).reject { |k| k == "all" } +
                      %w[types labels groups].flat_map { |k| (sidecar[k] || {}).keys }
          missing = mentioned.map(&:to_s).uniq - keys
          raise Error, "the sidecar names fields the template does not have: #{missing.join(", ")}" if missing.any?

          wrong = (sidecar["types"] || {}).values.map(&:to_s) - TYPE_VALUES
          raise Error, "unknown field types in the sidecar: #{wrong.join(", ")}" if wrong.any?
        end

        def definition(key, position, sidecar)
          person = Array(sidecar["person"]).map(&:to_s).include?(key)
          type = person ? "person" : (sidecar.dig("types", key) || guess_type(key)).to_s
          asked = sidecar["required"] == "all" || Array(sidecar["required"]).map(&:to_s).include?(key)
          { key: key, field_type: type, label: sidecar.dig("labels", key) || key.tr("_", " ").capitalize,
            group_key: sidecar.dig("groups", key), required: asked && typed_by_person?(key, type), position: position }
        end

        # Header, number and spelled-out fields are filled by the generator, so
        # "required" means nothing for them.
        def typed_by_person?(key, type)
          type != "org_header" && !TemplateFields.internal_number_key?(key) && !TemplateFields.words_suffix?(key)
        end

        def guess_type(key)
          return "org_header" if TemplateFields.org_header_key(key)
          return "text" if TemplateFields.words_suffix?(key) || TemplateFields.internal_number_key?(key)
          return "date" if key.start_with?("datum_") || key.end_with?("_datum")
          return "money" if %w[cena suma].any? { |w| key.start_with?("#{w}_") || key.end_with?("_#{w}") || key == w }

          "text"
        end

        def persist(meta, bytes, definitions)
          ActiveRecord::Base.transaction do
            siblings = ContractTemplate.where(organization: meta[:organization], lineage_key: meta[:lineage_key])
            template = ContractTemplate.create!(
              organization: meta[:organization], lineage_key: meta[:lineage_key], name: meta[:name],
              status: "draft", version: siblings.maximum(:version).to_i + 1,
              source_filename: File.basename(meta[:path]), source_checksum: Digest::SHA256.hexdigest(bytes)
            )
            template.file.attach(io: StringIO.new(DocxSanitizer.call(bytes)), filename: File.basename(meta[:path]),
                                 content_type: DOCX_TYPE, identify: false)
            definitions.each { |attrs| template.fields.create!(attrs) }
            siblings.where(status: "active").where.not(id: template.id).update_all(status: "archived",
                                                                                   updated_at: Time.current)
            template.update!(status: "active")
            template
          end
        rescue ActiveRecord::RecordInvalid => e
          raise Error, "could not save the template: #{e.record.errors.full_messages.join("; ")}"
        end
      end
    end
  end
end
