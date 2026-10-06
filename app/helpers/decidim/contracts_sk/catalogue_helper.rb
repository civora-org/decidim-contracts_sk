# frozen_string_literal: true

module Decidim
  module ContractsSk
    # View helpers of the public catalogue's filter form
    # (civora-org/civora-platform#116). Needs ApplicationHelper's
    # format_amount / format_date (both helpers are mixed into the public
    # controller).
    module CatalogueHelper
      AMOUNT_KEYS = %i[amount_min amount_max].freeze
      DATE_KEYS = %i[published_from published_to signed_from signed_to].freeze

      # The active filters as [label, value] pairs for the "active filters"
      # summary, built from the NORMALIZED query: what the reader sees is
      # what was applied (a swapped range shows swapped).
      def catalogue_active_filters(query)
        keys = query.active_filter_keys
        keys += [:sort] if query.non_default_sort?
        keys.map do |key|
          [t("decidim.contracts_sk.contracts.index.filters.active.#{key}"),
           catalogue_filter_text(key, query.filters.public_send(key))]
        end
      end

      # [key, label, text] of every applied filter (never the sort, which has
      # its own menu), each of which the page can offer to drop.
      def catalogue_removable_filters(query)
        keys = query.active_filter_keys
        keys.zip(catalogue_active_filters(query).first(keys.size)).map { |key, (label, text)| [key, label, text] }
      end

      # The filter chips of the catalogue's filter bar and the query keys each
      # one reads (CatalogueQuery::PARAM_KEYS minus q and sort).
      CHIPS = { amount: %i[amount_min amount_max], published: %i[published_from published_to],
                signed: %i[signed_from signed_to], party: %i[party], source: %i[source] }.freeze
      NBSP = " "

      def catalogue_chip_active?(query, chip)
        CHIPS.fetch(chip).any? { |key| !query.filters.public_send(key).nil? }
      end

      # "Suma" while the chip is idle, "Suma: 1 000–5 000 €" once it holds a
      # value: what is applied is readable without opening the chip.
      def catalogue_chip_label(query, chip)
        base = t("decidim.contracts_sk.contracts.index.chips.#{chip}")
        return base unless catalogue_chip_active?(query, chip)

        "#{base}: #{catalogue_chip_value(query, chip)}"
      end

      # The link that drops exactly one param (never the page: the result set
      # changes) and keeps every other filter and the sort.
      def catalogue_without_path(query, key)
        contracts_path(query.to_params.symbolize_keys.except(key.to_sym))
      end

      # Same filters, another sort; the default sort is the bare URL.
      def catalogue_sort_path(query, sort)
        contracts_path(query.with(sort: sort).to_params.symbolize_keys)
      end

      # The sort menu's current choice, as a short phrase ("najnovšie").
      def catalogue_sort_label(query)
        t("decidim.contracts_sk.contracts.index.toolbar.sorts.#{query.filters.sort}")
      end

      # The alert subscription page carrying the search; never the sort (a
      # digest is always newest first).
      def catalogue_follow_path(query)
        new_subscription_path(query.to_params.except("sort").symbolize_keys)
      end

      # "659 zmlúv" first, then the EUR total when any record carries one.
      def catalogue_summary_figures(summary)
        count = t("decidim.contracts_sk.contracts.index.toolbar.count", count: summary.count,
                                                                        n: catalogue_number(summary.count))
        figures = [count]
        figures << catalogue_total_text(summary.eur_total) if summary.eur_count.positive?
        figures
      end

      # The records the total leaves out, stated beside it (never dropped
      # silently, never summed across currencies).
      def catalogue_summary_notes(summary)
        toolbar_t = "decidim.contracts_sk.contracts.index.toolbar"
        notes = []
        notes << t("#{toolbar_t}.without_amount", count: summary.without_amount) if summary.without_amount.positive?
        notes << t("#{toolbar_t}.other_currency", count: summary.other_currency) if summary.other_currency.positive?
        notes
      end

      # "12,4 mil. EUR" from a million up, otherwise the exact amount; the
      # spaces never break a line.
      def catalogue_total_text(total)
        return format_amount(total, "EUR").tr(" ", NBSP) if total < 1_000_000

        value = number_with_precision(total / 1_000_000, precision: 1, strip_insignificant_zeros: true,
                                                         separator: catalogue_separators.last)
        t("decidim.contracts_sk.contracts.index.toolbar.millions", value: value, currency: "EUR").tr(" ", NBSP)
      end

      private

      def catalogue_number(number)
        number_with_delimiter(number, delimiter: catalogue_separators.first)
      end

      # [thousands, decimal] of the current locale: NBSP and comma for Slovak.
      def catalogue_separators
        I18n.locale == :sk ? [NBSP, ","] : [",", "."]
      end

      def catalogue_chip_value(query, chip)
        values = CHIPS.fetch(chip).map { |key| query.filters.public_send(key) }
        case chip
        when :party then values.first.value
        when :source then t("decidim.contracts_sk.contracts.index.filters.sources.#{values.first}")
        else catalogue_range_text(chip, *values)
        end
      end

      # "1 000–5 000 €", "od 1 000 €", "do 01. 09. 2026"; the two ends of a
      # range are joined by an en dash.
      def catalogue_range_text(chip, from, to)
        amount = chip == :amount
        format = ->(value) { amount ? catalogue_chip_amount(value) : format_date(value) }
        range_t = "decidim.contracts_sk.contracts.index.chips"
        text = if from && to then [format.call(from), format.call(to)].join(amount ? "–" : " – ")
               elsif from then t("#{range_t}.from", value: format.call(from))
               else t("#{range_t}.to", value: format.call(to))
               end
        amount ? "#{text}#{NBSP}€" : text
      end

      def catalogue_chip_amount(value)
        number_with_precision(value, precision: 2, strip_insignificant_zeros: true,
                                     delimiter: catalogue_separators.first, separator: catalogue_separators.last)
      end

      def catalogue_filter_text(key, value)
        return format_amount(value, "EUR") if AMOUNT_KEYS.include?(key)
        return format_date(value) if DATE_KEYS.include?(key)
        return value.value if key == :party

        catalogue_choice_text(key, value)
      end

      # source / sort are labelled choices; q is the plain term.
      def catalogue_choice_text(key, value)
        return value if key == :q

        t("decidim.contracts_sk.contracts.index.filters.#{key}s.#{value}")
      end
    end
  end
end
