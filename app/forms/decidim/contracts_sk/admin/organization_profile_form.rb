# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # The admin form of the organization's contract header
      # (civora-org/civora-platform#211, P6): one string attribute per allowed
      # header key. Blank values are dropped, so the stored JSON holds only
      # what was typed. Format rules (IČO, IBAN, lengths) live once, on
      # ContractOrganizationProfile; this form validates by building the
      # model and copying its header errors, so the two cannot drift.
      class OrganizationProfileForm
        include ActiveModel::Model
        include ActiveModel::Attributes

        ContractOrganizationProfile::HEADER_KEYS.each { |key| attribute key.to_sym, :string }

        ERROR_SCOPE = "decidim.contracts_sk.admin.organization_profiles.form.errors"

        validate :header_acceptable_to_model

        def self.for_profile(profile)
          values = profile&.header.is_a?(Hash) ? profile.header : {}
          new(values.slice(*ContractOrganizationProfile::HEADER_KEYS))
        end

        # The header to store: allowlisted keys with a non-blank value.
        def header
          ContractOrganizationProfile::HEADER_KEYS.each_with_object({}) do |key, hash|
            value = public_send(key).to_s.strip
            hash[key] = value if value.present?
          end
        end

        def error_for(key)
          Array(errors[key.to_sym]).first
        end

        private

        def header_acceptable_to_model
          if header.empty?
            return errors.add(:base,
                              I18n.t("decidim.contracts_sk.admin.organization_profiles.form.empty"))
          end

          probe = ContractOrganizationProfile.new(header: header)
          probe.valid?
          probe.errors.each do |error|
            next unless error.attribute == :header

            errors.add(target_attribute(error), I18n.t(error.type, scope: ERROR_SCOPE, default: :invalid_value))
          end
        end

        # The model's header errors name the key only in :invalid_value and
        # :too_long_value; the format errors belong to their own fields. The
        # model has no locale entries for them, the messages live here.
        def target_attribute(error)
          case error.type
          when :invalid_ico then :ico
          when :invalid_iban then :iban
          else
            error.options[:key].to_s.presence&.to_sym || :base
          end
        end
      end
    end
  end
end
