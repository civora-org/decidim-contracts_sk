# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's Contract model
# (M02-02-A, civora-org/civora-platform#55).
#
# The default run asserts class-level structure only (inheritance, table
# name, associations, validators, enum wiring, concern methods) — none of it
# touches a DB connection. The Decidim::ApplicationRecord /
# Decidim::Organization / Decidim::User stand-ins live in
# spec/support/contracts_sk_db_helpers.rb, loaded from spec_helper.rb before
# any spec file: the real ones live in decidim-core and cannot be required
# outside a full Rails app.
#
# The :db-tagged group exercises the model against the REAL migrations on an
# in-memory SQLite adapter. It is excluded by default (see
# spec_helper.rb); opting in via CONTRACTS_SK_DB=1 requires the sqlite3 gem,
# and the group skips with a clear message when it is absent.
#
# Once a dummy-app harness exists, delete the stand-ins and the explicit
# requires and let the application autoloader provide the real classes.
# ---------------------------------------------------------------------------

require "spec_helper"

engine_root = File.expand_path("../../..", __dir__)

require File.join(engine_root, "app/models/decidim/contracts_sk/application_record.rb")
require File.join(engine_root, "app/models/concerns/decidim/contracts_sk/contract_state.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/contract.rb")
# The contract's has_many targets: the association reflections below pin
# their namespace resolution, which requires the constants to be defined.
require File.join(engine_root, "app/models/decidim/contracts_sk/party.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/document.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/amendment.rb")

# The structural groups assert several related class-level facts per example
# and the :db group walks several scenarios, exceeding the default budgets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe Decidim::ContractsSk::Contract do
  let(:lifecycle) { Decidim::ContractsSk::ContractLifecycle }

  describe "class structure" do
    it "inherits from the engine's ApplicationRecord" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
    end

    it "maps to the prefixed contracts table" do
      expect(described_class.table_name).to eq("decidim_contracts_sk_contracts")
    end

    it "includes the ContractState concern" do
      expect(described_class.ancestors).to include(Decidim::ContractsSk::ContractState)
    end
  end

  describe "associations" do
    it "belongs to the tenant organization over the prefixed foreign key" do
      reflection = described_class.reflect_on_association(:organization)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("decidim_organization_id")
      expect(reflection.options[:class_name]).to eq("Decidim::Organization")
    end

    it "belongs to the authoring user over the prefixed foreign key" do
      reflection = described_class.reflect_on_association(:author)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("decidim_author_id")
      expect(reflection.options[:class_name]).to eq("Decidim::User")
    end

    it "has many parties in the engine namespace, destroyed with the contract" do
      reflection = described_class.reflect_on_association(:parties)

      expect(reflection.macro).to eq(:has_many)
      expect(reflection.klass).to eq(Decidim::ContractsSk::Party)
      expect(reflection.foreign_key).to eq("contract_id")
      expect(reflection.options[:dependent]).to eq(:destroy)
    end

    it "has many documents in the engine namespace, destroyed with the contract" do
      reflection = described_class.reflect_on_association(:documents)

      expect(reflection.macro).to eq(:has_many)
      expect(reflection.klass).to eq(Decidim::ContractsSk::Document)
      expect(reflection.foreign_key).to eq("contract_id")
      expect(reflection.options[:dependent]).to eq(:destroy)
    end

    it "has many amendments in the engine namespace, destroyed with the contract" do
      reflection = described_class.reflect_on_association(:amendments)

      expect(reflection.macro).to eq(:has_many)
      expect(reflection.klass).to eq(Decidim::ContractsSk::Amendment)
      expect(reflection.foreign_key).to eq("contract_id")
      expect(reflection.options[:dependent]).to eq(:destroy)
    end

    it "has many audit events as a polymorphic target, with no destroy cascade" do
      # The audit trail must survive contract deletion (the Decidim
      # ActionLog precedent), so the reflection must carry no dependent
      # option. A polymorphic has_many has no single klass to pin.
      reflection = described_class.reflect_on_association(:audit_events)

      expect(reflection.macro).to eq(:has_many)
      expect(reflection.options[:as]).to eq(:target)
      expect(reflection.options[:dependent]).to be_nil
    end
  end

  describe "validations" do
    it "requires a title of at most 255 characters" do
      validators = described_class.validators_on(:title)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      expect(validators.find { |v| v.is_a?(ActiveModel::Validations::LengthValidator) }.options[:maximum]).to eq(255)
    end

    it "requires an organization-scoped unique reference of at most 255 characters" do
      validators = described_class.validators_on(:reference)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      expect(validators.find { |v| v.is_a?(ActiveModel::Validations::LengthValidator) }.options[:maximum]).to eq(255)
      expect(validators.find { |v| v.is_a?(ActiveRecord::Validations::UniquenessValidator) }.options[:scope])
        .to eq(:decidim_organization_id)
    end

    it "requires a state" do
      expect(described_class.validators_on(:state))
        .to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
    end

    it "validates state inclusion against STRINGS, never the Symbol list" do
      inclusion = described_class.validators_on(:state).find do |validator|
        validator.is_a?(ActiveModel::Validations::InclusionValidator)
      end

      expect(inclusion.options[:in]).to eq(lifecycle::STATES.map(&:to_s))
      expect(inclusion.options[:in]).to all(be_a(String)) # a Symbol list silently invalidates every record
      expect(inclusion.options[:in]).to be_frozen # a mutable vocabulary could be corrupted through the validator
    end
  end

  describe "state enum" do
    it "derives STATE_VALUES from the lifecycle, never hand-enumerated" do
      expect(described_class::STATE_VALUES)
        .to eq(lifecycle::STATES.to_h { |state| [state, state.to_s] })
      expect(described_class::STATE_VALUES).to be_frozen
    end

    it "exposes states equal to STATE_VALUES, with keys matching the lifecycle" do
      # Rails stores enum values in a HashWithIndifferentAccess, so the
      # equality contract holds against the stringified mapping.
      expect(described_class.states).to eq(described_class::STATE_VALUES.stringify_keys)
      expect(described_class.states.keys.map(&:to_sym)).to match_array(lifecycle::STATES)
    end

    it "defines a predicate, a bang setter and both scopes for every state" do
      lifecycle::STATES.each do |state|
        expect(described_class.method_defined?(:"#{state}?")).to be(true)
        expect(described_class.method_defined?(:"#{state}!")).to be(true)
        expect(described_class.respond_to?(state.to_s)).to be(true)
        expect(described_class.respond_to?(:"not_#{state}")).to be(true)
      end
    end
  end

  describe "lifecycle behaviour (via ContractState)" do
    %i[
      transition_state!
      can_transition?
      allowed_events_for
      terminal?
      editable?
      publicly_visible?
      submit!
      return!
      approve!
      reject!
      publish!
      archive!
    ].each do |method_name|
      it "responds to ##{method_name}" do
        expect(described_class.method_defined?(method_name)).to be(true)
      end
    end
  end

  describe "database behaviour", :db do
    before { migrate_engine_schema! }

    it "defaults the state to draft on new and persisted records" do
      contract = described_class.new(contract_attributes)

      expect(contract.state).to eq("draft")

      contract.save!
      expect(contract.reload.state).to eq("draft")
    end

    it "raises RecordNotUnique when a second insert hits the (organization, reference) unique index" do
      # Both inserts bypass validations: the model's uniqueness validation
      # would otherwise reject the second row before it ever reaches the
      # database, and this example exists to pin the DB-level index.
      described_class.new(contract_attributes).save!(validate: false)

      expect do
        described_class.new(contract_attributes(title: "Duplicate reference")).save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "raises RecordInvalid on a duplicate reference through the validation path" do
      described_class.create!(contract_attributes)

      expect do
        described_class.create!(contract_attributes(title: "Duplicate reference"))
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "allows the same reference in a different organization" do
      described_class.create!(contract_attributes)

      other = described_class.create!(contract_attributes(organization: Decidim::Organization.create!))

      expect(other).to be_persisted
    end

    it "persists lifecycle transitions through the concern" do
      contract = described_class.create!(contract_attributes)

      expect(contract.submit!(by_role: :editor)).to equal(contract)
      expect(contract.reload.state).to eq("in_review")
      expect(contract).not_to be_editable
    end

    it "raises RecordInvalid on validation failures" do
      expect do
        described_class.create!(contract_attributes(title: ""))
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "raises ArgumentError when an unknown value is assigned through the enum layer" do
      contract = described_class.new(contract_attributes)

      # Rails 7.2 enums validate at assignment (assert_valid_value raises
      # for unknown values), so bogus input never even reaches the model's
      # inclusion validation — neither via the setter nor via []=.
      expect { contract.state = "bogus" }.to raise_error(ArgumentError)
      expect { contract[:state] = "bogus" }.to raise_error(ArgumentError)
    end

    it "is invalid when the column holds a state no enum assignment could produce" do
      # The inclusion validator's real job: guarding against DB corruption.
      # A raw SQL write bypasses the enum; on read the unknown string
      # deserializes to nil (EnumType#deserialize maps through the values),
      # and presence + inclusion invalidate the record.
      contract = described_class.create!(contract_attributes)
      ActiveRecord::Base.connection.execute(
        "UPDATE decidim_contracts_sk_contracts SET state = 'bogus' WHERE id = #{contract.id}"
      )

      expect(contract.reload.state).to be_nil
      expect(contract).not_to be_valid
      expect(contract.errors[:state]).to be_present
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
