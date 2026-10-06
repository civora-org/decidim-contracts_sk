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
    # Default (civora-org/civora-platform#110): the organization's confirmed,
    # available admins PLUS confirmed, available users holding a stored
    # :reviewer UserRole in that organization — exactly the users the default
    # role_resolver can grant :reviewer, so nobody is missed and no other
    # citizen account is scanned. Hosts that grant roles another way
    # override the seam, exactly like role_resolver, and must cover every
    # user the resolver can grant +:reviewer+. Config-time only: never
    # mutate at request time.
    #
    # Privacy: never log the users inside a candidates callable.
    class << self
      attr_accessor :notification_candidates
    end

    self.notification_candidates = lambda do |organization|
      users = Decidim::User.where(organization: organization).available.confirmed
      reviewer_ids = Decidim::ContractsSk::UserRole.where(decidim_organization_id: organization.id,
                                                          role: "reviewer")
                                                   .select(:decidim_user_id)
      users.where(admin: true).or(users.where(id: reviewer_ids))
    end
  end
end
