# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for GeneratedDocument (civora-org/civora-platform#211, step P1): the
# admin-only generated files. Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::GeneratedDocument, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:template) do
    Decidim::ContractsSk::ContractTemplate.create!(organization: organization, lineage_key: "kupna-zmluva",
                                                   version: 1, name: "Kúpna zmluva")
  end
  let(:entry) { Decidim::ContractsSk::ContractTemplateEntry.create!(contract: contract, contract_template: template) }

  def build_document(overrides = {})
    described_class.new({ contract: contract, entry: entry, variant: "internal", file_format: "docx",
                          generated_at: Time.current, template_version: 1 }.merge(overrides))
  end

  it "is valid, current by default, and holds a file through ActiveStorage" do
    document = build_document.tap(&:save!)
    document.file.attach(io: StringIO.new("%PDF-1.4"), filename: "zmluva.pdf", content_type: "application/pdf")

    expect(document.status).to eq("current")
    expect(document.reload.file).to be_attached
    expect(document.promoted_document).to be_nil
  end

  it "has no public surface: it is not the public Document model" do
    expect(described_class.ancestors).not_to include(Decidim::ContractsSk::Document)
    expect(described_class.table_name).to eq("decidim_contracts_sk_generated_documents")
    expect(Decidim::ContractsSk::Contract.reflect_on_association(:documents).klass)
      .to eq(Decidim::ContractsSk::Document)
  end

  it "validates the variant, format and status vocabularies" do
    %w[internal publication].each { |variant| expect(build_document(variant: variant)).to be_valid }
    %w[docx pdf].each { |format| expect(build_document(file_format: format)).to be_valid }
    %w[current superseded].each { |status| expect(build_document(status: status)).to be_valid }

    expect(build_document(variant: "public")).not_to be_valid
    expect(build_document(file_format: "odt")).not_to be_valid
    expect(build_document(status: "deleted")).not_to be_valid
    expect(build_document(variant: nil)).not_to be_valid
  end

  it "requires the contract, the entry, the generation time and a positive template version" do
    document = described_class.new

    expect(document).not_to be_valid
    expect(document.errors.attribute_names).to include(:contract, :entry, :generated_at, :template_version)
    expect(build_document(template_version: 0)).not_to be_valid
  end

  it "refuses an entry that belongs to another contract (tenancy follows the contract)" do
    other_contract = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-002"))
    document = build_document(contract: other_contract)

    expect(document).not_to be_valid
    expect(document.errors).to be_added(:entry, :invalid)
  end

  describe "promotion to a public document" do
    let(:public_document) do
      Decidim::ContractsSk::Document.create!(contract: contract, title: "Zmluva", kind: "contract")
    end

    it "links an existing public Document of the same contract" do
      document = build_document(file_format: "pdf", variant: "publication",
                                promoted_document: public_document).tap(&:save!)

      expect(document.reload.promoted_document).to eq(public_document)
    end

    it "refuses a Document of another contract" do
      other = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-002"))
      foreign = Decidim::ContractsSk::Document.create!(contract: other, title: "Cudzia", kind: "contract")
      document = build_document(promoted_document: foreign)

      expect(document).not_to be_valid
      expect(document.errors).to be_added(:promoted_document, :invalid)
    end

    it "does not block deleting the public document: the link is nulled" do
      document = build_document(promoted_document: public_document).tap(&:save!)

      public_document.destroy!

      expect(document.reload.promoted_document_id).to be_nil
    end
  end

  it "is destroyed with its contract" do
    build_document.save!

    expect { contract.destroy! }.to change(described_class, :count).by(-1)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
