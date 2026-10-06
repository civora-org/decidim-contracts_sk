# frozen_string_literal: true

module Decidim
  module ContractsSk
    class CatalogueQuery
      # Applies normalized filters and the sort to a relation. Every method
      # takes and returns a relation, so the caller's published-only,
      # organization-scoped relation is only ever narrowed.
      class Conditions
        def initialize(filters, time_zone)
          @filters = filters
          @zone = Time.find_zone(time_zone) || Time.find_zone!("UTC")
        end

        def filter(relation)
          %i[search amount published signed party source].reduce(relation) do |rel, name|
            send(:"by_#{name}", rel)
          end
        end

        # reorder: a reusing scope may arrive pre-ordered; determinism wins.
        # The publication date is the shared COALESCE(crz_published_on,
        # published_at) (Contract.publication_date_arel); nulls last in
        # both directions, then the id, so the order is total.
        def sort(relation)
          case @filters.sort
          when "published_asc" then relation.reorder(*ordering(Contract.publication_date_arel, :asc))
          when "amount_desc" then relation.reorder(*ordering(Contract.arel_table[:amount], :desc))
          when "amount_asc" then relation.reorder(*ordering(Contract.arel_table[:amount], :asc))
          else relation.reorder(*ordering(Contract.publication_date_arel, :desc))
          end
        end

        private

        # [column, id] ordering in one direction, NULLs last.
        def ordering(column, direction)
          [column.public_send(direction).nulls_last, Contract.arel_table[:id].public_send(direction)]
        end

        def by_search(relation)
          return relation unless @filters.q

          relation.where(TextSearch::CONTRACT_CONDITION, pattern: TextSearch.pattern(@filters.q))
        end

        # A NULL amount never satisfies a range, so records without an amount
        # drop out only while an amount filter is active.
        def by_amount(relation)
          return relation unless @filters.amount_min || @filters.amount_max

          relation.where(amount: @filters.amount_min..@filters.amount_max)
        end

        # The publication date (Contract.publication_date_arel) as calendar
        # days: a record carrying a CRZ date (crz_published_on, a date)
        # matches on it, inclusive on both ends; a record without one falls
        # back to published_at, an instant range, half-open: [from 00:00,
        # day after "to" 00:00) in the time zone — the whole "to" day is in.
        # Each column is compared with its own type (no CAST, no mixed
        # date/timestamp comparison), and either bound may be open. The
        # IS NULL guard makes the two branches disjoint: a record is judged
        # by its CRZ date alone, never by both.
        def by_published(relation)
          return relation unless @filters.published_from || @filters.published_to

          table = Contract.arel_table
          by_crz_date = crz_range(table)
          by_entry = table[:crz_published_on].eq(nil).and(entry_range(table))
          relation.where(by_crz_date.or(by_entry))
        end

        def crz_range(table)
          bounds(table[:crz_published_on], @filters.published_from, @filters.published_to)
        end

        def entry_range(table)
          lower = @filters.published_from && midnight(@filters.published_from)
          upper = @filters.published_to && midnight(@filters.published_to + 1)
          bounds(table[:published_at], lower, upper, upper_inclusive: false)
        end

        # An optionally open range over one column: >= lower and <= upper
        # (or < upper), each bound only when given. At least one is, by the
        # caller's guard.
        def bounds(column, lower, upper, upper_inclusive: true)
          conditions = []
          conditions << column.gteq(lower) if lower
          conditions << (upper_inclusive ? column.lteq(upper) : column.lt(upper)) if upper
          conditions.reduce(:and)
        end

        def by_signed(relation)
          return relation unless @filters.signed_from || @filters.signed_to

          relation.where(signed_on: @filters.signed_from..@filters.signed_to)
        end

        # IN-subquery over the parties: any role, no DISTINCT, no N+1.
        def by_party(relation)
          party = @filters.party
          return relation unless party

          relation.where(id: party_scope(party).select(:contract_id))
        end

        def party_scope(party)
          return Party.where(ico: party.value) if party.kind == :ico

          Party.where(TextSearch::PARTY_CONDITION, pattern: TextSearch.pattern(party.value))
        end

        def by_source(relation)
          case @filters.source
          when "crz" then relation.where(source: CrzImport::Mapper::SOURCE)
          when "editorial" then relation.where.not(source: CrzImport::Mapper::SOURCE)
          else relation
          end
        end

        def midnight(date)
          @zone.local(date.year, date.month, date.day)
        end
      end
    end
  end
end
