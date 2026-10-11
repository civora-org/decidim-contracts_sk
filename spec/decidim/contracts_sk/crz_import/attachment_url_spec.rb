# frozen_string_literal: true

require "spec_helper"

# The CRZ attachment URL allowlist (civora-org/civora-platform#189): a link
# is built only from digits + a known extension; everything else is nil.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Decidim::ContractsSk::CrzImport::AttachmentUrl do
  it "builds the official URL from an allowlisted name" do
    expect(described_class.for("7065995.pdf")).to eq("https://www.crz.gov.sk/data/att/7065995.pdf")
    expect(described_class.for("12.DOCX")).to eq("https://www.crz.gov.sk/data/att/12.DOCX")
  end

  [
    nil, "", "   ", 7_065_995, "abc.pdf", "7065995", "7065995.exe", "7065995.pdf.exe", "7065995.html",
    "../7065995.pdf", "a/7065995.pdf", "7065995.pdf?x=1", "7065995.pdf#x", "7065995.pdf\n", "7065995.pdf\nevil",
    " 7065995.pdf", "javascript:alert(1)", "https://evil.example/7065995.pdf", "//evil.example/1.pdf",
    "1.pdf%0d%0a", "7065995.p<script>", "#{"9" * 21}.pdf"
  ].each do |name|
    it "drops #{name.inspect}" do
      expect(described_class.for(name)).to be_nil
      expect(described_class.allowed?(name)).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
