# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Creates or updates the organization's contract header
      # (civora-org/civora-platform#211, P6). One row per organization,
      # updated under its row lock.
      #
      # Audit: one AuditEvent per header KEY whose value changed
      # (`organization_profile.changed.<key>`, target = the profile). The
      # trail records which keys changed, never a value, old or new.
      #
      # Broadcasts :ok(profile) or :invalid (form invalid, or the actor is no
      # longer an organization admin of this organization: re-checked here as
      # defense in depth behind the permission layer).
      class SaveOrganizationProfile < Decidim::Command
        def initialize(form, organization:, user:)
          super()
          @form = form
          @organization = organization
          @user = user
        end

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def call
          return broadcast(:invalid) unless OrganizationProfileActor.ok?(user, organization) && form.valid?

          profile = nil
          ContractOrganizationProfile.transaction do
            profile = find_or_build
            profile.lock! if profile.persisted?
            changed = changed_keys(profile)
            profile.header = form.header
            profile.save!
            changed.each { |key| audit!(profile, key) }
          end

          broadcast(:ok, profile)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
          broadcast(:invalid)
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        private

        attr_reader :form, :organization, :user

        def find_or_build
          ContractOrganizationProfile.find_by(organization: organization) ||
            ContractOrganizationProfile.new(organization: organization)
        end

        def changed_keys(profile)
          before = profile.header.is_a?(Hash) ? profile.header : {}
          after = form.header
          ContractOrganizationProfile::HEADER_KEYS.reject { |key| before[key].presence == after[key].presence }
        end

        def audit!(profile, key)
          AuditEvent.create!(action: "organization_profile.changed.#{key}", target: profile,
                             organization: organization, actor: user)
        end
      end
    end
  end
end
