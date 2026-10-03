# frozen_string_literal: true

# ---------------------------------------------------------------------------
# DB-backed specs for the Contract model's CRZ deadline scopes and instance
# helpers (§ 47a OZ, civora-org/civora-platform#124). Opt in with
# CONTRACTS_SK_DB=1 (in-memory SQLite, the engine's real migrations).
#
# The central contract: an instance's deadline status AGREES with its scope
# membership, for every record of a varied set and every "today" of a range
# that crosses month ends — the scopes compare signed_on against
# Ruby-computed thresholds, the instances use the same arithmetic.
# ---------------------------------------------------------------------------

require "spec_helper"

# Several related facts per example by design (a scope's whole membership).
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Contract, :db do
  include ActiveSupport::Testing::TimeHelpers

  let(:contract_class) { described_class }
  let(:today) { Date.new(2026, 6, 1) }

  before { migrate_engine_schema! }

  def create_contract!(reference, overrides = {})
    contract_class.create!(contract_attributes({ reference: reference,
                                                 signed_on: Date.new(2026, 3, 10) }.merge(overrides)))
  end

  def references(scope)
    scope.pluck(:reference).sort
  end

  describe ".crz_deadline_tracked" do
    it "includes unfiled editorial records in every non-terminal state, signed or not" do
      %w[draft in_review returned approved published].each_with_index do |state, index|
        create_contract!("T-#{index}", state: state)
      end
      create_contract!("T-UNSIGNED", signed_on: nil)

      expect(references(contract_class.crz_deadline_tracked))
        .to eq(%w[T-0 T-1 T-2 T-3 T-4 T-UNSIGNED])
    end

    it "excludes records confirmed as filed (crz_filed_at) but keeps a typed crz_url tracked (#125)" do
      create_contract!("FILED", crz_url: "https://crz.gov.sk/zmluva/1/", crz_filed_at: Time.current)
      create_contract!("TYPED-URL", crz_url: "https://crz.gov.sk/zmluva/2/")
      create_contract!("NULL", crz_url: nil)

      expect(references(contract_class.crz_deadline_tracked)).to eq(%w[NULL TYPED-URL])
    end

    it "excludes CRZ mirrors and terminal states" do
      create_contract!("MIRROR", source: "crz", source_id: "900000001", state: "published",
                                 crz_url: nil)
      create_contract!("REJECTED", state: "rejected")
      create_contract!("ARCHIVED", state: "archived")
      create_contract!("LIVE")

      expect(references(contract_class.crz_deadline_tracked)).to eq(%w[LIVE])
    end
  end

  describe ".crz_overdue and .crz_due_soon" do
    it "splits tracked records at the deadline boundaries (deadline = signed_on + 3 months)" do
      create_contract!("OVERDUE", signed_on: Date.new(2026, 2, 28))   # deadline 2026-05-28
      create_contract!("TODAY", signed_on: Date.new(2026, 3, 1))      # deadline 2026-06-01
      create_contract!("EDGE14", signed_on: Date.new(2026, 3, 15))    # deadline 2026-06-15, 14 left
      create_contract!("EDGE15", signed_on: Date.new(2026, 3, 16))    # deadline 2026-06-16, 15 left
      create_contract!("LATER", signed_on: Date.new(2026, 5, 20))

      expect(references(contract_class.crz_overdue(today))).to eq(%w[OVERDUE])
      expect(references(contract_class.crz_due_soon(today))).to eq(%w[EDGE14 TODAY])
    end

    it "leaves records without a signing date out of both scopes" do
      create_contract!("UNSIGNED", signed_on: nil)

      expect(contract_class.crz_overdue(today)).to be_empty
      expect(contract_class.crz_due_soon(today)).to be_empty
    end

    it "leaves filed, mirror and terminal records out of both scopes" do
      create_contract!("FILED", crz_filed_at: Time.current, signed_on: Date.new(2025, 1, 1))
      create_contract!("MIRROR", source: "crz", source_id: "900000001", state: "published",
                                 signed_on: Date.new(2025, 1, 1))
      create_contract!("REJECTED", state: "rejected", signed_on: Date.new(2025, 1, 1))

      expect(contract_class.crz_overdue(today)).to be_empty
    end

    it "classifies a record signed 2027-02-28 as overdue on 2027-05-31 (month-end clamp)" do
      create_contract!("CLAMP", signed_on: Date.new(2027, 2, 28))

      expect(references(contract_class.crz_overdue(Date.new(2027, 5, 31)))).to eq(%w[CLAMP])
    end

    it "defaults today to Date.current" do
      create_contract!("OVERDUE", signed_on: Date.new(2026, 2, 28))

      travel_to(Time.zone.local(2026, 6, 1, 12)) do
        expect(references(contract_class.crz_overdue)).to eq(%w[OVERDUE])
      end
    end
  end

  describe "instance helpers" do
    it "computes the deadline, days left and status" do
      record = create_contract!("A", signed_on: Date.new(2026, 3, 10))

      expect(record.crz_deadline).to eq(Date.new(2026, 6, 10))
      expect(record.crz_days_left(today: Date.new(2026, 6, 1))).to eq(9)
      expect(record.crz_deadline_status(today: Date.new(2026, 6, 1))).to eq(:due_soon)
      expect(record.crz_deadline_status(today: Date.new(2026, 6, 11))).to eq(:overdue)
      expect(record.crz_deadline_status(today: Date.new(2026, 5, 1))).to eq(:ok)
    end

    it "reports :unknown for a tracked record without a signing date and :untracked otherwise" do
      expect(create_contract!("U", signed_on: nil).crz_deadline_status(today: today)).to eq(:unknown)
      expect(create_contract!("F", crz_filed_at: Time.current)
               .crz_deadline_status(today: today)).to eq(:untracked)
      expect(create_contract!("R", state: "rejected").crz_deadline_status(today: today)).to eq(:untracked)
    end

    it "agrees with scope membership for a varied set across month ends and leap years" do
      records = []
      dates = [Date.new(2026, 11, 28), Date.new(2026, 11, 30), Date.new(2027, 2, 28), Date.new(2027, 11, 29),
               Date.new(2027, 11, 30), Date.new(2028, 2, 29), Date.new(2028, 3, 31), nil]
      dates.each_with_index do |signed, index|
        records << create_contract!("SET-#{index}", signed_on: signed)
      end
      records << create_contract!("SET-FILED", crz_filed_at: Time.current,
                                               signed_on: Date.new(2026, 11, 30))
      records << create_contract!("SET-REJECTED", state: "rejected", signed_on: Date.new(2026, 11, 30))

      (Date.new(2027, 2, 1)..Date.new(2028, 7, 31)).step(3).each do |day|
        overdue = contract_class.crz_overdue(day).to_a
        due_soon = contract_class.crz_due_soon(day).to_a
        records.each do |record|
          status = record.crz_deadline_status(today: day)
          expect(overdue.include?(record)).to eq(status == :overdue), "overdue #{record.reference} on #{day}"
          expect(due_soon.include?(record)).to eq(status == :due_soon), "due_soon #{record.reference} on #{day}"
        end
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
