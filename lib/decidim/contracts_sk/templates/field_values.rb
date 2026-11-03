# frozen_string_literal: true

require "bigdecimal"
require "date"

module Decidim
  module ContractsSk
    module Templates
      # Parsing and display of the values a person types into a contract
      # template form (civora-org/civora-platform#211). Pure: strings in,
      # strings out.
      #
      # Every type has ONE canonical stored form, so a value reads back the same
      # whatever the person typed:
      #
      #   date    "1. 1. 2026"  => "2026-01-01"   shown as "1. 1. 2026"
      #   money   "3 062,50"    => "3062.50"      shown as "3 062,50"
      #   number  "12,5"        => "12.5"         shown as "12,5"
      #   text, long_text, person: trimmed text, control characters removed
      #
      # Slovak input habits are accepted (decimal comma, spaces or dots between
      # thousands, "d. m. rrrr" dates); ISO dates and plain dot decimals too.
      # Anything ambiguous or out of range is an error, never a guess ("3.062"
      # could be three euro or three thousand, so it is refused).
      module FieldValues
        Parsed = Struct.new(:value, :error, keyword_init: true) do
          def ok? = error.nil?
        end

        MAX_TEXT = 255
        MAX_LONG_TEXT = 5000
        MAX_NUMBER_DIGITS = 15
        MAX_MONEY = BigDecimal("9999999999.99")
        YEAR_RANGE = (1900..2100)
        NBSP = " "

        # Control characters other than tab and line breaks; those are handled
        # per type.
        CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u0080-\u009F]/
        DATE_SK = /\A(\d{1,2})[.\s]+(\d{1,2})[.\s]+(\d{4})\.?\z/
        DATE_ISO = /\A(\d{4})-(\d{2})-(\d{2})\z/

        module_function

        # @return [Parsed] value is the canonical string ("" for a blank input);
        #   error is nil, :invalid, :too_long or :out_of_range
        def parse(type, raw)
          text = raw.to_s
          return Parsed.new(value: "") if text.strip.empty?

          case type.to_s
          when "date" then parse_date(text)
          when "money" then parse_money(text)
          when "number" then parse_number(text)
          when "long_text" then parse_long_text(text)
          else parse_text(text)
          end
        end

        # The canonical stored value as it is written into a document or form.
        def display(type, canonical)
          value = canonical.to_s
          return "" if value.empty?

          case type.to_s
          when "date" then display_date(value)
          when "money", "number" then display_decimal(value)
          else value
          end
        end

        def parse_text(text)
          value = text.gsub(/[[:space:]]+/, " ").gsub(CONTROL, "").strip
          return Parsed.new(error: :too_long) if value.length > MAX_TEXT

          Parsed.new(value: value)
        end

        def parse_long_text(text)
          value = text.gsub(/\r\n?/, "\n").gsub(/[ \t]+/, " ").gsub(CONTROL, "").gsub(/\n{3,}/, "\n\n").strip
          return Parsed.new(error: :too_long) if value.length > MAX_LONG_TEXT

          Parsed.new(value: value)
        end

        def parse_date(text)
          compact = text.gsub(/[[:space:]]+/, " ").strip
          day, month, year = date_parts(compact)
          return Parsed.new(error: :invalid) unless day && Date.valid_date?(year, month, day)
          return Parsed.new(error: :out_of_range) unless YEAR_RANGE.cover?(year)

          Parsed.new(value: format("%<y>04d-%<m>02d-%<d>02d", y: year, m: month, d: day))
        end

        def date_parts(text)
          sk = DATE_SK.match(text)
          return [sk[1].to_i, sk[2].to_i, sk[3].to_i] if sk

          iso = DATE_ISO.match(text)
          [iso[3].to_i, iso[2].to_i, iso[1].to_i] if iso
        end

        def parse_money(text)
          plain = normalize_decimal(text, max_places: 2)
          return Parsed.new(error: :invalid) unless plain

          amount = BigDecimal(plain)
          return Parsed.new(error: :out_of_range) if amount > MAX_MONEY

          int, frac = amount.to_s("F").split(".")
          Parsed.new(value: "#{int}.#{frac.to_s.ljust(2, "0")}")
        end

        def parse_number(text)
          plain = normalize_decimal(text, max_places: 6, allow_negative: true)
          return Parsed.new(error: :invalid) unless plain
          return Parsed.new(error: :out_of_range) if plain.delete("-.").length > MAX_NUMBER_DIGITS

          value = BigDecimal(plain).to_s("F").sub(/\.0\z/, "")
          Parsed.new(value: value == "-0" ? "0" : value)
        end

        # Turns "3 062,50", "3.062,50", "3,062.50", "3062.5" and "3062" into a
        # dot-decimal string, or nil when the shape is not one of those.
        def normalize_decimal(text, max_places:, allow_negative: false)
          s = text.gsub(/[[:space:]]+/, "")
          sign = ""
          if allow_negative && s.start_with?("-")
            sign = "-"
            s = s[1..]
          end
          plain = dot_decimal(s, "{1,#{max_places}}")
          plain && "#{sign}#{plain}"
        end

        def dot_decimal(str, places)
          case str
          when /\A\d{1,3}(\.\d{3})+,\d#{places}\z/ then str.delete(".").tr(",", ".")
          when /\A\d{1,3}(,\d{3})+\.\d#{places}\z/ then str.delete(",")
          when /\A\d+[.,]\d#{places}\z/ then str.tr(",", ".")
          when /\A\d+\z/ then str
          end
        end

        def display_date(iso)
          year, month, day = iso.split("-").map(&:to_i)
          "#{day}. #{month}. #{year}"
        end

        def display_decimal(canonical)
          sign = canonical.start_with?("-") ? "-" : ""
          int, frac = canonical.delete_prefix("-").split(".")
          grouped = int.reverse.scan(/\d{1,3}/).join(NBSP).reverse
          [sign + grouped, frac].compact.join(",")
        end
      end
    end
  end
end
