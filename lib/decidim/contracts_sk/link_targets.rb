# frozen_string_literal: true

module Decidim
  # Engine for Slovak public contracts workflow and catalogue.
  module ContractsSk
    # Config-time seam resolving a contract link's target into display
    # information (M01-87, civora-org/civora-platform#87).
    #
    # Two settings, both assigned by the host in an initializer at config
    # time and never mutated at request time — mirroring the role_resolver
    # and stale_after seams:
    #
    # - +supported_link_target_types+ — the whitelist of target types a
    #   link may reference (String class names). The default is the empty
    #   vocabulary, so the standalone engine can neither create nor render
    #   links: hosts opt in by assigning e.g.
    #   +%w[Decidim::Accountability::Result]+. The writer normalizes every
    #   element to a String and freezes the array, so a captured reference
    #   can never mutate the whitelist (the engine's frozen-vocabulary
    #   doctrine).
    #
    # - +link_target_resolver+ — a callable receiving the link and returning
    #   +{ label:, url: }+ display info (+url+ may be nil — the label then
    #   renders as plain text), or nil when the target cannot be presented.
    #   The default resolves nothing.
    #
    # +resolve_link_target+ is the single choke point both the public
    # catalogue and the admin surface go through. It whitelists the target
    # type, refuses dangling targets (the polymorphic row is gone), and
    # fails closed: any shape deviation or raising resolver yields nil, so
    # an unresolvable target can never raise or leak internals on a public
    # page. Results are computed fresh on every call — the host may change
    # the seam only at config time, but nothing here memoizes it.
    class << self
      attr_accessor :link_target_resolver

      def supported_link_target_types
        @supported_link_target_types ||= [].freeze
      end

      def supported_link_target_types=(types)
        @supported_link_target_types = Array(types).map(&:to_s).freeze
      end
    end

    self.link_target_resolver = ->(_link) { nil }

    # Resolves a contract link into { label:, url: } display info, or nil
    # when the target must not be presented: unsupported type, dangling
    # polymorphic row (including a target class that no longer exists),
    # a resolver that answers nil / a malformed shape / raises. See the
    # module comment for the seam's config-time doctrine.
    def self.resolve_link_target(link)
      return nil if link.blank?
      return nil unless supported_link_target_types.include?(link.target_type.to_s)
      return nil if link.target.blank?

      normalize(link_target_resolver.call(link))
    rescue StandardError
      nil
    end

    # Fails closed on the resolver's return shape: only a hash carrying a
    # present label is presentable; the URL is optional (nil renders the
    # label as plain text).
    def self.normalize(info)
      return nil unless info.is_a?(Hash)
      return nil if info[:label].blank?

      {
        label: info[:label].to_s,
        url: info[:url].present? ? info[:url].to_s : nil
      }
    end
    private_class_method :normalize
  end
end
