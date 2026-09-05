# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the engine's AuditEvent model
# (M02-02-C, civora-org/civora-platform#57).
#
# The default run asserts class-level structure only (inheritance, table
# name, associations, validators, the readonly? override) — none of it
# touches a DB connection. The Decidim::ApplicationRecord /
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

RSpec.describe Decidim::ContractsSk::AuditEvent do
  describe "class structure" do
    it "inherits from the engine's ApplicationRecord" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
    end

    it "maps to the prefixed audit events table" do
      expect(described_class.table_name).to eq("decidim_contracts_sk_audit_events")
    end
  end

  describe "associations" do
    it "belongs to the tenant organization over the prefixed foreign key" do
      reflection = described_class.reflect_on_association(:organization)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("decidim_organization_id")
      expect(reflection.klass).to eq(Decidim::Organization)
    end

    it "belongs to the acting user over the prefixed foreign key" do
      reflection = described_class.reflect_on_association(:actor)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("decidim_user_id")
      expect(reflection.klass).to eq(Decidim::User)
    end

    it "belongs to a polymorphic target" do
      reflection = described_class.reflect_on_association(:target)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.foreign_key).to eq("target_id")
      expect(reflection.options[:polymorphic]).to be(true)
    end
  end

  describe "validations" do
    it "requires an action of at most 255 characters" do
      validators = described_class.validators_on(:action)

      expect(validators).to include(a_kind_of(ActiveModel::Validations::PresenceValidator))
      expect(validators.find { |v| v.is_a?(ActiveModel::Validations::LengthValidator) }.options[:maximum]).to eq(255)
    end
  end

  describe "append-only wiring" do
    it "overrides readonly? on the model itself, not an inherited default" do
      expect(described_class.instance_method(:readonly?).owner).to eq(described_class)
    end

    # The writable/readonly split itself is behaviour: the :db group proves
    # it (Model.new needs a schema in Rails 7.2, so it cannot run here).
  end

  describe "database behaviour", :db do
    before { migrate_engine_schema! }

    let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

    def audit_event_attributes(overrides = {})
      {
        organization: organization,
        actor: author,
        target: contract,
        action: "contract.publish"
      }.merge(overrides)
    end

    it "persists an audit event for a real contract" do
      event = described_class.create!(audit_event_attributes)

      expect(event).to be_persisted
      expect(event.reload.target).to eq(contract)
      expect(event.reload.organization).to eq(organization)
      expect(event.reload.actor).to eq(author)
      expect(event.reload.action).to eq("contract.publish")
    end

    it "reports a new record as writable and a persisted one as readonly" do
      expect(described_class.new).not_to be_readonly

      event = described_class.create!(audit_event_attributes)
      expect(event.reload).to be_readonly
    end

    it "raises ReadOnlyRecord on every model write path once persisted, leaving the row intact" do
      # The enforced append-only surface: save, update, update!, touch,
      # update_columns and destroy all check #readonly? and raise.
      event = described_class.create!(audit_event_attributes)

      expect { event.save }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.update(action: "forged") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.update!(action: "forged") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.touch }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.update_columns(action: "forged") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)

      # Nothing went through, not even the destroy attempt.
      expect(described_class.count).to eq(1)
      expect(event.reload.action).to eq("contract.publish")
    end

    it "raises NotNullViolation when action is written as NULL below the validation layer" do
      expect do
        described_class.new(audit_event_attributes(action: nil)).save!(validate: false)
      end.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "raises InvalidForeignKey when the organization reference points nowhere" do
      attributes = audit_event_attributes(organization: nil, decidim_organization_id: 987_654)
      expect { described_class.new(attributes).save!(validate: false) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "raises InvalidForeignKey when the actor reference points nowhere" do
      attributes = audit_event_attributes(actor: nil, decidim_user_id: 987_654)
      expect { described_class.new(attributes).save!(validate: false) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "scopes polymorphic target lookups by both type and id" do
      event = described_class.create!(audit_event_attributes)
      other_contract = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-002"))
      described_class.create!(audit_event_attributes(target: other_contract))

      expect(described_class.where(target: contract).to_a).to contain_exactly(event)
      expect(contract.audit_events.to_a).to contain_exactly(event)
    end

    it "keeps audit events when the contract is destroyed while destroying its scoped children" do
      # Dangling targets are by design (the Decidim ActionLog precedent):
      # the trail outlives what it observed, parties/documents/amendments
      # do not.
      party = Decidim::ContractsSk::Party.create!(contract: contract, role: "contractor", name: "Zeleň a.s.")
      document = Decidim::ContractsSk::Document.create!(contract: contract, title: "Signed contract scan")
      amendment = Decidim::ContractsSk::Amendment.create!(contract: contract, version: 1,
                                                          summary: "Revision",
                                                          organization: organization,
                                                          author: author)
      event = described_class.create!(audit_event_attributes)

      contract.destroy

      expect(described_class.exists?(event.id)).to be(true)
      expect(event.reload.target_id).to eq(contract.id)
      expect(Decidim::ContractsSk::Party.exists?(party.id)).to be(false)
      expect(Decidim::ContractsSk::Document.exists?(document.id)).to be(false)
      expect(Decidim::ContractsSk::Amendment.exists?(amendment.id)).to be(false)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
