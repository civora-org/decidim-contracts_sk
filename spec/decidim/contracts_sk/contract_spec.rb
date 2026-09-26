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
# The model class is provided by the Stage-1 dummy harness (spec/dummy); the
# Decidim::ApplicationRecord / Decidim::Organization / Decidim::User
# stand-ins it builds on live in spec/support/contracts_sk_db_helpers.rb
# (the dummy is AR-free by design).
# ---------------------------------------------------------------------------

require "spec_helper"

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

    it "has many links (project/result targets), destroyed with the contract" do
      # Links are record content like the child records above
      # (civora-org/civora-platform#87) — unlike the audit trail. The
      # association name deliberately diverges from the class name.
      reflection = described_class.reflect_on_association(:links)

      expect(reflection.macro).to eq(:has_many)
      expect(reflection.options[:class_name]).to eq("Decidim::ContractsSk::ContractLink")
      expect(reflection.foreign_key).to eq("contract_id")
      expect(reflection.options[:dependent]).to eq(:destroy)
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

  describe "content field validations (civora-org/civora-platform#75)" do
    it "keeps the D1 currency allowlist frozen and EUR-only" do
      expect(described_class::SUPPORTED_CURRENCIES).to eq(%w[EUR])
      expect(described_class::SUPPORTED_CURRENCIES).to be_frozen
    end

    it "validates amount as a non-negative, column-capped number, nil allowed" do
      numericality = described_class.validators_on(:amount).find do |validator|
        validator.is_a?(ActiveModel::Validations::NumericalityValidator)
      end

      expect(numericality.options[:greater_than_or_equal_to]).to eq(0)
      expect(numericality.options[:less_than_or_equal_to]).to eq(described_class::MAX_AMOUNT)
      expect(numericality.options[:allow_nil]).to be(true)
    end

    it "caps the amount at the decimal(12,2) column's exact ceiling" do
      # A BigDecimal on purpose: a Float literal of the same value is
      # inexact and would make the boundary comparison itself unreliable.
      expect(described_class::MAX_AMOUNT).to eq(BigDecimal("9999999999.99"))
      expect(described_class::MAX_AMOUNT).to be_frozen
    end

    it "validates currency inclusion against the D1 allowlist" do
      inclusion = described_class.validators_on(:currency).find do |validator|
        validator.is_a?(ActiveModel::Validations::InclusionValidator)
      end

      expect(inclusion.options[:in]).to eq(%w[EUR])
      expect(inclusion.options[:in]).to be_frozen
    end

    it "validates crz_url as an anchored http(s) URL, blank allowed" do
      format_validator = described_class.validators_on(:crz_url).find do |validator|
        validator.is_a?(ActiveModel::Validations::FormatValidator)
      end

      expect(format_validator.options[:with]).to eq(described_class::CRZ_URL_FORMAT)
      expect(format_validator.options[:allow_blank]).to be(true)

      # The anchor is load-bearing (#75 review round): Rails format: matches
      # unanchored by default, so without \A...\z an https:// embedded in
      # another scheme or in surrounding text would pass.
      https_url = "https://crz.gov.sk/record/123"
      http_url = "http://crz.gov.sk/record/123"
      full_url = "https://crz.gov.sk/record/123?year=2026"
      ftp_url = "ftp://crz.gov.sk/record/123"
      script_url = "javascript:alert(1)"
      smuggled_url = "javascript:alert(https://evil)"
      surrounded_url = "garbage text https://crz.gov.sk more"
      leading_newline_url = "\nhttps://crz.gov.sk/record/123"

      expect(https_url).to match(described_class::CRZ_URL_FORMAT)
      expect(http_url).to match(described_class::CRZ_URL_FORMAT)
      expect(full_url).to match(described_class::CRZ_URL_FORMAT)
      expect(ftp_url).not_to match(described_class::CRZ_URL_FORMAT)
      expect(script_url).not_to match(described_class::CRZ_URL_FORMAT)
      expect(smuggled_url).not_to match(described_class::CRZ_URL_FORMAT)
      expect(surrounded_url).not_to match(described_class::CRZ_URL_FORMAT)
      expect(leading_newline_url).not_to match(described_class::CRZ_URL_FORMAT)
    end
  end

  describe "import provenance (civora-org/civora-platform#85)" do
    it "keeps the import-status vocabulary frozen and pinned to the approved set" do
      expect(described_class::IMPORT_STATUSES).to eq(%w[pending succeeded failed stale])
      expect(described_class::IMPORT_STATUSES).to be_frozen
    end

    it "validates import_status inclusion against the vocabulary, nil allowed" do
      inclusion = described_class.validators_on(:import_status).find do |validator|
        validator.is_a?(ActiveModel::Validations::InclusionValidator)
      end

      expect(inclusion.options[:in]).to eq(described_class::IMPORT_STATUSES)
      expect(inclusion.options[:in]).to all(be_a(String))
      expect(inclusion.options[:in]).to be_frozen # a mutable vocabulary could be corrupted through the validator
      expect(inclusion.options[:allow_nil]).to be(true)
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

    describe "content fields (civora-org/civora-platform#75)" do
      it "persists the content fields with typed values and defaults currency to EUR" do
        attributes = contract_attributes(
          subject_matter: "Supply and installation of road signage",
          amount: BigDecimal("1250.50"),
          signed_on: Date.new(2026, 9, 1),
          effective_from: Date.new(2026, 8, 15),
          crz_url: "https://crz.gov.sk/record/123"
        )
        contract = described_class.create!(attributes)

        expect(contract.reload.amount).to eq(BigDecimal("1250.50"))
        expect(contract.subject_matter).to eq("Supply and installation of road signage")
        expect(contract.signed_on).to eq(Date.new(2026, 9, 1))
        # Retroactive effectivity (effective_from before signed_on) persists
        # untouched — the D2 decision: no cross-validation between the dates.
        expect(contract.effective_from).to eq(Date.new(2026, 8, 15))
        expect(contract.crz_url).to eq("https://crz.gov.sk/record/123")
        expect(contract.currency).to eq("EUR")
      end

      it "defaults currency to EUR on unpersisted records too" do
        expect(described_class.new(contract_attributes).currency).to eq("EUR")
      end

      it "rejects a negative amount" do
        contract = described_class.new(contract_attributes(amount: BigDecimal("-1")))

        expect(contract).not_to be_valid
        expect(contract.errors[:amount]).to be_present
      end

      it "rejects an amount beyond the decimal(12,2) column's ceiling" do
        # A bigger value would otherwise survive validation and blow up on
        # PostgreSQL hosts with ActiveRecord::RangeError at write time
        # (#75 review round).
        contract = described_class.new(contract_attributes(amount: BigDecimal("10000000000")))

        expect(contract).not_to be_valid
        expect(contract.errors[:amount]).to be_present
      end

      it "rejects an unsupported currency (the D1 allowlist is EUR-only)" do
        contract = described_class.new(contract_attributes(currency: "USD"))

        expect(contract).not_to be_valid
        expect(contract.errors[:currency]).to be_present
      end

      it "rejects a malformed CRZ URL" do
        contract = described_class.new(contract_attributes(crz_url: "ftp://crz.gov.sk/record/123"))

        expect(contract).not_to be_valid
        expect(contract.errors[:crz_url]).to be_present
      end

      it "rejects an https:// smuggled into another scheme through the real validator" do
        # The unanchored make_regexp product used to let this through — the
        # \A...\z anchor is what stops it (#75 review round).
        contract = described_class.new(contract_attributes(crz_url: "javascript:alert(https://evil)"))

        expect(contract).not_to be_valid
        expect(contract.errors[:crz_url]).to be_present
      end

      it "accepts a blank CRZ URL" do
        contract = described_class.new(contract_attributes(crz_url: nil))

        expect(contract).to be_valid
      end

      it "accepts retroactive effectivity (effective_from before signed_on, D2)" do
        attributes = contract_attributes(
          signed_on: Date.new(2026, 9, 1),
          effective_from: Date.new(2026, 1, 1)
        )
        contract = described_class.new(attributes)

        expect(contract).to be_valid
      end
    end

    describe "import provenance (civora-org/civora-platform#85)" do
      it "accepts nil and each approved import status" do
        expect(described_class.new(contract_attributes(import_status: nil))).to be_valid

        described_class::IMPORT_STATUSES.each do |status|
          contract = described_class.new(contract_attributes(import_status: status))

          expect(contract).to be_valid
        end
      end

      it "rejects an import status outside the approved vocabulary" do
        contract = described_class.new(contract_attributes(import_status: "bogus"))

        expect(contract).not_to be_valid
        expect(contract.errors[:import_status]).to be_present
      end
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
