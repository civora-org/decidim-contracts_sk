# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Config-seam spec for Decidim::ContractsSk.crz_organization_ico_resolver
# (civora-org/civora-platform#145).
#
# Pins the fail-closed default and the normalization of the resolver's
# answer: only an exact 8-digit IČO (whitespace ignored) scopes the import;
# anything else — including a raising resolver — answers nil.
# ---------------------------------------------------------------------------

require "spec_helper"

RSpec.describe Decidim::ContractsSk do
  describe "crz_organization_ico seam (civora-org/civora-platform#145)" do
    let(:organization) { Object.new }

    around do |example|
      original = described_class.crz_organization_ico_resolver
      example.run
    ensure
      described_class.crz_organization_ico_resolver = original
    end

    it "resolves nothing by default, so an unconfigured host imports nothing" do
      expect(described_class.crz_organization_ico(organization)).to be_nil
    end

    it "normalizes a spaced IČO to its 8 digits" do
      described_class.crz_organization_ico_resolver = ->(_organization) { "00 313 271" }

      expect(described_class.crz_organization_ico(organization)).to eq("00313271")
    end

    it "rejects any answer that is not exactly 8 digits" do
      { "0031327" => nil, "003132711" => nil, "IČO 00313271" => nil, "" => nil, nil => nil }.each do |answer, expected|
        described_class.crz_organization_ico_resolver = ->(_organization) { answer }

        expect(described_class.crz_organization_ico(organization)).to eq(expected), answer.inspect
      end
    end

    it "fails closed when the resolver raises" do
      described_class.crz_organization_ico_resolver = ->(_organization) { raise "boom" }

      expect(described_class.crz_organization_ico(organization)).to be_nil
    end

    it "answers nil for a missing organization without calling the resolver" do
      calls = []
      described_class.crz_organization_ico_resolver = ->(organization) { calls << organization && "00313271" }

      expect([described_class.crz_organization_ico(nil), calls]).to eq([nil, []])
    end
  end

  describe Decidim::ContractsSk::CrzScope do
    let(:record) { { parties: [{ ico: "00000001" }, { ico: "00000002" }] } }

    it "is in scope when the organization IČO is on either party" do
      aggregate_failures do
        expect(described_class.in_scope?(record, "00000001")).to be(true)
        expect(described_class.in_scope?(record, "00000002")).to be(true)
      end
    end

    it "is out of scope for another IČO and fails closed without a configured IČO" do
      aggregate_failures do
        expect(described_class.in_scope?(record, "00000009")).to be(false)
        expect(described_class.in_scope?(record, nil)).to be(false)
        expect(described_class.in_scope?({ parties: [{ ico: nil }] }, nil)).to be(false)
      end
    end
  end
end
