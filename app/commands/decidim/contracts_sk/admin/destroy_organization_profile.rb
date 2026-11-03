# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Removes the organization's contract header (civora-org/civora-platform
      # #211, P6). Generation then stops with "missing header value" until a
      # new header is saved; generated documents are untouched. One audit
      # event (`organization_profile.removed`, target = the removed profile's
      # id); no values.
      class DestroyOrganizationProfile < Decidim::Command
        def initialize(profile, organization:, user:)
          super()
          @profile = profile
          @organization = organization
          @user = user
        end

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def call
          return broadcast(:invalid) unless profile.decidim_organization_id == organization.id &&
                                            OrganizationProfileActor.ok?(user, organization)

          ContractOrganizationProfile.transaction do
            profile.lock!
            profile.destroy!
            AuditEvent.create!(action: "organization_profile.removed", target: profile,
                               organization: organization, actor: user)
          end

          broadcast(:ok)
        rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordNotDestroyed
          broadcast(:invalid)
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        private

        attr_reader :profile, :organization, :user
      end
    end
  end
end
