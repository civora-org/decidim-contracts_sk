# frozen_string_literal: true

require "stringio"

# rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists

# Shared synthetic setup for the "new contract from a template" specs
# (civora-org/civora-platform#211): a small invented template with one field of
# every kind the form knows, an organization header and the Fake PDF converter.
# No real town, person or contract data anywhere.
module TemplateGenerationHelpers
  DOCX_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

  # [key, type, label, required, group_key, party_part (optional)]
  FIELD_SPECS = [
    ["cislo_zmluvy", "text", "Číslo zmluvy", false, nil],
    ["org_nazov", "org_header", "Názov organizácie", false, nil],
    ["org_ico", "org_header", "IČO organizácie", false, nil],
    ["predmet", "long_text", "Predmet zmluvy", true, "predmet"],
    ["kupujuci_meno", "person", "Kupujúci - meno", true, "kupujuci", "name"],
    ["kupujuci_adresa", "person", "Kupujúci - adresa", false, "kupujuci"],
    ["suma_celkom", "money", "Celková cena", true, "cena"],
    ["suma_slovom", "text", "Cena slovom", false, "cena"],
    ["plocha", "number", "Výmera (m2)", false, "cena"],
    ["datum_ucinnosti", "date", "Dátum účinnosti", false, "terminy"],
    ["datum_podpisu", "date", "Dátum podpisu", false, "terminy"]
  ].freeze

  module_function

  def template_docx(extra_body: "")
    d = DocxFixtures
    body = [
      d.para(d.text("Zmluva č. "), d.merge("=cislo_zmluvy")),
      d.para(d.merge("=org_nazov"), d.text(" IČO "), d.merge("=org_ico")),
      d.para(d.text("Predmet: "), d.merge("=predmet")),
      d.para(d.text("Kupujúci: "), d.merge("=kupujuci_meno"),
             d.text(", "), d.merge("=kupujuci_adresa")),
      d.para(d.text("Cena: "), d.merge("=suma_celkom"), d.text(" slovom "),
             d.merge("=suma_slovom"), d.text(" výmera "), d.merge("=plocha")),
      d.para(d.text("Účinnosť "), d.merge("=datum_ucinnosti"),
             d.text(" podpis "), d.merge("=datum_podpisu")),
      extra_body
    ].join
    d.docx(body)
  end

  def valid_params(overrides = {})
    {
      "predmet" => "Predaj pozemku parc. č. 1/1", "kupujuci_meno" => "Ján Testovací",
      "kupujuci_adresa" => "Ulica Nepravá 99, 000 00 Nikde", "suma_celkom" => "3 062,50",
      "plocha" => "12,5", "datum_ucinnosti" => "1. 1. 2027", "datum_podpisu" => "15. 12. 2026"
    }.merge(overrides)
  end
end

RSpec.shared_context "with a contract template" do
  let(:organization_profile_header) do
    { "official_name" => "Obec Vzorová", "ico" => "00000000", "seat" => "Námestie Vzorové 1" }
  end
  let(:profile) do
    Decidim::ContractsSk::ContractOrganizationProfile.create!(organization: organization,
                                                              header: organization_profile_header)
  end
  let(:template_status) { "active" }
  let(:template) do
    build_template(organization: organization, status: template_status)
  end

  before do
    migrate_engine_schema!
    profile
  end

  after { FileUtils.rm_rf(active_storage_root) }

  around do |example|
    original = Decidim::ContractsSk.pdf_converter
    Decidim::ContractsSk.pdf_converter = Decidim::ContractsSk::Templates::PdfConverter::Fake.new
    example.run
    Decidim::ContractsSk.pdf_converter = original
  end

  def build_template(organization:, status: "active", lineage_key: "kupna-zmluva", fields: TemplateGenerationHelpers::FIELD_SPECS,
                     docx: TemplateGenerationHelpers.template_docx, reference_pattern: nil, version: 1)
    record = Decidim::ContractsSk::ContractTemplate.create!(
      organization: organization, lineage_key: lineage_key, version: version, name: "Kúpna zmluva", status: status,
      reference_pattern: reference_pattern
    )
    record.file.attach(io: StringIO.new(docx), filename: "kupna-zmluva.docx",
                       content_type: TemplateGenerationHelpers::DOCX_TYPE)
    fields.each_with_index do |(key, type, label, required, group, part), position|
      record.fields.create!(key: key, field_type: type, label: label, required: required,
                            group_key: group, position: position, party_part: part)
    end
    record
  end

  def build_form(overrides = {}, title: "Kúpna zmluva - parcela 1/1", for_template: template)
    Decidim::ContractsSk::Admin::TemplateEntryForm.new(
      template: for_template, title: title, values: TemplateGenerationHelpers.valid_params(overrides)
    )
  end
end
# rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/ParameterLists
