# frozen_string_literal: true

require "spec_helper"

# civora-org/civora-platform#211: the dynamic form. Offline: the template and
# its fields are plain structs; only the form's own behavior is under test.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::TemplateEntryForm do
  before do
    stub_const("FormField", Struct.new(:key, :field_type, :label, :required, :personal_data, :group_key, :help_text,
                                       keyword_init: true))
    stub_const("FormTemplate", Struct.new(:fields))
    stub_const("Header", Struct.new(:data) do
      def header_value(key) = data[key].presence
    end)
  end

  def field(key, type = "text", required: false, personal: false, group: nil)
    FormField.new(key: key, field_type: type, label: key.capitalize, required: required,
                  personal_data: personal || type == "person", group_key: group)
  end

  let(:fields) do
    [field("cislo_zmluvy"), field("org_nazov", "org_header"), field("org_ico", "org_header"),
     field("predmet", "long_text", required: true, group: "predmet"),
     field("meno", "person", required: true, group: "kupujuci"), field("adresa", "person", group: "kupujuci"),
     field("suma_celkom", "money", required: true, group: "cena"), field("suma_slovom"),
     field("datum_podpisu", "date", group: "terminy"), field("plocha", "number", group: "terminy"),
     field("rodne_datum", "date", personal: true, group: "kupujuci")]
  end
  let(:template) { FormTemplate.new(fields) }
  let(:values) do
    { "predmet" => "Predaj", "meno" => "Ján Testovací", "adresa" => "Ulica 1", "suma_celkom" => "3 062,50",
      "datum_podpisu" => "15. 12. 2026", "plocha" => "12,5", "rodne_datum" => "2. 3. 1980" }
  end
  let(:header) { Header.new({ "official_name" => "Obec Vzorová", "ico" => "00000000" }) }

  def form(overrides = {}, title = "Kúpna zmluva")
    described_class.new(template: template, title: title, values: values.merge(overrides))
  end

  it "asks only for what a person types, grouped in template order" do
    expect(form.input_fields.map(&:key)).to eq(%w[predmet meno adresa suma_celkom datum_podpisu plocha rodne_datum])
    expect(form.groups.map(&:first)).to eq(%w[predmet kupujuci cena terminy])
    expect(form.header_fields.map(&:key)).to eq(%w[org_nazov org_ico])
    expect(form.words_fields.map(&:key)).to eq(["suma_slovom"])
  end

  it "parses every type into its canonical form and splits personal values off" do
    expect(form).to be_valid
    expect(form.stored_values).to eq("predmet" => "Predaj", "suma_celkom" => "3062.50",
                                     "datum_podpisu" => "2026-12-15", "plocha" => "12.5")
    expect(form.stored_personal_values).to eq("meno" => "Ján Testovací", "adresa" => "Ulica 1",
                                              "rodne_datum" => "1980-03-02")
    expect(form.personal_keys).to eq(%w[meno adresa rodne_datum])
    expect(form.amount).to eq(BigDecimal("3062.50"))
    expect(form.signed_on).to eq(Date.new(2026, 12, 15))
  end

  it "builds the document values: header, number, spelled amount and formatted fields" do
    result = form.document_values(profile: header, internal_number: "7/2026")

    expect(result).to include(
      "cislo_zmluvy" => "7/2026", "org_nazov" => "Obec Vzorová", "org_ico" => "00000000",
      "suma_celkom" => "3 062,50", "suma_slovom" => "tritisícšesťdesiatdva eur a päťdesiat centov",
      "datum_podpisu" => "15. 12. 2026", "plocha" => "12,5", "rodne_datum" => "2. 3. 1980", "meno" => "Ján Testovací"
    )
    expect(result.keys).to match_array(fields.map(&:key))
  end

  it "gives every blank value as an empty string, so the filler finds every key" do
    blank = form({ "adresa" => "", "plocha" => "", "datum_podpisu" => "", "suma_celkom" => "1" })
    result = blank.document_values(profile: header, internal_number: "1/2026")

    expect(result.values_at("adresa", "plocha", "datum_podpisu")).to eq(["", "", ""])
    expect(result["suma_slovom"]).to eq("jedno euro")
    expect(form({ "suma_celkom" => "" }).tap(&:valid?).document_values(profile: header,
                                                                       internal_number: "1")["suma_slovom"])
      .to eq("")
  end

  describe "validation" do
    it "requires the title and the required fields, naming each" do
      broken = form({ "predmet" => "", "meno" => "  ", "suma_celkom" => "" }, " ")

      expect(broken).not_to be_valid
      expect(broken.error_for("title")).to eq("This field is required.")
      %w[predmet meno suma_celkom].each { |key| expect(broken.error_for(key)).to eq("This field is required."), key }
      expect(broken.error_for("adresa")).to be_nil
      expect(broken.errors.full_messages).to include("Predmet: This field is required.")
    end

    it "reports unreadable and out-of-range values per field" do
      broken = form({ "suma_celkom" => "3.062", "datum_podpisu" => "31. 2. 2026", "plocha" => "abc" })

      expect(broken).not_to be_valid
      expect(broken.error_for("suma_celkom")).to include("could not be read")
      expect(broken.error_for("datum_podpisu")).to include("could not be read")
      expect(broken.error_for("plocha")).to include("could not be read")
      expect(form({ "suma_celkom" => "10 000 000 000" })).not_to be_valid
    end

    it "caps the title" do
      expect(form({}, "a" * 256)).not_to be_valid
      expect(form({}, "a" * 255)).to be_valid
    end

    it "recomputes on every call, so a corrected form becomes valid" do
      broken = form({ "predmet" => "" })
      expect(broken).not_to be_valid
      expect(broken.valid?).to be(false)
      expect(broken.errors.full_messages.size).to eq(1)
    end
  end

  describe "what the request cannot set" do
    it "drops keys that are not input fields: header, number, spelled amount, unknown" do
      sneaky = form({ "org_nazov" => "Podvrh", "cislo_zmluvy" => "99/1999", "suma_slovom" => "nula eur",
                      "neznamy" => "x", "org_ico" => "11111111" })

      expect(sneaky).to be_valid
      expect(sneaky.stored_values.keys).not_to include("org_nazov", "cislo_zmluvy", "suma_slovom", "neznamy", "org_ico")
      result = sneaky.document_values(profile: header, internal_number: "1/2026")
      expect(result.values_at("org_nazov", "org_ico", "cislo_zmluvy")).to eq(["Obec Vzorová", "00000000", "1/2026"])
      expect(result["suma_slovom"]).to start_with("tritisíc")
    end

    it "ignores non-string values (arrays and hashes from a crafted request)" do
      crafted = form({ "predmet" => ["a"], "meno" => { "x" => "y" } })

      expect(crafted).not_to be_valid
      expect(crafted.raw_value("predmet")).to eq("")
    end

    it "takes the template only from the constructor" do
      expect(form.template).to equal(template)
      expect(described_class.instance_method(:initialize).parameters).to include(%i[keyreq template])
      expect(form).not_to respond_to(:template=)
    end

    it "reads ActionController::Parameters the same way" do
      params = ActionController::Parameters.new(values.merge("neznamy" => "x")).permit(*values.keys)

      expect(described_class.new(template: template, title: "T", values: params)).to be_valid
    end
  end

  describe "header completeness" do
    it "names the header keys the profile leaves blank, or all when there is no profile" do
      expect(form.missing_header_keys(header)).to eq([])
      expect(form.missing_header_keys(Header.new({ "official_name" => "Obec" }))).to eq(["ico"])
      expect(form.missing_header_keys(nil)).to eq(%w[official_name ico])
    end
  end

  describe ".for_entry" do
    it "shows saved values the way they are typed" do
      entry = double(
        contract_template: template,
        values: { "suma_celkom" => "3062.50", "datum_podpisu" => "2026-12-15", "plocha" => "12.5",
                  "predmet" => "Predaj" },
        personal_values: { "meno" => "Ján Testovací" }
      )

      rebuilt = described_class.for_entry(entry, title: "Názov")

      expect(rebuilt.raw_value("suma_celkom")).to eq("3 062,50")
      expect(rebuilt.raw_value("datum_podpisu")).to eq("15. 12. 2026")
      expect(rebuilt.raw_value("plocha")).to eq("12,5")
      expect(rebuilt.raw_value("meno")).to eq("Ján Testovací")
      expect(rebuilt.title).to eq("Názov")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
