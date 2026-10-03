# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the CRZ import Mapper (ADR-008,
# civora-org/civora-platform#86): the spike-verified payload → engine
# attribute correspondence, the tolerance contract (missing/blank/divergent
# → nil — capture, never crash) and the checksum determinism gate.
#
# Fixture payloads are synthetic throughout: fictional municipality
# ("Obec Ukážková"), fictional companies and obviously fake IČO patterns
# ("00 000 00x") — no real parties, no PII.
#
# Cop note: the payload fixture is a declarative field list (the demo-data
# precedent), so the method-length budget is disabled file-wide along with
# the dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, Metrics/MethodLength
RSpec.describe Decidim::ContractsSk::CrzImport::Mapper do
  # The observed live payload shape (spike, id 2142424) with synthetic
  # values. `changed_at` is part of the checksummed payload only.
  def crz_payload(overrides = {})
    {
      "id" => 2_142_424,
      "contract_identifier" => "UKÁŽKA-2026/001",
      "subject" => "Dodávka výpočtovej techniky pre obec Ukážková",
      "subject_description" => "Dodávka a inštalácia výpočtovej techniky vrátane servisu",
      "contract_price_amount" => "1043.68",
      "signed_on" => "2026-04-13",
      "effective_from" => "2026-05-01",
      "contracting_authority_name" => "Obec Ukážková",
      "contracting_authority_cin" => "00 000 001",
      "contracting_authority_formatted_address" => "Ukážková 1, 000 00 Ukážkovo",
      "supplier_name" => "Demo Dodávky s.r.o.",
      "supplier_cin" => "00 000 002",
      "supplier_formatted_address" => "Demo ulica 5, 000 00 Ukážkovo",
      "changed_at" => "2026-09-07T22:16:44Z"
    }.merge(overrides)
  end

  describe ".map (full payload)" do
    it "maps the verified correspondence onto the engine columns" do
      record = described_class.map(crz_payload)

      aggregate_failures do
        expect(record[:source_id]).to eq("2142424")
        expect(record[:attributes][:title]).to eq("Dodávka výpočtovej techniky pre obec Ukážková")
        expect(record[:attributes][:reference]).to eq("UKÁŽKA-2026/001")
        expect(record[:attributes][:subject_matter])
          .to eq("Dodávka a inštalácia výpočtovej techniky vrátane servisu")
        expect(record[:attributes][:amount]).to eq(BigDecimal("1043.68"))
        expect(record[:attributes][:signed_on]).to eq(Date.new(2026, 4, 13))
        expect(record[:attributes][:effective_from]).to eq(Date.new(2026, 5, 1))
        expect(record[:attributes][:crz_url]).to eq("https://crz.gov.sk/zmluva/2142424/")
      end
    end

    it "maps both parties with normalized CINs and the disambiguated roles" do
      record = described_class.map(crz_payload)

      expect(record[:parties]).to contain_exactly(
        { role: "object", name: "Obec Ukážková", ico: "00000001",
          address: "Ukážková 1, 000 00 Ukážkovo" },
        { role: "contractor", name: "Demo Dodávky s.r.o.", ico: "00000002",
          address: "Demo ulica 5, 000 00 Ukážkovo" }
      )
    end

    it "never mirrors a currency (ADR-008: manual/editorial field)" do
      record = described_class.map(crz_payload)

      expect(record[:attributes]).not_to have_key(:currency)
    end
  end

  describe ".map (fallbacks)" do
    it "falls back title to contract_identifier and reference to the reference field" do
      record = described_class.map(crz_payload(
                                     "subject" => "",
                                     "contract_identifier" => "UKÁŽKA-2026/009",
                                     "reference" => "ref-77"
                                   ))

      aggregate_failures do
        expect(record[:attributes][:title]).to eq("UKÁŽKA-2026/009")
        expect(record[:attributes][:reference]).to eq("UKÁŽKA-2026/009")

        fallback_ref = described_class.map(crz_payload("subject" => "Predmet",
                                                       "contract_identifier" => "",
                                                       "reference" => "ref-77"))
        expect(fallback_ref[:attributes][:reference]).to eq("ref-77")
      end
    end

    it "falls back subject_matter to subject when subject_description is missing" do
      record = described_class.map(crz_payload("subject_description" => nil))

      expect(record[:attributes][:subject_matter])
        .to eq("Dodávka výpočtovej techniky pre obec Ukážková")
    end
  end

  describe ".map (tolerance contract: missing/blank/divergent → nil)" do
    it "maps blank and missing optional fields to nil, not crashes" do
      record = described_class.map(crz_payload(
                                     "contract_price_amount" => "",
                                     "signed_on" => "",
                                     "effective_from" => nil,
                                     "contracting_authority_formatted_address" => "",
                                     "supplier_formatted_address" => nil
                                   ))

      aggregate_failures do
        expect(record[:attributes][:amount]).to be_nil
        expect(record[:attributes][:signed_on]).to be_nil
        expect(record[:attributes][:effective_from]).to be_nil
        expect(record[:parties].pluck(:address)).to all(be_nil)
      end
    end

    it "maps the 0000-00-00 sentinel and unparseable dates to nil" do
      record = described_class.map(crz_payload("signed_on" => "0000-00-00",
                                               "effective_from" => "nie je dátum"))

      aggregate_failures do
        expect(record[:attributes][:signed_on]).to be_nil
        expect(record[:attributes][:effective_from]).to be_nil
      end
    end

    it "maps invalid amounts to nil (bad text, negative, beyond the column ceiling)" do
      aggregate_failures do
        expect(described_class.map(crz_payload("contract_price_amount" => "abc"))[:attributes][:amount]).to be_nil
        expect(described_class.map(crz_payload("contract_price_amount" => "1.2.3"))[:attributes][:amount]).to be_nil
        expect(described_class.map(crz_payload("contract_price_amount" => "-5"))[:attributes][:amount]).to be_nil
        # decimal(12,2) ceiling on the contracts table is 9999999999.99.
        beyond_ceiling = described_class.map(crz_payload("contract_price_amount" => "10000000000"))

        expect(beyond_ceiling[:attributes][:amount]).to be_nil
      end
    end

    it "skips a party whose name is blank (never a blank-named row)" do
      record = described_class.map(crz_payload("supplier_name" => "  ",
                                               "supplier_cin" => "00 000 002"))

      aggregate_failures do
        expect(record[:parties].length).to eq(1)
        expect(record[:parties].first[:role]).to eq("object")
      end
    end

    it "restores the leading zeros of an Integer CIN, as ekosystem serves it (civora-org/civora-platform#145)" do
      record = described_class.map(crz_payload("contracting_authority_cin" => 323_560,
                                               "supplier_cin" => 31_942_547))

      aggregate_failures do
        expect(record[:parties].find { |p| p[:role] == "object" }[:ico]).to eq("00323560")
        expect(record[:parties].find { |p| p[:role] == "contractor" }[:ico]).to eq("31942547")
      end
    end

    it "maps an Integer CIN outside the 8-digit range to nil" do
      record = described_class.map(crz_payload("contracting_authority_cin" => 0,
                                               "supplier_cin" => 123_456_789))

      expect(record[:parties].map { |p| p[:ico] }).to eq([nil, nil])
    end

    it "maps a malformed CIN to nil and keeps a well-formed one normalized" do
      record = described_class.map(crz_payload("contracting_authority_cin" => "bez ičo",
                                               "supplier_cin" => "00 000 002 "))

      aggregate_failures do
        expect(record[:parties].find { |p| p[:role] == "object" }[:ico]).to be_nil
        expect(record[:parties].find { |p| p[:role] == "contractor" }[:ico]).to eq("00000002")
      end
    end

    it "clips overlong strings to the validated 255-character limit" do
      record = described_class.map(crz_payload("subject" => "Dlhé" * 200))

      # 255 = 63 full "Dlhé" repetitions + the first 3 chars of the 64th.
      expect(record[:attributes][:title]).to eq("#{"Dlhé" * 63}Dlh")
    end
  end

  describe ".map (filing-confirmation fields, civora-org/civora-platform#125)" do
    it "maps status_id and the published date beside — never inside — the written attributes" do
      record = described_class.map(crz_payload("status_id" => 2, "published_at" => "2026-04-20"))

      aggregate_failures do
        expect(record[:status_id]).to eq(2)
        expect(record[:published_on]).to eq(Date.new(2026, 4, 20))
        expect(record[:attributes].keys).not_to include(:status_id, :published_on, :published_at)
      end
    end

    it "maps a blank status, a non-numeric status and the 0000-00-00 sentinel to nil" do
      aggregate_failures do
        expect(described_class.map(crz_payload)[:status_id]).to be_nil
        expect(described_class.map(crz_payload("status_id" => "n/a"))[:status_id]).to be_nil
        expect(described_class.map(crz_payload("status_id" => "4"))[:status_id]).to eq(4)
        expect(described_class.map(crz_payload("published_at" => "0000-00-00"))[:published_on]).to be_nil
        expect(described_class.map(crz_payload("published_at" => ""))[:published_on]).to be_nil
      end
    end

    it "takes a published_at timestamp on the Slovak calendar day (near-midnight UTC)" do
      published = lambda do |value|
        described_class.map(crz_payload("published_at" => value))[:published_on]
      end

      aggregate_failures do
        expect(published.call("2026-04-20T22:30:00Z")).to eq(Date.new(2026, 4, 21)) # CEST = UTC+2
        expect(published.call("2026-01-20T23:30:00Z")).to eq(Date.new(2026, 1, 21)) # CET = UTC+1
        expect(published.call("2026-04-20T10:00:00Z")).to eq(Date.new(2026, 4, 20))
        expect(published.call("2026-04-20 00:30:00")).to eq(Date.new(2026, 4, 20)) # zone-less = local
        expect(published.call("not a date")).to be_nil
      end
    end

    it "leaves the checksum a digest of the raw payload only (unchanged by the new keys)" do
      payload = crz_payload("status_id" => 2, "published_at" => "2026-04-20")

      expect(described_class.map(payload)[:checksum]).to eq(described_class.checksum(payload))
    end
  end

  describe ".checksum (determinism gate)" do
    it "is stable across key order and consistent across identical payloads" do
      shuffled = crz_payload.to_a.shuffle.to_h

      expect(described_class.checksum(crz_payload)).to eq(described_class.checksum(shuffled))
      expect(described_class.map(crz_payload)[:checksum]).to eq(described_class.checksum(crz_payload))
    end

    it "diverges for changed payloads (changed_at included via the payload)" do
      bumped = crz_payload("changed_at" => "2026-09-08T10:00:00Z")
      amended = crz_payload("contract_price_amount" => "2043.68")

      aggregate_failures do
        expect(described_class.checksum(crz_payload)).not_to eq(described_class.checksum(bumped))
        expect(described_class.checksum(crz_payload)).not_to eq(described_class.checksum(amended))
      end
    end

    it "sorts nested hash keys canonically" do
      nested = crz_payload("department" => { "name" => "Oddelenie", "id" => 7 })
      reordered = crz_payload("department" => { "id" => 7, "name" => "Oddelenie" })

      expect(described_class.checksum(nested)).to eq(described_class.checksum(reordered))
    end
  end

  describe ".map (structural quarantine)" do
    it "raises Mapper::Error for a missing or blank id" do
      aggregate_failures do
        expect { described_class.map(crz_payload("id" => nil)) }
          .to raise_error(Decidim::ContractsSk::CrzImport::Mapper::Error)
        expect { described_class.map(crz_payload("id" => "   ")) }
          .to raise_error(Decidim::ContractsSk::CrzImport::Mapper::Error)
      end
    end

    it "raises Mapper::Error when the payload is not a JSON object" do
      aggregate_failures do
        expect { described_class.map(%w[not an object]) }
          .to raise_error(Decidim::ContractsSk::CrzImport::Mapper::Error)
        expect { described_class.map("a string") }
          .to raise_error(Decidim::ContractsSk::CrzImport::Mapper::Error)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, Metrics/MethodLength
