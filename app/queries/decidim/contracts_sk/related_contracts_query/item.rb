# frozen_string_literal: true

module Decidim
  module ContractsSk
    class RelatedContractsQuery
      # One related contract, prepared for display. A plain object (the CRZ
      # handoff PDF precedent) that borrows the engine's formatting helpers,
      # so the partial renders identically when a host view — which has not
      # included the engine helpers — embeds it.
      #
      # Privacy: the only party data it exposes is the contractor's name for
      # a contractor that carries a well-formed 8-digit IČO. A party without
      # an IČO (possibly a natural person) and the object party never leave
      # this class.
      class Item
        include Decidim::ContractsSk::ApplicationHelper

        Supplier = Data.define(:name, :ico)

        attr_reader :contract

        delegate :id, :title, :reference, to: :contract

        def initialize(contract)
          @contract = contract
        end

        def amount_text
          return if contract.amount.blank?

          format_amount(contract.amount, contract.currency)
        end

        # True for a CRZ metadata mirror: shown with the provenance badge.
        def mirror?
          imported_contract?(contract)
        end

        def mirrored_on_text
          format_date(contract.imported_at) if contract.imported_at.present?
        end

        # Distinct contractors with a well-formed IČO, in party order.
        def suppliers
          @suppliers ||= contract.parties.to_a
                                 .select { |party| named_contractor?(party) }
                                 .uniq(&:ico)
                                 .map { |party| Supplier.new(name: party.name, ico: party.ico) }
        end

        private

        def named_contractor?(party)
          party.role.to_s == "contractor" && ICO_FORMAT.match?(party.ico.to_s)
        end
      end
    end
  end
end
