# frozen_string_literal: true

module Decidim
  module ContractsSk
    module SpreadsheetImport
      # The three parallel party columns of the export's shape
      # (party_roles, party_icos, party_names), each a "|"-separated list,
      # turned into Admin::PartyForm objects. Roles and IČOs may be omitted
      # wholesale (the role then defaults to contractor), never partially:
      # a list that does not line up with the names makes the row invalid.
      class PartyColumns
        SEPARATOR = "|"
        MAX_PARTIES = 10
        DEFAULT_ROLE = "contractor"

        # The names alone, for the formula check (roles and IČOs are
        # validated by the party form).
        attr_reader :names

        def initialize(cells)
          @names = split(cells["party_names"])
          @roles = split(cells["party_roles"])
          @icos = split(cells["party_icos"])
        end

        def blank?
          [@names, @roles, @icos].all?(&:empty?)
        end

        def name_count
          @names.size
        end

        # Names present, and roles/IČOs either absent or one per name.
        def aligned?
          @names.any? && [@roles, @icos].all? { |list| list.empty? || list.size == @names.size }
        end

        def forms
          @names.each_with_index.map do |name, index|
            Admin::PartyForm.new(name: name, role: @roles[index].presence&.downcase || DEFAULT_ROLE,
                                 ico: @icos[index].presence)
          end
        end

        private

        def split(value)
          value.to_s.empty? ? [] : value.split(SEPARATOR, -1).map(&:strip)
        end
      end
    end
  end
end
