# frozen_string_literal: true

require "spec_helper"

# The attachment-links backfill (civora-org/civora-platform#189). The client
# is a fake over Client#contract: no transport, no network.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
RSpec.describe Decidim::ContractsSk::CrzImport::BackfillAttachments, :db do
  before { migrate_engine_schema! }

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

  let!(:bare) { create_imported_record("901") }
  let!(:empty_upstream) { create_imported_record("902") } # rubocop:disable RSpec/LetSetup
  let!(:failing) { create_imported_record("903") } # rubocop:disable RSpec/LetSetup
  let!(:linked) do
    create_imported_record("904").tap do |contract|
      contract.crz_attachments.create!(kind: "scan", file_name: "1.pdf")
    end
  end
  let!(:editorial) do
    Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-2026-EDITORIAL", source_id: "905"))
  end

  def payload(id, attachments)
    crz_payload(id, "attachments" => attachments)
  end

  def run(confirm: true, **responses)
    client = fake_client.new(responses)
    [described_class.call(organization: organization, client: client, confirm: confirm, pause: 0), client]
  end

  it "lists candidates and fetches nothing on a dry run" do
    result, client = run(confirm: false)

    expect(result.candidate_ids).to eq(%w[901 902 903])
    expect(client.requested).to be_empty
    expect(bare.crz_attachments.count).to eq(0)
  end

  it "writes the allowlisted links only, touching nothing else, and counts skipped and failed" do
    snapshot = bare.reload.attributes
    result, client = run(
      "901" => payload("901", [{ "id" => 1, "title" => "T", "scan_file_name" => "55.pdf" },
                               { "id" => 2, "title" => "bad", "scan_file_name" => "../x.pdf" }]),
      "902" => payload("902", []),
      "903" => Decidim::ContractsSk::CrzImport::Client::NotFoundError.new("gone")
    )

    expect(result.updated_ids).to eq(%w[901])
    expect(result.skipped_ids).to eq(%w[902])
    expect(result.failed_ids).to eq(%w[903])
    expect(client.requested).to eq(%w[901 902 903])
    expect(bare.crz_attachments.pluck(:file_name)).to eq(["55.pdf"])
    expect(bare.reload.attributes).to eq(snapshot)
    expect(editorial.crz_attachments.count).to eq(0)
    expect(linked.crz_attachments.count).to eq(1)
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations, RSpec/MultipleMemoizedHelpers
