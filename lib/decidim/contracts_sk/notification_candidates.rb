# frozen_string_literal: true

module Decidim
  # Engine for Slovak public contracts workflow and catalogue.
  module ContractsSk
    # Config-time seam listing the users who MAY receive workflow
    # notifications (civora-org/civora-platform#94, M03-05-B / #105): a
    # callable +(organization) -> users+. The candidates are then narrowed
    # through +role_resolver+ (see TransitionNotification.recipients), so
    # this seam only bounds the set that is asked; it never grants a role.
    #
    # Default: the organization's confirmed, available admins — the default
    # role_resolver only grants roles to admins, so nobody is missed and no
    # citizen account is scanned. Hosts that grant roles to non-admins
    # override the seam, exactly like role_resolver, and must cover every
    # user the resolver can grant +:reviewer+. Config-time only: never
    # mutate at request time.
    #
    # Privacy: never log the users inside a candidates callable.
    class << self
      attr_accessor :notification_candidates
    end

    self.notification_candidates = lambda do |organization|
      Decidim::User.where(organization: organization, admin: true).available.confirmed
    end
  end
end
