# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations

# civora-org/civora-platform#211: parsing of the values typed into a contract
# template form. Pure, offline.
RSpec.describe Decidim::ContractsSk::Templates::FieldValues do
  def parse(type, raw) = described_class.parse(type, raw)

  def value(type, raw) = parse(type, raw).value

  def error(type, raw) = parse(type, raw).error

  describe "dates" do
    it "reads the Slovak and the ISO shapes into one canonical form" do
      ["1. 1. 2026", "1.1.2026", "01.01.2026", " 1 . 1 . 2026 ", "1. 1. 2026.", "2026-01-01"].each do |raw|
        expect(value("date", raw)).to eq("2026-01-01"), raw
      end
      expect(value("date", "31. 12. 2026")).to eq("2026-12-31")
    end

    it "refuses impossible, ambiguous and out-of-range dates" do
      ["31. 2. 2026", "1. 13. 2026", "32. 1. 2026", "1/1/2026", "abc", "2026-1-1", "1. 1. 26"].each do |raw|
        expect(error("date", raw)).to eq(:invalid), raw
      end
      expect(error("date", "1. 1. 1800")).to eq(:out_of_range)
      expect(error("date", "1. 1. 2200")).to eq(:out_of_range)
    end

    it "shows a date the way Slovak documents write it" do
      expect(described_class.display("date", "2026-01-05")).to eq("5. 1. 2026")
    end
  end

  describe "money" do
    it "reads decimal commas, spaces, dots and plain numbers to two decimals" do
      { "3 062,50" => "3062.50", "3 062,50" => "3062.50", "3062.5" => "3062.50", "3062" => "3062.00",
        "3.062,50" => "3062.50", "3,062.50" => "3062.50", "0,5" => "0.50", "12 000 000,99" => "12000000.99",
        "  100  " => "100.00" }.each do |raw, canonical|
        expect(value("money", raw)).to eq(canonical), raw
      end
    end

    it "refuses what could be read two ways or is not an amount" do
      ["3.062", "3,062", "1,234,56", "3,062.505", "1,005", "-5", "abc", "1e5", "12 EUR", "3,"].each do |raw|
        expect(error("money", raw)).to eq(:invalid), raw
      end
    end

    it "caps the amount at the contract column" do
      expect(value("money", "9 999 999 999,99")).to eq("9999999999.99")
      expect(error("money", "10 000 000 000")).to eq(:out_of_range)
    end

    it "shows grouped thousands with a decimal comma and a non-breaking space" do
      expect(described_class.display("money", "3062.50")).to eq("3 062,50")
      expect(described_class.display("money", "12000000.99")).to eq("12 000 000,99")
      expect(described_class.display("money", "7.00")).to eq("7,00")
    end
  end

  describe "numbers" do
    it "reads signed and decimal numbers" do
      { "12,5" => "12.5", "12" => "12", "-3,25" => "-3.25", "1 500" => "1500", "0,0" => "0", "-0" => "0" }
        .each { |raw, canonical| expect(value("number", raw)).to eq(canonical), raw }
    end

    it "refuses garbage and absurd sizes" do
      expect(error("number", "12,5,1")).to eq(:invalid)
      expect(error("number", "x")).to eq(:invalid)
      expect(error("number", "1" * 16)).to eq(:out_of_range)
    end

    it "shows a decimal comma" do
      expect(described_class.display("number", "12.5")).to eq("12,5")
      expect(described_class.display("number", "-1500")).to eq("-1 500")
    end
  end

  describe "text" do
    it "trims, collapses whitespace and strips control characters" do
      expect(value("text", "  Ján \t Testovací\n ")).to eq("Ján Testovací")
      expect(value("person", "Ján\u0000 Test\u0007ovací")).to eq("Ján Testovací")
    end

    it "keeps line breaks in long text, but not three in a row" do
      expect(value("long_text", "Riadok 1\r\nRiadok 2\n\n\n\nRiadok 3")).to eq("Riadok 1\nRiadok 2\n\nRiadok 3")
    end

    it "caps the length by type" do
      expect(error("text", "a" * 256)).to eq(:too_long)
      expect(value("text", "a" * 255).length).to eq(255)
      expect(error("long_text", "a" * 5001)).to eq(:too_long)
    end

    it "treats a blank as an empty value, never an error" do
      %w[text long_text date money number person].each do |type|
        expect(parse(type, "  \n ")).to have_attributes(value: "", error: nil)
      end
      expect(parse("money", nil).value).to eq("")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
