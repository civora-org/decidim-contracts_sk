# frozen_string_literal: true

# ---------------------------------------------------------------------------
# The derived effectiveness status of a contract that must be published in
# the CRZ (civora-org/civora-platform#202, § 47a ods. 1 and 2 OZ): "zatiaľ
# neúčinná" until the filing is confirmed, then effective from the day after
# publication, or from the agreed later date when that is later. Pure module
# examples first, then the Contract instance twins and the shared
# crz_attention scope (:db).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CrzDeadline do # rubocop:disable RSpec/MultipleDescribes
  let(:today) { Date.new(2026, 10, 13) }

  # A plain stand-in answering what the rule reads from a contract.
  def record(overrides = {})
    attrs = { source: "editorial", state: "published", crz_filed_at: nil, crz_published_on: nil,
              agreed_effective_on: nil }.merge(overrides)
    Struct.new(*attrs.keys).new(*attrs.values)
  end

  def effectiveness(overrides = {})
    described_class.effectiveness(record(overrides), today: today)
  end

  describe ".effectiveness" do
    it "is not effective while the CRZ filing is not confirmed" do
      expect(effectiveness).to eq(:not_effective)
      expect(effectiveness(state: "draft")).to eq(:not_effective)
    end

    it "stays not effective without a filing even if an agreed date lies in the past" do
      expect(effectiveness(agreed_effective_on: today - 30)).to eq(:not_effective)
    end

    it "becomes effective the day AFTER the CRZ publication, not on it" do
      filed = Time.utc(2026, 10, 1, 9)

      expect(effectiveness(crz_filed_at: filed, crz_published_on: today)).to eq(:not_effective)
      expect(effectiveness(crz_filed_at: filed, crz_published_on: today - 1)).to eq(:effective)
    end

    it "falls back to the filing day when the CRZ publication date is unknown" do
      expect(effectiveness(crz_filed_at: Time.utc(2026, 10, 13, 8))).to eq(:not_effective)
      expect(effectiveness(crz_filed_at: Time.utc(2026, 10, 12, 8))).to eq(:effective)
    end

    it "respects an agreed later effectiveness date" do
      published = { crz_filed_at: Time.utc(2026, 9, 1), crz_published_on: Date.new(2026, 9, 1) }

      expect(effectiveness(**published, agreed_effective_on: today + 1)).to eq(:not_effective)
      expect(effectiveness(**published, agreed_effective_on: today)).to eq(:effective)
      expect(effectiveness(**published, agreed_effective_on: today - 5)).to eq(:effective)
    end

    it "ignores an agreed date EARLIER than the day after publication (the law sets the floor)" do
      expect(effectiveness(crz_filed_at: Time.utc(2026, 10, 13, 8), crz_published_on: today,
                           agreed_effective_on: today - 10)).to eq(:not_effective)
    end

    it "is not applicable to CRZ mirrors and terminal records" do
      expect(effectiveness(source: "crz")).to eq(:not_applicable)
      expect(effectiveness(state: "archived")).to eq(:not_applicable)
      expect(effectiveness(state: "rejected")).to eq(:not_applicable)
    end
  end

  describe ".effective_on" do
    it "is nil until the filing is confirmed" do
      expect(described_class.effective_on(record(crz_published_on: today))).to be_nil
    end

    it "is the day after publication, or the later agreed date" do
      filed = Time.utc(2026, 9, 1)

      expect(described_class.effective_on(record(crz_filed_at: filed, crz_published_on: Date.new(2026, 9, 1))))
        .to eq(Date.new(2026, 9, 2))
      expect(described_class.effective_on(record(crz_filed_at: filed, crz_published_on: Date.new(2026, 9, 1),
                                                 agreed_effective_on: Date.new(2026, 11, 1)))).to eq(Date.new(2026,
                                                                                                              11, 1))
    end
  end
end

RSpec.describe Decidim::ContractsSk::Contract, :db do
  let(:today) { Date.new(2026, 10, 13) }

  before { migrate_engine_schema! }

  def create_contract!(overrides = {})
    described_class.create!(contract_attributes({ signed_on: Date.new(2026, 8, 1) }.merge(overrides)))
  end

  it "persists the optional agreed effectiveness date and defaults it to NULL" do
    expect(create_contract!.agreed_effective_on).to be_nil
    expect(create_contract!(reference: "ZP-2", agreed_effective_on: Date.new(2026, 12, 1)).reload
                                                                                          .agreed_effective_on)
      .to eq(Date.new(2026, 12, 1))
  end

  it "derives the status from the stored stamps" do
    unfiled = create_contract!(reference: "U")
    pending = create_contract!(reference: "P", crz_filed_at: Time.utc(2026, 10, 1),
                               crz_published_on: Date.new(2026, 10, 1), agreed_effective_on: Date.new(2026, 11, 1))
    effective = create_contract!(reference: "E", crz_filed_at: Time.utc(2026, 10, 1),
                                 crz_published_on: Date.new(2026, 10, 1))
    mirror = create_contract!(reference: "M", source: "crz", source_id: "900000001")

    expect(unfiled.crz_effectiveness(today: today)).to eq(:not_effective)
    expect(unfiled.crz_effective_on).to be_nil
    expect(pending.crz_effectiveness(today: today)).to eq(:not_effective)
    expect(pending.crz_effective_on).to eq(Date.new(2026, 11, 1))
    expect(effective.crz_effectiveness(today: today)).to eq(:effective)
    expect(effective.crz_effective_on).to eq(Date.new(2026, 10, 2))
    expect(mirror.crz_effectiveness(today: today)).to eq(:not_applicable)
  end

  it "keeps the crz_attention scope equal to overdue plus due soon, unfiled only" do
    overdue = create_contract!(reference: "O", signed_on: Date.new(2026, 6, 1))
    soon = create_contract!(reference: "S", signed_on: Date.new(2026, 7, 20))
    create_contract!(reference: "OK", signed_on: Date.new(2026, 10, 1))
    create_contract!(reference: "F", signed_on: Date.new(2026, 6, 1), crz_filed_at: Time.utc(2026, 7, 1))

    expect(described_class.crz_attention(today)).to contain_exactly(overdue, soon)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
