# frozen_string_literal: true

require "bigdecimal"
require_relative "../amount_in_words"

module Decidim
  module ContractsSk
    module Templates
      # The values for the public (redacted) variant of a contract document
      # (civora-org/civora-platform#211): every personal value becomes a fixed
      # block, so the filled document shows that something was hidden without
      # revealing what.
      module PublicationVariant
        PLACEHOLDER = "[osobné údaje – skryté]"

        module_function

        # Returns a deep copy of +values+ in which each non-blank value stored
        # under a key listed in +personal_keys+ (String or Symbol, at any
        # nesting depth, including inside table-row loops) is the placeholder.
        # A nil or blank value stays as it is: nothing is hidden, and nil may
        # be what removes an optional block. A Hash or Array under a personal
        # key is replaced leaf by leaf.
        def values_for(values, personal_keys)
          keys = Array(personal_keys).to_set(&:to_s)
          walk(values, keys, false)
        end

        def walk(value, keys, personal)
          case value
          when Hash then value.to_h { |k, v| [k, walk(v, keys, personal || keys.include?(k.to_s))] }
          when Array then value.map { |v| walk(v, keys, personal) }
          else personal && !blank?(value) ? PLACEHOLDER : value
          end
        end

        def blank?(value)
          value.nil? || value == false || (value.respond_to?(:strip) && value.strip.empty?)
        end
      end

      # Small helper a caller uses to build a "*_words" value; the filler stays
      # dumb and never calls this itself.
      #
      #   values[:suma_slovom] = Words.for_amount("3 062,50")
      module Words
        module_function

        # Accepts a BigDecimal, Integer or a String with "," or "." as the
        # decimal mark and optional spaces; raises ArgumentError otherwise.
        def for_amount(amount)
          decimal = amount.is_a?(BigDecimal) ? amount : BigDecimal(amount.to_s.gsub(/[[:space:]]/, "").tr(",", "."))
          AmountInWords.call(decimal)
        end
      end
    end
  end
end
