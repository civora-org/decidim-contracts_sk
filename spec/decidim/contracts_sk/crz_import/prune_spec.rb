# frozen_string_literal: true

require "spec_helper"

# Cleanup of mirrors imported before the sync was scoped to the
# organization's own contracts (civora-org/civora-platform#145).
# rubocop:disable RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CrzImport::Prune, :db do
  include_context "with the CRZ scope configured"

  before { migrate_engine_schema! }

  # The organization's IČO is the fixture authority's ("00000001"):
  # own on either side, a foreign municipality's mirror, a mirror with no
  # parties at all, and an editorial record with only a foreign party.
  let!(:records) do
    {
      own_authority: mirror_with_parties("600", authority_ico: "00000001"),
      own_supplier: mirror_with_parties("601", authority_ico: "00000009", supplier_ico: "00000001"),
      foreign: mirror_with_parties("602", authority_ico: "00000009"),
      foreign_without_parties: create_imported_record("603"),
      editorial: Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-700")).tap do |contract|
        contract.parties.create!(role: "object", name: "Iná obec", ico: "00000009")
      end
    }
  end

  def mirror_with_parties(source_id, authority_ico:, supplier_ico: "00000002")
    create_imported_record(source_id).tap do |contract|
      contract.parties.create!(role: "object", name: "Objednávateľ #{source_id}", ico: authority_ico)
      contract.parties.create!(role: "contractor", name: "Dodávateľ #{source_id}", ico: supplier_ico)
    end
  end

  def ids(*keys)
    records.values_at(*keys).map(&:id)
  end

  it "counts the out-of-scope mirrors without deleting anything on a dry run" do
    result = described_class.call(organization: organization, ico: "00000001")

    aggregate_failures do
      expect(result.matched).to eq(2)
      expect(result.confirmed).to be(false)
      expect(Decidim::ContractsSk::Contract.count).to eq(5)
    end
  end

  it "deletes only out-of-scope CRZ mirrors (and their parties) when confirmed" do
    result = described_class.call(organization: organization, ico: "00000001", confirm: true)

    aggregate_failures do
      expect(result.matched).to eq(2)
      expect(result.confirmed).to be(true)
      expect(Decidim::ContractsSk::Contract.pluck(:id)).to match_array(ids(:own_authority, :own_supplier, :editorial))
      expect(Decidim::ContractsSk::Party.where(contract_id: ids(:foreign, :foreign_without_parties))).to be_empty
    end
  end
end
# rubocop:enable RSpec/ExampleLength
