# frozen_string_literal: true

module Decidim
  module ContractsSk
    class CatalogueStatistics
      # The top-supplier rankings of the statistics page: contractor parties
      # of the given (published, scoped) contract relation, kept only with a
      # well-formed 8-digit IČO and counted once per (IČO, contract), however
      # many of a contract's parties carry that IČO. The name is the most
      # recent spelling, ordered like SuppliersController (publication date,
      # then contract id, then party id, newest first), so the two pages never
      # disagree about a supplier's name.
      #
      # by_amount is { currency => top suppliers } (amount desc, count desc,
      # IČO asc; only suppliers with an amount in that currency); by_count is
      # the top suppliers by contract count (count desc, IČO asc). Both are
      # capped at TOP.
      class Suppliers
        Ranking = Data.define(:by_amount, :by_count)

        # One plucked (contractor party x contract) row.
        Row = Data.define(:ico, :name, :party_id, :contract_id, :amount, :currency, :published_at)

        def initialize(relation)
          @relation = relation
        end

        def call
          suppliers = build
          Ranking.new(by_amount: by_amount(suppliers),
                      by_count: suppliers.sort_by { |supplier| [-supplier.count, supplier.ico] }.first(TOP).freeze)
        end

        private

        def by_amount(suppliers)
          currencies = suppliers.flat_map { |supplier| supplier.amounts.keys }.uniq.sort
          currencies.to_h { |currency| [currency, top_for(suppliers, currency)] }.freeze
        end

        def top_for(suppliers, currency)
          suppliers.select { |supplier| supplier.amounts.key?(currency) }
                   .sort_by { |supplier| [-supplier.amounts.fetch(currency), -supplier.count, supplier.ico] }
                   .first(TOP).freeze
        end

        def build
          rows.group_by(&:ico).map do |ico, group|
            per_contract = group.uniq(&:contract_id)
            Supplier.new(ico: ico, name: latest_name(group), count: per_contract.size,
                         amounts: amounts_of(per_contract)).freeze
          end
        end

        def latest_name(group)
          group.max_by { |row| [row.published_at || Time.zone.at(0), row.contract_id, row.party_id] }.name
        end

        def amounts_of(per_contract)
          per_contract.reject { |row| row.amount.nil? }.group_by { |row| row.currency.to_s }
                      .transform_values { |group| group.sum(BigDecimal("0"), &:amount) }
                      .sort.to_h.freeze
        end

        # Based on the contract relation, so every contract column is cast
        # by its own type (amount as BigDecimal, published_at as Time) on
        # any adapter.
        def rows
          @relation.joins(:parties).where(Party.table_name => { role: "contractor" })
                   .pluck(*columns).map { |values| Row.new(*values) }
                   .select { |row| ICO_FORMAT.match?(row.ico.to_s) }
        end

        def columns
          parties = Party.arel_table
          contracts = Contract.arel_table
          [parties[:ico], parties[:name], parties[:id], contracts[:id], contracts[:amount],
           contracts[:currency], contracts[:published_at]]
        end
      end
    end
  end
end
