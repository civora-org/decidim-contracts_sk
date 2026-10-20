# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations
# The converter seam, the PDF validation and the Fake adapter
# (civora-org/civora-platform#211).
RSpec.describe Decidim::ContractsSk::Templates::PdfConverter do
  include DocxFixtures

  let(:templates) { Decidim::ContractsSk::Templates }

  describe ".validate!" do
    it "returns a real PDF unchanged" do
      pdf = templates::MinimalPdf.build(lines: ["Zmluva"])
      expect(described_class.validate!(pdf)).to eq(pdf)
    end

    it "rejects empty output" do
      expect { described_class.validate!("") }.to raise_error(described_class::ConversionFailed, /no PDF/)
      expect { described_class.validate!(nil) }.to raise_error(described_class::ConversionFailed)
    end

    it "rejects text that does not start with %PDF" do
      expect { described_class.validate!("hello world") }
        .to raise_error(described_class::ConversionFailed, /%PDF/)
    end

    it "rejects a %PDF header over garbage" do
      expect { described_class.validate!("%PDF-1.4\nthis is not a pdf at all") }
        .to raise_error(described_class::ConversionFailed, /not a readable PDF/)
    end

    it "rejects a truncated PDF" do
      pdf = templates::MinimalPdf.build(lines: ["Zmluva"])
      expect { described_class.validate!(pdf.byteslice(0, 120)) }.to raise_error(described_class::ConversionFailed)
    end

    it "rejects a PDF with no pages" do
      pdf = templates::MinimalPdf.build(lines: ["Zmluva"], pages: 0)
      expect { described_class.validate!(pdf) }.to raise_error(described_class::ConversionFailed, /no pages/)
    end
  end

  describe Decidim::ContractsSk::Templates::PdfConverter::Fake do
    let(:docx) { DocxFixtures.docx(DocxFixtures.para(DocxFixtures.text("Zmluva č. 1 & dodatok"))) }

    it "returns a valid PDF carrying the folded document text" do
      pdf = described_class.new.call(docx)
      expect(templates::PdfConverter.validate!(pdf)).to eq(pdf)
      expect(PDF::Reader.new(StringIO.new(pdf)).pages.first.text).to include("Zmluva c. 1 & dodatok")
    end

    it "is deterministic" do
      first = described_class.new.call(docx)
      expect(described_class.new.call(docx.dup)).to eq(first)
    end

    it "still returns a valid PDF for bytes that are not a docx" do
      expect(templates::PdfConverter.validate!(described_class.new.call("garbage"))).to start_with("%PDF")
    end
  end

  describe "Decidim::ContractsSk.pdf_converter" do
    after { Decidim::ContractsSk.pdf_converter = nil }

    it "defaults to the LibreOffice adapter" do
      expect(Decidim::ContractsSk.pdf_converter).to be_a(described_class::LibreOfficeCli)
    end

    it "accepts any callable and resets to the default with nil" do
      callable = ->(_docx) { "pdf" }
      Decidim::ContractsSk.pdf_converter = callable
      expect(Decidim::ContractsSk.pdf_converter).to be(callable)
      Decidim::ContractsSk.pdf_converter = nil
      expect(Decidim::ContractsSk.pdf_converter).to be_a(described_class::LibreOfficeCli)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
