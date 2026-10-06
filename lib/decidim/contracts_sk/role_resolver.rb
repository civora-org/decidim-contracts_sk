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
    # Default (civora-org/civora-platform#110, parent #95): the union of
    # - the admin roles: organization admins who have accepted the admin
    #   terms hold every engine role (the pre-existing behaviour), and
    # - the stored roles: the user's UserRole rows (#109) for the user's own
    #   organization.
    # Everyone else holds none. The union is returned in ContractLifecycle::
    # ROLES order.
    #
    # The +context+ argument is IGNORED on purpose: the admin menu passes an
    # organization while Permissions passes a Hash
    # (docs/spikes/m03-06-a-role-admin-access.md, note N1). The tenant is
    # always the user's own organization, never anything derived from
    # +context+, so a stored grant can never leak across organizations.
    #
    # Query cost: admins short-circuit (they already hold every role), others
    # cost one indexed query per user object, memoized per object (see
    # StoredRoles) because views call the resolver once per row.
    #
    # Privacy: never log the user argument or anything derived from it inside
    # a resolver — see docs/roles-and-permissions.md.
    class << self
      attr_accessor :role_resolver
    end

    # Reads (and memoizes) a user's stored engine roles. The memo is keyed on
    # the user OBJECT in a WeakMap: current_user is built per request, so the
    # cache lives exactly one request and dies with the object (no global
    # state, no mutation of the Decidim core class). A grant written after
    # the object was first resolved is therefore only visible on a freshly
    # loaded user — use UserRole directly where read-your-writes matters.
    module StoredRoles
      CACHE = ObjectSpace::WeakMap.new

      def self.for(user)
        # Duck-typed fail-closed guard: anything that is not a persisted,
        # organization-scoped user holds no stored role.
        return [] unless user.respond_to?(:decidim_organization_id) && user.respond_to?(:id)
        return [] if user.id.nil?

        key = [user.id, user.decidim_organization_id]
        cached = CACHE[user]
        return cached.last if cached && cached.first == key

        CACHE[user] = [key, query(*key)]
        CACHE[user].last
      end

      def self.query(user_id, organization_id)
        ContractsSk::UserRole.where(decidim_user_id: user_id, decidim_organization_id: organization_id)
                             .pluck(:role).map(&:to_sym)
      end
    end

    self.role_resolver = lambda do |user, _context|
      next [] if user.nil?

      if user.admin? && user.admin_terms_accepted?
        ContractLifecycle::ROLES
      else
        ContractLifecycle::ROLES & StoredRoles.for(user)
      end
    end
  end
end
