# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, Layout/LineLength
# civora-org/civora-platform#211. sablon 0.4.3 over the synthetic template.
RSpec.describe Decidim::ContractsSk::Templates::DocxFiller do
  include DocxFixtures

  let(:template) { DocxFixtures.synthetic_template }
  let(:values) do
    {
      org_nazov: "Obec Vzorová", org_ico: "00000000", org_adresa: "Námestie Vzorové 1",
      cislo_zmluvy: "VZ-2026-001", predmet: "Oprava lavičky", datum_ucinnosti: "1. 1. 2027",
      polozky: [{ nazov: "Materiál", suma: "120,00" }, { nazov: "Práca", suma: "80,00" }, { nazov: "Doprava", suma: "20,00" }],
      suma_celkom: "220,00", suma_slovom: "dvestodvadsať eur",
      priloha: { nazov: "Rozpočet prác" },
      kupujuci_meno: "Ján Testovací", kupujuci_adresa: "Ulica Nepravá 99", kupujuci_rc: "000000/0000"
    }
  end

  def fill(overrides = {}, tpl = template)
    described_class.call(tpl, values.merge(overrides))
  end

  def part(bytes, name) = DocxFixtures.read_zip(bytes).fetch(name).force_encoding("UTF-8")

  def body(bytes) = part(bytes, "word/document.xml")

  it "fills body fields" do
    expect(body(fill)).to include("Oprava lavičky", "1. 1. 2027", "dvestodvadsať eur")
  end

  it "fills the party table" do
    expect(body(fill)).to include("Obec Vzorová", "Ulica Nepravá 99", "000000/0000")
  end

  it "repeats the table row for every item" do
    xml = body(fill)
    expect(xml).to include("Materiál", "Práca", "Doprava")
    expect(xml).not_to include("polozky")
  end

  it "fills the header and the footer" do
    result = fill
    expect(part(result, "word/header1.xml")).to include("Obec Vzorová", "00000000", "VZ-2026-001")
    expect(part(result, "word/footer1.xml")).to include("Obec Vzorová")
  end

  it "fills a repeated field everywhere it occurs (header and body twice)" do
    result = fill
    occurrences = ["word/document.xml", "word/header1.xml"].sum { |n| part(result, n).scan("VZ-2026-001").size }
    expect(occurrences).to eq(3)
  end

  it "keeps the PAGE field of the footer" do
    expect(part(fill, "word/footer1.xml")).to include("PAGE")
  end

  it "leaves no merge field behind" do
    result = fill
    expect(DocxFixtures.all_xml(result)).not_to include("MERGEFIELD")
    expect(Decidim::ContractsSk::Templates::TemplateLinter.call(result).merge_fields).to be_empty
  end

  describe "the optional block" do
    it "is kept when its value is given" do
      expect(body(fill)).to include("Rozpočet prác", "potvrdzuje prevzatie")
    end

    it "is removed when its value is nil" do
      xml = body(fill(priloha: nil))
      expect(xml).not_to include("Rozpočet prác")
      expect(xml).not_to include("potvrdzuje prevzatie")
      expect(xml).to include("Celková cena")
    end
  end

  it "escapes markup in values so the part stays well-formed XML" do
    result = fill(predmet: %(Lavička <b>&</b> "x"))
    xml = body(result)
    expect(xml).to include("&lt;b&gt;&amp;&lt;/b&gt;")
    expect { Decidim::ContractsSk::Templates::Xml.parse(xml) }.not_to raise_error
  end

  it "accepts string keys" do
    result = described_class.call(template, values.transform_keys(&:to_s).merge("polozky" => values[:polozky].map do |h|
      h.transform_keys(&:to_s)
    end))
    expect(body(result)).to include("Oprava lavičky", "Doprava")
  end

  it "does not mutate the caller's values" do
    snapshot = Marshal.load(Marshal.dump(values))
    fill
    expect(values).to eq(snapshot)
  end

  describe "guards on the values" do
    it "rejects a key that would make sablon read typed content (image:, html:)" do
      expect { fill("image:logo": "/etc/passwd") }.to raise_error(ArgumentError, /invalid key/)
    end

    it "rejects such a key nested inside a loop item" do
      expect { fill(polozky: [{ "html:nazov": "<b>x</b>" }]) }.to raise_error(ArgumentError, /invalid key/)
    end

    it "rejects values that are not strings, nil, booleans, hashes or arrays" do
      expect { fill(suma_celkom: 220.0) }.to raise_error(ArgumentError, /unsupported value type Float/)
      expect { fill(predmet: StringIO.new("x")) }.to raise_error(ArgumentError, /unsupported value type/)
    end
  end

  it "raises when the template is not a docx" do
    expect { described_class.call("not a docx", values) }.to raise_error(StandardError)
  end
end
# rubocop:enable RSpec/MultipleExpectations, Layout/LineLength
