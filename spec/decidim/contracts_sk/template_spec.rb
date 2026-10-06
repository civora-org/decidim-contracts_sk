# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the contract Template model (civora-org/civora-platform#127). The
# default run asserts structure only; the :db group runs against the real
# migrations on in-memory SQLite (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Template do
  describe "class structure" do
    it "inherits from the engine's ApplicationRecord and maps to the prefixed table" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
      expect(described_class.table_name).to eq("decidim_contracts_sk_templates")
    end

    it "belongs to its organization (by decidim_organization_id)" do
      organization = described_class.reflect_on_association(:organization)

      expect(organization.macro).to eq(:belongs_to)
      expect(organization.foreign_key).to eq("decidim_organization_id")
    end

    it "is not referenced by the contract (copy-on-create keeps no link back)" do
      expect(Decidim::ContractsSk::Contract.reflect_on_association(:template)).to be_nil
      expect(Decidim::ContractsSk::Contract.reflect_on_association(:templates)).to be_nil
    end
  end

  describe "party_skeleton", :db do
    before { migrate_engine_schema! }

    it "is nil without a party name and the object-party attributes with one" do
      expect(described_class.new.party_skeleton).to be_nil

      skeleton = described_class.new(object_party_name: "Mesto Demo", object_party_ico: "00000001",
                                     object_party_address: "").party_skeleton
      expect(skeleton).to eq(role: "object", name: "Mesto Demo", ico: "00000001", address: nil)
    end
  end

  describe "behaviour", :db do
    before { migrate_engine_schema! }

    def build_template(overrides = {})
      described_class.new({ organization: organization, name: "Rental of premises" }.merge(overrides))
    end

    it "persists a minimal template with the EUR default and has no template column on contracts" do
      template = build_template
      expect(template).to be_valid
      template.save!

      expect(template.reload.currency).to eq("EUR")
      expect(template.party_skeleton).to be_nil
      expect(Decidim::ContractsSk::Contract.column_names.grep(/template/)).to be_empty
    end

    it "requires a name of at most 255 characters" do
      expect(build_template(name: " ")).not_to be_valid
      expect(build_template(name: "n" * 256)).not_to be_valid
      expect(build_template(name: "n" * 255)).to be_valid
    end

    it "requires the organization" do
      expect(build_template(organization: nil)).not_to be_valid
    end

    it "keeps the name unique per organization only" do
      build_template.save!
      other_org = Decidim::Organization.create!

      duplicate = build_template
      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:name, :taken)
      expect(build_template(organization: other_org)).to be_valid
    end

    it "limits the currency to the supported vocabulary" do
      expect(build_template(currency: "USD")).not_to be_valid
      expect(build_template(currency: "")).not_to be_valid
    end

    it "caps the title pattern at 255 characters" do
      expect(build_template(title_pattern: "t" * 256)).not_to be_valid
      expect(build_template(title_pattern: "t" * 255)).to be_valid
    end

    it "validates the party skeleton like a party: IČO is blank or 8 digits, a name is needed with any detail" do
      expect(build_template(object_party_name: "Mesto", object_party_ico: "1234567")).not_to be_valid
      expect(build_template(object_party_name: "Mesto", object_party_ico: "1234567a")).not_to be_valid
      expect(build_template(object_party_name: "Mesto", object_party_ico: "12345678")).to be_valid
      expect(build_template(object_party_name: "Mesto", object_party_ico: "")).to be_valid
      expect(build_template(object_party_ico: "12345678")).not_to be_valid
      expect(build_template(object_party_address: "Main street 1")).not_to be_valid
      expect(build_template(object_party_name: "Mesto", object_party_address: "a" * 256)).not_to be_valid
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
