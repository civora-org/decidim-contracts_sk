# frozen_string_literal: true

# Offline specs for the open-data whitelist serializer (civora-org/civora-platform
# #119): plain structs, no database.

require "spec_helper"
require "csv"

# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::OpenData::ContractRecord do
  let(:party_struct) { Struct.new(:id, :role, :ico, :name, :address, keyword_init: true) }
  let(:contract_struct) do
    Struct.new(:id, :reference, :title, :subject_matter, :amount, :currency, :signed_on, :effective_from,
               :published_at, :source, :crz_url, :parties, :review_reason, keyword_init: true)
  end
  let(:parties) { [] }
  let(:overrides) { {} }
  let(:contract) do
    contract_struct.new(
      { id: 7, reference: "ZP-1", title: "Road", subject_matter: "Signs", amount: BigDecimal("1250.5"),
        currency: "EUR", signed_on: Date.new(2026, 9, 1), effective_from: nil,
        published_at: Time.new(2026, 9, 1, 14, 0, 0, "+02:00"), source: "editorial",
        crz_url: "https://crz.gov.sk/x", parties: parties, review_reason: "SECRET" }.merge(overrides)
    )
  end
  let(:record) { described_class.new(contract, url: "https://example.org/7") }

  describe "the whitelist" do
    it "pins the CSV columns in order" do
      expect(described_class::FIELDS).to eq(
        %w[reference title subject_matter amount currency signed_on effective_from published_at source
           crz_url party_roles party_icos party_names url]
      )
    end

    it "folds the party columns into one parties key for JSON, at the first party column's place" do
      expect(described_class::JSON_KEYS).to eq(
        %w[reference title subject_matter amount currency signed_on effective_from published_at source
           crz_url parties url]
      )
    end

    it "emits exactly FIELDS cells and JSON_KEYS keys, nothing from the record's other attributes" do
      aggregate_failures do
        expect(record.csv_row.size).to eq(described_class::FIELDS.size)
        expect(record.as_json_hash.keys).to eq(described_class::JSON_KEYS)
        expect(record.csv_row.join).not_to include("SECRET")
      end
    end
  end

  describe "docs/open-data.md" do
    let(:doc) { File.read(File.expand_path("../../../../docs/open-data.md", __dir__)) }
    let(:table_rows) { doc.lines.grep(/\A\| `/) }

    it "documents every CSV column and every JSON key in its field table, in the whitelist's order" do
      csv_cells = table_rows.map { |row| row.split("|")[1].scan(/`([a-z_]+)`/).flatten }.flatten
      json_cells = table_rows.map { |row| row.split("|")[2].scan(/`([a-z_]+)`/).flatten }.flatten

      aggregate_failures do
        expect(csv_cells).to eq(described_class::FIELDS)
        expect(json_cells).to eq(described_class::JSON_KEYS)
      end
    end
  end

  describe "values" do
    it "renders dates as ISO 8601 and published_at in UTC regardless of the offset" do
      row = record.as_json_hash

      expect(row.values_at("signed_on", "effective_from", "published_at"))
        .to eq(["2026-09-01", nil, "2026-09-01T12:00:00Z"])
    end

    it "formats the amount with two decimals, never scientific, with an optional decimal comma" do
      aggregate_failures do
        expect(record.csv_row[3]).to eq("1250.50")
        expect(record.csv_row(decimal_comma: true)[3]).to eq("1250,50")
        expect(described_class.decimal_string(BigDecimal("100000000"))).to eq("100000000.00")
        expect(described_class.decimal_string(BigDecimal("0.005"))).to eq("0.01")
        expect(record.as_json_hash["amount"]).to eq(1250.5)
      end
    end

    it "keeps a missing amount empty in CSV and null in JSON" do
      nil_record = described_class.new(contract_struct.new(contract.to_h.merge(amount: nil)), url: "u")

      expect([nil_record.csv_row[3], nil_record.as_json_hash["amount"]]).to eq([nil, nil])
    end
  end

  describe "parties" do
    let(:parties) do
      [party_struct.new(id: 3, role: "object", ico: "12345678", name: "Obec", address: "SECRET ADDRESS"),
       party_struct.new(id: 2, role: "contractor", ico: "87654321", name: "Dodávateľ"),
       party_struct.new(id: 4, role: "contractor", ico: "11111111", name: "Druhý"),
       party_struct.new(id: 5, role: "contractor", ico: nil, name: "Fyzická osoba"),
       party_struct.new(id: 6, role: "contractor", ico: "1234", name: "Bad Ico"),
       party_struct.new(id: 1, role: "contractor", ico: "123456789", name: "Too Long")]
    end

    it "keeps only well-formed IČO parties, ordered by role then id, and drops the rest entirely" do
      row = record.csv_row
      names = row[12]

      aggregate_failures do
        expect(row[10]).to eq("contractor | contractor | object")
        expect(row[11]).to eq("87654321 | 11111111 | 12345678")
        expect(names).to eq("Dodávateľ | Druhý | Obec")
        expect(names).not_to include("Fyzická")
        expect(record.csv_row.join).not_to include("SECRET ADDRESS")
      end
    end

    it "leaves the party cells nil (a truly empty CSV cell) when there is no party to list" do
      bare = described_class.new(contract_struct.new(contract.to_h.merge(parties: [])), url: "u")

      aggregate_failures do
        expect(bare.csv_row.values_at(10, 11, 12)).to eq([nil, nil, nil])
        expect(CSV.generate_line(bare.csv_row)).to include(",,,,")
      end
    end

    it "renders parties as role/ico/name objects for JSON, without addresses" do
      expect(record.as_json_hash["parties"].first)
        .to eq({ "role" => "contractor", "ico" => "87654321", "name" => "Dodávateľ" })
    end
  end

  describe "CSV formula injection" do
    %w[= + - @].each do |trigger|
      it "prefixes an apostrophe to a text cell starting with #{trigger.inspect}" do
        changed = contract_struct.new(contract.to_h.merge(title: "#{trigger}SUM(A1)"))
        row = described_class.new(changed, url: "u").csv_row

        expect(row[1]).to eq("'#{trigger}SUM(A1)")
      end
    end

    it "also neutralizes a leading tab or carriage return, and leaves ordinary text and JSON untouched" do
      changed = contract_struct.new(contract.to_h.merge(title: "\tx", reference: "\rx", subject_matter: "a=b"))
      tab = described_class.new(changed, url: "u")

      aggregate_failures do
        expect(tab.csv_row.values_at(0, 1, 2)).to eq(["'\rx", "'\tx", "a=b"])
        expect(tab.as_json_hash["title"]).to eq("\tx")
      end
    end

    it "neutralizes leading whitespace, NBSP, ideographic space, newline and fullwidth triggers" do
      [" =x", " =x", "　+x", "\n=x", "＝x", "＋x", "－x", "＠x", "  @x"].each do |text|
        row = described_class.new(contract_struct.new(contract.to_h.merge(title: text)), url: "u").csv_row

        expect(row[1]).to eq("'#{text}")
      end
    end

    it "does not prefix text that merely contains a trigger later on" do
      row = described_class.new(contract_struct.new(contract.to_h.merge(title: "a =b x-y")), url: "u").csv_row

      expect(row[1]).to eq("a =b x-y")
    end

    it "neutralizes the crz_url and party_names cells too" do
      hostile = party_struct.new(id: 9, role: "contractor", ico: "87654321", name: "=HYPERLINK(1)")
      changed = contract_struct.new(contract.to_h.merge(crz_url: "=cmd", parties: [hostile]))
      row = described_class.new(changed, url: "u").csv_row

      aggregate_failures do
        expect(row[9]).to eq("'=cmd")
        expect(row[12]).to eq("'=HYPERLINK(1)")
      end
    end

    it "does not touch the amount column (a numeric cell, never a text one)" do
      negative = described_class.new(contract_struct.new(contract.to_h.merge(amount: BigDecimal("-5"))), url: "u")

      expect(negative.csv_row[3]).to eq("-5.00")
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength
