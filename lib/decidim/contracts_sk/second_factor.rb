# frozen_string_literal: true

module Decidim
  # Engine for Slovak public contracts workflow and catalogue.
  module ContractsSk
    # Config-time seams for an optional second-factor guard on the engine
    # admin (civora-org/civora-platform#165, ADR-010). The engine knows
    # nothing about how 2FA is implemented, enrolled or challenged: that is
    # a host concern (civora-org/civora-platform#164). Both seams are
    # assigned by the host in an initializer and never mutated at request
    # time, like role_resolver and link_target_resolver.
    #
    # - +second_factor_satisfied+ — a callable +(user, session) -> boolean+.
    #   The engine admin base controller redirects when it returns falsey.
    #   The default always returns true, so nothing changes unless a host
    #   sets it.
    # - +second_factor_redirect_path+ — a callable +(controller) -> path+
    #   naming where an unsatisfied request is sent (typically the host's
    #   challenge screen). The default is the Decidim root.
    #
    # Scope: the engine admin only. The public catalogue, the in-space
    # component and Decidim's own /admin and /system are not touched.
    class << self
      attr_accessor :second_factor_satisfied, :second_factor_redirect_path
    end

    self.second_factor_satisfied = ->(_user, _session) { true }
    self.second_factor_redirect_path = lambda { |controller|
      controller.respond_to?(:decidim) ? controller.decidim.root_path : "/"
    }
  end
end
