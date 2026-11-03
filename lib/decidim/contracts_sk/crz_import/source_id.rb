# frozen_string_literal: true

module Decidim
  module ContractsSk
    module CrzImport
      # Turns what a referent pastes into the CRZ number box into the numeric
      # CRZ contract id. People copy the address of the record from the
      # browser, not the number, so both are accepted:
      #
      #   12851898
      #   https://www.crz.gov.sk/zmluva/12851898/
      #   crz.gov.sk/zmluva/12851898?foo=1#top   (scheme and "www." optional)
      #
      # Only the crz.gov.sk host and the /zmluva/<digits> path are accepted
      # (anchored, host compared exactly), so an address on another site that
      # merely contains a number is refused, never guessed from. Anything
      # else yields nil.
      module SourceId
        MAX_LENGTH = 20

        DIGITS = /\A\d{1,#{MAX_LENGTH}}\z/
        URL = %r{
          \A(?:https?://)?(?:www\.)?crz\.gov\.sk/zmluva/(?<id>\d{1,#{MAX_LENGTH}})/?(?:[?\#][^\s]*)?\z
        }xi

        # @return [String, nil] the digits-only id, or nil when the input is neither
        def self.parse(input)
          text = input.to_s.gsub(/[[:space:]]+\z/, "").gsub(/\A[[:space:]]+/, "")
          return text if DIGITS.match?(text)

          URL.match(text)&.[](:id)
        end
      end
    end
  end
end
