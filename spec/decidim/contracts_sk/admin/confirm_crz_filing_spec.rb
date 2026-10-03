# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for ConfirmCrzFiling (civora-org/civora-platform#125),
# run against the real migrations on an in-memory SQLite adapter (see
# spec/support/contracts_sk_db_helpers.rb; excluded from the default
# offline run). The CRZ client is stubbed at its exact boundary (the
# command's injection seam) with recorded-shape payloads from
# spec/support/crz_import_payloads.rb; the real FilingLookup,
# FilingComparison and lock machinery run.
#
# The lock-doctrine examples follow the deterministic "request-start copy"
# shape of the TransitionContract specs: a stale pre-loaded object, the row
# moved directly underneath it — no threads. The unique-index race is
# simulated at the write boundary (update! raising RecordNotUnique).
#
# Synthetic data only ("Obec Ukážková", fake IČO patterns), no real PII.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, Metrics/AbcSize
RSpec.describe Decidim::ContractsSk::Admin::ConfirmCrzFiling, :db do
  include_context "with the CRZ scope configured"

  let(:client_class) { Decidim::ContractsSk::CrzImport::Client }
  let(:client) { instance_double(client_class) }
  let(:crz_id) { "2142424" }
  let(:payload) { crz_payload(crz_id, "status_id" => 2, "published_at" => "2026-04-20") }
  let(:token) { Decidim::ContractsSk::CrzImport::Mapper.checksum(payload) }
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:audit_class) { Decidim::ContractsSk::AuditEvent }
  let(:roles) { %i[editor] }
  let(:contract) { create_editorial }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { roles }
    example.run
  ensure
    Decidim::ContractsSk.role_resolver = original
  end

  before do
    migrate_engine_schema!
    allow(client).to receive(:contract).with(crz_id).and_return(payload)
  end

  # An editorial, published record that matches the payload on every row.
  def create_editorial(overrides = {})
    record = contract_class.create!(
      contract_attributes({ reference: "UKÁŽKA-2026/#{crz_id}", state: "published",
                            amount: BigDecimal("1043.68") }.merge(overrides))
    )
    record.parties.create!(role: "object", name: "Obec Ukážková", ico: "00000001")
    record.parties.create!(role: "contractor", name: "Demo Dodávky s.r.o.", ico: "00000002")
    record
  end

  def call_command(target = contract, reason: nil, checksum: token, id: crz_id, user: author)
    described_class.call(target, crz_id: id, checksum: checksum, reason: reason, user: user, client: client)
  end

  def expect_untouched(record)
    fresh = record.reload
    expect(fresh.crz_filed_at).to be_nil
    expect(fresh.source_id).to be_nil
    expect(fresh.crz_url).to be_nil
    expect(fresh.crz_filing_reason).to be_nil
    expect(audit_class.count).to eq(0)
  end

  describe "a full match" do
    it "stamps the filing, keeps the record editorial and writes one crz_filed audit row" do
      events = call_command

      expect(events[:ok]).to eq(:filed)

      contract.reload
      expect(contract.crz_filed_at).to be_within(5.seconds).of(Time.current)
      expect(contract.crz_published_on).to eq(Date.new(2026, 4, 20))
      expect(contract.crz_url).to eq("https://crz.gov.sk/zmluva/2142424/")
      expect(contract.source_id).to eq("2142424")
      expect(contract.crz_filing_reason).to be_nil
      expect(contract.source).to eq("editorial")
      expect(contract.state).to eq("published")

      audit = audit_class.order(:id).last
      expect(audit_class.count).to eq(1)
      expect(audit.action).to eq("contract.crz_filed")
      expect(audit.target).to eq(contract)
      expect(audit.actor).to eq(author)
      expect(audit.organization).to eq(organization)
    end

    it "stores no published date when CRZ carries the 0000-00-00 sentinel" do
      payload["published_at"] = "0000-00-00"

      call_command

      expect(contract.reload.crz_published_on).to be_nil
      expect(contract.crz_filed_at).to be_present
    end

    it "refuses a reason on a clean match (no write, no audit)" do
      events = call_command(reason: "no differences, but let me explain")

      expect(events[:invalid]).to eq(:reason_rejected)
      expect_untouched(contract)
    end
  end

  describe "a mismatch or an unverifiable row" do
    before { contract.update!(amount: BigDecimal("999.00")) }

    it "refuses without a reason and changes nothing" do
      expect(call_command[:invalid]).to eq(:reason_required)
      expect(call_command(reason: "   ")[:invalid]).to eq(:reason_required)
      expect_untouched(contract)
    end

    it "files with a reason as an override: reason stored stripped, crz_filed_override audited" do
      events = call_command(reason: "  Amount was corrected in the CRZ after filing.  ")

      expect(events[:ok]).to eq(:filed_override)

      contract.reload
      expect(contract.crz_filed_at).to be_present
      expect(contract.crz_filing_reason).to eq("Amount was corrected in the CRZ after filing.")
      expect(audit_class.pluck(:action)).to eq(["contract.crz_filed_override"])
    end

    it "treats an unverifiable row like a mismatch" do
      contract.update!(amount: nil)

      expect(call_command[:invalid]).to eq(:reason_required)
      expect(call_command(reason: "amount not yet entered")[:ok]).to eq(:filed_override)
    end

    it "refuses an over-long reason before any network call" do
      events = call_command(reason: "x" * 1001)

      expect(events[:invalid]).to eq(:reason_rejected)
      expect(client).not_to have_received(:contract)
      expect_untouched(contract)
    end
  end

  describe "refusals before the lock" do
    it "answers :not_found for an unknown CRZ id and changes nothing" do
      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::NotFoundError)

      expect(call_command[:invalid]).to eq(:not_found)
      expect_untouched(contract)
    end

    it "answers :failed on a network failure, writing neither fields nor audit" do
      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::TransportError)

      expect(call_command[:invalid]).to eq(:failed)
      expect_untouched(contract)
    end

    it "answers :failed for an unreadable payload" do
      allow(client).to receive(:contract).with(crz_id).and_return({ "subject" => "no id" })

      expect(call_command[:invalid]).to eq(:failed)
    end

    it "answers :not_configured without a network call when the organization has no IČO" do
      Decidim::ContractsSk.crz_organization_ico_resolver = ->(_organization) {}

      expect(call_command[:invalid]).to eq(:not_configured)
      expect(client).not_to have_received(:contract)
      expect_untouched(contract)
    end

    it "answers :out_of_scope for a record of another organization" do
      payload["contracting_authority_cin"] = "00 000 009"
      payload["supplier_cin"] = "00 000 008"

      expect(call_command[:invalid]).to eq(:out_of_scope)
      expect_untouched(contract)
    end

    it "answers :withdrawn for CRZ status 4 and 5, even with a reason" do
      [4, 5].each do |status|
        payload["status_id"] = status

        expect(call_command(reason: "please")[:invalid]).to eq(:withdrawn)
      end
      expect_untouched(contract)
    end

    it "refuses a non-numeric CRZ id without a network call" do
      expect(call_command(id: "12/34")[:invalid]).to eq(:not_found)
      expect(client).not_to have_received(:contract)
    end

    context "when the user has no editor role" do
      let(:roles) { %i[reviewer] }

      it "refuses without a network call (defense in depth behind the permission layer)" do
        expect(call_command[:invalid]).to eq(:not_fileable)
        expect(client).not_to have_received(:contract)
        expect_untouched(contract)
      end
    end
  end

  describe "in-lock guards" do
    it "refuses a draft or an archived record" do
      %w[draft archived].each_with_index do |state, index|
        record = create_editorial(reference: "ZP-S-#{index}", state: state)

        expect(call_command(record)[:invalid]).to eq(:not_fileable)
        expect(record.reload.crz_filed_at).to be_nil
      end
    end

    it "refuses a CRZ mirror (never an editorial record)" do
      mirror = create_imported_record(crz_id)

      expect(call_command(mirror)[:invalid]).to eq(:not_fileable)
    end

    it "refuses an already filed record, keeping the first confirmation" do
      call_command
      first = contract.reload.crz_filed_at

      expect(call_command[:invalid]).to eq(:already_filed)
      expect(contract.reload.crz_filed_at).to eq(first)
      expect(audit_class.count).to eq(1)
    end

    it "re-reads the row under the lock: a stale copy of a record archived meanwhile is refused" do
      stale = contract_class.find(contract.id)
      contract.update_columns(state: "archived")

      expect(call_command(stale)[:invalid]).to eq(:not_fileable)
      expect(contract.reload.crz_filed_at).to be_nil
      expect(audit_class.count).to eq(0)
    end

    it "re-reads the row under the lock: a stale copy of a record filed meanwhile is refused" do
      stale = contract_class.find(contract.id)
      contract.update_columns(crz_filed_at: 1.hour.ago, source_id: crz_id)

      expect(call_command(stale)[:invalid]).to eq(:already_filed)
      expect(audit_class.count).to eq(0)
    end

    it "re-runs the comparison on the row as it is NOW: an amount edited after the preview needs a reason" do
      stale = contract_class.find(contract.id)
      contract.update_columns(amount: BigDecimal("5.00"))

      expect(call_command(stale)[:invalid]).to eq(:reason_required)
      expect(contract.reload.crz_filed_at).to be_nil
    end

    it "refuses with :stale when the official record changed since the preview" do
      expect(call_command(checksum: "token-of-an-older-payload")[:invalid]).to eq(:stale)
      expect(call_command(checksum: nil)[:invalid]).to eq(:stale)
      expect_untouched(contract)
    end

    it "refuses a record carrying a different source_id" do
      contract.update_columns(source_id: "999")

      expect(call_command[:invalid]).to eq(:not_fileable)
    end

    it "rolls the stamp back when the audit write fails (atomicity)" do
      allow(audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect(call_command[:invalid]).to eq(:not_fileable)
      expect(contract.reload.crz_filed_at).to be_nil
      expect(contract.source_id).to be_nil
    end
  end

  describe "the CRZ id already held by another record" do
    it "refuses when another editorial record holds the id" do
      create_editorial(reference: "ZP-HOLDER", source_id: crz_id)

      expect(call_command[:invalid]).to eq(:already_linked)
      expect(contract.reload.crz_filed_at).to be_nil
      expect(audit_class.count).to eq(0)
    end

    it "absorbs a pristine mirror: the mirror is destroyed, the id claimed, both audit rows written" do
      mirror = create_imported_record(crz_id)
      mirror.parties.create!(role: "contractor", name: "Demo Dodávky s.r.o.", ico: "00000002")

      events = call_command

      expect(events[:ok]).to eq(:filed)
      expect(contract_class.exists?(mirror.id)).to be(false)
      expect(Decidim::ContractsSk::Party.where(contract_id: mirror.id)).to be_empty
      expect(contract.reload.source_id).to eq(crz_id)
      expect(contract.source).to eq("editorial")
      expect(audit_class.order(:id).pluck(:action)).to eq(%w[contract.crz_mirror_absorbed contract.crz_filed])
      expect(audit_class.pluck(:target_id).uniq).to eq([contract.id])
    end

    {
      "an amendment" => lambda { |mirror, org, user|
        mirror.amendments.create!(version: 1, summary: "Dodatok", state: "draft", organization: org, author: user)
      },
      "a link" => lambda { |mirror, org, _user|
        mirror.links.create!(target_type: "Decidim::Organization", target_id: org.id)
      },
      "a document" => ->(mirror, _org, _user) { mirror.documents.create!(title: "Sken", kind: "annex") }
    }.each do |label, attach|
      it "refuses a mirror an editor has worked on (#{label}) and leaves it intact" do
        mirror = create_imported_record(crz_id)
        attach.call(mirror, organization, author)

        expect(call_command[:invalid]).to eq(:already_linked)
        expect(contract_class.exists?(mirror.id)).to be(true)
        expect_untouched(contract)
      end
    end

    it "reroutes a lost unique-index race to :already_linked, rolling the absorption back" do
      mirror = create_imported_record(crz_id)
      allow(contract).to receive(:update!).and_raise(ActiveRecord::RecordNotUnique)

      expect(call_command[:invalid]).to eq(:already_linked)
      expect(contract_class.exists?(mirror.id)).to be(true)
      expect(audit_class.count).to eq(0)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, Metrics/AbcSize
