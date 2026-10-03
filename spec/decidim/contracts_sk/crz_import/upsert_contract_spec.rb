# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for the CRZ import UpsertContract command (ADR-008,
# civora-org/civora-platform#86), run against the real migrations on an
# in-memory SQLite adapter (see spec/support/contracts_sk_db_helpers.rb;
# excluded from the default offline run).
#
# Decidim::Command.call subscribes a Decidim::EventRecorder and returns its
# captured events, so broadcast outcomes are asserted on the returned hash —
# the real pinned-gem command machinery, no stubs on the command itself.
# The lock-doctrine examples follow the deterministic "request-start copy"
# shape proven in the TransitionContract specs: a stale pre-read/pre-loaded
# object, the row moved directly in between, no threads.
#
# Synthetic data only ("Obec Ukážková", fake IČO patterns), no real PII.
#
# Command outcomes assert several related facts per example by design.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, Metrics/AbcSize
RSpec.describe Decidim::ContractsSk::CrzImport::UpsertContract, :db do
  before { migrate_engine_schema! }

  let(:actor) { author }

  def call_command(record)
    described_class.call(record, organization: organization, actor: actor)
  end

  describe "create path" do
    it "creates a published mirror with full provenance, parties, audit row and authorship" do
      record = mapped_crz_record("2142424")

      events = nil
      expect { events = call_command(record) }
        .to change(Decidim::ContractsSk::Contract, :count).by(1)
        .and change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      expect(events).to have_key(:ok)
      expect(events[:ok][:outcome]).to eq(:created)

      contract = Decidim::ContractsSk::Contract.find_by!(source_id: "2142424")
      aggregate_failures do
        # The ONE recorded lifecycle exception: mirrors land published,
        # with the publication stamp.
        expect(contract.state).to eq("published")
        expect(contract.published_at).to be_present
        # Full provenance per ADR-008 decision 4.
        expect(contract.source).to eq("crz")
        expect(contract.import_status).to eq("succeeded")
        expect(contract.imported_at).to be_present
        expect(contract.checksum).to eq(record[:checksum])
        # Content mirror + tenancy + authorship (the actor authors it —
        # both the author and audit-actor columns are NOT NULL by schema).
        expect(contract.title).to eq("Dodávka výpočtovej techniky pre obec Ukážková")
        expect(contract.reference).to eq("UKÁŽKA-2026/2142424")
        expect(contract.amount).to eq(BigDecimal("1043.68"))
        expect(contract.crz_url).to eq("https://crz.gov.sk/zmluva/2142424/")
        expect(contract.currency).to eq("EUR") # column default — never imported
        expect(contract.organization).to eq(organization)
        expect(contract.author).to eq(actor)
        expect(contract.parties.order(:id).pluck(:role, :name, :ico)).to eq(
          [["object", "Obec Ukážková", "00000001"], ["contractor", "Demo Dodávky s.r.o.", "00000002"]]
        )
      end

      audit = Decidim::ContractsSk::AuditEvent.order(:id).last
      aggregate_failures do
        expect(audit.action).to eq("crz_import_create")
        expect(audit.target_type).to eq("Decidim::ContractsSk::Contract")
        expect(audit.target_id).to eq(contract.id)
        expect(audit.organization).to eq(organization)
        expect(audit.actor).to eq(actor)
      end
    end

    it "broadcasts :invalid without persisting anything when the mapped data is invalid" do
      # subject and contract_identifier both blank → title and reference
      # both nil → the model rejects the create.
      record = mapped_crz_record("2142424", "subject" => "", "contract_identifier" => "")

      events = call_command(record)

      aggregate_failures do
        expect(events).to have_key(:invalid)
        expect(events[:invalid][:reason]).to eq(:record_invalid)
        expect(events[:invalid][:contract]).to be_nil
        expect(Decidim::ContractsSk::Contract.count).to eq(0)
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end
  end

  describe "unchanged path (checksum gate)" do
    it "treats a re-import of an identical payload as a no-op: zero writes, updated_at untouched" do
      record = mapped_crz_record("2142424")
      contract = create_imported_record("2142424", checksum: record[:checksum])
      before_updated_at = contract.updated_at

      events = call_command(record)

      aggregate_failures do
        expect(events[:ok][:outcome]).to eq(:unchanged)
        contract.reload
        expect(contract.updated_at).to eq(before_updated_at)
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
        expect(contract.parties.count).to eq(0) # parties untouched too
      end
    end
  end

  describe "update path" do
    it "updates a still-published mirror when the checksum differs: content, parties, provenance and audit" do
      contract = create_imported_record("2142424")
      contract.parties.create!(role: "object", name: "Stará obec (demo)", ico: "00000009")
      before_imported_at = contract.imported_at

      record = mapped_crz_record("2142424", "subject" => "Zmenený predmet dodávky",
                                            "supplier_name" => "Nový dodávateľ Demo a.s.")

      events = call_command(record)

      expect(events[:ok][:outcome]).to eq(:updated)

      contract.reload
      aggregate_failures do
        expect(contract.title).to eq("Zmenený predmet dodávky")
        expect(contract.checksum).to eq(record[:checksum])
        expect(contract.checksum).not_to eq("outdated-checksum")
        expect(contract.imported_at).to be > before_imported_at
        expect(contract.import_status).to eq("succeeded")
        # Lifecycle state, authorship and currency are never import writes.
        expect(contract.state).to eq("published")
        expect(contract.author).to eq(author)
        expect(contract.currency).to eq("EUR")
        expect(contract.parties.order(:id).pluck(:name))
          .to eq(["Obec Ukážková", "Nový dodávateľ Demo a.s."])
      end

      expect(Decidim::ContractsSk::AuditEvent.order(:id).last.action).to eq("crz_import_update")
    end

    it "broadcasts :invalid and keeps the prior data intact when an update fails validation" do
      contract = create_imported_record("2142424")
      before_updated_at = contract.updated_at

      record = mapped_crz_record("2142424", "subject" => "", "contract_identifier" => "")

      events = call_command(record)

      aggregate_failures do
        expect(events).to have_key(:invalid)
        expect(events[:invalid][:reason]).to eq(:record_invalid)
        expect(events[:invalid][:contract].id).to eq(contract.id)
        contract.reload
        expect(contract.title).to eq("Importovaný záznam (demo)")
        expect(contract.checksum).to eq("outdated-checksum")
        expect(contract.updated_at).to eq(before_updated_at)
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end
  end

  describe "collision path (editorial protection)" do
    it "never touches an editorial record holding the same source_id" do
      editorial = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", source_id: "2142424")
      )
      before_title = editorial.title
      before_updated_at = editorial.updated_at

      events = call_command(mapped_crz_record("2142424"))

      aggregate_failures do
        expect(events).to have_key(:invalid)
        expect(events[:invalid][:reason]).to eq(:collision)
        expect(events[:invalid][:contract].id).to eq(editorial.id)
        editorial.reload
        expect(editorial.title).to eq(before_title)
        expect(editorial.source).to eq("editorial")
        expect(editorial.updated_at).to eq(before_updated_at)
        expect(Decidim::ContractsSk::Contract.count).to eq(1)
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end
  end

  describe "linked path (editorial record confirmed as filed, civora-org/civora-platform#125)" do
    let!(:filed) do
      Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "ZP-2026-808", state: "published", source_id: "2142424",
                            crz_filed_at: Time.zone.parse("2026-09-01T10:00:00Z"))
      )
    end

    def expect_linked_without_writes(events)
      before = filed.updated_at

      expect(events).to have_key(:ok)
      expect(events[:ok][:outcome]).to eq(:linked)
      expect(events[:ok][:contract].id).to eq(filed.id)
      expect(filed.reload.updated_at).to eq(before)
      expect(filed.source).to eq("editorial")
      expect(Decidim::ContractsSk::Contract.count).to eq(1)
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end

    it "writes nothing and reports :linked — neither a mirror nor a collision" do
      expect_linked_without_writes(call_command(mapped_crz_record("2142424")))
    end

    it "stays a no-op however the payload changes (the filed record is canonical)" do
      call_command(mapped_crz_record("2142424"))

      expect_linked_without_writes(call_command(mapped_crz_record("2142424", "subject" => "Zmenený predmet")))
      expect(filed.reload.title).to eq("Road reconstruction")
    end

    it "honours a filing confirmed after the pre-read (create-edge reroute)" do
      original = Decidim::ContractsSk::Contract.method(:find_by)
      calls = 0
      allow(Decidim::ContractsSk::Contract).to receive(:find_by) do |**kwargs|
        calls += 1
        calls == 1 ? nil : original.call(**kwargs)
      end

      expect_linked_without_writes(call_command(mapped_crz_record("2142424")))
    end

    it "reroutes a lost unique-index race to :linked as well" do
      original = Decidim::ContractsSk::Contract.method(:find_by)
      lookups = 0
      allow(Decidim::ContractsSk::Contract).to receive(:find_by) do |**kwargs|
        lookups += 1
        lookups <= 2 ? nil : original.call(**kwargs)
      end
      allow(Decidim::ContractsSk::Contract).to receive(:create!)
        .and_raise(ActiveRecord::RecordNotUnique.new("idx_contracts_sk_contracts_on_org_and_source_id_unique"))

      expect_linked_without_writes(call_command(mapped_crz_record("2142424")))
    end

    it "ends :linked when the mirror row was absorbed between the pre-read and the lock (L-1)" do
      filed.update_columns(source_id: nil)
      mirror = create_imported_record("2142424")
      stale = Decidim::ContractsSk::Contract.find(mirror.id)
      mirror.destroy!
      filed.update_columns(source_id: "2142424")

      original = Decidim::ContractsSk::Contract.method(:find_by)
      calls = 0
      allow(Decidim::ContractsSk::Contract).to receive(:find_by) do |**kwargs|
        calls += 1
        calls == 1 ? stale : original.call(**kwargs)
      end

      expect_linked_without_writes(call_command(mapped_crz_record("2142424")))
    end

    it "still reports :collision for an UNFILED editorial record holding the id" do
      filed.update_columns(crz_filed_at: nil)

      events = call_command(mapped_crz_record("2142424"))

      expect(events[:invalid][:reason]).to eq(:collision)
    end
  end

  describe "lifecycle guard" do
    it "never updates an imported record that left the published state (archived stays archived)" do
      contract = create_imported_record("2142424", state: "archived")
      before_updated_at = contract.updated_at

      events = call_command(mapped_crz_record("2142424", "subject" => "Pokus o oživenie"))

      aggregate_failures do
        expect(events).to have_key(:invalid)
        expect(events[:invalid][:reason]).to eq(:lifecycle_guard)
        contract.reload
        expect(contract.state).to eq("archived")
        expect(contract.checksum).to eq("outdated-checksum")
        expect(contract.updated_at).to eq(before_updated_at)
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end
  end

  describe "lock doctrine (deterministic — no threads)" do
    it "re-checks the published guard inside the lock against a stale pre-read copy" do
      # The stale copy models the command's request-start read; the row was
      # then moved directly, bypassing the command. The in-lock re-check
      # (with_lock reloads the row) must refuse the write.
      contract = create_imported_record("2142424")
      stale = Decidim::ContractsSk::Contract.find(contract.id)
      contract.update!(state: "in_review")

      allow(Decidim::ContractsSk::Contract).to receive(:find_by).and_return(stale)

      events = call_command(mapped_crz_record("2142424", "subject" => "Pozdní zásah"))

      aggregate_failures do
        expect(events).to have_key(:invalid)
        expect(events[:invalid][:reason]).to eq(:lifecycle_guard)
        contract.reload
        expect(contract.state).to eq("in_review")
        expect(contract.title).to eq("Importovaný záznam (demo)")
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end

    it "reroutes the create path to the update path when the record appears in-transaction" do
      # The create path re-checks the lookup inside the transaction; a
      # concurrent import that won the race reroutes this one to the
      # update path instead of attempting a duplicate INSERT.
      create_imported_record("2142424")

      original = Decidim::ContractsSk::Contract.method(:find_by)
      calls = 0
      allow(Decidim::ContractsSk::Contract).to receive(:find_by) do |**kwargs|
        calls += 1
        calls == 1 ? nil : original.call(**kwargs)
      end

      events = call_command(mapped_crz_record("2142424", "subject" => "Súbežný import"))

      aggregate_failures do
        expect(events[:ok][:outcome]).to eq(:updated)
        expect(Decidim::ContractsSk::Contract.where(source_id: "2142424").count).to eq(1)
      end
    end

    it "reroutes to the update path when the unique index aborts the insert (lost create race)" do
      # The database-level backstop: even when both the pre-read AND the
      # in-transaction re-check find nothing (READ COMMITTED), the unique
      # (organization, source_id) index makes the losing INSERT raise
      # RecordNotUnique. The command must reroute to the winner's update
      # path — never let the error escape, which would stamp the winner
      # failed.
      contract = create_imported_record("2142424")

      original = Decidim::ContractsSk::Contract.method(:find_by)
      lookups = 0
      allow(Decidim::ContractsSk::Contract).to receive(:find_by) do |**kwargs|
        lookups += 1
        lookups <= 2 ? nil : original.call(**kwargs)
      end
      allow(Decidim::ContractsSk::Contract).to receive(:create!)
        .and_raise(ActiveRecord::RecordNotUnique.new("idx_contracts_sk_contracts_on_org_and_source_id_unique"))

      events = call_command(mapped_crz_record("2142424", "subject" => "Súbežný import"))

      aggregate_failures do
        expect(events[:ok][:outcome]).to eq(:updated)
        expect(Decidim::ContractsSk::Contract).to have_received(:create!).once
        expect(Decidim::ContractsSk::Contract.where(source_id: "2142424").count).to eq(1)
        contract.reload
        expect(contract.title).to eq("Súbežný import") # the winner was updated, not stamped failed
        expect(contract.import_status).to eq("succeeded")
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, Metrics/AbcSize
