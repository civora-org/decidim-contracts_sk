# frozen_string_literal: true

module Decidim
  module ContractsSk
    # The public statistics page's figures (civora-org/civora-platform#118):
    # totals, the last twelve months, per-year counts, the top suppliers and
    # the own-versus-CRZ split, computed over the caller's published,
    # organization-scoped relation (the CatalogueQuery over it is built here
    # with an EMPTY param set: V1 has no request filters).
    #
    #   stats = CatalogueStatistics.new(scope: published, time_zone: Time.zone).call
    #
    # The result is plain, frozen data (integers, BigDecimals, strings, Dates,
    # a Time): no ActiveRecord objects and no I18n, so it is safe to put in
    # the cache and render in any locale (labels belong to the view).
    #
    # Rules worth knowing:
    # * Periods are bucketed by SIGNING date (D1). #bucket_date is the one
    #   seam to change if the basis ever moves (e.g. to publication date).
    # * Bucketing is done in Ruby over one pluck: no database-specific date
    #   SQL, so SQLite and PostgreSQL agree.
    # * Amounts are never summed across currencies: every total is a
    #   { currency => sum } hash; a record without an amount counts in the
    #   record count and in `without_amount`, never in a sum.
    # * "Now" is the organization's calendar day (today:, from time_zone:).
    #   Records signed after today are left out of the twelve-month window and
    #   the this-month / this-year figures, but counted in the per-year table
    #   and the all-time totals (so those still add up).
    # * Suppliers: contractor parties with a well-formed 8-digit IČO only,
    #   deduplicated per (IČO, contract); the name is the most recent
    #   spelling, ordered like SuppliersController (publication date, then
    #   contract id, then party id, newest first).
    class CatalogueStatistics
      MONTHS = 12
      TOP = 10
      SCHEMA_VERSION = 1

      # count/amounts/without_amount of one set of records.
      Totals = Data.define(:count, :amounts, :without_amount)

      # One period: key is a Date (first day of the month), an Integer year,
      # or nil (signing date unknown); partial marks the running period.
      Row = Data.define(:key, :partial, :count, :amounts, :without_amount)

      # One supplier: amounts is { currency => sum } over all its contracts.
      Supplier = Data.define(:ico, :name, :count, :amounts)

      Result = Data.define(:computed_at, :today, :this_month, :this_year, :all_time, :months, :years,
                           :top_by_amount, :top_by_count, :own, :crz)

      CONTRACT_COLUMNS = %i[signed_on published_at amount currency source].freeze

      def initialize(scope:, time_zone: Time.zone, today: nil)
        @query = CatalogueQuery.new(scope: scope, params: {}, time_zone: time_zone)
        @time_zone = time_zone
        @today = today || time_zone.today
      end

      def call
        rows = contract_rows
        Result.new(computed_at: @time_zone.now, today: @today, **periods(rows), **origins(rows),
                   **suppliers_ranking)
      end

      private

      def periods(rows)
        { this_month: totals(within(rows, @today.beginning_of_month)),
          this_year: totals(within(rows, @today.beginning_of_year)),
          all_time: totals(rows), months: months(rows), years: years(rows) }
      end

      def origins(rows)
        own, crz = rows.partition { |row| !row.fetch(:crz) }
        { own: totals(own), crz: totals(crz) }
      end

      def suppliers_ranking
        ranking = Suppliers.new(@query.relation).call
        { top_by_amount: ranking.by_amount, top_by_count: ranking.by_count }
      end

      # The only place that decides which date a record is bucketed under.
      def bucket_date(row)
        row.fetch(:signed_on)
      end

      def contract_rows
        @query.relation.pluck(*CONTRACT_COLUMNS).map do |signed_on, published_at, amount, currency, source|
          { signed_on: signed_on, published_at: published_at, amount: amount, currency: currency.to_s,
            crz: source == CrzImport::Mapper::SOURCE }
        end
      end

      # Records bucketed from a date up to today (future-dated ones, and
      # undated ones, are out).
      def within(rows, from)
        rows.select do |row|
          date = bucket_date(row)
          !date.nil? && date >= from && date <= @today
        end
      end

      def totals(rows)
        without = rows.count { |row| row.fetch(:amount).nil? }
        Totals.new(count: rows.size, amounts: sums(rows), without_amount: without).freeze
      end

      def sums(rows)
        rows.reject { |row| row.fetch(:amount).nil? }
            .group_by { |row| row.fetch(:currency) }
            .transform_values { |group| group.sum(BigDecimal("0")) { |row| row.fetch(:amount) } }
            .sort.to_h.freeze
      end

      def row_for(key, partial, rows)
        total = totals(rows)
        Row.new(key: key, partial: partial, count: total.count, amounts: total.amounts,
                without_amount: total.without_amount).freeze
      end

      # The current month (partial) and the eleven before it, newest first;
      # months without records are present with zeros.
      def months(rows)
        current = @today.beginning_of_month
        by_month = rows.group_by { |row| bucket_date(row)&.beginning_of_month }
        (0...MONTHS).map do |back|
          month = current << back
          matching = by_month.fetch(month, []).select { |row| bucket_date(row) <= @today }
          row_for(month, back.zero?, matching)
        end.freeze
      end

      # Every year from the earliest to the later of the current and the
      # latest one, gaps as zero rows, newest first; undated records last.
      def years(rows)
        by_year = rows.group_by { |row| bucket_date(row)&.year }
        built = year_span(by_year.keys.compact).map do |year|
          row_for(year, year == @today.year, by_year.fetch(year, []))
        end
        built << row_for(nil, false, by_year.fetch(nil)) if by_year.key?(nil)
        built.freeze
      end

      def year_span(dated)
        return [] if dated.empty?

        (dated.min..[dated.max, @today.year].max).to_a.reverse
      end
    end
  end
end
