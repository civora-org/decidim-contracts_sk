# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

# civora-org/civora-platform#211: which merge fields a person never types.
# Pure, offline: fields are plain structs.
RSpec.describe Decidim::ContractsSk::Templates::TemplateFields do
  before { stub_const("SpecField", Struct.new(:key, :field_type)) }

  def field(key, type = "text") = SpecField.new(key, type)

  describe ".org_header_key" do
    it "maps the Slovak names and the header keys themselves" do
      { "org_nazov" => "official_name", "org_adresa" => "seat", "org_sidlo" => "seat", "org_ico" => "ico",
        "org_dic" => "dic", "org_iban" => "iban", "org_statutar" => "statutory_name",
        "org_official_name" => "official_name", "org_miesto_podpisu" => "signing_place" }.each do |key, header|
        expect(described_class.org_header_key(key)).to eq(header), key
      end
    end

    it "answers nil for anything that is not an allowlisted header key" do
      %w[org_heslo org_ ico predmet org_secret].each do |key|
        expect(described_class.org_header_key(key)).to be_nil, key
      end
    end
  end

  describe ".words_source" do
    let(:money) { field("suma_celkom", "money") }
    let(:fields) { [money, field("predmet"), field("suma_celkom_slovom")] }

    it "pairs a spelled-out field with the money field of the same base" do
      expect(described_class.words_source(fields.last, fields)).to eq(money)
      other = [field("cena", "money"), field("zaloha", "money"), field("cena_words")]
      expect(described_class.words_source(other.last, other)).to eq(other.first)
    end

    it "falls back to the only money field, and to none when it would be a guess" do
      lone = [money, field("celkom_slovom")]
      expect(described_class.words_source(lone.last, lone)).to eq(money)
      two = [money, field("zaloha", "money"), field("celkom_slovom")]
      expect(described_class.words_source(two.last, two)).to be_nil
      expect(described_class.words_source(field("slovom"), [money])).to be_nil
      expect(described_class.words_source(field("predmet"), [money])).to be_nil
    end
  end

  describe ".input_fields" do
    it "leaves out the header, the internal number and the spelled-out amounts" do
      fields = [field("cislo_zmluvy"), field("org_ico", "org_header"), field("org_nazov", "org_header"),
                field("predmet"), field("suma_celkom", "money"), field("suma_celkom_slovom"),
                field("interne_cislo"), field("org_neznamy", "org_header")]

      expect(described_class.input_fields(fields).map(&:key)).to eq(%w[predmet suma_celkom org_neznamy])
      expect(described_class.header_fields(fields).map(&:key)).to eq(%w[org_ico org_nazov])
    end

    it "keeps an org_ prefixed field that is not typed org_header in the form" do
      expect(described_class.input_fields([field("org_ico", "text")]).map(&:key)).to eq(["org_ico"])
    end
  end

  describe "contract amount and signing date" do
    it "picks the first well-known name of the right type" do
      fields = [field("cena", "money"), field("suma_celkom", "money"), field("datum_ucinnosti", "date"),
                field("datum_podpisu", "date"), field("suma_celkom_text", "text")]

      expect(described_class.amount_field(fields).key).to eq("suma_celkom")
      expect(described_class.signed_on_field(fields).key).to eq("datum_podpisu")
      expect(described_class.amount_field([field("suma_celkom", "text")])).to be_nil
      expect(described_class.signed_on_field([field("datum_ucinnosti", "date")])).to be_nil
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
