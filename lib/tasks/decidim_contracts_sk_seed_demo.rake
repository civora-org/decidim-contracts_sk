# frozen_string_literal: true

# Demo seed data for manual testing of the engine in a real Decidim host app
# (M02 manual test pass). Run from the host app root:
#
#   bin/rails "decidim_contracts_sk:seed_demo[<organization_id>]"
#
# What it creates (all fictional, no real PII):
#   - one admin user per role persona (default role_resolver grants all
#     engine roles to admins who accepted the admin terms — the seeded users
#     do exactly that);
#   - contract records covering every lifecycle state, including one of
#     another organization to prove tenant isolation;
#   - two synthetic CRZ-imported records (civora-org/civora-platform#88) to
#     exercise the public catalogue's provenance labelling: DEMO-2026-008
#     (fresh mirror) and DEMO-2026-009 (deliberately stale mirror —
#     imported_at 60 days back, beyond the default 48 h threshold);
#   - object/contractor parties, documents (metadata + attached demo files
#     from the engine's spec/fixtures/files), and numbered amendments;
#   - ADR-007 redaction stamps (#91) on every editorial record that is or
#     was published (DEMO-2026-004/006/007) — DEMO-2026-001 stays unstamped
#     as the single record demonstrating the publish gate, and the CRZ
#     mirrors stay unstamped by design (ADR-008 exemption).
#
# The CRZ deadline tracking demo (civora-org/civora-platform#124) is
# date-relative: DEMO-2026-003 is re-signed on every run so its deadline is
# ~7 days away (due-soon), while DEMO-2026-002 and -004 (fixed 2026 signing
# dates, no CRZ link) are overdue and DEMO-2026-001 (draft without a signing
# date) shows "deadline unknown". Re-seed to refresh the due-soon demo.
#
# Date.current uses the host's Time.zone (not the organization's), so near
# midnight the demo can be off by one day.
#
# Idempotent per (organization, reference): re-running upserts on the
# composite unique index instead of duplicating. A second organization is
# created when none other exists, so cross-tenant 404 behaviour is testable.
#
# Privacy: fixture data only — fictional names, placeholder IČO values
# (00000001+ pattern), no real persons or companies.

namespace :decidim_contracts_sk do
  desc "Seed fictional demo contracts (all lifecycle states), parties, documents and amendments for manual testing"
  task :seed_demo, [:organization_id] => :environment do |_task, args|
    require "digest"

    org_id = args[:organization_id].to_i
    abort "Usage: rails \"decidim_contracts_sk:seed_demo[<organization_id>]\"" unless org_id.positive?

    organization = Decidim::Organization.find(org_id)
    other_org = Decidim::Organization.where.not(id: org_id).first ||
                Decidim::Organization.create!(
                  name: { en: "Demo other organization", sk: "Demo iná organizácia" },
                  available_locales: %w[en sk], default_locale: "sk",
                  reference_prefix: "DEMO",
                  host: "other-#{Digest::MD5.hexdigest(Time.now.to_f.to_s)[0, 8]}.example.org"
                )

    admin = demo_user!(organization, "contracts-admin@example.org", terms: true)
    editor = demo_user!(organization, "contracts-editor@example.org", terms: true)
    author = editor

    contracts = {}

    seed = lambda do |ref:, title:, state:, imported_at: nil, redaction_confirmed: false, **content|
      record = Decidim::ContractsSk::Contract.find_or_initialize_by(
        organization: organization,
        reference: ref
      )
      record.assign_attributes(
        title: title,
        state: state,
        author: author,
        **content
      )
      # Seeded states are written directly, never submitter-attributed
      # (four-eyes, #123): reset any stamp a UI walkthrough left behind so a
      # re-seed returns the records to a state a single demo admin can judge.
      record.decidim_submitted_by_id = nil
      record.published_at = Time.current if state == "published" && record.published_at.blank?
      # ADR-007 redaction stamp (#91): editorial records that end published
      # — or sit one approve→publish walkthrough away — carry the
      # confirmation, written in the SAME save as the state (the seed
      # bypasses the command layer, so the stamp lands before the state
      # flip, mirroring the real editorial order). Stamped once, never
      # refreshed on re-seed (same idempotency doctrine as published_at).
      # Deliberately unstamped: DEMO-2026-001 is the single record
      # demonstrating the publish gate, and the CRZ mirrors carry no stamp
      # by design (their content is already-public upstream data, ADR-008
      # — the amendment publish exemption).
      record.redaction_confirmed_at = Time.current if redaction_confirmed && record.redaction_confirmed_at.blank?
      # Freshness metadata for the synthetic CRZ mirrors (#88) is stamped
      # only on FIRST creation: re-seeding must never refresh a mirror's
      # imported_at (the import ETL's checksum no-op gives real mirrors the
      # same guarantee) — otherwise the deliberately stale DEMO-2026-009
      # would silently heal itself on every demo re-seed.
      record.imported_at = imported_at if imported_at && record.new_record?
      record.save!
      contracts[ref] = record
      record
    end

    seed.call(
      ref: "DEMO-2026-001", title: "Rekonštrukcia komunikácie Hlavná ulica",
      state: "draft",
      subject_matter: "Stavebné práce — rekonštrukcia miestnej komunikácie, 850 m",
      amount: BigDecimal("148500.00"), signed_on: nil, effective_from: nil,
      crz_url: nil
    )

    seed.call(
      ref: "DEMO-2026-002", title: "Dodávka IT vybavenia pre mestský úrad",
      state: "in_review",
      subject_matter: "Dodávka a inštalácia výpočtovej techniky",
      amount: BigDecimal("39990.00"), signed_on: Date.new(2026, 3, 10),
      effective_from: Date.new(2026, 4, 1), crz_url: nil
    )

    seed.call(
      ref: "DEMO-2026-003", title: "Údržba verejnej zelene 2026",
      state: "returned",
      subject_matter: "Pravidelná údržba parkov a verejnej zelene",
      amount: BigDecimal("22100.00"),
      # CRZ deadline demo (civora-org/civora-platform#124): signed so the
      # § 47a OZ deadline falls 7 days after the seeding day — the amber
      # "7 dní" badge and the "due within 14 days" filter are demonstrable.
      # The smallest signing date whose deadline is on/after today + 7 is
      # computed with the engine's own month-end-exact helper (plain date
      # subtraction is off on month ends); the demo decays as days pass —
      # re-run the seed to re-demo. Where no signing date lands exactly on
      # today + 7 (a clamp gap at a month end) the deadline is the next
      # reachable day, still inside the 14-day window.
      signed_on: Decidim::ContractsSk::CrzDeadline.threshold(Date.current + 7),
      effective_from: Date.new(2026, 3, 1)
    )

    seed.call(
      ref: "DEMO-2026-004", title: "Prevádzka mestského informačného strediska",
      state: "approved", redaction_confirmed: true,
      subject_matter: "Prevádzkovanie informačného strediska pre turistov",
      amount: BigDecimal("54000.00"), signed_on: Date.new(2026, 1, 20),
      effective_from: Date.new(2026, 2, 1)
    )

    rejected = seed.call(
      ref: "DEMO-2026-005", title: "Marketingové služby — zastavaná schválená hodnota",
      state: "rejected",
      subject_matter: "Marketingové a komunikačné služby",
      amount: BigDecimal("12000.00")
    )

    seed.call(
      ref: "DEMO-2026-006", title: "Zber a Transport odpadu v meste",
      state: "published", redaction_confirmed: true,
      subject_matter: "Zber a odvoz komunálneho odpadu na území mesta",
      amount: BigDecimal("96800.00"), signed_on: Date.new(2025, 12, 15),
      effective_from: Date.new(2026, 1, 1),
      crz_url: "https://crz.gov.sk/demo-ukazkovy-zaznam"
    )

    seed.call(
      ref: "DEMO-2026-007", title: "Archivovaná zmluva — holičske služby 2024",
      state: "archived", redaction_confirmed: true,
      subject_matter: "Príklad archivovaného záznamu",
      amount: BigDecimal("5000.00")
    )

    # Synthetic CRZ-imported records (civora-org/civora-platform#88): a
    # fresh mirror and a deliberately stale one, so the catalogue's
    # provenance badge, imported date and stale indicator are demonstrable
    # without running the real import. Provenance follows the ETL's row
    # shape (source/source_id/import_status/checksum); source_id mirrors
    # the CRZ numeric id (stored in the string column), and the canonical
    # record link follows the crz.gov.sk/zmluva/<ID>/ shape. All data is
    # fictional — no real CRZ ids, companies or persons.
    seed.call(
      ref: "DEMO-2026-008", title: "Modernizácia verejného osvetlenia — import z CRZ",
      state: "published",
      subject_matter: "Dodávka a montáž LED svietidiel v intraviláne obce",
      amount: BigDecimal("78400.00"), signed_on: Date.new(2026, 5, 12),
      effective_from: Date.new(2026, 6, 1),
      crz_url: "https://crz.gov.sk/zmluva/900000001/",
      source: "crz", source_id: 900_000_001,
      import_status: "succeeded",
      imported_at: Time.current,
      checksum: Digest::SHA256.hexdigest("demo-900000001")
    )

    seed.call(
      ref: "DEMO-2026-009", title: "Úprava kúpaliska — import z CRZ (zastarané)",
      state: "published",
      subject_matter: "Rekonštrukcia letného kúpaliska — výmena technológie",
      amount: BigDecimal("31200.00"),
      crz_url: "https://crz.gov.sk/zmluva/900000002/",
      source: "crz", source_id: 900_000_002,
      import_status: "succeeded",
      imported_at: 60.days.ago, # well beyond the default 48 h stale_after
      checksum: Digest::SHA256.hexdigest("demo-900000002")
    )

    # Cross-tenant control record: must be invisible (404) from the seeded org.
    Decidim::ContractsSk::Contract.find_or_create_by!(organization: other_org, reference: "DEMO-OTHER-001") do |c|
      c.title = "Zmluva inej organizácie"
      c.state = "published"
      c.author = author
      c.published_at = Time.current
      c.redaction_confirmed_at = Time.current # editorial + published ⇒ stamped (ADR-007)
    end

    demo_parties = {
      "DEMO-2026-001" => [
        { role: "object", name: "Mesto Demo (objekt zmluvy)", ico: "00000001", address: "Hlavná 1, 811 01 Bratislava" },
        { role: "contractor", name: "Stavebná firma Demo s.r.o.", ico: "00000002",
          address: "Priemyselná 5, 831 02 Bratislava" }
      ],
      "DEMO-2026-006" => [
        { role: "object", name: "Mesto Demo (objekt zmluvy)", ico: "00000001", address: "Hlavná 1, 811 01 Bratislava" },
        { role: "contractor", name: "Odpadové služby Demo a.s.", ico: "00000003",
          address: "Skládková 9, 821 04 Bratislava" }
      ],
      # Parties for the fresh CRZ mirror: the ETL mirrors exactly the two
      # register parties (objednávateľ -> object, dodávateľ -> contractor).
      "DEMO-2026-008" => [
        { role: "object", name: "Obec Ukážková", ico: "00000004", address: "Ukážková 1, 900 00 Ukážkovo" },
        { role: "contractor", name: "Svetlá Demo, s.r.o.", ico: "00000005",
          address: "Priemyselná 12, 831 02 Bratislava" }
      ]
    }
    demo_parties.each do |ref, parties|
      parties.each do |attrs|
        contracts.fetch(ref).parties.find_or_create_by!(role: attrs[:role], name: attrs[:name]) do |p|
          p.ico = attrs[:ico]
          p.address = attrs[:address]
        end
      end
    end

    documents = [
      { ref: "DEMO-2026-006", title: "Zmluvný dokument", kind: "contract", file: "sample.pdf" },
      { ref: "DEMO-2026-006", title: "Príloha č. 1 — cenník", kind: "annex", file: "sample-notes.txt" }
    ]
    fixtures_dir = File.expand_path("../../spec/fixtures/files", __dir__)
    documents.each do |doc|
      record = contracts.fetch(doc[:ref]).documents.find_or_initialize_by(title: doc[:title])
      record.kind = doc[:kind]
      if record.new_record? || !record.file.attached?
        record.attach_file!(File.open(File.join(fixtures_dir, doc[:file])))
      end
      record.save!
    end

    # Amendments are seeded as drafts only: publication (and with it the
    # content snapshot) is the admin command's job (M02-05-B,
    # civora-org/civora-platform#65), so the seed never fabricates
    # published versions. Tenancy/attribution are explicit (the model
    # requires them).
    contracts.fetch("DEMO-2026-006").amendments.find_or_create_by!(version: 1) do |a|
      a.summary = "Zmena cenníka pre separovaný odpad"
      a.organization = organization
      a.author = author
    end
    contracts.fetch("DEMO-2026-001").amendments.find_or_create_by!(version: 1) do |a|
      a.summary = "Prvá demonštračná zmena"
      a.organization = organization
      a.author = author
    end

    # Audit-trail samples for the terminal-state records (find_or_create keeps
    # the task idempotent; the model itself is append-only).
    Decidim::ContractsSk::AuditEvent.find_or_create_by!(
      organization: organization, actor: admin, target: rejected, action: "reject"
    )

    puts "Seeded demo data for organization ##{organization.id}:"
    contracts.each_value { |c| puts "  [#{c.state}] #{c.reference} — #{c.title}" }
    puts "  imported (CRZ mirrors, provenance-labelled in the catalogue): " \
         "DEMO-2026-008 (fresh), DEMO-2026-009 (stale — imported 60 days ago)"
    puts "  users: #{admin.email} (admin), #{editor.email} (editor persona)"
    puts "Public catalogue: /<mount>/ — published-only; DEMO-OTHER-001 must 404."
  end

  def demo_user!(organization, email, terms:)
    Decidim::User.find_or_create_by!(email: email, organization: organization) do |u|
      local = email.split("@").first
      u.name = local.tr("-", " ").capitalize
      u.nickname = local.tr("-", "_")
      u.tos_agreement = "1"
      u.accepted_tos_version = organization.tos_version
      u.password = SecureRandom.hex(16) # intentionally unknown; reset via host app
      u.admin = true
      u.admin_terms_accepted_at = Time.current if terms
      u.confirmed_at = Time.current
    end
  end
end
