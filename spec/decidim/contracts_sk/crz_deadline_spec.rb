# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the CRZ publication deadline arithmetic
# and its config seam (§ 47a OZ, civora-org/civora-platform#124).
#
# Pure Ruby: every example passes `today:` explicitly (or a date to the
# threshold), so nothing depends on the wall clock. The threshold is pinned
# against a brute-force classification over month ends, leap years and
# several durations — it is the piece that lets the SQL scopes compare
# signed_on against plain dates (SQL date arithmetic is not portable).
# ---------------------------------------------------------------------------

require "spec_helper"

# Several related facts per example by design (boundary tables), and the
# brute-force examples are long loops over date ranges.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CrzDeadline do
  def date(string)
    Date.iso8601(string)
  end

  describe "the crz_deadline config seam" do
    after do
      # Restore the engine default so no example leaks an override.
      Decidim::ContractsSk.crz_deadline = 3.months
    end

    it "defaults to exactly three calendar months" do
      expect(Decidim::ContractsSk.crz_deadline).to eq(3.months)
    end

    it "accepts any positive ActiveSupport::Duration" do
      Decidim::ContractsSk.crz_deadline = 90.days

      expect(Decidim::ContractsSk.crz_deadline).to eq(90.days)
      expect(described_class.deadline_for(date("2026-03-10"))).to eq(date("2026-06-08"))
    end

    it "refuses an Integer (Date + Integer would silently add days, not months)" do
      expect { Decidim::ContractsSk.crz_deadline = 90 }.to raise_error(ArgumentError, /positive ActiveSupport::Duration/)
    end

    it "refuses zero, negative and non-Duration values and keeps the previous setting" do
      [0.days, -3.months, nil, "3.months", 3.5, 36.hours, 90.minutes,
       ActiveSupport::Duration.build(7_776_000), 1.month + 12.hours].each do |bad|
        expect { Decidim::ContractsSk.crz_deadline = bad }.to raise_error(ArgumentError)
      end
      expect(Decidim::ContractsSk.crz_deadline).to eq(3.months)
    end
  end

  describe ".deadline_for and .days_left" do
    it "is exactly three months after signing: 2026-03-10 -> 2026-06-10" do
      expect(described_class.deadline_for(date("2026-03-10"))).to eq(date("2026-06-10"))
    end

    it "counts 0 days on the deadline day (due today) and -1 the day after (overdue)" do
      signed = date("2026-03-10")

      expect(described_class.days_left(signed, today: date("2026-06-10"))).to eq(0)
      expect(described_class.days_left(signed, today: date("2026-06-11"))).to eq(-1)
      expect(described_class.days_left(signed, today: date("2026-06-09"))).to eq(1)
    end

    it "is nil for an unknown signing date" do
      expect(described_class.deadline_for(nil)).to be_nil
      expect(described_class.days_left(nil, today: date("2026-06-10"))).to be_nil
    end

    it "clamps month ends to the last day of the target month (§ 122(2) Civil Code)" do
      expect(described_class.deadline_for(date("2026-11-30"))).to eq(date("2027-02-28"))
      expect(described_class.deadline_for(date("2026-11-29"))).to eq(date("2027-02-28"))
      expect(described_class.deadline_for(date("2026-11-28"))).to eq(date("2027-02-28"))
    end

    it "honours leap years" do
      expect(described_class.deadline_for(date("2027-11-29"))).to eq(date("2028-02-29"))
      expect(described_class.deadline_for(date("2027-11-30"))).to eq(date("2028-02-29"))
      expect(described_class.deadline_for(date("2028-02-29"))).to eq(date("2028-05-29"))
    end
  end

  describe ".status" do
    let(:signed) { date("2026-03-10") } # deadline 2026-06-10

    it "classifies overdue, due soon (0..14 days, inclusive) and ok" do
      expect(described_class.status(signed, today: date("2026-06-11"))).to eq(:overdue)
      expect(described_class.status(signed, today: date("2026-06-10"))).to eq(:due_soon)
      expect(described_class.status(signed, today: date("2026-05-27"))).to eq(:due_soon) # 14 days left
      expect(described_class.status(signed, today: date("2026-05-26"))).to eq(:ok)       # 15 days left
    end

    it "classifies a missing signing date as unknown" do
      expect(described_class.status(nil, today: date("2026-06-10"))).to eq(:unknown)
    end

    it "pins the at-risk window at 14 days" do
      expect(described_class::DUE_SOON_DAYS).to eq(14)
    end
  end

  describe ".tracked?" do
    def tracked?(source: "editorial", state: "draft", crz_url: nil)
      described_class.tracked?(source: source, state: state, crz_url: crz_url)
    end

    it "tracks unfiled editorial records in every non-terminal state" do
      Decidim::ContractsSk::ContractLifecycle::DEADLINE_TRACKED_STATES.each do |state|
        expect(tracked?(state: state.to_s)).to be(true)
      end
      expect(Decidim::ContractsSk::ContractLifecycle::DEADLINE_TRACKED_STATES)
        .to eq(%i[draft in_review returned approved published])
    end

    it "treats NULL and '' crz_url as not filed, any other value as filed" do
      expect(tracked?(crz_url: nil)).to be(true)
      expect(tracked?(crz_url: "")).to be(true)
      expect(tracked?(crz_url: "https://crz.gov.sk/zmluva/1/")).to be(false)
    end

    it "excludes CRZ mirrors and terminal states" do
      expect(tracked?(source: "crz")).to be(false)
      expect(tracked?(state: "rejected")).to be(false)
      expect(tracked?(state: "archived")).to be(false)
    end
  end

  describe ".threshold" do
    it "is the smallest signing date whose deadline is on/after the date (month-end gap)" do
      # Naive inversion (2027-05-31 - 3 months = 2027-02-28) is wrong: a
      # record signed 2027-02-28 has the deadline 2027-05-28 and is overdue.
      expect(described_class.threshold(date("2027-05-31"))).to eq(date("2027-03-01"))
      expect(described_class.status(date("2027-02-28"), today: date("2027-05-31"))).to eq(:overdue)
    end

    it "raises instead of looping forever on a pathological search" do
      stub_const("Decidim::ContractsSk::CrzDeadline::MAX_THRESHOLD_STEPS", 0)

      expect { described_class.threshold(date("2027-05-31")) }
        .to raise_error(described_class::ThresholdError)
    end

    # Brute force: for every "today" in the range and every signing date in
    # a window around it, the threshold-based classification must equal the
    # direct deadline arithmetic. Ranges cover month ends and leap years.
    [
      ["3 months", 3.months],
      ["1 month", 1.month],
      ["14 days", 14.days],
      ["1 year", 1.year]
    ].each do |name, duration|
      ranges = [%w[2027-11-01 2028-06-30], %w[2026-01-01 2026-04-30], %w[2026-12-01 2027-06-30]]

      it "matches brute-force overdue/due-soon classification for #{name} over month ends and leap years" do
        mismatches = []
        ranges.each do |from, to|
          (date(from)..date(to)).each do |today|
            low = described_class.threshold(today, duration: duration)
            high = described_class.threshold(today + (described_class::DUE_SOON_DAYS + 1), duration: duration)
            ((today - 400.days)..(today + 5.days)).each do |signed|
              left = (signed + duration - today).to_i
              expected = if left.negative? then :overdue
                         elsif left <= described_class::DUE_SOON_DAYS then :due_soon
                         else :ok
                         end
              actual = if signed < low then :overdue
                       elsif signed < high then :due_soon
                       else :ok
                       end
              mismatches << [today, signed, expected, actual] unless expected == actual
            end
          end
        end

        expect(mismatches.first(5)).to eq([])
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
