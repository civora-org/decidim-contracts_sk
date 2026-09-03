# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's Document model
# (M02-02-B, civora-org/civora-platform#56).
#
# The default run asserts class-level structure only (inheritance, table
# name, associations, frozen vocabulary, validators, enum wiring) — none of
# it touches a DB connection. The stand-in loading pattern mirrors
# contract_spec.rb: a minimal Decidim::ApplicationRecord is defined before
# the engine model files are loaded, since the real one lives in decidim-core
# and cannot be required outside a full Rails app. Minimal stand-ins for
# Decidim::Organization / Decidim::User follow the same rule (the contract
# associations need them in the :db group).
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

# Workaround for activesupport 6.1.x on Ruby >= 3.3: ActiveSupport references
# ::Logger, which is no longer a default gem. Must load before ActiveSupport.
require "logger"

require "active_record"
require "active_support/concern"

# The structural groups assert several related class-level facts per example
# and the :db group walks several scenarios, exceeding the default budgets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

# Minimal stand-in for decidim-core's Decidim::ApplicationRecord.
unless defined?(Decidim::ApplicationRecord)
  module Decidim
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end

engine_root = File.expand_path("../../..", __dir__)

require File.join(engine_root, "app/models/decidim/contracts_sk/application_record.rb")
require File.join(engine_root, "app/models/concerns/decidim/contracts_sk/contract_state.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/contract.rb")
require File.join(engine_root, "app/models/decidim/contracts_sk/document.rb")
# Contract's dependent: :destroy resolves ALL its associations on destroy,
# so the sibling model must be defined too.
require File.join(engine_root, "app/models/decidim/contracts_sk/party.rb")

# Minimal stand-ins for the association targets: the Contract references
# them by class_name strings, but offline nothing else defines them. Inert in
# the structural run (no connection is opened at definition time).
unless defined?(Decidim::Organization)
  module Decidim
    Organization = Class.new(ActiveRecord::Base) do
      self.table_name = "decidim_organizations"
    end
  end
end

unless defined?(Decidim::User)
  module Decidim
    User = Class.new(ActiveRecord::Base) do
      self.table_name = "decidim_users"
    end
  end
end

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
    # Fixed migration lookups as plain methods, not lets: the migration
    # classes are deterministic engine identifiers, not per-example state
    # (same rationale as the structural migration specs). engine_root is a
    # method too, because a def cannot capture the file-level local.
    def engine_root
      File.expand_path("../../..", __dir__)
    end

    def contracts_migration_class
      require Dir.glob(File.join(engine_root, "db/migrate/*_create_decidim_contracts_sk_contracts.rb")).first
      CreateDecidimContractsSkContracts
    end

    def parties_migration_class
      require Dir.glob(File.join(engine_root, "db/migrate/*_create_decidim_contracts_sk_parties.rb")).first
      CreateDecidimContractsSkParties
    end

    def documents_migration_class
      require Dir.glob(File.join(engine_root, "db/migrate/*_create_decidim_contracts_sk_documents.rb")).first
      CreateDecidimContractsSkDocuments
    end

    let(:organization) { Decidim::Organization.create! }
    let(:author) { Decidim::User.create! }
    let(:contract) do
      Decidim::ContractsSk::Contract.create!(contract_attributes)
    end

    before do
      begin
        require "sqlite3"
      rescue LoadError
        skip "sqlite3 gem is not available; add it locally to run the CONTRACTS_SK_DB=1 group"
      end

      # Other :db groups in this process (the migration specs) may leave a
      # pooled connection — and its in-memory schema — behind: an identical
      # :memory: config reuses the live pool instead of opening a fresh
      # database. Cut the connection so this group starts from an empty one.
      ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
      # The documents table carries a real FK to the contracts table, so the
      # parent migration must come up first. Contract#destroy cascades into
      # BOTH child tables (dependent: :destroy), so the sibling parties
      # table must exist here too.
      contracts_migration_class.migrate(:up)
      parties_migration_class.migrate(:up)
      documents_migration_class.migrate(:up)
      ActiveRecord::Base.connection.create_table(:decidim_organizations, &:timestamps)
      ActiveRecord::Base.connection.create_table(:decidim_users, &:timestamps)
    end

    after do
      ActiveRecord::Base.connection_pool.disconnect! if ActiveRecord::Base.connected?
    end

    def contract_attributes(overrides = {})
      {
        organization: organization,
        author: author,
        title: "Road reconstruction",
        reference: "ZP-2026-001"
      }.merge(overrides)
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
