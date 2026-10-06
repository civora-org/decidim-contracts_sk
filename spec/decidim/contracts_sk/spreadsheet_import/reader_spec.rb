# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the spreadsheet import's hostile-input boundary
# (civora-org/civora-platform#129): encoding, delimiter, caps, headers and
# line numbers. Pure Ruby, offline, no database. Fictional data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# Each example pins one scenario with several related expectations by design.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

RSpec.describe Decidim::ContractsSk::SpreadsheetImport::Reader do
  def read(content, **options)
    described_class.call(content, **options)
  end

  def codes(result)
    result.problems.map(&:code)
  end

  let(:header) { "reference,title,amount" }

  describe "happy path" do
    it "reads rows with their cells keyed by the normalized header, stripped" do
      result = read("Reference , TITLE,amount\nDEMO-1, Cesta ,10.50\n")

      expect(result.rows).to eq([[2, { "reference" => "DEMO-1", "title" => "Cesta", "amount" => "10.50",
                                       "__extra" => 0 }]])
    end

    it "ignores unknown columns and names them (the export's published_at, source, url)" do
      result = read("#{header},published_at,source,url\nDEMO-1,Cesta,1,2026-01-01T00:00:00Z,editorial,https://x\n")

      expect(result.ignored_columns).to eq(%w[published_at source url])
      expect(result.rows.first.last.keys).not_to include("source")
    end

    it "reads the shipped sample file" do
      path = File.expand_path("../../../fixtures/files/spreadsheet_import/sample-contracts.csv", __dir__)

      expect(read(File.binread(path)).rows.size).to eq(3)
    end
  end

  describe "encoding" do
    it "reads UTF-8 with a byte-order mark and drops the mark" do
      result = read("\xEF\xBB\xBF#{header}\nDEMO-1,Údržba,1\n".b)

      expect(result.rows.first.last["reference"]).to eq("DEMO-1")
      expect(result.rows.first.last["title"]).to eq("Údržba")
    end

    it "reads UTF-8 without a mark" do
      expect(read("#{header}\nDEMO-1,Žilina,1\n").rows.first.last["title"]).to eq("Žilina")
    end

    it "reads Windows-1250 (the Slovak Excel default) when the bytes are not valid UTF-8" do
      bytes = "#{header}\nDEMO-1,Ľubovňa – údržba čistiarne,1\n".encode(Encoding::Windows_1250)
      result = read(bytes)

      expect(result.rows.first.last["title"]).to eq("Ľubovňa – údržba čistiarne")
    end

    it "refuses bytes that are neither UTF-8 nor defined in Windows-1250" do
      expect(codes(read("#{header}\nDEMO-1,a\x81b,1\n".b))).to eq([:encoding])
    end

    it "refuses a file with NUL bytes (xlsx, UTF-16 and other binaries)" do
      aggregate_failures do
        expect(codes(read("PK\x03\x04\x00\x00#{header}".b))).to eq([:not_text])
        expect(codes(read("#{header}\n".encode(Encoding::UTF_16LE)))).to eq([:not_text])
      end
    end
  end

  describe "delimiter" do
    it "detects the semicolon of the Excel profile" do
      result = read("reference;title;amount\nDEMO-1;Cesta;1250,50\n")

      expect(result.rows.first.last).to include("title" => "Cesta", "amount" => "1250,50")
    end
  end

  describe "caps and structure" do
    it "refuses a file over the byte cap before parsing it" do
      aggregate_failures do
        expect(codes(read("#{header}\n#{"a" * 20}", max_bytes: 10))).to eq([:too_large])
        expect(read("#{header}\nDEMO-1,a,1\n", max_bytes: 10).problems.first.detail).to eq(max: 0)
      end
    end

    it "accepts exactly the row cap and refuses one row more" do
      cap = Decidim::ContractsSk::SpreadsheetImport::MAX_ROWS
      body = ->(count) { (1..count).map { |i| "DEMO-#{i},Zmluva,1\n" }.join }

      aggregate_failures do
        expect(read("#{header}\n#{body.call(cap)}").rows.size).to eq(cap)
        expect(codes(read("#{header}\n#{body.call(cap + 1)}"))).to eq([:too_many_rows])
      end
    end

    it "aborts on a runaway quoted cell instead of buffering it" do
      huge = "\"#{"x" * (Decidim::ContractsSk::SpreadsheetImport::MAX_FIELD_SIZE + 1)}\""

      expect(codes(read("#{header}\nDEMO-1,#{huge},1\n"))).to eq([:malformed])
    end

    it "reports a malformed CSV with its line (unclosed quote)" do
      result = read("#{header}\nDEMO-1,\"Cesta,1\nDEMO-2,x,2\n")

      expect(result.problems.first).to have_attributes(code: :malformed, detail: { line: be_a(Integer) })
    end

    it "treats an empty file, whitespace and a header-only file as empty" do
      aggregate_failures do
        expect(codes(read(""))).to eq([:empty])
        expect(codes(read("  \n "))).to eq([:empty])
        expect(codes(read("#{header}\n"))).to eq([:empty])
        expect(codes(read("#{header}\n,,\n\n"))).to eq([:empty])
      end
    end

    it "refuses wrong headers: a required column missing" do
      result = read("nazov,suma\nCesta,1\n")

      expect(result.problems.first).to have_attributes(code: :missing_headers, detail: { columns: "reference, title" })
    end

    it "refuses a recognised column that appears twice" do
      expect(read("reference,title,title\nDEMO-1,a,b\n").problems.first)
        .to have_attributes(code: :duplicate_header, detail: { column: "title" })
    end

    it "counts cells beyond the header width instead of dropping them silently" do
      expect(read("#{header}\nDEMO-1,Cesta,1,surprise\n").rows.first.last["__extra"]).to eq(1)
    end
  end

  describe "line numbers" do
    it "reports the starting line of each row across blank lines and multi-line cells" do
      text = "#{header}\nDEMO-1,a,1\n\nDEMO-2,\"two\nlines\",2\nDEMO-3,c,3\n"

      expect(read(text).rows.map(&:first)).to eq([2, 4, 6])
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
