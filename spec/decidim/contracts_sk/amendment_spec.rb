# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's Amendment model
# (M02-02-C, civora-org/civora-platform#57).
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
# Once a dummy-app harness exists, delete the stand-ins and the explicit
# requires and let the application autoloader provide the real classes.
# ---------------------------------------------------------------------------

require "spec_helper"

# The structural groups assert several related class-level facts per example
# and the :db group walks several scenarios, exceeding the default budgets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

engine_root = File.expand_path("../../..", __dir__)

require File.join(engine_root, "app/models/decidim/contracts_sk/application_record.rb")
require File.join(engine_root, "app/models/concerns/decidim/contracts_sk/contract_state.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/contract.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/amendment.rb")
# Contract's dependent: :destroy resolves ALL its associations on destroy,
# so the sibling models must be defined too.
require File.join(engine_root, "app/models/decidim/contracts_sk/party.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/document.rb")

RSpec.describe Decidim::ContractsSk::Amendment do
  describe "class structure" do
    it "inherits from the engine's ApplicationRecord" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
    end

    it "maps to the prefixed amendments table" do
      expect(described_class.table_name).to eq("decidim_contracts_sk_amendments")
    end
  end

  describe "associations" do
    it "belongs to the contract it revises" do
      reflection = described_class.reflect_on_association(:contract)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("contract_id")
      expect(reflection.klass).to eq(Decidim::ContractsSk::Contract)
    end
  end

  describe "validations" do
    it "requires a positive integer version, unique per contract" do
      validators = described_class.validators_on(:version)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      numericality = validators.find { |v| v.is_a?(ActiveModel::Validations::NumericalityValidator) }
      expect(numericality.options[:only_integer]).to be(true)
      expect(numericality.options[:greater_than]).to eq(0)
      expect(validators.find { |v| v.is_a?(ActiveRecord::Validations::UniquenessValidator) }.options[:scope])
        .to eq(:contract_id)
    end

    it "requires a summary of at most 255 characters" do
      validators = described_class.validators_on(:summary)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      expect(validators.find { |v| v.is_a?(ActiveModel::Validations::LengthValidator) }.options[:maximum]).to eq(255)
    end
  end

  describe "deferred behaviour" do
    # Both guards pin what M02-02-C deliberately leaves out so the #65 arc
    # cannot land silently: immutability and sequencing arrive there.
    it "defines no enums — version is a plain validated integer until #65" do
      expect(described_class.defined_enums).to be_empty
    end

    it "does not override readonly? — records stay mutable until #65" do
      expect(described_class.instance_method(:readonly?).owner).not_to eq(described_class)
    end
  end

  describe "database behaviour", :db do
    before { migrate_engine_schema! }

    let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

    def amendment_attributes(overrides = {})
      {
        contract: contract,
        version: 1,
        summary: "Extended delivery deadline"
      }.merge(overrides)
    end

    it "persists an amendment attached to a real contract" do
      amendment = described_class.create!(amendment_attributes(version: 2))

      expect(amendment).to be_persisted
      expect(amendment.reload.contract).to eq(contract)
    end

    it "raises RecordNotUnique when a second insert hits the (contract, version) unique index" do
      # Bypasses the model's uniqueness validation: this example exists to
      # pin the DB-level composite unique index.
      described_class.new(amendment_attributes).save!(validate: false)

      expect do
        described_class.new(amendment_attributes(summary: "Duplicate version")).save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "raises InvalidForeignKey when the contract reference points nowhere" do
      # Bypasses the belongs_to presence validation: this example exists to
      # pin the DB-level FK constraint onto the contracts table.
      expect do
        described_class.new(version: 1, summary: "Orphan revision", contract_id: 987_654).save!(validate: false)
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "destroys amendments with their contract" do
      amendment = described_class.create!(amendment_attributes)

      contract.destroy

      expect(described_class.exists?(amendment.id)).to be(false)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
