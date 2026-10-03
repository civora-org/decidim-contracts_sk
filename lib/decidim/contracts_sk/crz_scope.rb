# frozen_string_literal: true

module Decidim
  # Engine for Slovak public contracts workflow and catalogue.
  module ContractsSk
    # Config-time seam scoping the CRZ import to one organization's own
    # contracts (civora-org/civora-platform#145). The ekosystem sync feed
    # carries every contract published anywhere in Slovakia; a record is
    # in scope for an organization only when the organization's IČO appears
    # on either mirrored party (contracting authority or supplier).
    #
    # The host assigns +Decidim::ContractsSk.crz_organization_ico_resolver+
    # in an initializer at config time — a callable receiving the
    # Decidim::Organization and returning its IČO — mirroring the
    # role_resolver and link_target_resolver seams. The default resolves
    # nothing, so a host that never configures the seam imports nothing.
    #
    # +crz_organization_ico+ is the single choke point the sync and the
    # prune task go through. It fails closed: a blank answer, anything that
    # is not exactly 8 digits after whitespace removal, or a raising
    # resolver yields nil — the import then refuses to run rather than
    # mirroring the whole national register.
    #
    # The scope predicate itself lives in CrzScope.in_scope? (below), shared
    # by the sync and the filing confirmation (civora-org/civora-platform
    # #125).
    #
    # Config-time only: never mutate the resolver at request time.
    class << self
      attr_accessor :crz_organization_ico_resolver
    end

    self.crz_organization_ico_resolver = ->(_organization) {}

    # The organization's normalized 8-digit IČO, or nil when the seam
    # cannot answer one (see the module comment).
    def self.crz_organization_ico(organization)
      return nil if organization.blank?

      ico = crz_organization_ico_resolver.call(organization).to_s.gsub(/\s+/, "")
      ico.match?(/\A\d{8}\z/) ? ico : nil
    rescue StandardError
      nil
    end

    # The record-in-scope predicate (civora-org/civora-platform#145, shared
    # with #125): a mapped CRZ record is in scope for an organization when
    # the organization's IČO is on either mirrored party. Pure; +ico+ is
    # the already-normalized organization IČO — nil (not configured)
    # answers false, so callers fail closed.
    module CrzScope
      module_function

      def in_scope?(record, ico)
        return false if ico.blank?

        record[:parties].any? { |party| party[:ico] == ico }
      end
    end
  end
end
