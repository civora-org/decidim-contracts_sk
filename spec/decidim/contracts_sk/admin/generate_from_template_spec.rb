# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for GenerateFromTemplate (civora-org/civora-platform#211):
# the entry, the internal number, the four generated documents, regeneration,
# and every guard that must leave the database untouched. The Fake converter
# stands in for LibreOffice. Synthetic data only.
#
# Each guard example was mutation-checked (the guard commented out, the
# example went red, the guard restored).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::GenerateFromTemplate, :db do
  include_context "with a contract template"

  let(:year) { Time.zone.today.year }
  let(:other_organization) { Decidim::Organization.create! }

  def call(form = build_form, **options)
    described_class.call(form, template: template, user: author, organization: organization, **options)
  end

  def docx_xml(document)
    DocxFixtures.read_zip(document.file.download).fetch("word/document.xml").force_encoding("UTF-8")
  end

  def pdf_text(document)
    PDF::Reader.new(StringIO.new(document.file.download)).pages.map(&:text).join
  end

  def document_for(entry, variant, format, status: "current")
    entry.generated_documents.find_by!(variant: variant, file_format: format, status: status)
  end

  def table_counts
    [Decidim::ContractsSk::Contract, Decidim::ContractsSk::ContractTemplateEntry,
     Decidim::ContractsSk::GeneratedDocument, Decidim::ContractsSk::AuditEvent,
     Decidim::ContractsSk::ReferenceCounter].map(&:count)
  end

  describe "a new contract" do
    it "creates a draft with the entry, the number and four documents" do
      events = call

      expect(events).to have_key(:ok)
      contract = events[:ok]
      expect(contract).to be_persisted
      expect(contract.state).to eq("draft")
      expect(contract.title).to eq("Kúpna zmluva - parcela 1/1")
      expect(contract.reference).to eq("1/#{year}")
      expect(contract.amount).to eq(BigDecimal("3062.50"))
      expect(contract.signed_on).to eq(Date.new(2026, 12, 15))
      expect(contract.author).to eq(author)

      entry = contract.template_entry
      expect(entry.contract_template).to eq(template)
      expect(entry.internal_number).to eq("1/#{year}")
      expect(entry.last_generated_at).to be_present
      expect(entry.generated_documents.pluck(:variant, :file_format, :status))
        .to contain_exactly(%w[internal docx current], %w[internal pdf current],
                            %w[publication docx current], %w[publication pdf current])
      expect(entry.generated_documents.map { |d| d.file.attached? }).to all(be(true))
      expect(entry.generated_documents.map(&:checksum)).to all(match(/\A\h{64}\z/))
      expect(entry.generated_documents.map(&:template_version).uniq).to eq([template.version])
    end

    it "splits the values: personal ones only in the encrypted store, in canonical form" do
      entry = call[:ok].template_entry

      expect(entry.values).to include("predmet" => "Predaj pozemku parc. č. 1/1", "suma_celkom" => "3062.50",
                                      "plocha" => "12.5", "datum_ucinnosti" => "2027-01-01")
      expect(entry.values.keys).not_to include("kupujuci_meno", "kupujuci_adresa")
      expect(entry.personal_values).to eq("kupujuci_meno" => "Ján Testovací",
                                          "kupujuci_adresa" => "Ulica Nepravá 99, 000 00 Nikde")
      expect(entry.values.to_json).not_to include("Testovací", "Nepravá")
    end

    it "fills the header from the organization profile, the number, and the amount in words" do
      entry = call[:ok].template_entry
      internal = docx_xml(document_for(entry, "internal", "docx"))

      expect(internal).to include("Obec Vzorová", "00000000", "1/#{year}", "Ján Testovací", "3 062,50")
      expect(internal).to include("tritisícšesťdesiatdva eur a päťdesiat centov")
      expect(internal).to include("12,5", "1. 1. 2027", "15. 12. 2026")
    end

    it "hides the personal values in the publication copy and keeps them in the internal one" do
      entry = call[:ok].template_entry

      expect(pdf_text(document_for(entry, "internal", "pdf"))).to include("Jan Testovaci")
      %w[docx pdf].each do |format|
        document = document_for(entry, "publication", format)
        text = format == "docx" ? docx_xml(document) : pdf_text(document)
        expect(text).not_to include("Testovaci", "Testovací", "Nepravá", "Nikde")
        expect(text).to include("skryt")
      end
    end

    it "writes one audit event holding ids and timestamps, never a value" do
      contract = call[:ok]

      event = Decidim::ContractsSk::AuditEvent.sole
      expect(event.action).to eq("contract.generated_from_template")
      expect(event.target).to eq(contract)
      expect(event.actor).to eq(author)
      expect(event.organization).to eq(organization)
      expect(event.attributes.values.join(" ")).not_to match(/Testov|Nepravá|3062|Predaj/)
    end

    it "numbers the next contract 2 and starts a new sequence per organization" do
      call
      second = call(build_form({}, title: "Druhá zmluva"))
      expect(second[:ok].template_entry.internal_number).to eq("2/#{year}")

      other_template = build_template(organization: other_organization)
      other_profile = Decidim::ContractsSk::ContractOrganizationProfile.create!(organization: other_organization,
                                                                                header: organization_profile_header)
      other_user = Decidim::User.create!(organization: other_organization)
      expect(other_profile).to be_persisted
      other = described_class.call(build_form({}, for_template: other_template), template: other_template,
                                                                                 user: other_user,
                                                                                 organization: other_organization)
      expect(other[:ok].template_entry.internal_number).to eq("1/#{year}")
    end

    it "skips a number whose reference is already taken and moves the counter past it" do
      Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "1/#{year}"))
      Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "2/#{year}"))

      events = call

      expect(events[:ok].reference).to eq("3/#{year}")
      expect(events[:ok].template_entry.internal_number).to eq("3/#{year}")
      expect(Decidim::ContractsSk::ReferenceCounter.sole.last_value).to eq(3)
      expect(call(build_form({}, title: "Druhá"))[:ok].reference).to eq("4/#{year}")
    end

    it "uses the template's reference pattern" do
      patterned = build_template(organization: organization, lineage_key: "other", reference_pattern: "ZM-{YYYY}-{N}")

      events = described_class.call(build_form({}, for_template: patterned), template: patterned, user: author,
                                                                             organization: organization)

      expect(events[:ok].reference).to eq("ZM-#{year}-1")
    end
  end

  describe "regeneration" do
    let!(:contract) { call[:ok] }
    let(:changed_form) do
      build_form({ "kupujuci_meno" => "Jana Skúšobná", "suma_celkom" => "100" }, title: "Nový názov")
    end

    def regenerate(form = changed_form, record: contract)
      described_class.call(form, template: template, user: author, organization: organization, contract: record)
    end

    it "reuses the number, supersedes the previous documents and does not touch the counter" do
      entry = contract.template_entry
      old_ids = entry.generated_documents.pluck(:id)

      events = regenerate

      expect(events).to have_key(:ok)
      entry.reload
      expect(entry.internal_number).to eq("1/#{year}")
      expect(Decidim::ContractsSk::ReferenceCounter.sole.last_value).to eq(1)
      expect(entry.generated_documents.where(status: "superseded").pluck(:id)).to match_array(old_ids)
      expect(entry.generated_documents.where(status: "current").count).to eq(4)
      expect(entry.generated_documents.where(status: "current").pluck(:id) & old_ids).to be_empty
      expect(entry.personal_values["kupujuci_meno"]).to eq("Jana Skúšobná")
      expect(docx_xml(document_for(entry, "internal", "docx"))).to include("Jana Skúšobná", "1/#{year}")
      expect(contract.reload.title).to eq("Nový názov")
      expect(contract.amount).to eq(BigDecimal("100"))
      expect(Decidim::ContractsSk::AuditEvent.where(action: "contract.generated_from_template").count).to eq(2)
    end

    it "clears the redaction confirmation, because the documents changed" do
      contract.update!(redaction_confirmed_at: Time.current)

      regenerate

      expect(contract.reload.redaction_confirmed_at).to be_nil
    end

    it "keeps the old documents' files readable" do
      old = document_for(contract.template_entry, "internal", "docx")

      regenerate

      expect(old.reload.status).to eq("superseded")
      expect(old.file.download).to start_with("PK")
    end

    it "refuses a contract that left the editable states, even from a stale pre-loaded object" do
      stale = Decidim::ContractsSk::Contract.find(contract.id)
      expect(stale).to be_editable
      contract.update_columns(state: "approved")
      counts = table_counts

      events = regenerate(record: stale)

      expect(events).to have_key(:not_editable)
      expect(events).not_to have_key(:ok)
      expect(table_counts).to eq(counts)
      expect(contract.template_entry.reload.personal_values["kupujuci_meno"]).to eq("Ján Testovací")
    end

    it "regenerates against the pinned version even after the template is archived" do
      template.update!(status: "archived")

      expect(regenerate).to have_key(:ok)
    end

    it "refuses another template than the one the entry was written with" do
      other = build_template(organization: organization, lineage_key: "druha")
      counts = table_counts

      events = described_class.call(build_form({}, for_template: other), template: other, user: author,
                                                                         organization: organization, contract: contract)

      expect(events).to have_key(:invalid)
      expect(table_counts).to eq(counts)
    end

    it "extends an editable contract that has no entry yet, keeping its own reference" do
      plain = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "RUCNE-1"))

      events = call(build_form, contract: plain)

      expect(events).to have_key(:ok)
      expect(plain.reload.reference).to eq("RUCNE-1")
      expect(plain.template_entry.internal_number).to eq("2/#{year}")
      expect(plain.template_entry.generated_documents.count).to eq(4)
    end

    it "refuses a contract of another organization" do
      foreign_author = Decidim::User.create!(organization: other_organization)
      foreign = Decidim::ContractsSk::Contract.create!(
        contract_attributes(organization: other_organization, author: foreign_author)
      )
      counts = table_counts

      expect(call(build_form, contract: foreign)).to have_key(:invalid)
      expect(table_counts).to eq(counts)
    end
  end

  describe "guards that store nothing" do
    it "answers :redaction_failed when the publication copy leaks, and stores nothing" do
      leaky = lambda do |_docx|
        Decidim::ContractsSk::Templates::MinimalPdf.build(lines: ["Kupujuci: Jan Testovaci"], info: {})
      end
      Decidim::ContractsSk.pdf_converter = leaky
      counts = table_counts

      events = call

      expect(events).to have_key(:redaction_failed)
      expect(events).not_to have_key(:ok)
      expect(table_counts).to eq(counts)
      expect(ActiveStorage::Blob.where.not(filename: "kupna-zmluva.docx").count).to eq(0)
    end

    it "keeps the previous documents current when a regeneration fails the redaction check" do
      contract = call[:ok]
      Decidim::ContractsSk.pdf_converter = lambda do |_docx|
        Decidim::ContractsSk::Templates::MinimalPdf.build(lines: ["Kupujuci: Jana Skusobna"], info: {})
      end
      form = build_form({ "kupujuci_meno" => "Jana Skusobna" })

      events = described_class.call(form, template: template, user: author, organization: organization,
                                          contract: contract)

      expect(events).to have_key(:redaction_failed)
      expect(contract.template_entry.generated_documents.pluck(:status).uniq).to eq(["current"])
      expect(contract.template_entry.reload.personal_values["kupujuci_meno"]).to eq("Ján Testovací")
    end

    it "answers :conversion_failed when the converter fails, and stores nothing" do
      Decidim::ContractsSk.pdf_converter = ->(_docx) { raise Decidim::ContractsSk::Templates::PdfConverter::ConversionTimeout }
      counts = table_counts

      expect(call).to have_key(:conversion_failed)
      expect(table_counts).to eq(counts)
    end

    it "answers :header_incomplete with the missing keys when the profile lacks a header value" do
      profile.update!(header: { "official_name" => "Obec Vzorová" })
      counts = table_counts

      events = call

      expect(events[:header_incomplete]).to eq(["ico"])
      expect(table_counts).to eq(counts)
    end

    it "answers :header_incomplete when the organization has no profile at all" do
      profile.destroy!

      expect(call).to have_key(:header_incomplete)
    end

    it "refuses an invalid form" do
      counts = table_counts

      expect(call(build_form({ "predmet" => "" }))).to have_key(:invalid)
      expect(table_counts).to eq(counts)
    end

    it "refuses a template that was archived after the request loaded it (stale object)" do
      form = build_form
      Decidim::ContractsSk::ContractTemplate.find(template.id).update!(status: "archived")
      expect(template.status).to eq("active")
      counts = table_counts

      expect(described_class.call(form, template: template, user: author, organization: organization))
        .to have_key(:invalid)
      expect(table_counts).to eq(counts)
    end

    it "refuses another organization's template" do
      foreign = build_template(organization: other_organization)
      counts = table_counts

      events = described_class.call(build_form({}, for_template: foreign), template: foreign, user: author,
                                                                           organization: organization)

      expect(events).to have_key(:invalid)
      expect(table_counts).to eq(counts)
    end

    it "refuses a form built for a different template than the one passed" do
      other = build_template(organization: organization, lineage_key: "druha")

      events = described_class.call(build_form, template: other, user: author, organization: organization)

      expect(events).to have_key(:invalid)
    end

    it "rolls the counter back when the contract cannot be saved after the number was taken" do
      allow(Decidim::ContractsSk::Contract).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      counts = table_counts

      expect(call).to have_key(:invalid)
      expect(table_counts).to eq(counts)
      expect(Decidim::ContractsSk::ReferenceCounter.count).to eq(0)
    end

    it "answers :encryption_unavailable when the host has no encryption keys, and stores nothing" do
      allow(Decidim::ContractsSk::ContractTemplateEntry).to receive(:create!)
        .and_raise(ActiveRecord::Encryption::Errors::Configuration, "Missing Active Record encryption credential")
      counts = table_counts

      events = call

      expect(events).to have_key(:encryption_unavailable)
      expect(table_counts).to eq(counts)
    end

    it "answers :invalid when the template has no file" do
      template.file.purge
      counts = table_counts

      expect(call).to have_key(:invalid)
      expect(table_counts).to eq(counts)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
