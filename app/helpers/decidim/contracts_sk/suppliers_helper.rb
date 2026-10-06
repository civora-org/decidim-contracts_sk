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

      # The contractors of a register row, in entry order. Reads the loaded
      # association (the lists preload parties), so a row costs no query. The
      # object party is the contracting body itself and is left out.
      def contract_contractors(contract)
        contract.parties.select { |party| party.role.to_s == "contractor" }.sort_by(&:id)
      end

      private

      def supplier_linkable?(party)
        party.role.to_s == "contractor" && Decidim::ContractsSk::ICO_FORMAT.match?(party.ico.to_s)
      end
    end
  end
end
