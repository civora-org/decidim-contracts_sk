# frozen_string_literal: true

require "spec_helper"

RSpec.describe Decidim::ContractsSk::CrzImport::SourceId do
  describe ".parse" do
    {
      "12851898" => "12851898",
      "  12851898\n" => "12851898",
      "https://www.crz.gov.sk/zmluva/12851898/" => "12851898",
      "https://crz.gov.sk/zmluva/12851898" => "12851898",
      "http://www.crz.gov.sk/zmluva/12851898/?x=1#y" => "12851898",
      "www.crz.gov.sk/zmluva/12851898/" => "12851898",
      "HTTPS://WWW.CRZ.GOV.SK/zmluva/12851898/" => "12851898"
    }.each do |input, id|
      it "reads #{input.inspect} as #{id}" do
        expect(described_class.parse(input)).to eq(id)
      end
    end

    [
      nil, "", "   ", "abc", "12/34", "12 34", "-5", "1e5",
      "https://www.crz.gov.sk/zmluva//", "https://www.crz.gov.sk/zmluva/12851898/extra",
      "https://notcrz.gov.sk/zmluva/12851898/", "https://crz.gov.sk.evil.example/zmluva/12851898/",
      "https://evil.example/?u=https://www.crz.gov.sk/zmluva/12851898/",
      "javascript:alert(1)//crz.gov.sk/zmluva/1/", "https://www.crz.gov.sk/zmluva/12851898/\nhttps://evil.example",
      "9" * 21
    ].each do |input|
      it "refuses #{input.inspect}" do
        expect(described_class.parse(input)).to be_nil
      end
    end
  end
end
