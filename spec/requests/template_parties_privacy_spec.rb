# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the public side of the parties a contract template creates
# (civora-org/civora-platform#211, follow-up): a contract generated for a
# natural person shows "Fyzická osoba" and none of the typed values on the
# catalogue page, the lists, the open-data exports, the party filter, the
# supplier pages and the statistics; a company counterparty is published with
# its name and IČO. Real :db group; synthetic data only.
#
# Mutation-checked: the natural-person branch of Templates::PartyValues was
# changed to copy the typed name, and the "no typed value" examples went red.
# ---------------------------------------------------------------------------

require "spec_helper"
require "csv"
require "json"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "parties created from a contract template", :db, type: :request do
  include_context "with a contract template"

  let(:typed) { %W[J\u00E1n Testovac\u00ED Neprav\u00E1 Nikde] }

  before do
    [Decidim::ContractsSk::ContractsController, Decidim::ContractsSk::OpenDataController,
     Decidim::ContractsSk::SuppliersController, Decidim::ContractsSk::StatisticsController].each do |klass|
      allow_any_instance_of(klass).to receive(:current_organization).and_return(organization)
    end
  end

  def generate!(form)
    contract = Decidim::ContractsSk::Admin::GenerateFromTemplate
               .call(form, template: form.template, user: author, organization: organization)[:ok]
    contract.update_columns(state: "published", published_at: Time.utc(2026, 11, 1, 10), updated_at: Time.current)
    contract
  end

  def person_contract
    @person_contract ||= generate!(build_form)
  end

  def company_template
    @company_template ||= build_template(
      organization: organization, lineage_key: "dielo",
      fields: TemplateGenerationHelpers::FIELD_SPECS.reject { |f| f.first.start_with?("kupujuci_") } + [
        ["partner_nazov", "text", "Obchodné meno", true, "partner", "name"],
        ["partner_ico", "text", "IČO", false, "partner", "ico"],
        ["partner_sidlo", "text", "Sídlo", false, "partner", "address"]
      ]
    )
  end

  def company_contract
    values = TemplateGenerationHelpers.valid_params.except("kupujuci_meno", "kupujuci_adresa").merge(
      "partner_nazov" => "Stavby Vzorové s.r.o.", "partner_ico" => "12345678", "partner_sidlo" => "Dlhá 5, Nikde"
    )
    @company_contract ||= generate!(Decidim::ContractsSk::Admin::TemplateEntryForm
      .new(template: company_template, title: "Zmluva o dielo", values: values))
  end

  def expect_no_typed_value(text)
    typed.each { |value| expect(text).not_to include(value) }
  end

  describe "a natural-person counterparty" do
    it "renders as Fyzická osoba on the catalogue page, without any typed value" do
      get "/#{person_contract.id}"

      expect(response).to have_http_status(:ok)
      html = response.body
      expect(html).to include("Fyzická osoba").and include("Obec Vzorová")
      expect(html).not_to include("nie sú zaznamenané žiadne zmluvné strany")
      expect_no_typed_value(html)
    end

    it "does not appear in the list pages with a typed value, and the list shows no name for it" do
      person_contract
      get "/"

      expect(response).to have_http_status(:ok)
      expect_no_typed_value(response.body)
    end

    it "is left out of the CSV and JSON exports (only IČO parties are exported), with no typed value" do
      person_contract

      get "/export.csv"
      rows = CSV.parse(response.body.delete_prefix("﻿"), headers: true)
      expect(rows.size).to eq(1)
      expect(rows.first["party_names"]).to eq("Obec Vzorová")
      expect(rows.first["party_icos"]).to eq("00000000")
      expect_no_typed_value(response.body)
      expect(response.body).not_to include("Fyzická osoba")

      get "/export.json"
      expect(JSON.parse(response.body).first["parties"]).to eq([{ "role" => "object", "ico" => "00000000",
                                                                  "name" => "Obec Vzorová" }])
      expect_no_typed_value(response.body)
    end

    it "cannot be found through the party filter, by the typed name or by the placeholder" do
      person_contract

      ["Ján Testovací", "Testovací", "Fyzická osoba", "Fyzická"].each do |needle|
        get "/", params: { party: needle }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("/#{person_contract.id}\""), "party=#{needle}"
      end
    end

    it "has no supplier page and does not enter the statistics rankings" do
      person_contract

      get "/statistics"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Fyzická osoba")
      expect_no_typed_value(response.body)
    end

    it "keeps every typed value out of the parties table" do
      person_contract
      stored = Decidim::ContractsSk::Party.all.flat_map { |p| p.attributes.values }.join(" ")

      expect_no_typed_value(stored)
    end
  end

  describe "a company counterparty" do
    it "is published with its name, IČO and seat, and is exported" do
      company_contract

      get "/#{company_contract.id}"
      expect(response.body).to include("Stavby Vzorové s.r.o.", "12345678", "Dlhá 5, Nikde")
      expect(response.body).to include("/suppliers/12345678")

      get "/export.csv"
      row = CSV.parse(response.body.delete_prefix("﻿"), headers: true).first
      expect(row["party_icos"]).to eq("12345678 | 00000000")
      expect(row["party_names"]).to eq("Stavby Vzorové s.r.o. | Obec Vzorová")

      get "/suppliers/12345678"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Stavby Vzorové s.r.o.")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
