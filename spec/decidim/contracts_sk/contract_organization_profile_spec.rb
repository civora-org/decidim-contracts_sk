# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for ContractOrganizationProfile (civora-org/civora-platform#211,
# step P1): one row per organization, an allowlisted JSON header. Synthetic
# identifiers only (an invented town, a documentation IBAN).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Decidim::ContractsSk::ContractOrganizationProfile, :db do
  before { migrate_engine_schema! }

  let(:header) do
    { "official_name" => "Obec Vzorová", "seat" => "Hlavná 1, 000 00 Vzorová", "ico" => "00000000",
      "dic" => "2020000000", "bank_name" => "Vzorová banka", "iban" => "SK31 1200 0000 1987 4263 7541",
      "bic" => "VZORSKBX", "statutory_name" => "Ing. Vzorová Starostka", "statutory_title" => "starostka",
      "signing_place" => "Vzorová" }
  end

  def build_profile(overrides = {})
    described_class.new({ organization: organization, header: header }.merge(overrides))
  end

  it "allowlists exactly the ten header keys" do
    expect(described_class::HEADER_KEYS).to eq(
      %w[official_name seat ico dic bank_name iban bic statutory_name statutory_title signing_place]
    )
  end

  it "persists a full header and reads it back" do
    profile = build_profile.tap(&:save!)

    expect(profile.reload.header).to eq(header)
    expect(profile.header_value(:official_name)).to eq("Obec Vzorová")
  end

  it "defaults to an empty header, which is valid" do
    profile = described_class.create!(organization: organization)

    expect(profile.header).to eq({})
    expect(profile.header_value("ico")).to be_nil
  end

  describe "the key allowlist" do
    it "rejects unknown keys" do
      profile = build_profile(header: header.merge("mayor_phone" => "000"))

      expect(profile).not_to be_valid
      expect(profile.errors).to be_added(:header, :unknown_keys, keys: "mayor_phone")
    end

    it "rejects unknown keys given as symbols too (keys are normalized to strings first)" do
      profile = build_profile(header: { official_name: "Obec Vzorová", note: "x" })

      expect(profile).not_to be_valid
      expect(profile.errors).to be_added(:header, :unknown_keys, keys: "note")
    end

    it "accepts symbol keys of allowlisted names and stores them as strings" do
      profile = build_profile(header: { official_name: "Obec Vzorová" }).tap(&:save!)

      expect(profile.reload.header).to eq("official_name" => "Obec Vzorová")
    end

    it "only reads allowlisted keys through header_value" do
      profile = build_profile.tap(&:save!)
      profile.update_column(:header, header.merge("secret" => "x"))

      expect(profile.reload.header_value("secret")).to be_nil
    end

    it "requires the header to be a JSON object" do
      ["text", %w[official_name], 5].each do |bad|
        profile = build_profile(header: bad)

        expect(profile).not_to be_valid, "#{bad.inspect} must be rejected"
        expect(profile.errors).to be_added(:header, :invalid)
      end
    end

    it "rejects non-string and over-long values" do
      expect(build_profile(header: { "seat" => { "a" => 1 } })).not_to be_valid
      expect(build_profile(header: { "seat" => "x" * 256 })).not_to be_valid
      expect(build_profile(header: { "seat" => "x" * 255 })).to be_valid
    end
  end

  describe "the IČO" do
    it "must be exactly 8 digits" do
      expect(build_profile(header: { "ico" => "12345678" })).to be_valid
      %w[1234567 123456789 1234567a 12 345 678].each do |ico|
        expect(build_profile(header: { "ico" => ico })).not_to be_valid, "#{ico.inspect} must be rejected"
      end
    end

    it "is not rewritten into a valid shape (surrounding whitespace is the only thing trimmed)" do
      expect(build_profile(header: { "ico" => " 12345678 " }).tap(&:valid?).header["ico"]).to eq("12345678")
      expect(build_profile(header: { "ico" => "1234 5678" })).not_to be_valid
    end
  end

  describe "the IBAN (loose)" do
    it "accepts spaced and lower-case IBANs of plausible shape" do
      ["SK3112000000198742637541", "sk31 1200 0000 1987 4263 7541", "DE89370400440532013000"].each do |iban|
        expect(build_profile(header: { "iban" => iban })).to be_valid, "#{iban.inspect} must pass"
      end
    end

    it "rejects obvious non-IBANs" do
      bad = ["12345", "SK31", "SK3112", "XX", "1231200000019874263754",
             "SK31 1200 0000 1987 4263 7541 99999999999999"]
      bad.each do |iban|
        expect(build_profile(header: { "iban" => iban })).not_to be_valid, "#{iban.inspect} must fail"
      end
    end

    it "does not verify the mod-97 check digits (loose by decision)" do
      expect(build_profile(header: { "iban" => "SK00 1200 0000 1987 4263 7541" })).to be_valid
    end
  end

  describe "one profile per organization" do
    it "refuses a second row for the same organization" do
      build_profile.save!

      duplicate = build_profile
      expect(duplicate).not_to be_valid
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "lets another organization have its own, and scopes reads by tenant" do
      mine = build_profile.tap(&:save!)
      other = Decidim::Organization.create!
      theirs = build_profile(organization: other, header: { "official_name" => "Iná obec" }).tap(&:save!)

      expect(described_class.where(organization: organization)).to contain_exactly(mine)
      expect(described_class.where(organization: other)).to contain_exactly(theirs)
    end

    it "requires an organization" do
      expect(build_profile(organization: nil)).not_to be_valid
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
