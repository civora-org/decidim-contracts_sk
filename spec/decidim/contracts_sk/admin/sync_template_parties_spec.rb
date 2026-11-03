# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db specs for the parties a contract template creates
# (civora-org/civora-platform#211, follow-up): the municipality from the header
# profile, the counterparty from the declared fields, idempotency on
# regeneration, manual parties left alone, and the privacy rule that a natural
# person is stored as "Fyzická osoba" only. Synthetic data only.
#
# Each guard example was mutation-checked (the guard commented out, the
# example went red, the guard restored); see tmp/evidence/template-parties.md.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::SyncTemplateParties, :db do
  include_context "with a contract template"

  let(:party_class) { Decidim::ContractsSk::Party }

  # A company counterparty: name, IČO and seat are plain (not personal) fields.
  let(:company_fields) do
    TemplateGenerationHelpers::FIELD_SPECS.reject { |f| f.first.start_with?("kupujuci_") } + [
      ["partner_nazov", "text", "Obchodné meno", true, "partner", "name"],
      ["partner_ico", "text", "IČO", false, "partner", "ico"],
      ["partner_sidlo", "text", "Sídlo", false, "partner", "address"]
    ]
  end
  let(:company_template) { build_template(organization: organization, fields: company_fields) }
  let(:company_params) do
    TemplateGenerationHelpers.valid_params.except("kupujuci_meno", "kupujuci_adresa").merge(
      "partner_nazov" => "Stavby Vzorové s.r.o.", "partner_ico" => "12 345 678",
      "partner_sidlo" => "Dlhá 5, 000 00 Nikde"
    )
  end

  def call(form = build_form, **options)
    Decidim::ContractsSk::Admin::GenerateFromTemplate.call(form, template: template, user: author,
                                                                 organization: organization, **options)
  end

  def company_form(overrides = {})
    Decidim::ContractsSk::Admin::TemplateEntryForm.new(
      template: company_template, title: "Zmluva o dielo", values: company_params.merge(overrides)
    )
  end

  def company_call(form = company_form, **options)
    Decidim::ContractsSk::Admin::GenerateFromTemplate.call(form, template: company_template, user: author,
                                                                 organization: organization, **options)
  end

  def attrs(party)
    party.attributes.slice("role", "name", "ico", "address", "template_slot")
  end

  describe "the municipality" do
    it "is added as the object party from the header profile" do
      contract = call[:ok]

      municipality = contract.parties.find_by!(template_slot: "municipality")
      expect(attrs(municipality)).to eq("role" => "object", "name" => "Obec Vzorová", "ico" => "00000000",
                                        "address" => "Námestie Vzorové 1", "template_slot" => "municipality")
    end

    it "falls back to the organization name when the header has no official name" do
      organization.update!(name: { "sk" => "Obec z organizácie" }, default_locale: "sk")
      bare = Decidim::ContractsSk::ContractOrganizationProfile.new(organization: organization,
                                                                   header: { "ico" => "00000000" })

      expect(Decidim::ContractsSk::Templates::PartyValues.municipality(bare, organization))
        .to include(name: "Obec z organizácie", ico: "00000000", role: "object")
    end
  end

  describe "a natural-person counterparty" do
    it "is stored as Fyzická osoba with no name, address, IČO or typed value anywhere in the parties table" do
      contract = call[:ok]

      counterparty = contract.parties.find_by!(template_slot: "counterparty")
      expect(attrs(counterparty)).to eq("role" => "contractor", "name" => "Fyzická osoba", "ico" => nil,
                                        "address" => nil, "template_slot" => "counterparty")
      dump = party_class.all.map { |party| party.attributes.values.join(" ") }.join(" ")
      expect(dump).not_to include("Ján", "Testovací", "Nepravá", "Nikde")
    end

    it "keeps the real name only in the encrypted entry" do
      contract = call[:ok]

      expect(contract.template_entry.personal_values["kupujuci_meno"]).to eq("Ján Testovací")
    end
  end

  describe "a company counterparty" do
    it "is stored with the typed name, the normalized IČO and the seat" do
      contract = company_call[:ok]

      expect(attrs(contract.parties.find_by!(template_slot: "counterparty")))
        .to eq("role" => "contractor", "name" => "Stavby Vzorové s.r.o.", "ico" => "12345678",
               "address" => "Dlhá 5, 000 00 Nikde", "template_slot" => "counterparty")
    end

    it "refuses an IČO that is not eight digits, storing nothing" do
      before = [party_class.count, Decidim::ContractsSk::Contract.count]

      events = company_call(company_form("partner_ico" => "1234"))

      expect(events).to have_key(:invalid)
      expect([party_class.count, Decidim::ContractsSk::Contract.count]).to eq(before)
    end

    it "accepts a company without an IČO or seat" do
      contract = company_call(company_form("partner_ico" => "", "partner_sidlo" => ""))[:ok]

      expect(attrs(contract.parties.find_by!(template_slot: "counterparty")))
        .to include("name" => "Stavby Vzorové s.r.o.", "ico" => nil, "address" => nil)
    end
  end

  describe "a template without a declared counterparty" do
    let(:template) do
      build_template(organization: organization,
                     fields: TemplateGenerationHelpers::FIELD_SPECS.map { |f| f.first(5) })
    end

    it "still adds the municipality and no counterparty" do
      contract = call[:ok]

      expect(contract.parties.pluck(:template_slot)).to eq(["municipality"])
    end
  end

  describe "regenerating" do
    it "updates the same two parties in place (no duplicates) and keeps their ids" do
      contract = company_call[:ok]
      ids = contract.parties.order(:id).pluck(:id)

      company_call(company_form("partner_nazov" => "Nový názov s.r.o.", "partner_ico" => "87654321"),
                   contract: contract)

      expect(contract.parties.order(:id).pluck(:id)).to eq(ids)
      expect(contract.parties.find_by!(template_slot: "counterparty")).to have_attributes(name: "Nový názov s.r.o.",
                                                                                          ico: "87654321")
    end

    it "picks up a changed header" do
      contract = call[:ok]
      profile.update!(header: organization_profile_header.merge("seat" => "Nová 2"))

      call(build_form, contract: contract)

      expect(contract.parties.find_by!(template_slot: "municipality").address).to eq("Nová 2")
    end

    it "never deletes or edits a party a person added by hand" do
      contract = call[:ok]
      manual = contract.parties.create!(role: "contractor", name: "Ručne pridaná s.r.o.", ico: "11111111")

      call(build_form, contract: contract)
      call(build_form({ "kupujuci_meno" => "Iná Osoba" }), contract: contract)

      expect(contract.parties.where(template_slot: nil).pluck(:id, :name,
                                                              :ico)).to eq([[manual.id, "Ručne pridaná s.r.o.",
                                                                             "11111111"]])
      expect(contract.parties.count).to eq(3)
    end

    it "removes the counterparty it created when the company name is emptied" do
      template_optional = build_template(organization: organization, fields: company_fields.map do |f|
        f.first == "partner_nazov" ? ["partner_nazov", "text", "Obchodné meno", false, "partner", "name"] : f
      end, lineage_key: "optional")
      contract = Decidim::ContractsSk::Admin::GenerateFromTemplate.call(
        Decidim::ContractsSk::Admin::TemplateEntryForm.new(template: template_optional, title: "Z",
                                                           values: company_params),
        template: template_optional, user: author, organization: organization
      )[:ok]

      Decidim::ContractsSk::Admin::GenerateFromTemplate.call(
        Decidim::ContractsSk::Admin::TemplateEntryForm.new(template: template_optional, title: "Z",
                                                           values: company_params.merge("partner_nazov" => "")),
        template: template_optional, user: author, organization: organization, contract: contract
      )

      expect(contract.parties.pluck(:template_slot)).to eq(["municipality"])
    end
  end

  describe "rolling back" do
    it "stores no party when the generation fails" do
      template.file.purge
      template.reload

      expect { call }.not_to change(party_class, :count)
    end
  end

  describe "the schema" do
    it "allows one party per slot and contract but any number of manual parties" do
      contract = call[:ok]

      expect do
        party_class.create!(contract: contract, role: "contractor", name: "X", template_slot: "counterparty")
      end.to raise_error(ActiveRecord::RecordInvalid)
      expect do
        party_class.new(contract: contract, role: "contractor", name: "X",
                        template_slot: "counterparty").save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
      expect { 2.times { contract.parties.create!(role: "contractor", name: "Ručná") } }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
