# frozen_string_literal: true

module Decidim
  module ContractsSk
    class CatalogueQuery
      # Turns raw request params into the normalized, frozen
      # CatalogueQuery::Filters. Pure and defensive: only String values are
      # considered (arrays and hashes are ignored), every invalid value
      # becomes nil, nothing raises. Never Date.parse — only two explicit
      # date shapes are accepted (ISO yyyy-mm-dd and Slovak d.m.yyyy).
      class Normalizer
        YEAR_RANGE = (1900..2100)
        # Shared cap for the free-text params (q and party).
        TEXT_MAX_LENGTH = 255
        AMOUNT_MAX_INPUT_LENGTH = 30
        ISO_DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/
        SK_DATE = /\A(\d{1,2})\.\s?(\d{1,2})\.\s?(\d{4})\z/
        AMOUNT_FORMAT = /\A\d+(?:[.,]\d{1,2})?\z/
        ICO_FORMAT = /\A\d{8}\z/

        # from-key, to-key, value parser of every from/to pair.
        RANGES = [
          %i[amount_min amount_max amount],
          %i[published_from published_to date],
          %i[signed_from signed_to date]
        ].freeze

        def self.call(params)
          new(params).filters
        end

        def initialize(params)
          hash = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
          @raw = hash.stringify_keys.slice(*CatalogueQuery::PARAM_KEYS.map(&:to_s))
                     .select { |_key, value| value.is_a?(String) }
        end

        def filters
          CatalogueQuery::Filters.new(
            q: text(@raw["q"]).strip.first(TEXT_MAX_LENGTH).strip.presence,
            **range_filters,
            party: party(@raw["party"]), source: choice("source", CatalogueQuery::SOURCES),
            sort: choice("sort", CatalogueQuery::SORTS) || CatalogueQuery::DEFAULT_SORT
          )
        end

        private

        def range_filters
          RANGES.each_with_object({}) do |(from_key, to_key, parser), out|
            from, upto = range(from_key, to_key) { |value| send(parser, value) }
            out[from_key] = from
            out[to_key] = upto
          end
        end

        # Parses a from/to pair and swaps it when reversed.
        def range(from_key, to_key)
          from = yield(@raw[from_key.to_s])
          upto = yield(@raw[to_key.to_s])
          from && upto && from > upto ? [upto, from] : [from, upto]
        end

        def text(value)
          TextSearch.clean(value)
        end

        def choice(key, allowed)
          value = @raw[key].to_s.strip.downcase
          value if allowed.include?(value)
        end

        def amount(value)
          text = value&.gsub(/[[:space:]  ]/, "")
          return unless text && text.length <= AMOUNT_MAX_INPUT_LENGTH && text.match?(AMOUNT_FORMAT)

          parsed = BigDecimal(text.tr(",", "."))
          parsed if parsed <= Contract::MAX_AMOUNT
        end

        def date(value)
          year, month, day = date_parts(value.to_s.strip)
          return unless year && YEAR_RANGE.cover?(year) && Date.valid_date?(year, month, day)

          Date.new(year, month, day)
        end

        def date_parts(text)
          if (match = ISO_DATE.match(text))
            match.captures.map(&:to_i)
          elsif (match = SK_DATE.match(text))
            [match[3].to_i, match[2].to_i, match[1].to_i]
          end
        end

        def party(value)
          term = text(value).squish.first(TEXT_MAX_LENGTH).strip
          return if term.blank?

          digits = term.delete(" ")
          kind, value = digits.match?(ICO_FORMAT) ? [:ico, digits] : [:name, term]
          CatalogueQuery::PartyFilter.new(kind, value)
        end
      end
    end
  end
end
