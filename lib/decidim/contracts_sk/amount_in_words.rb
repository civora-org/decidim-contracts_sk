# frozen_string_literal: true

require "bigdecimal"

module Decidim
  module ContractsSk
    # Slovak "slovom" rendering of a EUR amount for contract text
    # (civora-org/civora-platform#211): 3062.50 becomes
    # "tritisícšesťdesiatdva eur a päťdesiat centov".
    #
    # Grammar rules (Pravidlá slovenského pravopisu, JÚĽŠ SAV, chapter on
    # numerals; Slovak Wikipedia "Číslovka"). Judgement calls are marked:
    # - Numbers below one million are ONE word ("dvadsaťjeden",
    #   "tritisícšesťdesiatdva", "dvestotisíc"); millions and billions
    #   groups are separate words ("dva milióny päťstotisíc").
    # - A bare 1 or 2 takes the gender of the counted noun: euro is neuter
    #   ("jedno euro", "dve eurá"), cent and milión are masculine ("jeden
    #   cent", "dva centy", "dva milióny"), miliarda is feminine ("jedna
    #   miliarda", "dve miliardy"). A multiplier of tisíc ends in the
    #   feminine/neuter "dve" ("dvetisíc", "dvadsaťdvetisíc"). Inside any
    #   other compound the masculine form is used ("dvadsaťdva eur",
    #   "stojeden eur").
    # - Noun number: exactly 1 is singular, exactly 2-4 nominative plural
    #   (eurá, centy, milióny, miliardy); everything else, including 21
    #   and 22, genitive plural (eur, centov, miliónov, miliárd).
    # - JUDGEMENT: a bare thousand is "tisíc" (not "jedentisíc"), while a
    #   multiplier ending in one keeps "jeden" ("dvadsaťjedentisíc").
    # - Zero cents are omitted; zero euro with cents reads "nula eur a ...".
    module AmountInWords
      UNITS = %w[nula jeden dva tri štyri päť šesť sedem osem deväť].freeze
      TEENS = %w[desať jedenásť dvanásť trinásť štrnásť pätnásť šestnásť sedemnásť osemnásť devätnásť].freeze
      TENS = %w[_ _ dvadsať tridsať štyridsať päťdesiat šesťdesiat sedemdesiat osemdesiat deväťdesiat].freeze
      HUNDREDS = %w[_ sto dvesto tristo štyristo päťsto šesťsto sedemsto osemsto deväťsto].freeze

      # [singular, nominative plural (2-4), genitive plural (5+, compounds)]
      EURO = %w[euro eurá eur].freeze
      CENT = %w[cent centy centov].freeze
      MILLION = %w[milión milióny miliónov].freeze
      BILLION = %w[miliarda miliardy miliárd].freeze

      module_function

      # @param amount [BigDecimal, Integer] EUR between 0 and
      #   Contract::MAX_AMOUNT, at most two decimals
      # @return [String]
      # @raise [ArgumentError] on nil, other types, negatives, sub-cent
      #   precision or values above the maximum
      def call(amount)
        euros, cents = to_cents(amount).divmod(100)
        parts = ["#{euro_words(euros)} #{noun(EURO, euros)}"]
        parts << "#{words(cents)} #{noun(CENT, cents)}" if cents.positive?
        parts.join(" a ")
      end

      def to_cents(amount)
        validate!(amount)
        scaled = BigDecimal(amount) * 100
        raise ArgumentError, "amount has more than two decimals" unless scaled.frac.zero?

        scaled.to_i
      end

      def validate!(amount)
        unless amount.is_a?(BigDecimal) || amount.is_a?(Integer)
          raise ArgumentError, "amount must be a BigDecimal or Integer"
        end
        raise ArgumentError, "amount must be finite" unless amount.finite?
        raise ArgumentError, "amount must not be negative" if amount.negative?
        raise ArgumentError, "amount exceeds the maximum" if amount > Contract::MAX_AMOUNT
      end

      # Only a bare 1 or 2 takes the neuter forms of "euro".
      def euro_words(euros)
        { 1 => "jedno", 2 => "dve" }.fetch(euros) { words(euros) }
      end

      def noun(forms, count)
        return forms[0] if count == 1

        (2..4).cover?(count) ? forms[1] : forms[2]
      end

      def words(number)
        return UNITS[0] if number.zero?

        billions, rest = number.divmod(1_000_000_000)
        millions, rest = rest.divmod(1_000_000)
        thousands, units = rest.divmod(1000)
        [
          group(billions, BILLION, one: "jedna", two: "dve"),
          group(millions, MILLION),
          ("#{thousand_words(thousands)}#{below_thousand(units)}" if rest.positive?)
        ].compact.join(" ")
      end

      def group(count, forms, one: "jeden", two: "dva")
        return unless count.positive?

        "#{count == 1 ? one : below_thousand(count, two: two)} #{noun(forms, count)}"
      end

      def thousand_words(count)
        return "" if count.zero?

        count == 1 ? "tisíc" : "#{below_thousand(count, two: "dve")}tisíc"
      end

      def below_thousand(number, two: "dva")
        hundreds, rest = number.divmod(100)
        tens, digit = rest.divmod(10)
        text = hundreds.positive? ? HUNDREDS[hundreds] : ""
        return text + TEENS[digit] if tens == 1

        text += TENS[tens] if tens > 1
        text + unit_word(digit, two)
      end

      def unit_word(digit, two)
        return "" if digit.zero?

        digit == 2 ? two : UNITS[digit]
      end
    end
  end
end
