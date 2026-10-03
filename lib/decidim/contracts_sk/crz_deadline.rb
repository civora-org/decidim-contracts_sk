# frozen_string_literal: true

require "date"
require "active_support"
require "active_support/duration"
require "active_support/core_ext/integer/time"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/date/calculations"

module Decidim
  # Engine for Slovak public contracts workflow and catalogue.
  module ContractsSk
    # Config-time length of the CRZ publication window
    # (civora-org/civora-platform#124): under § 47a of Act No. 211/2000 Coll.
    # (OZ) a contract that must be published in the CRZ and is not published
    # within three months of its conclusion is deemed never concluded. The
    # engine shows the days left until that deadline for every editorial
    # record not yet recorded as filed in CRZ.
    #
    # The host may assign +Decidim::ContractsSk.crz_deadline+ in an
    # initializer at config time, mirroring the stale_after seam. Unlike
    # stale_after it accepts ONLY a positive ActiveSupport::Duration
    # ("3.months", "90.days"): the calendar semantics live in the Duration
    # (Date + 3.months clamps to the month end), and #to_i would flatten
    # them into seconds — Date + Integer then adds DAYS, a silent
    # miscalculation. Anything else raises ArgumentError at assignment.
    # The default is 3.months, the statutory window.
    #
    # Config-time only: never mutate this setting at request time.
    class << self
      attr_reader :crz_deadline

      def crz_deadline=(value)
        unless value.is_a?(ActiveSupport::Duration) && value.parts.any? &&
               value.parts.values.all?(&:positive?)
          raise ArgumentError,
                "crz_deadline must be a positive ActiveSupport::Duration (e.g. 3.months), " \
                "got #{value.inspect}"
        end

        @crz_deadline = value
      end
    end

    self.crz_deadline = 3.months

    # Pure-Ruby deadline arithmetic and classification for the CRZ
    # publication deadline (civora-org/civora-platform#124). The Contract
    # model's scopes and instance helpers, the admin controller and the
    # views all delegate here, so the rule lives in exactly one place.
    #
    # The deadline is COMPUTED, never stored: signed_on +
    # Decidim::ContractsSk.crz_deadline. "Conclusion" is read as the date of
    # the LAST signature, which is what signed_on records.
    #
    # Disclaimer: this is an aid for the editors, not legal advice. Month-end
    # handling follows § 122(2) of the Civil Code (a period counted in
    # months that ends in a month lacking the day ends on that month's last
    # day) — which is exactly what Ruby's Date + n.months clamps to. The
    # § 122(3) shift of a deadline falling on a weekend or public holiday to
    # the next working day is deliberately NOT modeled: the displayed
    # deadline is the conservative (earlier) one.
    #
    # SQL cannot reproduce Ruby's calendar arithmetic portably (SQLite
    # date('2026-11-30', '+3 months') is 2027-03-02, PostgreSQL and Ruby
    # clamp to 2027-02-28), so the scopes only ever compare signed_on
    # against dates computed here (see .threshold).
    module CrzDeadline
      # The "at risk" window: a deadline 0..14 days away (inclusive) is
      # due soon. A constant, not config, until a pilot asks for more.
      DUE_SOON_DAYS = 14

      # Safety cap for the threshold search loops. Month-end clamping moves
      # the answer by at most a few days, so the cap is never reached for a
      # sane duration; hitting it means the duration is pathological.
      MAX_THRESHOLD_STEPS = 400

      class ThresholdError < Decidim::ContractsSk::Error; end

      module_function

      # The statutory deadline date for a signing date; nil when the
      # signing date is unknown. +duration+ defaults to the config seam.
      def deadline_for(signed_on, duration: Decidim::ContractsSk.crz_deadline)
        return nil if signed_on.nil?

        signed_on + duration
      end

      # Whole days from +today+ to the deadline (0 = due today, negative =
      # overdue); nil when the signing date is unknown.
      def days_left(signed_on, today:, duration: Decidim::ContractsSk.crz_deadline)
        deadline = deadline_for(signed_on, duration: duration)
        deadline && (deadline - today).to_i
      end

      # The smallest signing date s with s + duration >= date. Because Ruby's
      # Date + Duration is monotone non-decreasing in the date, this turns
      # every deadline comparison into a plain signed_on comparison:
      #
      #   deadline <  t  <=>  signed_on <  threshold(t)
      #   deadline >= t  <=>  signed_on >= threshold(t)
      #
      # A naive inversion (signed_on < t - duration) is wrong on days whose
      # day-of-month does not exist in the target month: for t = 2027-05-31
      # the naive bound is 2027-02-28, yet a record signed 2027-02-28 has
      # the deadline 2027-05-28 and IS overdue. The search starts at a
      # lower bound, walks back while the previous day still satisfies the
      # predicate, then forward until it does — exact for any duration.
      def threshold(date, duration: Decidim::ContractsSk.crz_deadline)
        candidate = (date - duration) - 4.days
        candidate = walk(candidate, -1) { |day| (day - 1.day) + duration >= date }
        walk(candidate, 1) { |day| day + duration < date }
      end

      # The deadline status of a signing date: :unknown (no signing date),
      # :overdue (deadline passed), :due_soon (0..DUE_SOON_DAYS days left)
      # or :ok. Agrees with the Contract scopes by construction — both
      # derive from the same deadline arithmetic.
      def status(signed_on, today:, duration: Decidim::ContractsSk.crz_deadline)
        left = days_left(signed_on, today: today, duration: duration)
        return :unknown if left.nil?
        return :overdue if left.negative?
        return :due_soon if left <= DUE_SOON_DAYS

        :ok
      end

      # Whether a record is subject to deadline tracking: an editorial
      # record (the CRZ mirror is already filed by definition), in a
      # non-terminal state, not yet recorded as filed. "Filed" is the
      # +crz_url+ proxy (NULL or empty means not filed) until real filing
      # confirmation lands (civora-org/civora-platform#125). The unfiled
      # test is deliberately exactly "NULL or ''" so it matches the SQL
      # scope; a whitespace-only value counts as filed in both.
      def tracked?(source:, state:, crz_url:)
        source.to_s != mirror_source &&
          Decidim::ContractsSk::ContractLifecycle::DEADLINE_TRACKED_STATES.include?(state&.to_sym) &&
          crz_url.to_s.empty?
      end

      # The provenance value of CRZ mirror rows (single source: the import
      # mapper's constant).
      def mirror_source
        Decidim::ContractsSk::CrzImport::Mapper::SOURCE
      end

      # Moves +day+ one calendar day at a time (+step+ = 1 or -1) while the
      # block says to keep going; raises when the search exceeds the cap.
      def walk(day, step)
        (MAX_THRESHOLD_STEPS + 1).times do
          return day unless yield(day)

          day += step.days
        end

        raise ThresholdError, "crz_deadline threshold search exceeded #{MAX_THRESHOLD_STEPS} steps"
      end
      private_class_method :walk
    end
  end
end
