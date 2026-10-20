# frozen_string_literal: true

require "tempfile"
require "sablon"

module Decidim
  module ContractsSk
    module Templates
      # Fills the MERGEFIELDs of a .docx template with sablon 0.4.3
      # (civora-org/civora-platform#211). Deliberately dumb: the caller passes
      # strings that are already formatted (dates, amounts, "slovom"), and the
      # filler only validates the shape of the values and renders.
      #
      #   DocxFiller.call(template_bytes, cislo_zmluvy: "VZ-1", polozky: [{nazov: "A"}], priloha: nil)
      #
      # Values: String, nil, true or false; a Hash (nested group); or an Array
      # of Hashes (a table-row loop). A nil or false value removes an optional
      # block (x:if). Anything else raises ArgumentError.
      #
      # Why keys are restricted: sablon treats a context key shaped "type:name"
      # as typed content ("image:logo" reads a file or IO, "html:x" injects
      # markup), so a key containing ":" must never reach it.
      module DocxFiller
        KEY = /\A[A-Za-z_][A-Za-z0-9_]*\z/

        module_function

        def call(template_bytes, values)
          context = normalize(values)
          Tempfile.create(["contract-template", ".docx"], binmode: true) do |file|
            file.write(template_bytes)
            file.flush
            Sablon.template(file.path).render_to_string(context)
          end
        end

        def normalize(value, path = "values")
          case value
          when Hash then value.to_h { |k, v| [normalize_key(k, path), normalize(v, "#{path}.#{k}")] }
          when Array then value.each_with_index.map { |v, i| normalize(v, "#{path}[#{i}]") }
          when String, nil, true, false then value
          else raise ArgumentError, "#{path}: unsupported value type #{value.class}"
          end
        end

        def normalize_key(key, path)
          name = key.to_s
          raise ArgumentError, "#{path}: invalid key #{name.inspect}" unless KEY.match?(name)

          name
        end
      end
    end
  end
end
