# frozen_string_literal: true

module Decidim
  module ContractsSk
    # View helpers of the supplier pages (civora-org/civora-platform#117) and
    # of the detail page's links to them.
    module SuppliersHelper
      # The party's name, linked to its supplier page only when a page can
      # exist for it: a CONTRACTOR with a well-formed 8-digit IČO. Everything
      # else (the object party, no IČO, a malformed stored IČO) renders as
      # plain text, and the helper never raises: the route would refuse a
      # malformed IČO with a UrlGenerationError.
      #
      # Supplier pages are routed only by the standalone engine: inside a
      # participatory space (civora-org/civora-platform#89) the component's
      # route table has no supplier route, so the name renders as plain
      # text there instead of raising NoMethodError.
      def supplier_link_or_name(party, **options)
        return party.name unless respond_to?(:supplier_path) && supplier_linkable?(party)

        link_to party.name, supplier_path(ico: party.ico), **options
      end

      private

      def supplier_linkable?(party)
        party.role.to_s == "contractor" && Decidim::ContractsSk::ICO_FORMAT.match?(party.ico.to_s)
      end
    end
  end
end
