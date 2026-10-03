# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the pure CRZ filing comparison
# (civora-org/civora-platform#125): the editorial contract against the
# mapped CRZ record, row by row — match, mismatch, unverifiable and the
# normalization rules (integer CIN, whitespace/case reference, BigDecimal
# cents), plus the withdrawn-status predicate. No database: the contract is
# a plain struct standing in for the attributes the comparison reads.
#
# Synthetic data only ("Obec Ukážková", fake IČO patterns), no real PII.
# ---------------------------------------------------------------------------

require "spec_helper"

# Plain structs standing in for the attributes the comparison reads.
FilingFakeContract = Struct.new(:reference, :amount, :parties, keyword_init: true)
FilingFakeParty = Struct.new(:role, :ico, keyword_init: true)

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CrzImport::FilingComparison do
  def crz_payload(overrides = {})
    {
      "id" => 2_142_424,
      "contract_identifier" => "UKÁŽKA-2026/001",
      "subject" => "Dodávka výpočtovej techniky",
      "contract_price_amount" => "1043.68",
      "contracting_authority_name" => "Obec Ukážková",
      "contracting_authority_cin" => "00 000 001",
      "supplier_name" => "Demo Dodávky s.r.o.",
      "supplier_cin" => "00 000 002"
    }.merge(overrides)
  end

  def record(overrides = {})
    Decidim::ContractsSk::CrzImport::Mapper.map(crz_payload(overrides))
  end

  def contract(reference: "UKÁŽKA-2026/001", amount: BigDecimal("1043.68"), contractor_icos: ["00000002"])
    parties = [FilingFakeParty.new(role: "object", ico: "00000001")] +
              contractor_icos.map { |ico| FilingFakeParty.new(role: "contractor", ico: ico) }
    FilingFakeContract.new(reference: reference, amount: amount, parties: parties)
  end

  def statuses(comparison)
    comparison.rows.to_h { |row| [row.field, row.status] }
  end

  def compare(contract_overrides = {}, payload_overrides = {})
    described_class.new(contract: contract(**contract_overrides), record: record(payload_overrides))
  end

  it "matches every row for an identical record" do
    comparison = compare

    expect(statuses(comparison)).to eq(reference: :match, supplier_ico: :match, amount: :match)
    expect(comparison.all_match?).to be(true)
    expect(comparison.needs_reason?).to be(false)
  end

  describe "reference" do
    it "ignores whitespace and case, including non-ASCII case folding" do
      comparison = compare({ reference: "  ukážka - 2026 / 001 " }, { "contract_identifier" => "UKÁŽKA-2026/001" })

      expect(statuses(comparison)[:reference]).to eq(:match)
    end

    it "mismatches a different reference" do
      expect(statuses(compare({ reference: "ZP-2026-999" }))[:reference]).to eq(:mismatch)
    end

    it "is unverifiable when either side is blank" do
      aggregate_failures do
        expect(statuses(compare({ reference: " " }))[:reference]).to eq(:unverifiable)
        expect(statuses(compare({}, { "contract_identifier" => nil, "reference" => nil }))[:reference])
          .to eq(:unverifiable)
      end
    end
  end

  describe "supplier IČO" do
    it "matches when ANY editorial contractor carries the CRZ supplier IČO" do
      comparison = compare(contractor_icos: %w[00000077 00000002])

      expect(statuses(comparison)[:supplier_ico]).to eq(:match)
    end

    it "normalizes the integer CIN CRZ serves (leading zeros restored by the mapper)" do
      comparison = compare({ contractor_icos: ["00000002"] }, { "supplier_cin" => 2 })

      expect(statuses(comparison)[:supplier_ico]).to eq(:match)
    end

    it "mismatches when no editorial contractor carries it" do
      expect(statuses(compare(contractor_icos: ["00000077"]))[:supplier_ico]).to eq(:mismatch)
    end

    it "does not count the object party as a contractor" do
      object_only = described_class.new(
        contract: FilingFakeContract.new(reference: "UKÁŽKA-2026/001", amount: BigDecimal("1043.68"),
                                         parties: [FilingFakeParty.new(role: "object", ico: "00000002")]),
        record: record
      )

      expect(statuses(object_only)[:supplier_ico]).to eq(:unverifiable)
    end

    it "is unverifiable without an editorial contractor IČO or without a CRZ supplier IČO" do
      aggregate_failures do
        expect(statuses(compare(contractor_icos: [nil]))[:supplier_ico]).to eq(:unverifiable)
        expect(statuses(compare(contractor_icos: []))[:supplier_ico]).to eq(:unverifiable)
        expect(statuses(compare({}, { "supplier_cin" => "bez ičo" }))[:supplier_ico]).to eq(:unverifiable)
      end
    end
  end

  describe "amount" do
    it "compares BigDecimal cents exactly" do
      aggregate_failures do
        expect(statuses(compare({ amount: BigDecimal("1043.68") }))[:amount]).to eq(:match)
        expect(statuses(compare({ amount: BigDecimal("1043.69") }))[:amount]).to eq(:mismatch)
        expect(statuses(compare({ amount: BigDecimal("1043.6") }, { "contract_price_amount" => "1043.60" }))[:amount])
          .to eq(:match)
      end
    end

    it "is unverifiable when either side has no amount, but a zero amount is a real value" do
      aggregate_failures do
        expect(statuses(compare({ amount: nil }))[:amount]).to eq(:unverifiable)
        expect(statuses(compare({}, { "contract_price_amount" => nil }))[:amount]).to eq(:unverifiable)
        expect(statuses(compare({ amount: BigDecimal("0") }, { "contract_price_amount" => "0.00" }))[:amount])
          .to eq(:match)
      end
    end
  end

  describe "reason requirement" do
    it "needs a reason for a mismatch and for an unverifiable row alike" do
      aggregate_failures do
        expect(compare({ reference: "ZP-2026-999" }).needs_reason?).to be(true)
        expect(compare({ amount: nil }).needs_reason?).to be(true)
        expect(compare({ amount: nil }).all_match?).to be(false)
      end
    end
  end

  describe ".withdrawn?" do
    it "flags only CRZ status 4 (cancelled) and 5 (withdrawn)" do
      aggregate_failures do
        expect(described_class.withdrawn?(record("status_id" => 4))).to be(true)
        expect(described_class.withdrawn?(record("status_id" => 5))).to be(true)
        expect(described_class.withdrawn?(record("status_id" => 2))).to be(false)
        expect(described_class.withdrawn?(record)).to be(false)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
