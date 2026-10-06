# frozen_string_literal: true

require "spec_helper"

# The one-off backfill of the real CRZ publication date for mirrors imported
# before it was stored (civora-org/civora-platform#159). The client is a
# fake over the Client#contract seam: no transport, no network. Payloads use
# the live published_at format (UTC timestamp with microseconds).
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
RSpec.describe Decidim::ContractsSk::CrzImport::BackfillPublishedOn, :db do
  before { migrate_engine_schema! }

  let(:client_class) { Decidim::ContractsSk::CrzImport::Client }

  # Answers contract(id) from a { source_id => payload | Exception } table
  # and remembers the requested ids.
  let(:fake_client) do
    Class.new do
      attr_reader :requested

      def initialize(responses)
        @responses = responses
        @requested = []
      end

      def contract(id)
        @requested << id
        response = @responses.fetch(id)
        raise response if response.is_a?(Exception)

        response
      end
    end
  end

  let!(:undated) { create_imported_record("701") }
  let!(:other_undated) { create_imported_record("702") }
  let!(:dated) do
    create_imported_record("703").tap { |contract| contract.update_columns(crz_published_on: Date.new(2020, 2, 2)) }
  end
  let!(:editorial) do
    Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-EDITORIAL", source_id: "704"))
  end
  let!(:foreign) do
    create_imported_record("705").tap do |contract|
      contract.update_columns(decidim_organization_id: Decidim::Organization.create!.id)
    end
  end

  def payload(id, published_at)
    crz_payload(id, "published_at" => published_at)
  end

  def run(confirm: true, **responses)
    client = fake_client.new(responses)
    [described_class.call(organization: organization, client: client, confirm: confirm, pause: 0), client]
  end

  it "reports the candidates and fetches and writes nothing on a dry run" do
    result, client = run(confirm: false)

    aggregate_failures do
      expect(result.confirmed).to be(false)
      expect(result.candidate_ids).to eq(%w[701 702])
      expect(result.candidates).to eq(2)
      expect(client.requested).to be_empty
      expect(undated.reload.crz_published_on).to be_nil
    end
  end

  it "writes only the NULL mirrors of the organization when confirmed, in Bratislava calendar days" do
    result, client = run("701" => payload("701", "2026-03-01T23:30:00.000000Z"),
                         "702" => payload("702", "2015-11-06T17:58:31.000000Z"))

    aggregate_failures do
      expect(result.updated_ids).to eq(%w[701 702])
      expect(result.updated).to eq(2)
      expect(result.skipped).to eq(0)
      expect(result.failed).to eq(0)
      expect(undated.reload.crz_published_on).to eq(Date.new(2026, 3, 2))
      expect(other_undated.reload.crz_published_on).to eq(Date.new(2015, 11, 6))
      # Never fetched: a mirror that already has a date, an editorial record, another organization's mirror.
      expect(client.requested).to eq(%w[701 702])
      expect(dated.reload.crz_published_on).to eq(Date.new(2020, 2, 2))
      expect(editorial.reload.crz_published_on).to be_nil
      expect(foreign.reload.crz_published_on).to be_nil
    end
  end

  it "writes ONLY the date column: updated_at, checksum, provenance, parties and audit trail stay put" do
    undated.parties.create!(role: "object", name: "Obec Ukážková", ico: "00000001")
    snapshot = undated.reload.attributes.except("crz_published_on")

    expect { run("701" => payload("701", "2026-03-01T23:30:00.000000Z"), "702" => payload("702", "")) }
      .not_to change(Decidim::ContractsSk::AuditEvent, :count)

    aggregate_failures do
      expect(undated.reload.attributes.except("crz_published_on")).to eq(snapshot)
      expect(undated.checksum).to eq("outdated-checksum")
      expect(undated.parties.count).to eq(1)
    end
  end

  it "counts a blank, sentinel or garbage date as skipped and writes nothing for it" do
    result, = run("701" => payload("701", "0000-00-00"), "702" => payload("702", "garbage"))

    aggregate_failures do
      expect(result.skipped_ids).to eq(%w[701 702])
      expect(result.updated).to eq(0)
      expect(undated.reload.crz_published_on).to be_nil
    end
  end

  it "counts per-record errors as failed and carries on with the rest of the run" do
    result, client = run("701" => client_class::NotFoundError.new("gone"),
                         "702" => payload("702", "2026-04-20T10:00:00.000000Z"))

    aggregate_failures do
      expect(result.failed_ids).to eq(%w[701])
      expect(result.updated_ids).to eq(%w[702])
      expect(client.requested).to eq(%w[701 702])
      expect(undated.reload.crz_published_on).to be_nil
      expect(other_undated.reload.crz_published_on).to eq(Date.new(2026, 4, 20))
    end
  end

  it "counts transport, parse and structurally invalid payload errors as failed" do
    result, = run("701" => client_class::TransportError.new("down"),
                  "702" => { "no_id" => true })
    parse_result, = run("701" => client_class::ParseError.new("bad json"),
                        "702" => Decidim::ContractsSk::CrzImport::Mapper::Error.new("bad record"))

    aggregate_failures do
      expect(result.failed_ids).to eq(%w[701 702])
      expect(parse_result.failed_ids).to eq(%w[701 702])
      expect(result.updated).to eq(0)
    end
  end

  it "is idempotent: a second confirmed run has nothing left to do" do
    run("701" => payload("701", "2026-03-01T12:00:00.000000Z"), "702" => payload("702", "2026-03-02T12:00:00.000000Z"))

    result, client = run

    aggregate_failures do
      expect(result.candidates).to eq(0)
      expect(client.requested).to be_empty
    end
  end

  describe "throttling (ekosystem allows 60 requests a minute)" do
    let(:responses) do
      { "701" => payload("701", "2026-03-01T12:00:00.000000Z"), "702" => payload("702", "2026-03-02T12:00:00.000000Z") }
    end

    before { allow(described_class).to receive(:sleep) }

    it "defaults to a pause that stays under 60 fetches a minute" do
      expect(60 / described_class::DEFAULT_PAUSE).to be < 60
    end

    it "pauses between fetches, not before the first or after the last" do
      described_class.call(organization: organization, client: fake_client.new(responses), confirm: true,
                           pause: 1.1)

      expect(described_class).to have_received(:sleep).with(1.1).once
    end

    it "uses the default pause when none is given" do
      described_class.call(organization: organization, client: fake_client.new(responses), confirm: true)

      expect(described_class).to have_received(:sleep).with(described_class::DEFAULT_PAUSE).once
    end

    it "never sleeps with a zero pause or on a dry run" do
      described_class.call(organization: organization, client: fake_client.new(responses), confirm: true, pause: 0)
      described_class.call(organization: organization, client: fake_client.new({}), confirm: false, pause: 5)

      expect(described_class).not_to have_received(:sleep)
    end
  end

  describe ".format_ids" do
    it "lists every id up to the limit and caps longer listings with the remainder" do
      ids = (1..53).map(&:to_s)

      aggregate_failures do
        expect(described_class.format_ids(%w[1 2 3])).to eq("1, 2, 3")
        expect(described_class.format_ids(ids.first(50))).to eq(ids.first(50).join(", "))
        expect(described_class.format_ids(ids)).to eq("#{ids.first(50).join(", ")}, \u2026 and 3 more")
      end
    end
  end

  describe ".write_date (lock doctrine: stale pre-loaded object, no threads)" do
    it "skips a row that received a date after it was loaded" do
      stale = Decidim::ContractsSk::Contract.find(undated.id)
      undated.update_columns(crz_published_on: Date.new(2019, 9, 9))

      written = described_class.write_date(stale, Date.new(2026, 3, 2))

      aggregate_failures do
        expect(written).to be(false)
        expect(undated.reload.crz_published_on).to eq(Date.new(2019, 9, 9))
      end
    end

    it "skips a row that stopped being a mirror after it was loaded" do
      stale = Decidim::ContractsSk::Contract.find(undated.id)
      undated.update_columns(source: "editorial")

      expect(described_class.write_date(stale, Date.new(2026, 3, 2))).to be(false)
      expect(undated.reload.crz_published_on).to be_nil
    end

    it "skips a row that was deleted after it was loaded" do
      stale = Decidim::ContractsSk::Contract.find(undated.id)
      undated.destroy!

      expect(described_class.write_date(stale, Date.new(2026, 3, 2))).to be(false)
    end

    it "is reported as skipped by the run" do
      stale_client = fake_client.new("701" => payload("701", "2026-03-01T12:00:00.000000Z"),
                                     "702" => payload("702", "2026-03-02T12:00:00.000000Z"))
      # The date lands between the candidate load and the write (the fetch).
      allow(stale_client).to receive(:contract).and_wrap_original do |original, id|
        Decidim::ContractsSk::Contract.where(source_id: id).update_all(crz_published_on: Date.new(2019, 9, 9))
        original.call(id)
      end

      result = described_class.call(organization: organization, client: stale_client, confirm: true, pause: 0)

      expect(result.skipped_ids).to eq(%w[701 702])
      expect(result.updated).to eq(0)
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
