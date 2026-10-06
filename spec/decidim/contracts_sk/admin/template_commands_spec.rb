# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db specs for the template form and the CreateTemplate / UpdateTemplate /
# DestroyTemplate commands (civora-org/civora-platform#127), against the real
# migrations on in-memory SQLite. Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

admin_ns = Decidim::ContractsSk::Admin

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/DescribeClass
RSpec.describe "contract template commands", :db do
  before { migrate_engine_schema! }

  let(:template_class) { Decidim::ContractsSk::Template }
  let(:form) { admin_ns::TemplateForm.new(name: "Rental", title_pattern: "Rental - ", currency: "EUR") }

  describe admin_ns::TemplateForm do
    it "validates like the model: name required, currency in the vocabulary, IČO blank or 8 digits" do
      expect(described_class.new(name: "x")).to be_valid
      expect(described_class.new(name: "")).not_to be_valid
      expect(described_class.new(name: "x", currency: "USD")).not_to be_valid
      expect(described_class.new(name: "x", object_party_name: "M", object_party_ico: "123")).not_to be_valid
      expect(described_class.new(name: "x", object_party_ico: "12345678")).not_to be_valid
      expect(described_class.new(name: "x", object_party_name: "M", object_party_ico: "12345678")).to be_valid
    end

    it "defaults the currency to EUR and has no organization attribute (tenancy is never form input)" do
      expect(described_class.new.currency).to eq("EUR")
      expect(described_class.attribute_names).not_to include("organization", "decidim_organization_id")
    end
  end

  describe admin_ns::CreateTemplate do
    def call(template_form = form, org: organization)
      described_class.call(template_form, organization: org)
    end

    it "creates a template in the given organization from the form" do
      events = nil
      expect { events = call }.to change(template_class, :count).by(1)

      template = events[:ok]
      expect(template.organization).to eq(organization)
      expect([template.name, template.title_pattern, template.currency]).to eq(["Rental", "Rental - ", "EUR"])
    end

    it "answers :invalid and writes nothing for an invalid form" do
      expect do
        expect(call(admin_ns::TemplateForm.new(name: ""))).to have_key(:invalid)
      end.not_to change(template_class, :count)
    end

    it "answers :invalid with a :taken name error for a duplicate name, but only within the organization" do
      call
      duplicate = admin_ns::TemplateForm.new(name: "Rental")

      expect { expect(call(duplicate)).to have_key(:invalid) }.not_to change(template_class, :count)
      expect(duplicate.errors).to be_of_kind(:name, :taken)

      other = Decidim::Organization.create!
      expect(call(admin_ns::TemplateForm.new(name: "Rental"), org: other)).to have_key(:ok)
    end

    it "reports the unique index as :taken when two requests race past the validation" do
      call
      allow_any_instance_of(template_class).to receive(:valid?).and_return(true) # rubocop:disable RSpec/AnyInstance
      duplicate = admin_ns::TemplateForm.new(name: "Rental")

      expect { expect(call(duplicate)).to have_key(:invalid) }.not_to change(template_class, :count)
      expect(duplicate.errors).to be_of_kind(:name, :taken)
    end
  end

  describe admin_ns::UpdateTemplate do
    let!(:template) { template_class.create!(organization: organization, name: "Rental", subject_matter: "Old") }

    def call(record, template_form)
      described_class.call(template_form, record)
    end

    it "updates the template in place from the form" do
      new_form = admin_ns::TemplateForm.new(name: "Rental v2", subject_matter: "New", currency: "EUR",
                                            object_party_name: "Mesto", object_party_ico: "00000001")

      expect(call(template, new_form)).to have_key(:ok)
      expect(template.reload.attributes.values_at("name", "subject_matter", "object_party_name"))
        .to eq(["Rental v2", "New", "Mesto"])
    end

    it "answers :invalid and leaves the template untouched for an invalid form" do
      expect(call(template, admin_ns::TemplateForm.new(name: ""))).to have_key(:invalid)
      expect(template.reload.name).to eq("Rental")
    end

    it "answers :invalid with a :taken error when renaming onto another template's name" do
      template_class.create!(organization: organization, name: "Works")
      rename = admin_ns::TemplateForm.new(name: "Works")

      expect(call(template, rename)).to have_key(:invalid)
      expect(rename.errors).to be_of_kind(:name, :taken)
      expect(template.reload.name).to eq("Rental")
    end

    it "does not resurrect a template removed in the meantime (the lock reloads the row)" do
      stale = template_class.find(template.id)
      template_class.where(id: template.id).delete_all

      expect(call(stale, form)).to have_key(:invalid)
      expect(template_class.count).to eq(0)
    end

    it "never moves a template to another organization" do
      other = Decidim::Organization.create!
      call(template, form)

      expect(template.reload.decidim_organization_id).to eq(organization.id)
      expect(template_class.where(organization: other)).to be_empty
    end
  end

  describe admin_ns::DestroyTemplate do
    let!(:template) { template_class.create!(organization: organization, name: "Rental") }

    it "removes the template and leaves contracts created from it untouched" do
      contract = admin_ns::CreateContractFromTemplate.call(
        admin_ns::ContractForm.new(title: "Rental - Shop", reference: "ZP-1"), template,
        user: author, organization: organization
      )[:ok]

      expect(described_class.call(template)).to have_key(:ok)
      expect(template_class.count).to eq(0)
      expect(Decidim::ContractsSk::Contract.find(contract.id).title).to eq("Rental - Shop")
    end

    it "answers :invalid for a template already removed by a concurrent request" do
      stale = template_class.find(template.id)
      template_class.where(id: template.id).delete_all

      expect(described_class.call(stale)).to have_key(:invalid)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/DescribeClass
