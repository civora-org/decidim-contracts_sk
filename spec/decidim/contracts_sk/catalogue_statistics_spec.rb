# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the public statistics figures (civora-org/civora-platform#118):
# real SQL on the in-memory SQLite adapter (CONTRACTS_SK_DB=1), with "today"
# and the time zone injected so nothing depends on the wall clock. Synthetic
# data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CatalogueStatistics, :db do
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:today) { Date.new(2026, 10, 15) }
  let(:serials) { (1..).each }
  let(:scope) { contract_class.where(organization: organization).published }

  before { migrate_engine_schema! }

  def stats(time_zone: Time.find_zone!("UTC"), on: today)
    described_class.new(scope: scope, time_zone: time_zone, today: on).call
  end

  def make(overrides = {}, contractors: [])
    serial = serials.next
    contract = contract_class.create!(
      contract_attributes({ state: "published", reference: "ST-#{serial}", title: "Zmluva #{serial}",
                            published_at: Time.utc(2026, 9, 1, 12) + serial.minutes,
                            amount: BigDecimal("100.00"), signed_on: Date.new(2026, 8, 1) }.merge(overrides))
    )
    contractors.each { |attrs| contract.parties.create!({ role: "contractor", name: "Dodávateľ" }.merge(attrs)) }
    contract
  end

  def month(result, year, mon)
    result.months.find { |row| row.key == Date.new(year, mon, 1) }
  end

  describe "an empty scope" do
    it "returns zeros, twelve month rows and no suppliers" do
      result = stats

      expect(result.all_time.count).to eq(0)
      expect(result.all_time.amounts).to eq({})
      expect(result.months.size).to eq(12)
      expect(result.months.sum(&:count)).to eq(0)
      expect(result.years).to eq([])
      expect(result.top_by_amount).to eq({})
      expect(result.top_by_count).to eq([])
      expect(result.own.count).to eq(0)
      expect(result.crz.count).to eq(0)
    end
  end

  describe "totals and the twelve-month window" do
    before do
      make({ signed_on: Date.new(2026, 10, 2), amount: BigDecimal("100.00") })
      make({ signed_on: Date.new(2026, 10, 10), amount: nil })
      make({ signed_on: Date.new(2026, 10, 20), amount: BigDecimal("7.00") }) # future-dated
      make({ signed_on: Date.new(2026, 9, 30), amount: BigDecimal("50.00"), source: "crz", source_id: "9001" })
      make({ signed_on: Date.new(2025, 11, 1), amount: BigDecimal("10.00") })
      make({ signed_on: Date.new(2025, 10, 31), amount: BigDecimal("3.00") }) # twelve months back: outside
      make({ signed_on: Date.new(2024, 5, 5), amount: BigDecimal("1000.00") })
      make({ signed_on: Date.new(2022, 1, 1), amount: BigDecimal("1.00") })
      make({ signed_on: nil, amount: BigDecimal("5.00") }).update_column(:currency, "USD")
      make({ state: "draft", signed_on: Date.new(2026, 10, 3) }) # never counted
    end

    it "builds twelve rows, current month first and flagged partial, zeros included" do
      result = stats

      expect(result.months.map(&:key)).to eq((0..11).map { |back| Date.new(2026, 10, 1) << back })
      expect(result.months.map(&:partial)).to eq([true] + [false] * 11)
      expect(result.months.map(&:count)).to eq([2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
    end

    it "leaves future-dated and twelve-months-back records out of the window and this-month figures" do
      result = stats

      expect(month(result, 2026, 10).count).to eq(2)
      expect(result.this_month.count).to eq(2)
      expect(result.months.map(&:key)).not_to include(Date.new(2025, 10, 1))
      expect(result.months.sum(&:count)).to eq(4)
    end

    it "sums amounts per currency, never across, and counts records without an amount" do
      result = stats

      expect(result.all_time.count).to eq(9)
      expect(result.all_time.amounts).to eq("EUR" => BigDecimal("1171.00"), "USD" => BigDecimal("5.00"))
      expect(result.all_time.without_amount).to eq(1)
      expect(month(result, 2026, 10).amounts).to eq("EUR" => BigDecimal("100.00"))
      expect(month(result, 2026, 10).without_amount).to eq(1)
      expect(result.this_year.count).to eq(3)
    end

    it "lists every year from the earliest to the current newest first, gaps as zero rows, unknown last" do
      years = stats.years

      expect(years.map(&:key)).to eq([2026, 2025, 2024, 2023, 2022, nil])
      expect(years.map(&:count)).to eq([4, 2, 1, 0, 1, 1])
      expect(years.first.partial).to be(true)
      expect(years.last.amounts).to eq("USD" => BigDecimal("5.00"))
    end

    it "splits own records from CRZ mirrors" do
      result = stats

      expect(result.crz.count).to eq(1)
      expect(result.crz.amounts).to eq("EUR" => BigDecimal("50.00"))
      expect(result.own.count).to eq(8)
    end

    it "treats every source other than crz as an own record" do
      make.update_column(:source, "legacy")

      expect(stats.crz.count).to eq(1)
      expect(stats.own.count).to eq(9)
    end

    it "returns frozen plain data" do
      result = stats

      expect(result).to be_frozen
      expect(result.months).to be_frozen
      expect(result.all_time.amounts).to be_frozen
      expect(Marshal.load(Marshal.dump(result))).to eq(result)
    end
  end

  describe "the organization's calendar day" do
    it "buckets the current month by the injected time zone, not by UTC" do
      make({ signed_on: Date.new(2026, 11, 1), amount: BigDecimal("1.00") })
      bratislava = Time.find_zone!("Europe/Bratislava")

      travel_to_instant = Time.utc(2026, 10, 31, 23, 30)
      utc_day = described_class.new(scope: scope, time_zone: Time.find_zone!("UTC"),
                                    today: travel_to_instant.to_date).call
      local_day = described_class.new(scope: scope, time_zone: bratislava,
                                      today: travel_to_instant.in_time_zone(bratislava).to_date).call

      expect(utc_day.months.first.key).to eq(Date.new(2026, 10, 1))
      expect(utc_day.this_month.count).to eq(0)
      expect(local_day.months.first.key).to eq(Date.new(2026, 11, 1))
      expect(local_day.this_month.count).to eq(1)
    end

    it "defaults today to the zone's current day" do
      zone = Time.find_zone!("Europe/Bratislava")

      expect(described_class.new(scope: scope, time_zone: zone).call.today).to eq(zone.today)
    end
  end

  describe "top suppliers" do
    it "keeps ten per ranking and drops the eleventh" do
      11.times do |i|
        ico = format("%08d", 10_000_000 + i)
        make({ amount: BigDecimal((100 + i).to_s) }, contractors: [{ ico: ico, name: "S#{i}" }])
      end

      result = stats

      expect(result.top_by_count.size).to eq(10)
      expect(result.top_by_amount.fetch("EUR").size).to eq(10)
      expect(result.top_by_amount.fetch("EUR").map(&:name)).not_to include("S0")
      expect(result.top_by_amount.fetch("EUR").first.name).to eq("S10")
    end

    it "breaks ties deterministically: amount, then count, then IČO ascending" do
      make({ amount: BigDecimal("50.00") }, contractors: [{ ico: "22222222", name: "B" }])
      make({ amount: BigDecimal("50.00") }, contractors: [{ ico: "11111111", name: "A" }])
      make({ amount: BigDecimal("25.00") }, contractors: [{ ico: "33333333", name: "C" }])
      make({ amount: BigDecimal("25.00") }, contractors: [{ ico: "33333333", name: "C" }])

      result = stats

      expect(result.top_by_amount.fetch("EUR").map(&:ico)).to eq(%w[33333333 11111111 22222222])
      expect(result.top_by_count.map(&:ico)).to eq(%w[33333333 11111111 22222222])
    end

    it "ranks per currency and carries each supplier's per-currency totals" do
      make({ amount: BigDecimal("10.00") }, contractors: [{ ico: "11111111" }])
      make({ amount: BigDecimal("900.00") }, contractors: [{ ico: "22222222" }]).update_column(:currency, "USD")

      result = stats

      expect(result.top_by_amount.keys).to eq(%w[EUR USD])
      expect(result.top_by_amount.fetch("USD").map(&:ico)).to eq(["22222222"])
      expect(result.top_by_amount.fetch("EUR").map(&:ico)).to eq(["11111111"])
      expect(result.top_by_count.find { |s| s.ico == "22222222" }.amounts).to eq("USD" => BigDecimal("900.00"))
    end

    it "counts a contract once per IČO even when two parties of it carry the same IČO" do
      twice = [{ ico: "11111111", name: "Same" }, { ico: "11111111", name: "Same s.r.o." }]
      make({ amount: BigDecimal("40.00") }, contractors: twice)

      supplier = stats.top_by_count.first

      expect(supplier.count).to eq(1)
      expect(supplier.amounts).to eq("EUR" => BigDecimal("40.00"))
    end

    it "names a supplier by its most recent spelling" do
      make({ published_at: Time.utc(2026, 1, 1) }, contractors: [{ ico: "11111111", name: "Old name" }])
      make({ published_at: Time.utc(2026, 6, 1) }, contractors: [{ ico: "11111111", name: "New name" }])

      expect(stats.top_by_count.first.name).to eq("New name")
    end

    # civora-org/civora-platform#159: the same publication-date rule as the
    # catalogue sort and the supplier page (the CRZ date, else published_at).
    it "names a supplier by the spelling with the latest CRZ publication date, not the latest import" do
      make({ crz_published_on: Date.new(2026, 2, 1), published_at: Time.utc(2026, 9, 9) },
           contractors: [{ ico: "11111111", name: "CRZ older" }])
      make({ crz_published_on: Date.new(2026, 6, 1), published_at: Time.utc(2026, 9, 1) },
           contractors: [{ ico: "11111111", name: "CRZ newer" }])
      make({ published_at: Time.utc(2026, 4, 1) }, contractors: [{ ico: "11111111", name: "Plain April" }])

      expect(stats.top_by_count.first.name).to eq("CRZ newer")
    end

    it "ignores the object role, drafts and a malformed or missing IČO" do
      make({}, contractors: [{ ico: "11111111", name: "Real" }])
      make({}, contractors: [{ ico: nil, name: "No ICO" }])
      malformed = make({}, contractors: [{ ico: "33333333", name: "Malformed" }])
      malformed.parties.first.update_column(:ico, "12AB5678")
      make({}).parties.create!(role: "object", name: "Obec", ico: "22222222")
      make({ state: "draft" }, contractors: [{ ico: "44444444", name: "Draft only" }])

      expect(stats.top_by_count.map(&:ico)).to eq(["11111111"])
    end

    it "shows a supplier without any amount only in the count ranking" do
      make({ amount: nil }, contractors: [{ ico: "11111111", name: "No amount" }])

      result = stats

      expect(result.top_by_count.first.amounts).to eq({})
      expect(result.top_by_amount).to eq({})
    end
  end

  describe "tenancy" do
    it "never reads another organization's records" do
      other = Decidim::Organization.create!
      contract_class.create!(contract_attributes(organization: other, state: "published", reference: "X-1",
                                                 published_at: Time.utc(2026, 9, 1), signed_on: Date.new(2026, 10, 1)))

      expect(stats.all_time.count).to eq(0)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
