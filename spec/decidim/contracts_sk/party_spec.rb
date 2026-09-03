# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's Party model
# (M02-02-B, civora-org/civora-platform#56).
#
# The default run asserts class-level structure only (inheritance, table
# name, associations, frozen vocabulary, validators, enum wiring) — none of
# it touches a DB connection. The Decidim::ApplicationRecord /
# Decidim::Organization / Decidim::User stand-ins live in
# spec/support/contracts_sk_db_helpers.rb, loaded from spec_helper.rb before
# any spec file: the real ones live in decidim-core and cannot be required
# outside a full Rails app.
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

engine_root = File.expand_path("../../..", __dir__)

require File.join(engine_root, "app/models/decidim/contracts_sk/application_record.rb")
require File.join(engine_root, "app/models/concerns/decidim/contracts_sk/contract_state.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/contract.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/party.rb")
# Contract's dependent: :destroy resolves ALL its associations on destroy,
# so the sibling models must be defined too.
require File.join(engine_root, "app/models/decidim/contracts_sk/document.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/amendment.rb")

# The structural groups assert several related class-level facts per example
# and the :db group walks several scenarios, exceeding the default budgets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe Decidim::ContractsSk::Party do
  describe "class structure" do
    it "inherits from the engine's ApplicationRecord" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
    end

    it "maps to the prefixed parties table" do
      expect(described_class.table_name).to eq("decidim_contracts_sk_parties")
    end
  end

  describe "associations" do
    it "belongs to the contract it hangs off" do
      reflection = described_class.reflect_on_association(:contract)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("contract_id")
      expect(reflection.klass).to eq(Decidim::ContractsSk::Contract)
    end
  end

  describe "role vocabulary" do
    it "exposes the approved role vocabulary as frozen strings" do
      expect(described_class::ROLES).to eq(%w[object contractor])
      expect(described_class::ROLES).to all(be_a(String)) # a Symbol list silently invalidates every record
      expect(described_class::ROLES).to be_frozen
    end

    it "derives ROLE_VALUES from ROLES, never hand-enumerated" do
      expect(described_class::ROLE_VALUES)
        .to eq(described_class::ROLES.to_h { |role| [role, role] })
      expect(described_class::ROLE_VALUES).to be_frozen
    end
  end

  describe "validations" do
    it "requires a role within the frozen vocabulary" do
      validators = described_class.validators_on(:role)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      inclusion = validators.find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }
      expect(inclusion.options[:in]).to eq(%w[object contractor])
      expect(inclusion.options[:in]).to all(be_a(String))
      expect(inclusion.options[:in]).to be_frozen # a mutable vocabulary could be corrupted through the validator
    end

    it "requires a name of at most 255 characters" do
      validators = described_class.validators_on(:name)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      expect(validators.find { |v| v.is_a?(ActiveModel::Validations::LengthValidator) }.options[:maximum]).to eq(255)
    end

    it "constrains ico to blank or an exactly-8-digit identifier" do
      validators = described_class.validators_on(:ico)

      length = validators.find { |v| v.is_a?(ActiveModel::Validations::LengthValidator) }
      expect(length.options[:is]).to eq(8)

      format_validator = validators.find { |v| v.is_a?(ActiveModel::Validations::FormatValidator) }
      expect(format_validator.options[:with]).to eq(/\A\d{8}\z/)
      expect(format_validator.options[:allow_blank]).to be(true)
    end

    it "allows an address of at most 255 characters, or none" do
      validators = described_class.validators_on(:address)

      length = validators.find { |v| v.is_a?(ActiveModel::Validations::LengthValidator) }
      expect(length.options[:maximum]).to eq(255)
      expect(length.options[:allow_nil]).to be(true)
    end
  end

  describe "role enum" do
    it "exposes roles equal to ROLE_VALUES" do
      # Rails stores enum values in a HashWithIndifferentAccess, so the
      # equality contract holds against the stringified mapping.
      expect(described_class.roles).to eq(described_class::ROLE_VALUES.stringify_keys)
      expect(described_class.roles.keys).to contain_exactly("object", "contractor")
    end

    it "defines a predicate, a bang setter and both scopes for every role" do
      described_class::ROLES.each do |role|
        expect(described_class.method_defined?(:"#{role}?")).to be(true)
        expect(described_class.method_defined?(:"#{role}!")).to be(true)
        expect(described_class.respond_to?(role)).to be(true)
        expect(described_class.respond_to?(:"not_#{role}")).to be(true)
      end
    end

    # There is deliberately no default (see the enum comment in party.rb);
    # asserting that needs Model.new, which requires a schema in Rails 7.2,
    # so it lives in the :db group below.
  end

  describe "database behaviour", :db do
    before { migrate_engine_schema! }

    let(:contract) do
      Decidim::ContractsSk::Contract.create!(contract_attributes)
    end

    def party_attributes(overrides = {})
      {
        contract: contract,
        role: "contractor",
        name: "Zeleň a.s."
      }.merge(overrides)
    end

    it "persists a party attached to a real contract" do
      party = described_class.create!(party_attributes(role: "object"))

      expect(party).to be_persisted
      expect(party.reload.contract).to eq(contract)
      expect(party.reload).to be_object
    end

    it "sets no default: a new party must state its role explicitly" do
      expect(described_class.new.role).to be_nil
    end

    it "raises InvalidForeignKey when the contract reference points nowhere" do
      # Bypasses the belongs_to presence validation: this example exists to
      # pin the DB-level FK constraint onto the contracts table.
      expect do
        described_class.new(role: "object", name: "Obec Zelen", contract_id: 987_654).save!(validate: false)
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "raises NotNullViolation when role is written as NULL below the validation layer" do
      expect do
        described_class.new(party_attributes(role: nil)).save!(validate: false)
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "invalidates an ico that is not exactly 8 digits, while blank passes" do
      expect(described_class.new(party_attributes(ico: "12345678"))).to be_valid
      expect(described_class.new(party_attributes(ico: nil))).to be_valid
      expect(described_class.new(party_attributes(ico: "1234567"))).not_to be_valid
      expect(described_class.new(party_attributes(ico: "1234567a"))).not_to be_valid
    end

    it "destroys parties with their contract" do
      party = described_class.create!(party_attributes)

      contract.destroy

      expect(described_class.exists?(party.id)).to be(false)
    end

    it "raises ArgumentError when an unknown value is assigned through the enum layer" do
      party = described_class.new(party_attributes)

      # Rails 7.2 enums validate at assignment, so bogus input never even
      # reaches the model's inclusion validation.
      expect { party.role = "bogus" }.to raise_error(ArgumentError)
    end

    it "is invalid when the column holds a role no enum assignment could produce" do
      # The inclusion validator's real job: guarding against DB corruption.
      # A raw SQL write bypasses the enum; on read the unknown string
      # deserializes to nil, and presence + inclusion invalidate the record.
      party = described_class.create!(party_attributes)
      ActiveRecord::Base.connection.execute(
        "UPDATE decidim_contracts_sk_parties SET role = 'bogus' WHERE id = #{party.id}"
      )

      expect(party.reload.role).to be_nil
      expect(party).not_to be_valid
      expect(party.errors[:role]).to be_present
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
