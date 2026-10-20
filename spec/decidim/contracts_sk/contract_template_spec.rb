# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for ContractTemplate and ContractTemplateField (civora-org/
# civora-platform#211, step P1): validations, tenancy, versioning and the
# immutability of a version once an entry references it. Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::ContractTemplate, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

  def build_template(overrides = {})
    described_class.new({ organization: organization, lineage_key: "kupna-zmluva", version: 1,
                          name: "Kúpna zmluva" }.merge(overrides))
  end

  def create_template(overrides = {})
    build_template(overrides).tap(&:save!)
  end

  def use!(template)
    Decidim::ContractsSk::ContractTemplateEntry.create!(contract: contract, contract_template: template)
  end

  describe "validations" do
    it "is valid with the minimum attributes and starts as a draft" do
      template = build_template

      expect(template).to be_valid
      expect(template.status).to eq("draft")
    end

    it "requires an organization, a name and a lineage key" do
      template = build_template(organization: nil, name: nil, lineage_key: nil)

      expect(template).not_to be_valid
      expect(template.errors.attribute_names).to include(:organization, :name, :lineage_key)
    end

    it "accepts only kebab/snake ASCII lineage keys" do
      expect(build_template(lineage_key: "Kúpna zmluva")).not_to be_valid
      expect(build_template(lineage_key: "kupna_zmluva-2")).to be_valid
    end

    it "validates the status vocabulary" do
      expect(build_template(status: "archived")).to be_valid
      expect(build_template(status: "published")).not_to be_valid
    end

    it "requires a positive integer version" do
      expect(build_template(version: 0)).not_to be_valid
      expect(build_template(version: 1.5)).not_to be_valid
    end

    it "keeps (organization, lineage_key, version) unique" do
      create_template

      duplicate = build_template
      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_added(:version, :taken, value: 1)
      expect(build_template(version: 2)).to be_valid
    end

    it "backs the uniqueness with a database index" do
      create_template

      expect { build_template.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "lets two organizations use the same lineage key and version" do
      create_template
      other = Decidim::Organization.create!

      expect(build_template(organization: other)).to be_valid
    end

    it "refuses a creator from another organization" do
      stranger = Decidim::User.create!(organization: Decidim::Organization.create!)

      expect(build_template(created_by: stranger)).not_to be_valid
      expect(build_template(created_by: author)).to be_valid
    end
  end

  describe "tenancy" do
    it "scopes reads through the organization" do
      mine = create_template
      other = Decidim::Organization.create!
      theirs = create_template(organization: other)

      expect(described_class.where(organization: organization)).to contain_exactly(mine)
      expect(described_class.where(organization: other)).to contain_exactly(theirs)
    end
  end

  describe "file attachment" do
    it "holds a Word source through ActiveStorage" do
      template = create_template
      template.file.attach(io: StringIO.new("docx bytes"), filename: "zmluva.docx",
                           content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")

      expect(template.reload.file).to be_attached
    end
  end

  describe "immutability once an entry references the version" do
    let!(:template) { create_template(name: "Original", source_checksum: "abc") }

    it "reports used? only after an entry exists" do
      expect(template).not_to be_used
      use!(template)
      expect(template).to be_used
    end

    it "allows any change while the version is unused" do
      expect(template.update(name: "Renamed", reference_pattern: "ZM-{YYYY}-{N}")).to be(true)
    end

    it "refuses content changes to a used version" do
      use!(template)

      %i[name lineage_key reference_pattern source_filename source_checksum].each do |attribute|
        expect(template.update(attribute => "changed")).to be(false), "#{attribute} must be frozen"
        expect(template.errors).to be_added(:base, :immutable_once_used)
        template.reload
      end
      expect(template.update(version: 2)).to be(false)
    end

    it "refuses replacing the attached file of a used version" do
      template.file.attach(io: StringIO.new("one"), filename: "a.docx", content_type: "application/octet-stream")
      use!(template)
      template.reload

      template.file.attach(io: StringIO.new("two"), filename: "b.docx", content_type: "application/octet-stream")

      expect(template.save).to be(false)
      expect(template.errors).to be_added(:base, :immutable_once_used)
    end

    it "still lets the lifecycle status move (draft, active, archived)" do
      use!(template)

      expect(template.update(status: "active")).to be(true)
      expect(template.update(status: "archived")).to be(true)
    end

    it "catches a stale, pre-loaded instance (the guard reads the database, not the object)" do
      stale = described_class.find(template.id)
      use!(template)

      expect(stale.update(name: "Sneaky")).to be(false)
      expect(template.reload.name).to eq("Original")
    end

    it "refuses to destroy a used version" do
      use!(template)

      expect(template.destroy).to be(false)
      expect(described_class.exists?(template.id)).to be(true)
      expect(template.errors).not_to be_empty
    end

    it "destroys an unused version together with its fields" do
      template.fields.create!(key: "predmet", label: "Predmet")

      expect { template.destroy }.to change(Decidim::ContractsSk::ContractTemplateField, :count).by(-1)
    end

    it "does not freeze a sibling version of the same lineage" do
      use!(template)
      sibling = create_template(version: 2)

      expect(sibling.update(name: "Draft v2 edited")).to be(true)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
