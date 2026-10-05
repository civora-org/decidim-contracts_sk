# frozen_string_literal: true

require "bigdecimal/util"

module Decidim
  module ContractsSk
    # View helpers of the public statistics page (civora-org/civora-platform
    # #118). Needs ApplicationHelper's format_amount / format_datetime (mixed
    # into the controller's views).
    module StatisticsHelper
      # Smallest visible bar for a non-zero value, so a tiny count is still
      # seen next to a large one; zero stays empty.
      MIN_BAR_PERCENT = 2

      MONTH_KEYS = %w[january february march april may june july august september october november december].freeze

      # Width of a bar in percent of the largest value (count basis, D4).
      def bar_percent(value, maximum)
        return 0 unless value.to_d.positive? && maximum.to_d.positive?

        [(value.to_f / maximum * 100).round(1), MIN_BAR_PERCENT].max
      end

      # "október 2026" / "October 2026", from the engine's own month names
      # (never the host's locale data).
      def month_label(date)
        "#{I18n.t("decidim.contracts_sk.statistics.months.#{MONTH_KEYS.fetch(date.month - 1)}")} #{date.year}"
      end

      # One-decimal share, locale-aware ("33,3 %" / "33.3%"); empty total is 0.
      def share_percent(part, total)
        value = total.to_i.zero? ? 0 : (part.to_f / total * 100)
        separator = I18n.t("decidim.contracts_sk.statistics.decimal_separator")
        I18n.t("decidim.contracts_sk.statistics.percent",
               value: number_with_precision(value, precision: 1, separator: separator))
      end

      # Slovak legal-form suffixes ("s. r. o.", "a. s.", "v. o. s.", "k. s.",
      # "spol. s r. o.") whose internal spaces must never break a line.
      LEGAL_FORM = /(?:spol\.\s+s\s+r\.\s*o\.|s\.\s*r\.\s*o\.|v\.\s*o\.\s*s\.|a\.\s*s\.|k\.\s*s\.)\z/i

      # A supplier's register name with its legal-form suffix bound by
      # non-breaking spaces, so "s. r. o." never splits across lines.
      def supplier_display_name(name)
        name.to_s.sub(LEGAL_FORM) { |suffix| suffix.gsub(/\s+/, "\u00A0") }
      end

      # "1 250,00 EUR · 3 000,00 USD" for a { currency => sum } hash.
      def amounts_text(amounts)
        amounts.map { |currency, sum| format_amount(sum, currency) }.join(" · ")
      end
    end
  end
end
