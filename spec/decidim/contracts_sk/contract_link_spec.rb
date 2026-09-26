# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's ContractLink model
# (M01-87, civora-org/civora-platform#87).
#
# The default run asserts class-level structure only (inheritance, table
# name, associations, validators) — none of it touches a DB connection. The
# Decidim::ApplicationRecord / Decidim::Organization / Decidim::User
# stand-ins live in spec/support/contracts_sk_db_helpers.rb, loaded from
# spec_helper.rb before any spec file: the real ones live in decidim-core
# and cannot be required outside a full Rails app.
#
# The :db-tagged group exercises the model against the REAL migrations on an
# in-memory SQLite adapter. It is excluded by default (see spec_helper.rb);
# opting in via CONTRACTS_SK_DB=1 requires the sqlite3 gem, and the group
# skips with a clear message when it is absent.
#
# The model class is provided by the Stage-1 dummy harness (spec/dummy).
# ---------------------------------------------------------------------------

require "spec_helper"

# The structural groups assert several related class-level facts per example
# and the :db group walks several scenarios, exceeding the default budgets.
# rubocop:disable RSpec/MultipleExpectations

RSpec.describe Decidim::ContractsSk::ContractLink do
  describe "class structure" do
    it "inherits from the engine's ApplicationRecord" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
    end

    it "maps to the prefixed contract links table" do
      expect(described_class.table_name).to eq("decidim_contracts_sk_contract_links")
    end
  end

  describe "associations" do
    it "belongs to the contract it hangs off" do
      reflection = described_class.reflect_on_association(:contract)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("contract_id")
      expect(reflection.klass).to eq(Decidim::ContractsSk::Contract)
    end

    it "belongs to an optional polymorphic target (dangling tolerated)" do
      reflection = described_class.reflect_on_association(:target)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("target_id")
      expect(reflection.options[:polymorphic]).to be(true)
      # A persisted link whose target row is gone must stay loadable —
      # the admin surface flags it, the public catalogue hides it.
      expect(reflection.options[:optional]).to be(true)
    end
  end

  describe "validations" do
    it "requires a target type and a target id" do
      %i[target_type target_id].each do |attribute|
        validators = described_class.validators_on(attribute)

        expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator)),
                              "missing presence on :#{attribute}"
      end
    end

    it "mirrors the DB's unique (contract_id, target_type, target_id) index" do
      validators = described_class.validators_on(:target_id)
      uniqueness = validators.find { |v| v.is_a?(ActiveRecord::Validations::UniquenessValidator) }

      expect(uniqueness).to be_present
      expect(uniqueness.options[:scope]).to eq(%i[contract_id target_type])
    end
  end

  describe "contract-side association" do
    it "is destroyed with its contract (record content, unlike the audit trail)" do
      reflection = Decidim::ContractsSk::Contract.reflect_on_association(:links)

      expect(reflection.macro).to eq(:has_many)
      expect(reflection.options[:class_name]).to eq("Decidim::ContractsSk::ContractLink")
      expect(reflection.options[:dependent]).to eq(:destroy)
    end
  end

  describe "database behaviour", :db do
    before { migrate_engine_schema! }

    let(:contract) do
      Decidim::ContractsSk::Contract.create!(contract_attributes)
    end

    def link_attributes(overrides = {})
      {
        contract: contract,
        target_type: "Decidim::Accountability::Result",
        target_id: 12
      }.merge(overrides)
    end

    it "persists a link attached to a real contract" do
      link = described_class.create!(link_attributes)

      expect(link).to be_persisted
      expect(link.reload.contract).to eq(contract)
      expect(link.target_id).to eq(12)
    end

    it "raises InvalidForeignKey when the contract reference points nowhere" do
      # Bypasses the belongs_to presence validation: this example exists to
      # pin the DB-level FK constraint onto the contracts table.
      expect do
        described_class.new(link_attributes(contract_id: 987_654)).save!(validate: false)
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "raises NotNullViolation when target_type is written as NULL below the validation layer" do
      expect do
        described_class.new(link_attributes(target_type: nil)).save!(validate: false)
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "invalidates a duplicate (contract, target) pair" do
      described_class.create!(link_attributes)
      duplicate = described_class.new(link_attributes)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:target_id]).to be_present
    end

    it "allows the same target on two different contracts" do
      described_class.create!(link_attributes)
      other_contract = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-002")
      )

      expect(described_class.new(link_attributes(contract: other_contract))).to be_valid
    end

    it "allows two different targets on the same contract" do
      described_class.create!(link_attributes)

      expect(described_class.new(link_attributes(target_id: 13))).to be_valid
    end

    it "tolerates a dangling target at the model level" do
      # The polymorphic target has no FK; a link whose target row is gone
      # (or never existed) stays a legal, persisted record.
      link = described_class.create!(link_attributes(target_id: 4_242_424))

      expect(link).to be_persisted
      expect(link.reload).to be_valid
    end

    it "destroys links with their contract" do
      link = described_class.create!(link_attributes)

      contract.destroy

      expect(described_class.exists?(link.id)).to be(false)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations
