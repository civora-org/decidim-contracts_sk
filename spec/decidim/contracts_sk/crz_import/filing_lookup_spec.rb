# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the read-only CRZ verification fetch
# behind the filing confirmation (civora-org/civora-platform#125): refusal
# order and the "never network on a bad id / unconfigured organization"
# guarantees. The Client is stubbed at its exact boundary.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CrzImport::FilingLookup do
  let(:client_class) { Decidim::ContractsSk::CrzImport::Client }
  let(:client) { instance_double(client_class) }
  let(:organization) { Object.new }
  let(:payload) do
    { "id" => 77, "contract_identifier" => "ZP-77", "contract_price_amount" => "10.00",
      "contracting_authority_name" => "Obec Ukážková", "contracting_authority_cin" => "00 000 001",
      "supplier_name" => "Demo s.r.o.", "supplier_cin" => "00 000 002", "status_id" => 2 }
  end

  around do |example|
    original = Decidim::ContractsSk.crz_organization_ico_resolver
    Decidim::ContractsSk.crz_organization_ico_resolver = ->(_organization) { "00000001" }
    example.run
  ensure
    Decidim::ContractsSk.crz_organization_ico_resolver = original
  end

  def lookup(id = "77")
    described_class.call(crz_id: id, organization: organization, client: client)
  end

  it "returns the mapped record for an in-scope, live CRZ record" do
    allow(client).to receive(:contract).with("77").and_return(payload)

    result = lookup

    expect(result).to be_ok
    expect(result.record[:source_id]).to eq("77")
    expect(result.record[:status_id]).to eq(2)
  end

  it "refuses a non-numeric id before any network call" do
    allow(client).to receive(:contract)

    expect(lookup("12 34").refusal).to eq(:not_found)
    expect(lookup("").refusal).to eq(:not_found)
    expect(client).not_to have_received(:contract)
  end

  it "fails closed without a configured organization IČO, before any network call" do
    Decidim::ContractsSk.crz_organization_ico_resolver = ->(_organization) {}
    allow(client).to receive(:contract)

    expect(lookup.refusal).to eq(:not_configured)
    expect(client).not_to have_received(:contract)
  end

  it "maps a missing record to :not_found and source trouble to :failed" do
    allow(client).to receive(:contract).and_raise(client_class::NotFoundError)
    expect(lookup.refusal).to eq(:not_found)

    allow(client).to receive(:contract).and_raise(client_class::TransportError)
    expect(lookup.refusal).to eq(:failed)

    allow(client).to receive(:contract).and_raise(client_class::ParseError)
    expect(lookup.refusal).to eq(:failed)
  end

  it "never accepts a payload for a different record id" do
    allow(client).to receive(:contract).with("78").and_return(payload)

    expect(lookup("78").refusal).to eq(:not_found)
  end

  it "refuses another organization's record and withdrawn/cancelled records" do
    allow(client).to receive(:contract).with("77")
                                       .and_return(payload.merge("contracting_authority_cin" => "00 000 009",
                                                                 "supplier_cin" => "00 000 008"))
    expect(lookup.refusal).to eq(:out_of_scope)

    allow(client).to receive(:contract).with("77").and_return(payload.merge("status_id" => 5))
    expect(lookup.refusal).to eq(:withdrawn)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
