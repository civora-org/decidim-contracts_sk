# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for ContractTemplateField (civora-org/civora-platform#211, step P1):
# key and type validation, the forced personal flag and the freeze once the
# template version is used. Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::ContractTemplateField, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let!(:template) { create_template }

  def create_template(overrides = {})
    Decidim::ContractsSk::ContractTemplate.create!(
      { organization: organization, lineage_key: "kupna-zmluva", version: 1, name: "Kúpna zmluva" }.merge(overrides)
    )
  end

  def use!(template)
    Decidim::ContractsSk::ContractTemplateEntry.create!(contract: contract, contract_template: template)
  end

  def build_field(overrides = {})
    described_class.new({ contract_template: template, key: "predmet", label: "Predmet zmluvy" }.merge(overrides))
  end

  it "is valid with a key and a label and defaults to an optional text field" do
    field = build_field

    expect(field).to be_valid
    expect(field.field_type).to eq("text")
    expect(field.required).to be(false)
    expect(field.position).to eq(0)
  end

  it "accepts only ASCII snake_case keys" do
    ["Predmet", "predmet-zmluvy", "1predmet", "predmet zmluvy", "predmet\u010D"].each do |key|
      expect(build_field(key: key)).not_to be_valid, "#{key.inspect} must be rejected"
    end
    expect(build_field(key: "cislo_zmluvy_2")).to be_valid
    expect(build_field(key: "a" * 65)).not_to be_valid
  end

  it "keeps the key unique per template only" do
    build_field.save!

    expect(build_field).not_to be_valid
    expect(build_field(contract_template: create_template(version: 2))).to be_valid
    expect { build_field.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "validates the field type vocabulary" do
    %w[text long_text date money number person org_header].each do |type|
      expect(build_field(field_type: type)).to be_valid
    end
    expect(build_field(field_type: "checkbox")).not_to be_valid
  end

  it "forces personal_data on for the person type, whatever was passed" do
    field = build_field(field_type: "person", personal_data: false)

    expect(field).to be_valid
    expect(field.personal_data).to be(true)
    expect(build_field(field_type: "text", personal_data: false).tap(&:valid?).personal_data).to be(false)
    expect(build_field(field_type: "text", personal_data: true).tap(&:valid?).personal_data).to be(true)
  end

  it "validates the optional group key like a key" do
    expect(build_field(group_key: "kupujuci")).to be_valid
    expect(build_field(group_key: "Kupujúci")).not_to be_valid
  end

  it "orders a template's fields by position, then id" do
    b = build_field(key: "b", position: 2).tap(&:save!)
    a = build_field(key: "a", position: 1).tap(&:save!)
    c = build_field(key: "c", position: 1).tap(&:save!)

    expect(template.reload.fields.to_a).to eq([a, c, b])
  end

  it "is frozen once an entry references the template version" do
    field = build_field.tap(&:save!)
    use!(template)

    expect(build_field(key: "dalsie")).not_to be_valid
    expect(field.update(label: "Zmena")).to be(false)
    expect(field.errors).to be_added(:base, :template_used)
    expect(field.destroy).to be(false)
    expect(described_class.exists?(field.id)).to be(true)
  end

  it "stays editable on an unused template" do
    field = build_field.tap(&:save!)

    expect(field.update(label: "Zmena", required: true)).to be(true)
    expect(field.destroy).to be_truthy
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
