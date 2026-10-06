# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's UserRole model (M03-06-B,
# civora-org/civora-platform#109). The default run asserts class-level
# structure only; the :db group runs against the real migrations on an
# in-memory SQLite adapter (CONTRACTS_SK_DB=1). Users and organizations are
# the anonymous stand-ins from spec/support/contracts_sk_db_helpers.rb.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::UserRole do
  describe "class structure" do
    it "inherits from the engine's ApplicationRecord and maps to the prefixed table" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
      expect(described_class.table_name).to eq("decidim_contracts_sk_user_roles")
    end

    it "draws its role vocabulary from ContractLifecycle::ROLES" do
      expect(described_class::ROLES).to eq(Decidim::ContractsSk::ContractLifecycle::ROLES.map(&:to_s))
    end

    it "belongs to a Decidim user and organization through the prefixed FKs" do
      user = described_class.reflect_on_association(:user)
      organization = described_class.reflect_on_association(:organization)

      expect(user.macro).to eq(:belongs_to)
      expect(user.foreign_key).to eq("decidim_user_id")
      expect(user.options[:class_name]).to eq("Decidim::User")
      expect(organization.macro).to eq(:belongs_to)
      expect(organization.foreign_key).to eq("decidim_organization_id")
      expect(organization.options[:class_name]).to eq("Decidim::Organization")
    end

    it "validates role inclusion and mirrors the unique index with a scoped uniqueness" do
      validators = described_class.validators_on(:role)
      inclusion = validators.find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }
      uniqueness = validators.find { |v| v.is_a?(ActiveRecord::Validations::UniquenessValidator) }

      expect(inclusion.options[:in]).to eq(%w[editor reviewer])
      expect(uniqueness.options[:scope]).to eq(%i[decidim_user_id decidim_organization_id])
    end
  end

  describe "database behaviour", :db do
    before { migrate_engine_schema! }

    let(:user) { Decidim::User.create!(organization: organization) }

    def role_attributes(overrides = {})
      { user: user, organization: organization, role: "editor" }.merge(overrides)
    end

    it "is valid and persisted for the editor and reviewer roles" do
      %w[editor reviewer].each do |role|
        record = described_class.create!(role_attributes(role: role))

        expect(record).to be_persisted
        expect(record.reload.user).to eq(user)
        expect(record.organization).to eq(organization)
      end
    end

    it "rejects roles outside the engine vocabulary" do
      ["admin", "", nil].each do |role|
        record = described_class.new(role_attributes(role: role))

        expect(record).not_to be_valid
        expect(record.errors[:role]).to be_present
      end
    end

    it "requires a user and an organization" do
      expect(described_class.new(role_attributes(user: nil))).not_to be_valid
      expect(described_class.new(role_attributes(organization: nil))).not_to be_valid
    end

    it "invalidates a duplicate (user, organization, role) at the model level" do
      described_class.create!(role_attributes)
      duplicate = described_class.new(role_attributes)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:role]).to be_present
    end

    it "raises RecordNotUnique for a duplicate written below the validation layer" do
      described_class.create!(role_attributes)

      expect do
        described_class.new(role_attributes).save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "lets one user hold both roles" do
      described_class.create!(role_attributes(role: "editor"))

      expect(described_class.new(role_attributes(role: "reviewer"))).to be_valid
    end

    it "lets two users hold the same role" do
      described_class.create!(role_attributes)
      other = Decidim::User.create!(organization: organization)

      expect(described_class.new(role_attributes(user: other))).to be_valid
    end

    it "rejects a grant whose user belongs to another organization (no cross-tenant grants)" do
      other_organization = Decidim::Organization.create!
      record = described_class.new(role_attributes(organization: other_organization))

      expect(record).not_to be_valid
      expect(record.errors[:user]).to be_present
    end

    it "raises InvalidForeignKey for user and organization references pointing nowhere" do
      expect do
        described_class.new(role_attributes(user: nil, decidim_user_id: 987_654)).save!(validate: false)
      end.to raise_error(ActiveRecord::InvalidForeignKey)
      expect do
        described_class.new(role_attributes(organization: nil, decidim_organization_id: 987_654))
                       .save!(validate: false)
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "raises NotNullViolation for a NULL role written below the validation layer" do
      expect do
        described_class.new(role_attributes(role: nil)).save!(validate: false)
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "scopes grants by organization" do
      other_organization = Decidim::Organization.create!
      other_user = Decidim::User.create!(organization: other_organization)
      mine = described_class.create!(role_attributes)
      described_class.create!(user: other_user, organization: other_organization, role: "editor")

      expect(described_class.where(decidim_organization_id: organization.id)).to contain_exactly(mine)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
