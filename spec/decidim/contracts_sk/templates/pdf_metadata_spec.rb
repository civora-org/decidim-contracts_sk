# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations
# Info-dictionary blanking (civora-org/civora-platform#211). All PDFs are built
# by the engine's MinimalPdf or by hand; every name is invented.
RSpec.describe Decidim::ContractsSk::Templates::PdfMetadata do
  let(:pdf_module) { Decidim::ContractsSk::Templates::MinimalPdf }
  let(:info) do
    { "Title" => "Zmluva Ján Testovací", "Author" => "Fiktívny Autor", "Creator" => "Writer",
      "Producer" => "LibreOffice 25.2", "Subject" => "predmet" }
  end
  let(:pdf) { pdf_module.build(lines: ["Zmluva c. 1"], info: info) }

  def info_of(bytes) = PDF::Reader.new(StringIO.new(bytes)).info

  it "blanks Title, Author, Creator, Producer and Subject" do
    result = described_class.blank(pdf)
    blanked = info_of(result).slice(:Title, :Author, :Creator, :Producer, :Subject)
    expect(blanked.values.map { |v| v.to_s.strip }).to all(be_empty)
  end

  it "removes the old strings from the file bytes, not just from the parsed view" do
    result = described_class.blank(pdf)
    expect(result).not_to include("Fiktivny", "LibreOffice", "Testovac", "Writer")
  end

  it "keeps the byte length, the page text and the other keys" do
    with_date = pdf_module.build(lines: ["Zmluva c. 1"], info: "/CreationDate (D:20260101000000Z) /Title (Ahoj)")
    result = described_class.blank(with_date)
    expect(result.bytesize).to eq(with_date.bytesize)
    expect(PDF::Reader.new(StringIO.new(result)).pages.first.text).to include("Zmluva c. 1")
    expect(info_of(result)[:CreationDate]).to eq("D:20260101000000Z")
  end

  it "blanks strings with escapes and nested parentheses without touching what follows" do
    tricky = pdf_module.build(lines: ["x"], info: "/Author (a \\) b (c) \\\\ d) /Creator (tail)")
    result = described_class.blank(tricky)
    expect(result.bytesize).to eq(tricky.bytesize)
    expect(info_of(result)[:Author].to_s.strip).to be_empty
    expect(info_of(result)[:Creator].to_s.strip).to be_empty
  end

  it "blanks hex strings, including an odd number of digits" do
    hex = pdf_module.build(lines: ["x"], info: "/Author <FEFF0041004200430044> /Creator <41424> /Title (t)")
    result = described_class.blank(hex)
    expect(result.bytesize).to eq(hex.bytesize)
    expect(info_of(result).slice(:Author, :Creator).values.map { |v| v.to_s.strip }).to all(be_empty)
  end

  it "does not take a key name inside a string value for a key" do
    pdf = pdf_module.build(lines: ["x"], info: { "Title" => "see /Author (secret) here", "Author" => "Eva" })
    result = described_class.blank(pdf)
    expect(info_of(result).slice(:Title, :Author).values.map { |v| v.to_s.strip }).to all(be_empty)
    expect(result).not_to include("secret", "Eva")
  end

  it "returns a PDF without an Info dictionary unchanged" do
    bare = pdf_module.build(lines: ["x"])
    expect(described_class.blank(bare)).to eq(bare)
  end

  describe "failing closed" do
    it "raises on bytes that are not a PDF" do
      expect { described_class.blank("not a pdf") }.to raise_error(described_class::Error)
    end

    it "raises when the Info dictionary has an indirect string" do
      indirect = pdf_module.build(lines: ["x"], info: "/Title 4 0 R")
      expect { described_class.blank(indirect) }.to raise_error(described_class::Error, /indirect/)
    end

    it "raises on an incremental update" do
      incremental = pdf_module.build(lines: ["x"], info: { "Title" => "t" }, extra_trailer: "/Prev 0")
      expect { described_class.blank(incremental) }.to raise_error(described_class::Error)
    end

    it "raises when the Info object cannot be found as plain bytes" do
      # same length, so the xref stays valid, but the object number no longer matches
      moved = pdf.sub("6 0 obj", "7 0 obj")
      expect { described_class.blank(moved) }.to raise_error(described_class::Error)
    end

    it "raises when the sanitized file does not verify as blank" do
      allow(described_class).to receive(:blank_object).and_return(pdf)
      expect { described_class.blank(pdf) }.to raise_error(described_class::Error, /not blank/)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
