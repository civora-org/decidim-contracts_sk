# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for ContractTemplateEntry (civora-org/civora-platform#211, step P1):
# validations, tenancy, the personal/non-personal value split and encryption
# at rest. Synthetic data only; the encryption keys are the dummy app's fixed
# test keys (spec/dummy/config/application.rb).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::ContractTemplateEntry, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:template) do
    Decidim::ContractsSk::ContractTemplate.create!(
      organization: organization, lineage_key: "kupna-zmluva", version: 3, name: "Kúpna zmluva"
    ).tap do |created|
      created.fields.create!(key: "predmet", label: "Predmet")
      created.fields.create!(key: "kupujuci", label: "Kupujúci", field_type: "person")
      created.fields.create!(key: "rodne_cislo", label: "Rodné číslo", personal_data: true)
    end
  end

  def build_entry(overrides = {})
    described_class.new({ contract: contract, contract_template: template }.merge(overrides))
  end

  def raw_personal_values(entry)
    described_class.connection.select_value(
      "SELECT personal_values FROM #{described_class.table_name} WHERE id = #{entry.id.to_i}"
    )
  end

  describe "validations" do
    it "is valid with a contract and a template, pinning the template version" do
      entry = build_entry

      expect(entry).to be_valid
      expect(entry.template_version).to eq(3)
      expect(entry.values).to eq({})
      expect(entry.personal_values).to eq({})
    end

    it "requires a contract and a template" do
      entry = described_class.new

      expect(entry).not_to be_valid
      expect(entry.errors.attribute_names).to include(:contract, :contract_template)
    end

    it "allows one entry per contract, in the model and in the database" do
      build_entry.save!

      duplicate = build_entry
      expect(duplicate).not_to be_valid
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "refuses a template from another organization (tenancy)" do
      foreign = Decidim::ContractsSk::ContractTemplate.create!(
        organization: Decidim::Organization.create!, lineage_key: "x", version: 1, name: "Cudzia"
      )
      entry = build_entry(contract_template: foreign)

      expect(entry).not_to be_valid
      expect(entry.errors).to be_added(:contract_template, :invalid)
    end

    it "refuses a creator from another organization" do
      stranger = Decidim::User.create!(organization: Decidim::Organization.create!)

      expect(build_entry(created_by: stranger)).not_to be_valid
      expect(build_entry(created_by: author)).to be_valid
    end

    it "refuses a template version that is not the template's own" do
      entry = build_entry(template_version: 2)

      expect(entry).not_to be_valid
      expect(entry.errors).to be_added(:template_version, :invalid)
    end

    it "requires both value stores to be JSON objects" do
      entry = build_entry
      entry.values = %w[not an object]

      expect(entry).not_to be_valid
      expect(entry.errors).to be_added(:values, :invalid)
    end

    it "caps the internal number" do
      expect(build_entry(internal_number: "ZM-2026-0001")).to be_valid
      expect(build_entry(internal_number: "x" * 101)).not_to be_valid
    end
  end

  describe "the personal / non-personal split" do
    it "accepts non-personal keys in values and personal keys in personal_values" do
      entry = build_entry(values: { "predmet" => "Predaj pozemku" },
                          personal_values: { "kupujuci" => "Ján Vzorový", "rodne_cislo" => "000000/0000" })

      expect(entry).to be_valid
    end

    it "refuses a personal field's value in the plaintext values" do
      entry = build_entry(values: { "kupujuci" => "Ján Vzorový" })

      expect(entry).not_to be_valid
      expect(entry.errors).to be_added(:values, :contains_personal_data)
    end

    it "treats a personal_data flag on a non-person field as personal too" do
      entry = build_entry(values: { "rodne_cislo" => "000000/0000" })

      expect(entry).not_to be_valid
    end

    it "refuses non-personal keys in the encrypted store" do
      entry = build_entry(personal_values: { "predmet" => "Predaj pozemku" })

      expect(entry).not_to be_valid
      expect(entry.errors).to be_added(:personal_values, :not_personal_fields)
    end
  end

  describe "encryption at rest" do
    let(:buyer) { "Ján Vzorový, Vzorová 1, 000 00 Vzorová" }
    let(:entry) do
      build_entry(personal_values: { "kupujuci" => buyer }).tap(&:save!)
    end

    it "round-trips the value through the model" do
      expect(described_class.find(entry.id).personal_values).to eq("kupujuci" => buyer)
    end

    it "stores ciphertext, never the plaintext, in the raw column" do
      raw = raw_personal_values(entry)

      expect(raw).to be_present
      expect(raw).not_to include("Vzorový")
      expect(raw).not_to include("kupujuci")
      expect(raw).not_to include(buyer)
      expect(JSON.parse(raw)).to include("p", "h") # the Active Record Encryption envelope
    end

    it "uses a random IV, so equal values give different ciphertexts" do
      other_contract = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2"))
      other = described_class.create!(contract: other_contract, contract_template: template,
                                      personal_values: { "kupujuci" => buyer })

      expect(raw_personal_values(other)).not_to eq(raw_personal_values(entry))
    end

    it "keeps the non-personal values readable in SQL" do
      plain = build_entry(values: { "predmet" => "Predaj pozemku" }).tap(&:save!)
      raw = described_class.connection.select_value(
        "SELECT \"values\" FROM #{described_class.table_name} WHERE id = #{plain.id}"
      )

      expect(raw).to include("Predaj pozemku")
    end

    it "filters personal_values from inspect and the request parameter filter" do
      expect(entry.inspect).to include("personal_values: [FILTERED]")
      expect(entry.inspect).not_to include("Vzorový")
      expect(described_class.filter_attributes).to include(:personal_values)
      expect(Rails.application.config.filter_parameters).to include(:personal_values)
    end
  end

  describe "association lifecycle" do
    it "is destroyed with its contract, generated documents included" do
      entry = build_entry.tap(&:save!)
      Decidim::ContractsSk::GeneratedDocument.create!(
        contract: contract, entry: entry, variant: "internal", file_format: "docx",
        generated_at: Time.current, template_version: 3
      )

      expect { contract.destroy! }
        .to change(described_class, :count).by(-1)
        .and change(Decidim::ContractsSk::GeneratedDocument, :count).by(-1)
    end

    it "makes the template used, which freezes it" do
      expect(template).not_to be_used
      build_entry.save!

      expect(template).to be_used
      expect(template.update(name: "Zmena")).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
