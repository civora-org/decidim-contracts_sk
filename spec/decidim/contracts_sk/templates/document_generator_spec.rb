# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
# civora-org/civora-platform#211. Default runs use the Fake converter; the
# :libreoffice example runs the whole pipeline on the real binary.
RSpec.describe Decidim::ContractsSk::Templates::DocumentGenerator do
  include DocxFixtures

  let(:templates) { Decidim::ContractsSk::Templates }
  let(:converter) { templates::PdfConverter::Fake.new }
  let(:template) { DocxFixtures.synthetic_template }
  let(:hidden) { "[osobné údaje – skryté]" }
  let(:personal_keys) { %i[kupujuci_meno kupujuci_adresa kupujuci_rc] }
  let(:values) do
    {
      org_nazov: "Obec Vzorová", org_ico: "00000000", org_adresa: "Námestie Vzorové 1",
      cislo_zmluvy: "VZ-2026-001", predmet: "Oprava lavičky", datum_ucinnosti: "1. 1. 2027",
      polozky: [{ nazov: "Materiál", suma: "120,00" }, { nazov: "Práca", suma: "80,00" },
                { nazov: "Doprava", suma: "20,00" }],
      suma_celkom: "220,00", suma_slovom: "dvestodvadsať eur", priloha: nil,
      kupujuci_meno: "Ján Testovací", kupujuci_adresa: "Ulica Nepravá 99", kupujuci_rc: "000000/0000"
    }
  end

  def generate(**overrides)
    described_class.call(**{ template_bytes: template, values: values, personal_keys: personal_keys,
                             converter: converter }.merge(overrides))
  end

  def docx_text(bytes) = DocxFixtures.read_zip(bytes).fetch("word/document.xml").force_encoding("UTF-8")

  def pdf_text(bytes) = PDF::Reader.new(StringIO.new(bytes)).pages.map(&:text).join

  def pdf_info(bytes) = PDF::Reader.new(StringIO.new(bytes)).info

  describe "the result" do
    subject(:result) { generate }

    it "returns the four documents" do
      expect(result.keys).to contain_exactly(:internal_docx, :internal_pdf, :publication_docx, :publication_pdf)
      expect(result.values).to all(be_a(String))
    end

    it "keeps the personal values in the internal variant only" do
      expect(docx_text(result[:internal_docx])).to include("Ján Testovací", "000000/0000")
      expect(pdf_text(result[:internal_pdf])).to include("Jan Testovaci")

      expect(docx_text(result[:publication_docx])).to include(hidden)
      expect(docx_text(result[:publication_docx])).not_to include("Testovací", "000000/0000", "Nepravá")
      expect(pdf_text(result[:publication_pdf])).not_to include("Testovaci", "000000/0000", "Nepravá")
      expect(pdf_text(result[:publication_pdf])).to include("VZ-2026-001")
    end

    it "sanitizes the docx metadata of both variants" do
      %i[internal_docx publication_docx].each do |key|
        entries = DocxFixtures.read_zip(result[key])
        expect(entries["docProps/core.xml"]).not_to include("Fiktívny Autor")
      end
    end

    it "blanks Title, Author, Creator and Producer in both PDFs" do
      %i[internal_pdf publication_pdf].each do |key|
        info = pdf_info(result[key]).slice(:Title, :Author, :Creator, :Producer)
        expect(info.values.map { |v| v.to_s.strip }).to all(be_empty)
        expect(result[key]).not_to include("Fake author", "Fake producer")
      end
    end

    it "is deterministic" do
      expect(generate).to eq(result)
    end
  end

  it "uses Decidim::ContractsSk.pdf_converter when no converter is given" do
    Decidim::ContractsSk.pdf_converter = converter
    result = described_class.call(template_bytes: template, values: values, personal_keys: personal_keys)
    expect(result[:publication_pdf]).to start_with("%PDF")
  ensure
    Decidim::ContractsSk.pdf_converter = nil
  end

  it "needs no verification when no personal key holds a value" do
    blank = values.merge(kupujuci_meno: nil, kupujuci_adresa: "", kupujuci_rc: nil)
    result = generate(values: blank)
    expect(result[:publication_pdf]).to start_with("%PDF")
  end

  it "refuses an empty personal_keys list instead of publishing the internal variant" do
    expect { generate(personal_keys: []) }.to raise_error(ArgumentError, /personal_keys/)
  end

  describe "failing closed" do
    it "raises RedactionFailed when a personal value leaks through a non-personal field" do
      leaky = values.merge(predmet: "Dodávka pre Ján Testovací")
      expect { generate(values: leaky) }
        .to raise_error(described_class::RedactionFailed) { |e|
          expect(e.leaks.map(&:location)).to include("docx:word/document.xml", "pdf:text")
          expect(e.message).not_to include("Testovací", "Testovaci")
        }
    end

    it "raises when only the PDF leaks, though the docx is clean" do
      leaky_pdf = templates::MinimalPdf.build(lines: ["Kupujuci: Jan Testovaci"], info: {})
      expect { generate(converter: ->(_docx) { leaky_pdf }) }
        .to raise_error(described_class::RedactionFailed) { |e| expect(e.leaks.map(&:location)).to include("pdf:text") }
    end

    it "raises when the converter returns garbage" do
      garbage = ->(_docx) { "not a pdf" }
      expect { generate(converter: garbage) }.to raise_error(templates::PdfConverter::ConversionFailed)
    end

    it "raises when the PDF has no extractable text, because nothing can be proven" do
      textless = ->(_docx) { templates::MinimalPdf.build(lines: [], info: {}) }
      expect { generate(converter: textless) }
        .to raise_error(described_class::RedactionFailed) { |e|
          expect(e.findings.map(&:code)).to include(:pdf_no_text)
        }
    end

    it "propagates converter errors" do
      timeout = ->(_docx) { raise templates::PdfConverter::ConversionTimeout, "too slow" }
      expect { generate(converter: timeout) }.to raise_error(templates::PdfConverter::ConversionTimeout)
    end

    it "returns nothing when verification fails" do
      leaky = values.merge(predmet: "Ján Testovací")
      result = nil
      begin
        result = generate(values: leaky)
      rescue described_class::RedactionFailed
        nil
      end
      expect(result).to be_nil
    end
  end

  describe "with real LibreOffice", :libreoffice do
    it "generates and verifies all four documents" do
      result = described_class.call(template_bytes: template, values: values, personal_keys: personal_keys)
      expect(result[:publication_pdf]).to start_with("%PDF")
      expect(pdf_text(result[:internal_pdf])).to include("Testovací")
      expect(pdf_text(result[:publication_pdf])).not_to include("Testovací")
      info = pdf_info(result[:publication_pdf]).slice(:Title, :Author, :Creator, :Producer)
      expect(info.values.map { |v| v.to_s.strip }).to all(be_empty)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
