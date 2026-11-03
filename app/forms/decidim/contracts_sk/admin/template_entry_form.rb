# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # The "new contract from a template" form (civora-org/civora-platform
      # #211), built dynamically from the fields of ONE template version.
      #
      # What is form input and what is not:
      # - the template is a constructor argument. It comes from the
      #   controller's organization-scoped lookup and is never read from params,
      #   so a request can neither pick another tenant's template nor change
      #   the field list;
      # - the values are read ONLY for the template's input fields (see
      #   Templates::TemplateFields.input_fields); unknown keys in the request
      #   are dropped. The organization header, the internal number and the
      #   spelled-out amounts are computed, never typed;
      # - the contract title is the only contract-level input. Amount and
      #   signing date of the contract come from the matching money / date
      #   fields, so nothing is entered twice.
      #
      # Raw input is kept for re-rendering a rejected form; parsed (canonical)
      # values feed the command. Values of personal-data fields are kept apart
      # (#stored_personal_values) because they are stored encrypted.
      # Cop note: the form is deliberately cohesive (input, parsing and the
      # document values of one template in one place).
      # rubocop:disable Metrics/ClassLength
      class TemplateEntryForm
        include ActiveModel::Model

        FieldValues = Templates::FieldValues
        TemplateFields = Templates::TemplateFields

        MAX_TITLE = 255

        attr_reader :template, :title

        # Rebuilds the form from a saved entry, to edit and regenerate.
        def self.for_entry(entry, title:)
          template = entry.contract_template
          stored = entry.values.to_h.merge(entry.personal_values.to_h)
          types = template.fields.index_by(&:key)
          raw = stored.to_h { |key, value| [key.to_s, FieldValues.display(types[key.to_s]&.field_type, value)] }
          new(template: template, title: title, values: raw)
        end

        def initialize(template:, title: nil, values: {})
          super()
          @template = template
          @title = title.to_s.gsub(FieldValues::CONTROL, "").gsub(/[[:space:]]+/, " ").strip
          @field_errors = {}
          @raw = known_values(values)
        end

        def fields
          @fields ||= template.fields.to_a
        end

        def input_fields
          @input_fields ||= TemplateFields.input_fields(fields)
        end

        def header_fields
          TemplateFields.header_fields(fields)
        end

        def words_fields
          TemplateFields.words_fields(fields)
        end

        # Input fields grouped by group_key in template order: [[group_key, [field, ...]], ...];
        # the ungrouped fields come under nil.
        def groups
          input_fields.group_by(&:group_key).map { |key, list| [key.presence, list] }
        end

        # What the person typed (or the saved value, shown in the form's format).
        def raw_value(key)
          @raw[key.to_s].to_s
        end

        def error_for(key)
          @field_errors[key.to_s]
        end

        # The money field a spelled-out field belongs to, for the live preview.
        def words_source(words_field)
          TemplateFields.words_source(words_field, fields)
        end

        validate :validate_title
        validate :validate_values

        # Canonical values, split by sensitivity. Call only on a valid form.
        def stored_values
          input_fields.reject(&:personal_data).to_h { |field| [field.key, canonical(field)] }
        end

        def stored_personal_values
          input_fields.select(&:personal_data).to_h { |field| [field.key, canonical(field)] }
        end

        def personal_keys
          fields.select(&:personal_data).map(&:key)
        end

        def amount
          field = TemplateFields.amount_field(input_fields)
          value = field && canonical(field)
          value.present? ? BigDecimal(value) : nil
        end

        def signed_on
          field = TemplateFields.signed_on_field(input_fields)
          value = field && canonical(field)
          value.present? ? Date.iso8601(value) : nil
        end

        # Header keys the template needs that the organization profile leaves
        # blank (the profile may be nil).
        def missing_header_keys(profile)
          header_fields.filter_map do |field|
            key = TemplateFields.org_header_key(field.key)
            key if profile.nil? || profile.header_value(key).blank?
          end.uniq
        end

        # Every merge field of the template with the text the document shows.
        # Blank values are "" (the filler needs every key present).
        def document_values(profile:, internal_number:)
          fields.to_h { |field| [field.key, document_value(field, profile, internal_number)] }
        end

        private

        def known_values(values)
          source = values.respond_to?(:to_unsafe_h) ? values.to_unsafe_h : values.to_h
          allowed = input_fields.map(&:key)
          picked = source.to_h { |key, value| [key.to_s, value] }.slice(*allowed)
          picked.transform_values { |value| value.is_a?(String) ? value : "" }
        end

        def parsed
          @parsed ||= input_fields.to_h { |field| [field.key, FieldValues.parse(field.field_type, @raw[field.key])] }
        end

        def canonical(field)
          parsed.fetch(field.key).value.to_s
        end

        def validate_title
          @field_errors = {}
          code = :blank if title.blank?
          code = :too_long if title.length > MAX_TITLE
          add_error("title", I18n.t("decidim.contracts_sk.admin.template_entries.form.title"), code) if code
        end

        def add_error(key, label, code)
          message = I18n.t("decidim.contracts_sk.admin.template_entries.errors.#{code}")
          @field_errors[key] = message
          errors.add(:base, "#{label}: #{message}")
        end

        def validate_values
          input_fields.each do |field|
            result = parsed.fetch(field.key)
            code = result.error || (:blank if field.required && result.value.blank?)
            next unless code

            add_error(field.key, field.label, code)
          end
        end

        def document_value(field, profile, internal_number)
          if TemplateFields.header_field?(field)
            profile&.header_value(TemplateFields.org_header_key(field.key)).to_s
          elsif TemplateFields.internal_number_key?(field.key)
            internal_number.to_s
          elsif (source = TemplateFields.words_source(field, fields))
            words_for(source)
          else
            FieldValues.display(field.field_type, canonical(field))
          end
        end

        def words_for(source)
          value = canonical(source)
          value.empty? ? "" : Templates::Words.for_amount(value)
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
