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

        def sort(relation)
          table = Contract.arel_table
          # reorder: a reusing scope may arrive pre-ordered; determinism wins.
          case @filters.sort
          when "published_asc" then relation.reorder(published_at: :asc, id: :asc)
          when "amount_desc" then relation.reorder(table[:amount].desc.nulls_last, table[:id].desc)
          when "amount_asc" then relation.reorder(table[:amount].asc.nulls_last, table[:id].asc)
          else relation.reorder(published_at: :desc, id: :desc)
          end
        end

        private

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

        # Calendar days in the time zone as an instant range, half-open:
        # [from 00:00, day after "to" 00:00) — the whole "to" day is in.
        def by_published(relation)
          return relation unless @filters.published_from || @filters.published_to

          lower = @filters.published_from && midnight(@filters.published_from)
          upper = @filters.published_to && midnight(@filters.published_to + 1)
          relation.where(published_at: lower...upper)
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
