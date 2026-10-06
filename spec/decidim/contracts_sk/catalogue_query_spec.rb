# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the public catalogue's filter/sort object (civora-org/civora-
# platform#116). Two groups: the offline one pins the param normalization
# (no scope, no connection); the :db one (CONTRACTS_SK_DB=1) runs real SQL on
# the in-memory SQLite adapter. Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CatalogueQuery do
  def filters_for(params)
    described_class.new(scope: nil, params: params).filters
  end

  describe "PARAM_KEYS" do
    it "lists exactly the catalogue's request params" do
      expect(described_class::PARAM_KEYS).to eq(
        %i[q amount_min amount_max published_from published_to signed_from signed_to party source sort]
      )
    end
  end

  describe "defaults" do
    it "has no filters and the default sort for empty params" do
      query = described_class.new(scope: nil, params: {})

      expect(query).not_to be_active
      expect(query.active_filter_keys).to eq([])
      expect(query.filters.sort).to eq("published_desc")
      expect(query.to_params).to eq({})
      expect(query.filters).to be_frozen
    end

    it "treats blank strings as absent" do
      query = described_class.new(scope: nil, params: described_class::PARAM_KEYS.index_with { "  " })

      expect(query).not_to be_active
    end

    it "ignores arrays, hashes and non-string values" do
      query = described_class.new(scope: nil, params: {
                                    "q" => ["road"], "amount_min" => { "a" => "1" }, "party" => ["x"],
                                    "source" => ["crz"], "sort" => ["amount_asc"], "signed_from" => 5
                                  })

      expect(query).not_to be_active
      expect(query.filters.sort).to eq("published_desc")
    end

    it "ignores keys outside PARAM_KEYS" do
      expect(described_class.new(scope: nil, params: { "page" => "2", "evil" => "x" }).to_params).to eq({})
    end

    it "accepts symbol keys and ActionController::Parameters" do
      expect(filters_for(q: "road").q).to eq("road")
      expect(filters_for(ActionController::Parameters.new(q: "road")).q).to eq("road")
    end
  end

  describe "q" do
    it "is stripped" do
      expect(filters_for("q" => "  road  ").q).to eq("road")
    end

    it "replaces control characters, NUL included (PostgreSQL raises on a NUL bind)" do
      expect(filters_for("q" => "ro\u0000ad").q).to eq("ro ad")
      expect(filters_for("q" => "\u0000").q).to be_nil
      expect(filters_for("q" => "a\tb\n").q).to eq("a b")
    end

    it "is capped at the shared 255 characters" do
      expect(filters_for("q" => "a" * 400).q.length).to eq(255)
      expect(described_class::Normalizer::TEXT_MAX_LENGTH).to eq(255)
    end
  end

  describe "amounts" do
    {
      "10000" => "10000", "10000.5" => "10000.5", "10000,50" => "10000.5", "10 000,50" => "10000.5",
      "10 000,5" => "10000.5", "10 000" => "10000", "0" => "0", "9999999999.99" => "9999999999.99",
      " 12.30 " => "12.3"
    }.each do |input, expected|
      it "accepts #{input.inspect} as #{expected}" do
        expect(filters_for("amount_min" => input).amount_min).to eq(BigDecimal(expected))
      end
    end

    ["10.000", "1.234,56", "-5", "+5", "abc", "1e3", "10.", ".5", "1,2,3", "9999999999.995",
     "10000000000", "1" * 40, "5 EUR", "０"].each do |input|
      it "rejects #{input.inspect}" do
        expect(filters_for("amount_min" => input).amount_min).to be_nil
        expect(filters_for("amount_max" => input).amount_max).to be_nil
      end
    end

    it "rejects an over-long digit string before ever building a BigDecimal" do
      normalizer = described_class::Normalizer.new("amount_min" => "9" * 100_000)
      allow(normalizer).to receive(:BigDecimal).and_call_original

      expect(normalizer.filters.amount_min).to be_nil
      expect(normalizer).not_to have_received(:BigDecimal)
    end

    it "swaps a reversed range" do
      filters = filters_for("amount_min" => "500", "amount_max" => "100")

      expect([filters.amount_min, filters.amount_max]).to eq([BigDecimal(100), BigDecimal(500)])
    end

    it "keeps open-ended ranges" do
      filters = filters_for("amount_max" => "100")

      expect([filters.amount_min, filters.amount_max]).to eq([nil, BigDecimal(100)])
    end

    it "drops an invalid bound and keeps the valid one" do
      filters = filters_for("amount_min" => "nope", "amount_max" => "100")

      expect([filters.amount_min, filters.amount_max]).to eq([nil, BigDecimal(100)])
    end
  end

  describe "dates" do
    %w[published_from signed_from].each do |key|
      {
        "2026-09-01" => Date.new(2026, 9, 1), "1.9.2026" => Date.new(2026, 9, 1),
        "01.09.2026" => Date.new(2026, 9, 1), "1. 9. 2026" => Date.new(2026, 9, 1),
        " 2026-09-01 " => Date.new(2026, 9, 1), "29.2.2024" => Date.new(2024, 2, 29)
      }.each do |input, expected|
        it "#{key} accepts #{input.inspect}" do
          expect(filters_for(key => input).public_send(key)).to eq(expected)
        end
      end

      ["2026-13-01", "2026-02-30", "29.2.2025", "2026-9-1", "26-09-01", "1899-12-31", "2101-01-01",
       "1.1.1899", "tomorrow", "2026/09/01", "09/01/2026", "2026-09-01T10:00", "1.9.26", "０１.９.２０２６"].each do |input|
        it "#{key} rejects #{input.inspect}" do
          expect(filters_for(key => input).public_send(key)).to be_nil
        end
      end
    end

    it "swaps reversed published and signed ranges" do
      filters = filters_for("published_from" => "2026-09-10", "published_to" => "2026-09-01",
                            "signed_from" => "5.5.2026", "signed_to" => "1.1.2026")

      expect([filters.published_from, filters.published_to]).to eq([Date.new(2026, 9, 1), Date.new(2026, 9, 10)])
      expect([filters.signed_from, filters.signed_to]).to eq([Date.new(2026, 1, 1), Date.new(2026, 5, 5)])
    end
  end

  describe "party" do
    it "treats exactly 8 digits as an IČO, with spaces removed" do
      expect(filters_for("party" => "00123456").party).to eq(described_class::PartyFilter.new(:ico, "00123456"))
      expect(filters_for("party" => "0012 3456").party).to eq(described_class::PartyFilter.new(:ico, "00123456"))
    end

    it "treats anything else as a name, squished" do
      expect(filters_for("party" => "  Obec   Ukážková ").party)
        .to eq(described_class::PartyFilter.new(:name, "Obec Ukážková"))
      expect(filters_for("party" => "1234567").party.kind).to eq(:name)
      expect(filters_for("party" => "123456789").party.kind).to eq(:name)
    end

    it "replaces control characters, NUL included" do
      expect(filters_for("party" => "Ob\u0000ec").party.value).to eq("Ob ec")
      expect(filters_for("party" => "\u0000\u0001").party).to be_nil
      expect(filters_for("party" => "0012\u00003456").party.value).to eq("00123456")
    end

    it "caps the name at 255 characters" do
      expect(filters_for("party" => "a" * 400).party.value.length).to eq(255)
    end
  end

  describe "source and sort" do
    it "accepts the two sources, case-insensitively" do
      expect(filters_for("source" => "crz").source).to eq("crz")
      expect(filters_for("source" => " Editorial ").source).to eq("editorial")
      expect(filters_for("source" => "other").source).to be_nil
    end

    it "whitelists sort and falls back to the default" do
      %w[published_desc published_asc amount_desc amount_asc].each do |sort|
        expect(filters_for("sort" => sort).sort).to eq(sort)
      end
      expect(filters_for("sort" => "amount; DROP TABLE").sort).to eq("published_desc")
    end
  end

  describe "#to_params" do
    it "emits normalized strings and round-trips" do
      query = described_class.new(scope: nil, params: {
                                    "q" => " road ", "amount_min" => "10 000,50", "amount_max" => "5",
                                    "published_from" => "1.9.2026", "signed_to" => "2026-09-30",
                                    "party" => "0012 3456", "source" => "CRZ", "sort" => "amount_asc"
                                  })

      expect(query.to_params).to eq(
        "q" => "road", "amount_min" => "5", "amount_max" => "10000.5", "published_from" => "2026-09-01",
        "signed_to" => "2026-09-30", "party" => "00123456", "source" => "crz", "sort" => "amount_asc"
      )
      expect(described_class.new(scope: nil, params: query.to_params).filters).to eq(query.filters)
    end

    it "omits the default sort" do
      expect(described_class.new(scope: nil, params: { "sort" => "published_desc", "q" => "a" }).to_params)
        .to eq("q" => "a")
    end
  end

  describe "#active?" do
    it "is true for any filter and false for sort alone" do
      expect(described_class.new(scope: nil, params: { "source" => "crz" })).to be_active
      sorted = described_class.new(scope: nil, params: { "sort" => "amount_asc" })
      expect(sorted).not_to be_active
      expect(sorted).to be_non_default_sort
    end
  end

  describe "#with" do
    it "raises on keys outside PARAM_KEYS (a typo must not widen the result)" do
      base = described_class.new(scope: nil, params: {})

      expect { base.with(ico: "36396567") }.to raise_error(ArgumentError, /unknown catalogue param.*ico/)
    end

    it "raises when a non-nil override does not normalize" do
      base = described_class.new(scope: nil, params: {})

      expect { base.with(party: "   ") }.to raise_error(ArgumentError, /party/)
      expect { base.with(amount_min: "10.000") }.to raise_error(ArgumentError, /amount_min/)
      expect { base.with(signed_from: "2026-02-30") }.to raise_error(ArgumentError, /signed_from/)
      expect { base.with(source: "other") }.to raise_error(ArgumentError, /source/)
      expect { base.with(sort: "bogus") }.to raise_error(ArgumentError, /sort/)
    end

    it "accepts valid overrides, including a valid sort" do
      expect(described_class.new(scope: nil, params: {}).with(sort: "amount_asc", source: "crz").to_params)
        .to eq("source" => "crz", "sort" => "amount_asc")
    end

    it "returns a new query with overrides applied and nil removing a key" do
      base = described_class.new(scope: nil, params: { "q" => "road", "source" => "crz" })
      derived = base.with(party: "36396567", source: nil, amount_min: BigDecimal("12.5"),
                          signed_from: Date.new(2026, 1, 2))

      expect(derived.to_params).to eq("q" => "road", "party" => "36396567", "amount_min" => "12.5",
                                      "signed_from" => "2026-01-02")
      expect(base.to_params).to eq("q" => "road", "source" => "crz")
    end
  end

  describe "database behaviour", :db do
    before { migrate_engine_schema! }

    let(:zone) { ActiveSupport::TimeZone["Europe/Bratislava"] }

    def create_contract!(reference, overrides = {})
      Decidim::ContractsSk::Contract.create!(
        contract_attributes({ reference: reference, title: "Contract #{reference}", state: "published",
                              published_at: Time.utc(2026, 9, 1, 12), currency: "EUR" }.merge(overrides))
      )
    end

    def add_party!(contract, name, ico = nil, role = "contractor")
      Decidim::ContractsSk::Party.create!(contract: contract, role: role, name: name, ico: ico)
    end

    def query(params = {}, scope: Decidim::ContractsSk::Contract.where(organization: organization).published)
      described_class.new(scope: scope, params: params, time_zone: zone)
    end

    def refs(params = {}, **)
      query(params, **).results.pluck(:reference)
    end

    def refs_unordered(params)
      query(params).relation.pluck(:reference).sort
    end

    describe "scoping" do
      it "keeps the caller's published-only and organization scope under every filter" do
        create_contract!("PUB")
        create_contract!("DRAFT", state: "draft", published_at: nil)
        create_contract!("FOREIGN", organization: Decidim::Organization.create!)

        expect(refs_unordered({ "q" => "contract" })).to eq(["PUB"])
        expect(refs_unordered({ "source" => "editorial", "sort" => "amount_asc" })).to eq(["PUB"])
        expect(refs_unordered({ "party" => "x" })).to eq([])
      end
    end

    describe "amount" do
      before do
        create_contract!("A100", amount: 100)
        create_contract!("A200", amount: BigDecimal("200.50"))
        create_contract!("A300", amount: 300)
        create_contract!("NONE", amount: nil)
      end

      it "bounds are inclusive" do
        expect(refs_unordered({ "amount_min" => "100", "amount_max" => "200,50" })).to eq(%w[A100 A200])
      end

      it "supports open-ended bounds" do
        expect(refs_unordered({ "amount_min" => "200.5" })).to eq(%w[A200 A300])
        expect(refs_unordered({ "amount_max" => "100" })).to eq(%w[A100])
      end

      it "excludes records without an amount only while an amount filter is active" do
        expect(refs_unordered({ "amount_min" => "0" })).not_to include("NONE")
        expect(refs_unordered({ "amount_max" => "9999999999" })).not_to include("NONE")
        expect(refs_unordered({})).to include("NONE")
        expect(refs_unordered({ "amount_min" => "garbage" })).to include("NONE")
      end

      it "treats a reversed range like the swapped one" do
        expect(refs_unordered({ "amount_min" => "300", "amount_max" => "100" })).to eq(%w[A100 A200 A300])
      end
    end

    describe "publication date (calendar days in the time zone)" do
      before do
        # Bratislava is UTC+2 in September: local midnight = 22:00 UTC the day before.
        create_contract!("BEFORE", published_at: Time.utc(2026, 8, 31, 21, 59, 59))
        create_contract!("FIRST-EDGE", published_at: Time.utc(2026, 8, 31, 22, 0, 0))
        create_contract!("LAST-EDGE", published_at: Time.utc(2026, 9, 1, 21, 59, 59))
        create_contract!("AFTER", published_at: Time.utc(2026, 9, 1, 22, 0, 0))
      end

      it "includes the whole from and to days, local time" do
        expect(refs_unordered({ "published_from" => "2026-09-01", "published_to" => "2026-09-01" }))
          .to eq(%w[FIRST-EDGE LAST-EDGE])
      end

      it "supports open-ended and Slovak-format bounds" do
        expect(refs_unordered({ "published_from" => "2.9.2026" })).to eq(%w[AFTER])
        expect(refs_unordered({ "published_to" => "31.8.2026" })).to eq(%w[BEFORE])
      end

      it "swaps a reversed range" do
        expect(refs_unordered({ "published_from" => "2026-09-01", "published_to" => "2026-08-31" }))
          .to eq(%w[BEFORE FIRST-EDGE LAST-EDGE])
      end

      it "honours the time zone it is given" do
        utc = described_class.new(scope: Decidim::ContractsSk::Contract.published, time_zone: "UTC",
                                  params: { "published_from" => "2026-09-01", "published_to" => "2026-09-01" })

        expect(utc.relation.pluck(:reference).sort).to eq(%w[AFTER LAST-EDGE])
      end
    end

    # civora-org/civora-platform#159: the publication date is the real CRZ
    # date (crz_published_on) when the record carries one — a mirror or a
    # filed editorial record — else published_at. Each column is compared
    # with its own type, so the two branches never mix.
    describe "publication date with a CRZ date (#159)" do
      before do
        # A mirror entered the catalogue in September but was published in
        # CRZ in March: its CRZ date decides, in either direction.
        create_contract!("MIRROR-MARCH", source: "crz", source_id: "9001", crz_published_on: Date.new(2026, 3, 10),
                                         published_at: Time.utc(2026, 9, 1, 12))
        # A filed editorial record carries a CRZ date too (any source).
        create_contract!("FILED-EDITORIAL", crz_published_on: Date.new(2026, 5, 5), crz_filed_at: Time.utc(2026, 5, 6),
                                            published_at: Time.utc(2026, 9, 2, 12))
        # No CRZ date: published_at decides.
        create_contract!("PLAIN-JUNE", published_at: Time.utc(2026, 6, 15, 12))
        # CRZ date inside, entry instant outside, and the reverse.
        create_contract!("CRZ-IN-ENTRY-OUT", source: "crz", source_id: "9002", crz_published_on: Date.new(2026, 7, 1),
                                             published_at: Time.utc(2025, 1, 1, 12))
        create_contract!("CRZ-OUT-ENTRY-IN", source: "crz", source_id: "9003", crz_published_on: Date.new(2020, 1, 1),
                                             published_at: Time.utc(2026, 7, 1, 12))
      end

      it "filters by the CRZ date when present and by published_at otherwise" do
        expect(refs_unordered({ "published_from" => "2026-03-01", "published_to" => "2026-03-31" }))
          .to eq(%w[MIRROR-MARCH])
        expect(refs_unordered({ "published_from" => "2026-05-01", "published_to" => "2026-06-30" }))
          .to eq(%w[FILED-EDITORIAL PLAIN-JUNE])
      end

      it "judges a record by its CRZ date alone, never by both columns" do
        july = { "published_from" => "2026-07-01", "published_to" => "2026-07-31" }

        expect(refs_unordered(july)).to eq(%w[CRZ-IN-ENTRY-OUT])
        # MIRROR-MARCH entered the catalogue in September, yet September misses it.
        expect(refs_unordered({ "published_from" => "2026-09-01", "published_to" => "2026-09-30" })).to eq([])
      end

      it "includes the CRZ date on both bounds (inclusive calendar days)" do
        expect(refs_unordered({ "published_from" => "2026-03-10", "published_to" => "2026-03-10" }))
          .to eq(%w[MIRROR-MARCH])
        expect(refs_unordered({ "published_from" => "2026-03-11", "published_to" => "2026-03-11" })).to eq([])
        expect(refs_unordered({ "published_from" => "2026-03-09", "published_to" => "2026-03-09" })).to eq([])
      end

      it "supports open-ended ranges over both columns" do
        # FILED-EDITORIAL entered in September but its CRZ date (May) is before June.
        expect(refs_unordered({ "published_from" => "2026-06-01" })).to eq(%w[CRZ-IN-ENTRY-OUT PLAIN-JUNE])
        expect(refs_unordered({ "published_to" => "2026-03-31" })).to eq(%w[CRZ-OUT-ENTRY-IN MIRROR-MARCH])
      end

      it "orders by the shared date in both directions, id as the tie-break" do
        create_contract!("TIE", source: "crz", source_id: "9004", crz_published_on: Date.new(2026, 5, 5),
                                published_at: Time.utc(2030, 1, 1))

        # 2020-01-01, 2026-03-10, 2026-05-05 (x2: FILED-EDITORIAL < TIE by id), 2026-06-15, 2026-07-01
        expected = %w[CRZ-OUT-ENTRY-IN MIRROR-MARCH FILED-EDITORIAL TIE PLAIN-JUNE CRZ-IN-ENTRY-OUT]
        expect(refs({ "sort" => "published_asc" })).to eq(expected)
        expect(refs({ "sort" => "published_desc" }))
          .to eq(%w[CRZ-IN-ENTRY-OUT PLAIN-JUNE TIE FILED-EDITORIAL MIRROR-MARCH CRZ-OUT-ENTRY-IN])
      end

      it "sorts on COALESCE(crz_published_on, published_at) with NULLS LAST, without a CAST" do
        sql = query({ "sort" => "published_desc" }).results.to_sql

        expect(sql).to include("COALESCE(").and include("NULLS LAST")
        expect(sql).not_to include("CAST(")
      end

      it "keeps records with neither date after the dated ones in both directions" do
        create_contract!("UNDATED", published_at: nil, state: "published")

        expect(refs({ "sort" => "published_asc" }).last).to eq("UNDATED")
        expect(refs({ "sort" => "published_desc" }).last).to eq("UNDATED")
      end
    end

    describe "signing date" do
      before do
        create_contract!("S1", signed_on: Date.new(2026, 5, 1))
        create_contract!("S2", signed_on: Date.new(2026, 5, 10))
        create_contract!("S3", signed_on: Date.new(2026, 5, 20))
        create_contract!("SNIL", signed_on: nil)
      end

      it "is inclusive on both ends and excludes unknown dates while active" do
        expect(refs_unordered({ "signed_from" => "2026-05-01", "signed_to" => "20.5.2026" })).to eq(%w[S1 S2 S3])
        expect(refs_unordered({ "signed_from" => "2026-05-02", "signed_to" => "2026-05-19" })).to eq(%w[S2])
        expect(refs_unordered({ "signed_from" => "2000-01-01" })).not_to include("SNIL")
      end

      it "swaps a reversed range" do
        expect(refs_unordered({ "signed_from" => "2026-05-10", "signed_to" => "2026-05-01" })).to eq(%w[S1 S2])
      end
    end

    describe "party" do
      before do
        obec = create_contract!("OBEC")
        add_party!(obec, "Obec Ukážková", "00123456", "object")
        add_party!(obec, "Stavby 100% s.r.o.", "36396567")
        other = create_contract!("OTHER")
        add_party!(other, "Dodávateľ_X", "12345678")
        add_party!(other, "Iná obec", nil, "object")
        create_contract!("NOPARTY")
      end

      it "matches an exact IČO, leading zero included, in any role" do
        expect(refs_unordered({ "party" => "00123456" })).to eq(%w[OBEC])
        expect(refs_unordered({ "party" => "0012 3456" })).to eq(%w[OBEC])
        expect(refs_unordered({ "party" => "36396567" })).to eq(%w[OBEC])
      end

      it "does not match an IČO by partial digits or by dropping the leading zero" do
        expect(refs_unordered({ "party" => "123456" })).to eq([])
        expect(refs_unordered({ "party" => "0123456" })).to eq([])
      end

      it "matches names by case-insensitive substring" do
        expect(refs_unordered({ "party" => "obec" })).to eq(%w[OBEC OTHER])
        expect(refs_unordered({ "party" => "OBEC UK" })).to eq(%w[OBEC])
      end

      it "matches an upper-case term against a lower-case name" do
        expect(refs_unordered({ "party" => "STAVBY" })).to eq(%w[OBEC])
      end

      it "treats % and _ literally" do
        expect(refs_unordered({ "party" => "100%" })).to eq(%w[OBEC])
        expect(refs_unordered({ "party" => "%" })).to eq(%w[OBEC])
        expect(refs_unordered({ "party" => "X_" })).to eq([])
        expect(refs_unordered({ "party" => "Dodávateľ_" })).to eq(%w[OTHER])
        expect(refs_unordered({ "party" => "_" })).to eq(%w[OTHER])
      end

      it "treats a backslash literally in party names" do
        add_party!(create_contract!("BSP"), "Firma A\\B")

        expect(refs_unordered({ "party" => "a\\b" })).to eq(%w[BSP])
        expect(refs_unordered({ "party" => "\\%" })).to eq([])
      end

      it "down-cases the party term in Ruby (upper-case diacritic term, lower-case name)" do
        add_party!(create_contract!("DIA"), "dodávateľ štúr")

        expect(refs_unordered({ "party" => "ŠTÚR" })).to eq(%w[DIA])
      end

      it "returns each contract once even when several parties match (no DISTINCT needed)" do
        expect(query({ "party" => "obec" }).relation.pluck(:id).size).to eq(2)
        expect(query({ "party" => "s" }).relation.pluck(:id).tally.values.max).to eq(1)
      end
    end

    describe "source" do
      before do
        create_contract!("EDIT")
        create_contract!("CRZ", source: "crz", source_id: "1")
      end

      it "splits editorial from CRZ mirrors" do
        expect(refs_unordered({ "source" => "crz" })).to eq(%w[CRZ])
        expect(refs_unordered({ "source" => "editorial" })).to eq(%w[EDIT])
        expect(refs_unordered({ "source" => "bogus" })).to eq(%w[CRZ EDIT])
      end
    end

    describe "q" do
      before do
        create_contract!("ZP-ROAD-1", title: "Road repair 100% done")
        create_contract!("ZP-OTHER-2", title: "Bridge_over")
      end

      it "matches title and reference case-insensitively, with upper-case terms" do
        expect(refs_unordered({ "q" => "ROAD" })).to eq(%w[ZP-ROAD-1])
        expect(refs_unordered({ "q" => "zp-other" })).to eq(%w[ZP-OTHER-2])
      end

      it "treats % and _ literally" do
        expect(refs_unordered({ "q" => "100%" })).to eq(%w[ZP-ROAD-1])
        expect(refs_unordered({ "q" => "%" })).to eq(%w[ZP-ROAD-1])
        expect(refs_unordered({ "q" => "e_o" })).to eq(%w[ZP-OTHER-2])
        expect(refs_unordered({ "q" => "r_a" })).to eq([])
      end

      it "treats a backslash literally" do
        create_contract!("ZP-BS-1", title: "Path C:\\temp")
        create_contract!("ZP-BS-2", title: "Fifty % off")

        expect(refs_unordered({ "q" => "c:\\temp" })).to eq(%w[ZP-BS-1])
        expect(refs_unordered({ "q" => "\\%" })).to eq([])
        expect(refs_unordered({ "q" => "\\" })).to eq(%w[ZP-BS-1])
      end

      it "down-cases the term in Ruby, so an upper-case diacritic term matches a lower-case value" do
        create_contract!("ZP-DIA-1", title: "Oprava štúrovej ulice")

        expect(refs_unordered({ "q" => "ŠTÚR" })).to eq(%w[ZP-DIA-1])
      end

      it "combines with the other filters" do
        create_contract!("ZP-ROAD-3", title: "Road two", amount: 50, source: "crz", source_id: "9")

        expect(refs_unordered({ "q" => "road", "source" => "crz", "amount_max" => "60" })).to eq(%w[ZP-ROAD-3])
        expect(refs_unordered({ "q" => "road", "source" => "editorial", "amount_max" => "60" })).to eq([])
      end
    end

    describe "sorting" do
      before do
        create_contract!("P1", published_at: Time.utc(2026, 1, 1), amount: 300)
        create_contract!("P2", published_at: Time.utc(2026, 2, 1), amount: nil)
        create_contract!("P3", published_at: Time.utc(2026, 3, 1), amount: 100)
        create_contract!("P4", published_at: Time.utc(2026, 4, 1), amount: 300)
      end

      it "defaults to newest publication first" do
        expect(refs).to eq(%w[P4 P3 P2 P1])
      end

      it "sorts oldest first" do
        expect(refs({ "sort" => "published_asc" })).to eq(%w[P1 P2 P3 P4])
      end

      it "sorts amounts descending with NULLs last and the id as a same-direction tiebreak" do
        expect(refs({ "sort" => "amount_desc" })).to eq(%w[P4 P1 P3 P2])
      end

      it "sorts amounts ascending with NULLs last and the id as a same-direction tiebreak" do
        expect(refs({ "sort" => "amount_asc" })).to eq(%w[P3 P1 P4 P2])
      end

      it "breaks equal publication timestamps by id in the sort direction" do
        stamp = Time.utc(2026, 6, 1)
        first = create_contract!("T1", published_at: stamp)
        second = create_contract!("T2", published_at: stamp)

        expect(refs({ "published_from" => "2026-06-01" }).first(2)).to eq(%w[T2 T1])
        expect(refs({ "published_from" => "2026-06-01", "sort" => "published_asc" }).first(2)).to eq(%w[T1 T2])
        expect(first.id).to be < second.id
      end

      it "always ends the ORDER BY with the id, in the sort's own direction" do
        { "published_desc" => "DESC", "published_asc" => "ASC", "amount_desc" => "DESC", "amount_asc" => "ASC" }
          .each do |sort, direction|
          order_by = query({ "sort" => sort }).results.to_sql[/ORDER BY.*\z/]
          expect(order_by).to match(/"id" #{direction}\z/), "#{sort}: #{order_by}"
        end
      end

      it "emits NULLS LAST SQL for both amount sorts" do
        %w[amount_desc amount_asc].each do |sort|
          expect(query({ "sort" => sort }).results.to_sql).to include("NULLS LAST")
        end
      end

      it "replaces an order carried by a pre-ordered scope (reorder, not order)" do
        ordered = Decidim::ContractsSk::Contract.where(organization: organization).published.order(reference: :desc)

        expect(query({ "sort" => "published_asc" }, scope: ordered).results.pluck(:reference))
          .to eq(%w[P1 P2 P3 P4])
        expect(query({ "sort" => "published_asc" }, scope: ordered).results.to_sql).not_to include("reference")
      end

      it "leaves #relation unordered" do
        expect(query({ "sort" => "amount_asc" }).relation.to_sql).not_to include("ORDER BY")
      end
    end

    describe "#with" do
      it "applies overrides on the same scope" do
        solo = create_contract!("ONE")
        add_party!(solo, "Dodávateľ", "36396567")
        create_contract!("TWO")

        base = query({ "q" => "contract" })

        expect(base.relation.count).to eq(2)
        expect(base.with(party: "36396567").relation.pluck(:reference)).to eq(%w[ONE])
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
