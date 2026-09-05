# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's Amendment model
# (M02-05-B, civora-org/civora-platform#65; originally M02-02-C,
# civora-org/civora-platform#57).
#
# The default run asserts class-level structure only (inheritance, table
# name, associations, validators, the enum, the published scope and the
# readonly? override) — none of it touches a DB connection. The
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
# The model class is provided by the Stage-1 dummy harness (spec/dummy); the
# Decidim::ApplicationRecord / Decidim::Organization / Decidim::User
# stand-ins it builds on live in spec/support/contracts_sk_db_helpers.rb
# (the dummy is AR-free by design).
# ---------------------------------------------------------------------------

require "spec_helper"

# The structural groups assert several related class-level facts per example
# and the :db group walks several scenarios, exceeding the default budgets.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

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

    it "belongs to the tenant organization over the prefixed foreign key" do
      reflection = described_class.reflect_on_association(:organization)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("decidim_organization_id")
      expect(reflection.klass).to eq(Decidim::Organization)
    end

    it "belongs to the author over the prefixed foreign key" do
      reflection = described_class.reflect_on_association(:author)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("decidim_author_id")
      expect(reflection.klass).to eq(Decidim::User)
    end
  end

  describe "state enum" do
    it "defines exactly the draft/published state enum" do
      expect(described_class.defined_enums.keys).to eq(%w[state])
      expect(described_class.defined_enums["state"]).to eq("draft" => "draft", "published" => "published")
    end

    it "freezes the stored-string vocabulary" do
      expect(described_class::STATES).to eq(%w[draft published]).and be_frozen
      expect(described_class::STATE_VALUES).to be_frozen
    end
  end

  describe "published scope" do
    it "declares the published scope the public version history reads through" do
      # Offline-safe structural pin: building the relation itself would
      # type-cast :state against the (connection-bound) schema, so only the
      # scope's existence is asserted here — the real filtering is
      # behaviour, proven in the :db group below.
      expect(described_class).to respond_to(:published)
    end
  end

  describe "snapshot vocabulary" do
    it "pins exactly the contract's data-dictionary content fields (#75), minus the system stamps" do
      # published_at is a system stamp, not content (the #75 doctrine);
      # title/reference are identity fields rendered from the live record.
      expect(described_class::SNAPSHOT_FIELDS)
        .to eq(%w[subject_matter amount currency signed_on effective_from crz_url])
        .and be_frozen
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

    it "requires a state from the frozen vocabulary" do
      validators = described_class.validators_on(:state)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      inclusion = validators.find { |v| v.is_a?(ActiveModel::Validations::InclusionValidator) }
      expect(inclusion.options[:in]).to eq(described_class::STATES)
    end
  end

  describe "immutability wiring (#65, ADR-006)" do
    it "overrides readonly? on the model itself, not an inherited default" do
      expect(described_class.instance_method(:readonly?).owner).to eq(described_class)
    end

    # The writable/readonly split itself is behaviour: the :db group proves
    # it (Model.new needs a schema in Rails 7.2, so it cannot run here).
  end

  describe "database behaviour", :db do
    before { migrate_engine_schema! }

    let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes(state: "published")) }

    def amendment_attributes(overrides = {})
      {
        contract: contract,
        version: 1,
        summary: "Extended delivery deadline",
        organization: organization,
        author: author
      }.merge(overrides)
    end

    it "persists an amendment attached to a real contract, defaulting to draft" do
      amendment = described_class.create!(amendment_attributes(version: 2))

      expect(amendment).to be_persisted
      expect(amendment.reload.contract).to eq(contract)
      expect(amendment).to be_draft
      expect(amendment.published_at).to be_nil
      expect(amendment.content_snapshot).to be_nil
    end

    it "requires the explicit tenancy and attribution the schema adds (#65)" do
      expect { described_class.create!(amendment_attributes.merge(organization: nil, author: nil)) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "scopes .published to exactly the published amendments (ADR-006)" do
      draft = described_class.create!(amendment_attributes(version: 1))
      published = described_class.create!(amendment_attributes(version: 2, state: "published"))

      expect(described_class.published).to contain_exactly(published)
      expect(described_class.published).not_to include(draft)
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

    it "raises InvalidForeignKey when the organization reference points nowhere" do
      # Bypasses the belongs_to presence validation: pins the DB-level FK
      # onto the organizations table added by the #65 migration.
      expect do
        described_class.new(amendment_attributes(organization: nil, decidim_organization_id: 987_654))
                       .save!(validate: false)
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "round-trips a JSON content snapshot with string keys" do
      snapshot = {
        "subject_matter" => "Supply and installation of road signage",
        "amount" => "1250.5",
        "currency" => "EUR",
        "signed_on" => "2026-09-01",
        "effective_from" => "2026-08-15",
        "crz_url" => "https://crz.gov.sk/record/123"
      }
      amendment = described_class.create!(amendment_attributes.merge(content_snapshot: snapshot))

      expect(amendment.reload.content_snapshot).to eq(snapshot)
    end

    it "destroys amendments with their contract" do
      amendment = described_class.create!(amendment_attributes)

      contract.destroy

      expect(described_class.exists?(amendment.id)).to be(false)
    end

    describe "immutability (#65, ADR-006)" do
      it "reports new records and persisted drafts as writable" do
        expect(described_class.new).not_to be_readonly

        amendment = described_class.create!(amendment_attributes)
        expect(amendment.reload).not_to be_readonly
      end

      it "reports a persisted published amendment as readonly" do
        amendment = described_class.create!(amendment_attributes)

        amendment.update!(state: "published")

        expect(amendment.reload).to be_readonly
      end

      it "lets a draft be updated and destroyed" do
        amendment = described_class.create!(amendment_attributes)

        amendment.update!(summary: "Retitled draft")
        expect(amendment.reload.summary).to eq("Retitled draft")

        amendment.destroy
        expect(described_class.exists?(amendment.id)).to be(false)
      end

      it "raises ReadOnlyRecord on every model write path once published, leaving the row intact" do
        # The immutability surface mirrors AuditEvent's append-only one:
        # save, update, update!, touch and destroy all check #readonly?
        # and raise.
        amendment = described_class.create!(amendment_attributes)
        amendment.update!(state: "published")

        expect { amendment.reload.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
        expect { amendment.reload.update(summary: "forged") }.to raise_error(ActiveRecord::ReadOnlyRecord)
        expect { amendment.reload.update!(summary: "forged") }.to raise_error(ActiveRecord::ReadOnlyRecord)
        expect { amendment.reload.touch }.to raise_error(ActiveRecord::ReadOnlyRecord)
        expect { amendment.reload.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)

        # Nothing went through, not even the destroy attempt.
        expect(described_class.count).to eq(1)
        expect(amendment.reload.summary).to eq("Extended delivery deadline")
      end
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
