# frozen_string_literal: true

module Decidim
  module ContractsSk
    # The town's contract header (civora-org/civora-platform#211): who the
    # organization is on a contract (official name, seat, IČO, bank account,
    # statutory representative, signing place). One row per organization.
    #
    # Stored as an allowlisted JSON (`header`), by founder decision: the
    # allowlist is the schema. Unknown keys are rejected by validation, so a
    # template or a form can never smuggle arbitrary data into the header;
    # adding a key is a code change here, not a migration. All values are the
    # organization's own public identifiers, never citizen data.
    class ContractOrganizationProfile < ApplicationRecord
      HEADER_KEYS = %w[
        official_name seat ico dic bank_name iban bic statutory_name statutory_title signing_place
      ].freeze

      MAX_VALUE_LENGTH = 255

      # Loose IBAN shape: two letters, two digits, then 11 to 30 alphanumerics
      # (spaces ignored, any case). The mod-97 check digit is NOT verified.
      IBAN_FORMAT = /\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/

      belongs_to :organization,
                 foreign_key: "decidim_organization_id",
                 class_name: "Decidim::Organization"

      validates :organization, presence: true
      validates :decidim_organization_id, uniqueness: true, allow_nil: true

      before_validation :normalize_header
      validate :header_is_valid

      # The header value for a key, or nil. Only allowlisted keys are readable.
      def header_value(key)
        return unless HEADER_KEYS.include?(key.to_s)

        header.is_a?(Hash) ? header[key.to_s].presence : nil
      end

      private

      # Stringify keys and strip surrounding whitespace so the stored JSON is
      # canonical; anything that is not a Hash is left for the validation.
      def normalize_header
        return unless header.is_a?(Hash)

        self.header = header.to_h.transform_keys(&:to_s).transform_values do |value|
          value.is_a?(String) ? value.strip : value
        end
      end

      def header_is_valid
        return errors.add(:header, :invalid) unless header.is_a?(Hash)

        unknown = header.keys - HEADER_KEYS
        errors.add(:header, :unknown_keys, keys: unknown.join(", ")) if unknown.any?
        header.slice(*HEADER_KEYS).each { |key, value| validate_header_value(key, value) }
      end

      def validate_header_value(key, value)
        return if value.nil?
        return errors.add(:header, :invalid_value, key: key) unless value.is_a?(String)
        return errors.add(:header, :too_long_value, key: key) if value.length > MAX_VALUE_LENGTH

        validate_header_format(key, value)
      end

      def validate_header_format(key, value)
        return if value.blank?

        errors.add(:header, :invalid_ico) if key == "ico" && !value.match?(ICO_FORMAT)
        errors.add(:header, :invalid_iban) if key == "iban" && !value.delete(" ").upcase.match?(IBAN_FORMAT)
      end
    end
  end
end
