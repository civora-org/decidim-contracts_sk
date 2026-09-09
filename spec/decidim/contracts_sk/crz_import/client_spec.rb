# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the CRZ import Client (ADR-008,
# civora-org/civora-platform#86) over a stubbed Transport — the injection
# seam keeps the suite network-free (no webmock dependency).
#
# Pinned here: the sync URL shape, cursor handling (the Link URL is
# followed VERBATIM, never reconstructed), the bounded-retry policy
# (2 retries on transient failures only), the domain error vocabulary,
# and the privacy guardrail — logs carry URLs and statuses, never bodies.
#
# Cop note: the transport/logger/url fixtures are harness, not test state
# (hence MultipleMemoizedHelpers), and each transport interaction asserts
# its request + its outcome together by design — the dense-assertion cops
# are disabled file-wide along with the example-length budget, mirroring
# the sibling request specs.
# ---------------------------------------------------------------------------

require "spec_helper"
require "stringio"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
RSpec.describe Decidim::ContractsSk::CrzImport::Client do
  let(:logger_io) { StringIO.new }
  let(:transport) { instance_double(Decidim::ContractsSk::CrzImport::Transport) }
  let(:client) do
    described_class.new(transport: transport, logger: Logger.new(logger_io), backoff: [0, 0])
  end
  let(:since_url) { sync_url("since=2026-09-08T00%3A00%3A00Z") }
  let(:next_cursor) { sync_url("last_id=12765392&since=2026-09-08T03%3A00%3A06.741945Z") }
  let(:page_body) { [{ "id" => 2_142_424, "subject" => "Synthetic" }].to_json }

  def response(status:, body: "", headers: {}, error: nil)
    Decidim::ContractsSk::CrzImport::Transport::Result.new(
      status: status, body: body, headers: headers, error: error
    )
  end

  def stub_get(url, responses)
    allow(transport).to receive(:get).with(url).and_return(*responses)
  end

  def sync_url(query)
    "https://datahub.ekosystem.slovensko.digital/api/data/crz/contracts/sync?#{query}"
  end

  describe "#sync (first page)" do
    it "requests the sync endpoint with the encoded since and returns records + cursor" do
      stub_get(since_url, [response(status: 200, body: page_body,
                                    headers: { "link" => "<#{next_cursor}>; rel='next'" })])

      page = client.sync(since: "2026-09-08T00:00:00Z")

      aggregate_failures do
        expect(page[:records]).to eq([{ "id" => 2_142_424, "subject" => "Synthetic" }])
        expect(page[:next_cursor]).to eq(next_cursor)
      end
    end

    it "parses the Link cursor with double quotes, bare rel and case-insensitive rel too" do
      aggregate_failures do
        stub_get(since_url,
                 [response(status: 200, body: "[]", headers: { "link" => "<#{next_cursor}>; rel=\"next\"" })])
        expect(client.sync(since: "2026-09-08T00:00:00Z")[:next_cursor]).to eq(next_cursor)

        stub_get(since_url, [response(status: 200, body: "[]", headers: { "link" => "<#{next_cursor}>; REL=next" })])
        expect(client.sync(since: "2026-09-08T00:00:00Z")[:next_cursor]).to eq(next_cursor)
      end
    end

    it "returns a nil cursor when the response carries no Link header" do
      stub_get(since_url, [response(status: 200, body: "[]")])

      expect(client.sync(since: "2026-09-08T00:00:00Z")[:next_cursor]).to be_nil
    end

    it "also accepts an object body carrying a contracts array" do
      stub_get(since_url, [response(status: 200, body: { "contracts" => [{ "id" => 1 }] }.to_json)])

      expect(client.sync(since: "2026-09-08T00:00:00Z")[:records]).to eq([{ "id" => 1 }])
    end

    it "raises ParseError for an unparseable page body" do
      stub_get(since_url, [response(status: 200, body: "<html>not json</html>")])

      expect { client.sync(since: "2026-09-08T00:00:00Z") }
        .to raise_error(Decidim::ContractsSk::CrzImport::Client::ParseError)
    end
  end

  describe "#sync (cursor follow)" do
    it "follows the cursor URL verbatim — never reconstructs since" do
      stub_get(next_cursor, [response(status: 200, body: "[]")])

      page = client.sync(since: "2026-09-08T00:00:00Z", cursor: next_cursor)

      aggregate_failures do
        expect(page[:records]).to eq([])
        expect(transport).to have_received(:get).with(next_cursor)
      end
    end
  end

  describe "bounded retries" do
    it "retries a transient 5xx once and succeeds on the second attempt" do
      stub_get(since_url, [response(status: 503), response(status: 200, body: page_body)])

      expect(client.sync(since: "2026-09-08T00:00:00Z")[:records].length).to eq(1)
      expect(transport).to have_received(:get).twice
    end

    it "retries a transient 429 and a transport-level failure (status 0)" do
      aggregate_failures do
        stub_get(since_url, [response(status: 429), response(status: 200, body: "[]")])
        expect(client.sync(since: "2026-09-08T00:00:00Z")).to be_present

        stub_get(since_url, [response(status: 0, error: Net::OpenTimeout.new),
                             response(status: 200, body: "[]")])
        expect(client.sync(since: "2026-09-08T00:00:00Z")).to be_present
      end
    end

    it "raises TransportError after the two retries are exhausted (three attempts)" do
      stub_get(since_url, [response(status: 503), response(status: 503), response(status: 503)])

      expect { client.sync(since: "2026-09-08T00:00:00Z") }
        .to raise_error(Decidim::ContractsSk::CrzImport::Client::TransportError)
      expect(transport).to have_received(:get).exactly(3).times
    end

    it "does not retry non-transient 4xx failures" do
      stub_get(since_url, [response(status: 403)])

      expect { client.sync(since: "2026-09-08T00:00:00Z") }
        .to raise_error(Decidim::ContractsSk::CrzImport::Client::Error)
      expect(transport).to have_received(:get).once
    end

    it "raises a status error for a final non-2xx sync response before parsing" do
      # A 404 page is final (non-transient) — the client surfaces the
      # status as a domain error instead of feeding the body to the parser.
      stub_get(since_url, [response(status: 404, body: "<html>gone</html>")])

      expect { client.sync(since: "2026-09-08T00:00:00Z") }
        .to raise_error(Decidim::ContractsSk::CrzImport::Client::Error, /HTTP 404/)
      expect(transport).to have_received(:get).once
    end
  end

  describe "#contract" do
    let(:contract_url) { "https://datahub.ekosystem.slovensko.digital/api/data/crz/contracts/2142424" }

    it "fetches a single record by its CRZ numeric id" do
      stub_get(contract_url, [response(status: 200, body: { "id" => 2_142_424 }.to_json)])

      expect(client.contract(2_142_424)).to eq({ "id" => 2_142_424 })
    end

    it "unwraps an object body carrying the record under a contract key" do
      stub_get(contract_url, [response(status: 200, body: { "contract" => { "id" => 2_142_424 } }.to_json)])

      expect(client.contract("2142424")).to eq({ "id" => 2_142_424 })
    end

    it "raises NotFoundError immediately on a 404 (no retry)" do
      stub_get(contract_url, [response(status: 404)])

      expect { client.contract(2_142_424) }
        .to raise_error(Decidim::ContractsSk::CrzImport::Client::NotFoundError)
      expect(transport).to have_received(:get).once
    end

    it "raises TransportError when the retries are exhausted" do
      stub_get(contract_url, [response(status: 0, error: Net::ReadTimeout.new)] * 3)

      expect { client.contract(2_142_424) }
        .to raise_error(Decidim::ContractsSk::CrzImport::Client::TransportError)
    end
  end

  describe "privacy guardrail (no payload logging)" do
    it "logs the URL and status but never the body" do
      body = [{ "subject" => "SECRET-PAYLOAD Obec Ukážková" }].to_json
      stub_get(since_url, [response(status: 503),
                           response(status: 200, body: body,
                                    headers: { "link" => "<#{next_cursor}>; rel='next'" })])

      client.sync(since: "2026-09-08T00:00:00Z")

      aggregate_failures do
        expect(logger_io.string).to include("/api/data/crz/contracts/sync")
        expect(logger_io.string).to include("503")
        expect(logger_io.string).to include("200")
        expect(logger_io.string).not_to include("SECRET-PAYLOAD")
        expect(logger_io.string).not_to include("Obec Ukážková")
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
