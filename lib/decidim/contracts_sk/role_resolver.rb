# frozen_string_literal: true

module Decidim
  # Engine for Slovak public contracts workflow and catalogue.
  module ContractsSk
    # Config-time seam mapping a Decidim user onto the engine-logical roles
    # (ContractLifecycle::ROLES — :editor, :reviewer).
    #
    # The host assigns +Decidim::ContractsSk.role_resolver+ to a proc/lambda
    # in an initializer at config time. The callable receives +(user,
    # context)+ and returns an Array of engine-role symbols. Results are
    # always intersected with ContractLifecycle::ROLES before use, so foreign
    # symbols are ignored. Config-time only: never mutate the resolver at
    # request time.
    #
    # Default: organization admins who have accepted the admin terms hold
    # every engine role; everyone else holds none.
    #
    # Privacy: never log the user argument or anything derived from it inside
    # a resolver — see docs/roles-and-permissions.md.
    class << self
      attr_accessor :role_resolver
    end

    self.role_resolver = lambda do |user, _context|
      if user&.admin? && user.admin_terms_accepted?
        ContractLifecycle::ROLES
      else
        []
      end
    end
  end
end
