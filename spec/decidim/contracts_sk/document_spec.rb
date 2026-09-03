# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's Document model
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
require File.join(engine_root, "app/models/decidim/contracts_sk/document.rb")
# Contract's dependent: :destroy resolves ALL its associations on destroy,
# so the sibling models must be defined too.
require File.join(engine_root, "app/models/decidim/contracts_sk/party.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/amendment.rb")

# The structural groups assert several related class-level facts per example
# and the :db group walks several scenarios, exceeding the default budgets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe Decidim::ContractsSk::Document do
  describe "class structure" do
    it "inherits from the engine's ApplicationRecord" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
    end

    it "maps to the prefixed documents table" do
      expect(described_class.table_name).to eq("decidim_contracts_sk_documents")
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

  describe "kind vocabulary" do
    it "exposes the approved kind vocabulary as frozen strings" do
      expect(described_class::KINDS).to eq(%w[contract crz_export annex other])
      expect(described_class::KINDS).to all(be_a(String)) # a Symbol list silently invalidates every record
      expect(described_class::KINDS).to be_frozen
    end

    it "derives KIND_VALUES from KINDS, never hand-enumerated" do
      expect(described_class::KIND_VALUES)
        .to eq(described_class::KINDS.to_h { |kind| [kind, kind] })
      expect(described_class::KIND_VALUES).to be_frozen
    end
  end

  describe "validations" do
    it "requires a kind within the frozen vocabulary" do
      validators = described_class.validators_on(:kind)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      inclusion = validators.find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }
      expect(inclusion.options[:in]).to eq(%w[contract crz_export annex other])
      expect(inclusion.options[:in]).to all(be_a(String))
      expect(inclusion.options[:in]).to be_frozen # a mutable vocabulary could be corrupted through the validator
    end

    it "requires a title of at most 255 characters" do
      validators = described_class.validators_on(:title)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      expect(validators.find { |v| v.is_a?(ActiveModel::Validations::LengthValidator) }.options[:maximum]).to eq(255)
    end
  end

  describe "kind enum" do
    it "exposes kinds equal to KIND_VALUES" do
      # Rails stores enum values in a HashWithIndifferentAccess, so the
      # equality contract holds against the stringified mapping.
      expect(described_class.kinds).to eq(described_class::KIND_VALUES.stringify_keys)
      expect(described_class.kinds.keys).to contain_exactly("contract", "crz_export", "annex", "other")
    end

    it "defines a predicate, a bang setter and both scopes for every kind" do
      described_class::KINDS.each do |kind|
        expect(described_class.method_defined?(:"#{kind}?")).to be(true)
        expect(described_class.method_defined?(:"#{kind}!")).to be(true)
        expect(described_class.respond_to?(kind)).to be(true)
        expect(described_class.respond_to?(:"not_#{kind}")).to be(true)
      end
    end

    # The "contract" default itself is behaviour: the migration spec pins the
    # column default structurally, and the :db group exercises it on a live
    # schema (Model.new needs the schema in Rails 7.2, so it cannot run here).
  end

  describe "database behaviour", :db do
    before { migrate_engine_schema! }

    let(:contract) do
      Decidim::ContractsSk::Contract.create!(contract_attributes)
    end

    def document_attributes(overrides = {})
      {
        contract: contract,
        title: "Signed contract scan"
      }.merge(overrides)
    end

    it "defaults the kind to contract on new and persisted records" do
      document = described_class.new(document_attributes)

      expect(document.kind).to eq("contract")

      document.save!
      expect(document.reload.kind).to eq("contract")
    end

    it "persists a document attached to a real contract" do
      document = described_class.create!(document_attributes(kind: "annex", file_name: "priloha-1.pdf"))

      expect(document).to be_persisted
      expect(document.reload.contract).to eq(contract)
      expect(document.reload).to be_annex
    end

    it "raises InvalidForeignKey when the contract reference points nowhere" do
      # Bypasses the belongs_to presence validation: this example exists to
      # pin the DB-level FK constraint onto the contracts table.
      expect do
        described_class.new(title: "Orphan scan", contract_id: 987_654).save!(validate: false)
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "raises NotNullViolation when title is written as NULL below the validation layer" do
      expect do
        described_class.new(document_attributes(title: nil)).save!(validate: false)
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "destroys documents with their contract" do
      document = described_class.create!(document_attributes)

      contract.destroy

      expect(described_class.exists?(document.id)).to be(false)
    end

    it "raises ArgumentError when an unknown value is assigned through the enum layer" do
      document = described_class.new(document_attributes)

      # Rails 7.2 enums validate at assignment, so bogus input never even
      # reaches the model's inclusion validation.
      expect { document.kind = "bogus" }.to raise_error(ArgumentError)
    end

    it "is invalid when the column holds a kind no enum assignment could produce" do
      # The inclusion validator's real job: guarding against DB corruption.
      # A raw SQL write bypasses the enum; on read the unknown string
      # deserializes to nil, and presence + inclusion invalidate the record.
      document = described_class.create!(document_attributes)
      ActiveRecord::Base.connection.execute(
        "UPDATE decidim_contracts_sk_documents SET kind = 'bogus' WHERE id = #{document.id}"
      )

      expect(document.reload.kind).to be_nil
      expect(document).not_to be_valid
      expect(document.errors[:kind]).to be_present
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
