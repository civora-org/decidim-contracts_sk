# frozen_string_literal: true

# Synthetic CRZ payload fixtures for the :db import groups (ADR-008,
# civora-org/civora-platform#86). Complements the shared db helpers and
# demo data: this module owns the ekosystem payload shape (spike-verified
# field names) and imported-record factories.
#
# All data is fictional: "Obec Ukážková", demo companies, obviously fake
# IČO patterns ("00 000 00x") — no real parties, no PII.
module ContractsSkCrzPayloads
  # The observed live payload shape (spike, record 2142424) with synthetic
  # values. The id doubles as the reference suffix so a batch of records
  # never collides on (organization, reference).
  def crz_payload(id, overrides = {})
    {
      "id" => id,
      "contract_identifier" => "UKÁŽKA-2026/#{id}",
      "subject" => "Dodávka výpočtovej techniky pre obec Ukážková",
      "subject_description" => "Dodávka a inštalácia výpočtovej techniky vrátane servisu",
      "contract_price_amount" => "1043.68",
      "signed_on" => "2026-04-13",
      "effective_from" => "2026-05-01",
      "contracting_authority_name" => "Obec Ukážková",
      "contracting_authority_cin" => "00 000 001",
      "contracting_authority_formatted_address" => "Ukážková 1, 000 00 Ukážkovo",
      "supplier_name" => "Demo Dodávky s.r.o.",
      "supplier_cin" => "00 000 002",
      "supplier_formatted_address" => "Demo ulica 5, 000 00 Ukážkovo",
      "changed_at" => "2026-09-07T22:16:44Z"
    }.merge(overrides)
  end

  # The Mapper output for a payload (what the upsert command consumes).
  def mapped_crz_record(id, overrides = {})
    Decidim::ContractsSk::CrzImport::Mapper.map(crz_payload(id, overrides))
  end

  # An existing imported mirror row (source="crz") with stale provenance —
  # the "prior data" a re-import must never degrade.
  def create_imported_record(source_id, state: "published", checksum: "outdated-checksum")
    Decidim::ContractsSk::Contract.create!(
      contract_attributes(
        title: "Importovaný záznam (demo)",
        reference: "ZP-2026-9#{source_id}",
        state: state,
        source: "crz",
        source_id: source_id.to_s,
        checksum: checksum,
        import_status: "succeeded",
        imported_at: Time.zone.parse("2026-01-01T08:00:00Z")
      )
    )
  end
end

RSpec.configure { |config| config.include ContractsSkCrzPayloads, :db }

# The CRZ import fails closed without an organization IČO
# (civora-org/civora-platform#145). Import specs opt in to the scope seam
# answering the fixture contracting authority's IČO ("00 000 001" in
# crz_payload), restoring the engine default afterwards.
RSpec.shared_context "with the CRZ scope configured" do
  around do |example|
    original = Decidim::ContractsSk.crz_organization_ico_resolver
    Decidim::ContractsSk.crz_organization_ico_resolver = ->(_organization) { "00000001" }
    example.run
  ensure
    Decidim::ContractsSk.crz_organization_ico_resolver = original
  end
end
