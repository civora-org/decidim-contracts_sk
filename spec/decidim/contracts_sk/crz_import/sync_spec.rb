# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db specs for the CRZ import batch orchestrator (ADR-008,
# civora-org/civora-platform#86), run against the real migrations on an
# in-memory SQLite adapter, with the Client stubbed at its exact boundary —
# the transport/client seam keeps everything offline and deterministic.
#
# Pinned here: the summary-count contract, quarantine-without-abort, the
# cursor follow, the stale fallback (a failed run never degrades prior
# data), and the single-record import outcomes.
#
# Synthetic data only ("Obec Ukážková", fake IČO patterns), no real PII.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CrzImport::Sync, :db do
  include_context "with the CRZ scope configured"

  before { migrate_engine_schema! }

  let(:client) { instance_double(Decidim::ContractsSk::CrzImport::Client) }

  def page(records, next_cursor: nil)
    { records: records, next_cursor: next_cursor }
  end

  def run_sync(since: "2026-09-08T00:00:00Z")
    described_class.run(organization: organization, since: since, actor: author, client: client)
  end

  describe ".run (mixed batch)" do
    it "folds every record outcome into the correct summary counts" do
      changed = create_imported_record("300")
      same = crz_payload("301")
      unchanged = create_imported_record("301", checksum: mapped_crz_record("301")[:checksum])
      editorial = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", source_id: "302")
      )
      create_imported_record("303", state: "archived")

      records = [
        crz_payload("400"),                                     # created
        crz_payload("401"),                                     # created
        crz_payload("300", "subject" => "Zmenený predmet"),     # updated (checksum differs)
        same,                                                   # unchanged
        crz_payload("302"),                                     # collision — editorial
        { "subject" => "no id here" },                          # quarantined
        crz_payload("303", "subject" => "Pokus o oživenie")     # skipped — archived
      ]
      allow(client).to receive(:sync).with(since: "2026-09-08T00:00:00Z").and_return(page(records))

      result = run_sync

      aggregate_failures do
        expect(result.created).to eq(2)
        expect(result.created_ids.length).to eq(2)
        expect(result.updated).to eq(1)
        expect(result.unchanged).to eq(1)
        expect(result.collisions).to eq(1)
        expect(result.collision_ids).to eq([editorial.id])
        expect(result.quarantined).to eq(1)
        expect(result.skipped).to eq(1)
        expect(result.failed).to eq(0)
        expect(result.error).to be_nil
      end

      expect(changed.reload.title).to eq("Zmenený predmet") # updated from subject
      expect(unchanged.reload.import_status).to eq("succeeded")
      expect(editorial.reload.title).to eq("Road reconstruction") # untouched
    end
  end

  describe ".run (malformed records)" do
    it "quarantines malformed records without aborting the batch" do
      records = [
        crz_payload("400"),
        "garbage-not-a-hash",
        { "subject" => "missing id" },
        crz_payload("401")
      ]
      allow(client).to receive(:sync).and_return(page(records))

      result = run_sync

      aggregate_failures do
        expect(result.created).to eq(2)
        expect(result.quarantined).to eq(2)
        expect(result.error).to be_nil
        expect(Decidim::ContractsSk::Contract.where(source_id: %w[400 401]).count).to eq(2)
      end
    end

    it "stamps the existing mirror failed (not quarantined) for malformed garbage carrying a known id" do
      # A payload that carries a valid id but is otherwise structural
      # garbage (mixed key types break the canonical-JSON checksum) is
      # quarantinable BY id: the pre-existing mirror row is stamped failed
      # — data intact — and the run counts it as failed, not quarantined.
      existing = create_imported_record("300")
      before_title = existing.title

      records = [
        { 1 => "mixed key types", "id" => "300" },
        crz_payload("401")
      ]
      allow(client).to receive(:sync).and_return(page(records))

      result = run_sync

      aggregate_failures do
        expect(result.failed).to eq(1)
        expect(result.failed_ids).to eq([existing.id])
        expect(result.quarantined).to eq(0)
        expect(result.created).to eq(1) # the batch continued
        existing.reload
        expect(existing.import_status).to eq("failed")
        expect(existing.title).to eq(before_title) # prior data intact
      end
    end

    it "keeps the batch going when a record fails unexpectedly, stamping the known mirror failed" do
      # One-shot unexpected failure injection at the command boundary: the
      # first record's upsert raises StandardError (the second runs for
      # real). The failed record's mirror is stamped and counted; the rest
      # of the page is processed.
      existing = create_imported_record("300")

      original = Decidim::ContractsSk::CrzImport::UpsertContract.method(:call)
      upsert_calls = 0
      allow(Decidim::ContractsSk::CrzImport::UpsertContract).to receive(:call) do |*args, **kwargs|
        upsert_calls += 1
        raise StandardError, "boom" if upsert_calls == 1

        original.call(*args, **kwargs)
      end

      allow(client).to receive(:sync).and_return(page([crz_payload("300"), crz_payload("401")]))

      result = run_sync

      aggregate_failures do
        expect(result.failed).to eq(1)
        expect(result.failed_ids).to eq([existing.id])
        expect(result.created).to eq(1)
        expect(result.error).to be_nil
        existing.reload
        expect(existing.import_status).to eq("failed")
        expect(existing.title).to eq("Importovaný záznam (demo)") # prior data intact
        expect(Decidim::ContractsSk::Contract.where(source_id: "401").count).to eq(1)
      end
    end
  end

  describe ".run (filed editorial records, civora-org/civora-platform#125)" do
    it "counts a filing-confirmed editorial record as linked — not a collision — and writes nothing" do
      filed = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", state: "published", source_id: "302",
                            crz_filed_at: Time.zone.parse("2026-09-01T10:00:00Z"))
      )
      unfiled = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-809", source_id: "303")
      )
      allow(client).to receive(:sync)
        .and_return(page([crz_payload("302"), crz_payload("303"), crz_payload("400")]))
      before = filed.updated_at

      result = run_sync

      aggregate_failures do
        expect(result.linked).to eq(1)
        expect(result.linked_ids).to eq([filed.id])
        expect(result.collisions).to eq(1)
        expect(result.collision_ids).to eq([unfiled.id])
        expect(result.created).to eq(1)
        expect(Decidim::ContractsSk::Contract.where(source_id: "302").count).to eq(1)
        expect(filed.reload.updated_at).to eq(before)
        expect(filed.title).to eq("Road reconstruction")
      end
    end

    it "is repeatable: the next sync of the same filed record links again, never duplicates" do
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", state: "published", source_id: "302",
                            crz_filed_at: Time.current)
      )
      allow(client).to receive(:sync).and_return(page([crz_payload("302")]))

      2.times { expect(run_sync.linked).to eq(1) }
      expect(Decidim::ContractsSk::Contract.count).to eq(1)
    end

    it "never stamps import_status on an editorial record when its id is quarantined (G4)" do
      editorial = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", source_id: "302")
      )
      allow(client).to receive(:sync).and_return(page([{ 1 => "mixed key types", "id" => "302" }]))

      result = run_sync

      aggregate_failures do
        expect(result.quarantined).to eq(1)
        expect(result.failed).to eq(0)
        expect(editorial.reload.import_status).to be_nil
      end
    end

    it "never stamps import_status on an editorial record after an unexpected per-record failure (G4)" do
      editorial = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", source_id: "302", crz_filed_at: Time.current)
      )
      allow(Decidim::ContractsSk::CrzImport::UpsertContract).to receive(:call).and_raise(StandardError, "boom")
      allow(client).to receive(:sync).and_return(page([crz_payload("302")]))

      run_sync

      expect(editorial.reload.import_status).to be_nil
    end

    it "never stamps an editorial record when a single import of its id fails (G4)" do
      editorial = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", source_id: "302", crz_filed_at: Time.current)
      )
      allow(client).to receive(:contract).and_raise(Decidim::ContractsSk::CrzImport::Client::TransportError)

      outcome = described_class.import_one(source_id: "302", organization: organization,
                                           actor: author, client: client)

      expect(outcome).to eq(:failed)
      expect(editorial.reload.import_status).to be_nil
    end

    it "answers :linked for a single import of a filed record's id" do
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", state: "published", source_id: "302",
                            crz_filed_at: Time.current)
      )
      allow(client).to receive(:contract).with("302").and_return(crz_payload("302"))

      outcome = described_class.import_one(source_id: "302", organization: organization,
                                           actor: author, client: client)

      expect(outcome).to eq(:linked)
    end
  end

  describe ".run (pagination and stale fallback)" do
    it "follows the Link cursor verbatim across pages" do
      first_page = page([crz_payload("400")],
                        next_cursor: "https://datahub.ekosystem.slovensko.digital/api/data/crz/contracts/sync?last_id=401")
      calls = []
      allow(client).to receive(:sync) do |**kwargs|
        calls << kwargs
        kwargs[:cursor] ? page([]) : first_page
      end

      run_sync

      expect(calls).to eq(
        [{ since: "2026-09-08T00:00:00Z" },
         { since: nil, cursor: "https://datahub.ekosystem.slovensko.digital/api/data/crz/contracts/sync?last_id=401" }]
      )
    end

    it "keeps prior pages and reports the stopping error when the client fails mid-pagination" do
      first_page = page([crz_payload("400")], next_cursor: "https://example.next")
      call_count = 0
      allow(client).to receive(:sync) do |**_kwargs|
        call_count += 1
        call_count == 1 ? first_page : raise(Decidim::ContractsSk::CrzImport::Client::TransportError, "upstream down")
      end

      result = run_sync

      aggregate_failures do
        expect(result.created).to eq(1)
        expect(Decidim::ContractsSk::Contract.where(source_id: "400").count).to eq(1) # page-1 write stands
        expect(result.error).to be_present
        expect(Decidim::ContractsSk::Contract.count).to eq(1) # nothing else fabricated
      end
    end

    it "stamps the existing mirror failed and keeps its data intact when a changed payload maps to invalid content" do
      existing = create_imported_record("300")
      before_checksum = existing.checksum
      allow(client).to receive(:sync).and_return(
        page([crz_payload("300", "subject" => "", "contract_identifier" => "")])
      )

      result = run_sync

      aggregate_failures do
        expect(result.failed).to eq(1)
        expect(result.failed_ids).to eq([existing.id])
        existing.reload
        expect(existing.import_status).to eq("failed")
        expect(existing.title).to eq("Importovaný záznam (demo)") # prior data intact
        expect(existing.checksum).to eq(before_checksum)
      end
    end
  end

  describe ".run (organization scope, civora-org/civora-platform#145)" do
    it "imports only records carrying the organization's IČO on either party" do
      records = [
        crz_payload("500"), # authority side
        crz_payload("501", "contracting_authority_cin" => "00 000 009",
                           "supplier_cin" => "00 000 001"), # supplier side
        crz_payload("502", "contracting_authority_cin" => "00 000 009"), # another municipality
        crz_payload("503", "contracting_authority_cin" => nil, "supplier_cin" => nil)
      ]
      allow(client).to receive(:sync).and_return(page(records))

      result = run_sync

      aggregate_failures do
        expect(result.created).to eq(2)
        expect(result.out_of_scope).to eq(2)
        expect(result.quarantined).to eq(0)
        expect(result.error).to be_nil
        expect(Decidim::ContractsSk::Contract.pluck(:source_id)).to contain_exactly("500", "501")
      end
    end

    it "never updates an existing mirror once its record is out of scope" do
      existing = create_imported_record("504")
      allow(client).to receive(:sync).and_return(
        page([crz_payload("504", "contracting_authority_cin" => "00 000 009", "subject" => "Cudzí predmet")])
      )

      result = run_sync

      aggregate_failures do
        expect(result.out_of_scope).to eq(1)
        expect(existing.reload.title).to eq("Importovaný záznam (demo)")
      end
    end

    it "refuses to run without a configured IČO and never calls the source" do
      Decidim::ContractsSk.crz_organization_ico_resolver = ->(_organization) {}
      allow(client).to receive(:sync)

      result = run_sync

      aggregate_failures do
        expect(result.error).to eq(described_class::NOT_CONFIGURED_MESSAGE)
        expect(result.created).to eq(0)
        expect(client).not_to have_received(:sync)
      end
    end
  end

  describe ".import_one" do
    it "creates the mirror for a fresh CRZ id" do
      allow(client).to receive(:contract).with("2142424").and_return(crz_payload("2142424"))

      outcome = described_class.import_one(source_id: "2142424", organization: organization,
                                           actor: author, client: client)

      aggregate_failures do
        expect(outcome).to eq(:created)
        expect(Decidim::ContractsSk::Contract.find_by!(source_id: "2142424").state).to eq("published")
      end
    end

    it "answers :not_found without persisting anything when the source id is unknown" do
      allow(client).to receive(:contract).with("404404")
                                         .and_raise(Decidim::ContractsSk::CrzImport::Client::NotFoundError)

      outcome = described_class.import_one(source_id: "404404", organization: organization,
                                           actor: author, client: client)

      aggregate_failures do
        expect(outcome).to eq(:not_found)
        expect(Decidim::ContractsSk::Contract.count).to eq(0)
      end
    end

    it "marks the existing mirror failed and keeps its data when the source is unreachable" do
      existing = create_imported_record("300")
      allow(client).to receive(:contract).with("300")
                                         .and_raise(Decidim::ContractsSk::CrzImport::Client::TransportError)

      outcome = described_class.import_one(source_id: "300", organization: organization,
                                           actor: author, client: client)

      aggregate_failures do
        expect(outcome).to eq(:failed)
        existing.reload
        expect(existing.import_status).to eq("failed")
        expect(existing.title).to eq("Importovaný záznam (demo)") # prior data intact
      end
    end

    it "answers :out_of_scope without persisting another organization's contract" do
      allow(client).to receive(:contract).with("505")
                                         .and_return(crz_payload("505", "contracting_authority_cin" => "00 000 009"))

      outcome = described_class.import_one(source_id: "505", organization: organization,
                                           actor: author, client: client)

      aggregate_failures do
        expect(outcome).to eq(:out_of_scope)
        expect(Decidim::ContractsSk::Contract.count).to eq(0)
      end
    end

    it "answers :not_configured without calling the source when no IČO is configured" do
      Decidim::ContractsSk.crz_organization_ico_resolver = ->(_organization) {}
      allow(client).to receive(:contract)

      outcome = described_class.import_one(source_id: "506", organization: organization,
                                           actor: author, client: client)

      aggregate_failures do
        expect(outcome).to eq(:not_configured)
        expect(client).not_to have_received(:contract)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
