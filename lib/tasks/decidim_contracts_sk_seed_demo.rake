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
#   - 24 more published records (DEMO-2026-010..033) spread over the last
#     twelve months relative to the seeding day, with repeat contractors,
#     varied amounts, two without an amount and three CRZ mirrors, so the
#     public statistics page (#118) looks real (re-seed to slide them);
#     DEMO-2026-010 (play equipment) is left untouched when it already exists;
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
      crz_url: "https://crz.gov.sk/zmluva/900000003/", source_id: "900000003",
      # Confirmed as filed in CRZ (civora-org/civora-platform#125): the
      # demo record that carries no deadline badge, and the public
      # "Zverejnené v CRZ dňa" line. Constant values keep re-seeds
      # idempotent.
      crz_filed_at: Time.zone.local(2026, 1, 10, 12), crz_published_on: Date.new(2026, 1, 10)
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

    # Statistics demo (civora-org/civora-platform#118): 24 more published,
    # fictional contracts spread over the last twelve months RELATIVE to the
    # seeding day, so the public statistics page (trend, per-year counts,
    # top suppliers, own-versus-CRZ split) looks real in a demo. Repeat
    # contractors with different volumes (so the by-value and by-count
    # rankings differ), varied amounts, two records without an amount and
    # three CRZ mirrors. Idempotent per reference like everything above:
    # signing and publication dates are recomputed on each run (the whole
    # picture slides with the seeding day, like DEMO-2026-003), so re-seed to
    # refresh it. Editorial records are stamped redacted and carry a CRZ
    # filing (so the admin deadline chips and counts stay untouched); the
    # mirrors follow the CRZ ETL's shape.
    today = Date.current
    stat_suppliers = {
      3 => ["Odpadové služby Demo a.s.", "Skládková 9, 821 04 Bratislava"],
      5 => ["Svetlá Demo, s.r.o.", "Priemyselná 12, 831 02 Bratislava"],
      11 => ["Stavebná Ukážka s.r.o.", "Murárska 7, 811 02 Bratislava"],
      12 => ["Zelená Údržba Demo, s.r.o.", "Parková 3, 821 05 Bratislava"],
      13 => ["Digitálne Riešenia Demo a.s.", "Technologická 21, 841 04 Bratislava"],
      14 => ["Catering Demo s.r.o.", "Jedlá 4, 811 03 Bratislava"],
      15 => ["Poradenstvo Vzor, s.r.o.", "Právnická 15, 811 01 Bratislava"]
    }
    # [reference number, months back, day of month, title, supplier, amount, CRZ mirror?]
    stat_rows = [
      [10, 0, 3, "Dodávka a montáž herných prvkov na detské ihriská", 11, "23600.00", false],
      [11, 0, 8, "Rekonštrukcia chodníka Školská ulica", 11, "142300.00", false],
      [12, 0, 12, "Údržba verejnej zelene — jesenná kosba", 12, "9650.00", false],
      [13, 1, 5, "Poradenstvo pri verejnom obstarávaní", 15, "6200.00", false],
      [14, 1, 14, "Zimná údržba komunikácií — import z CRZ", 5, "45000.00", true],
      [15, 2, 2, "Licencie a podpora informačného systému", 13, "24800.00", false],
      [16, 2, 11, "Zber a odvoz bioodpadu", 3, "38200.00", false],
      [17, 2, 20, "Oprava strechy materskej školy", 11, "87600.00", false],
      [18, 3, 7, "Catering pre mestské slávnosti", 14, "7400.00", false],
      [19, 3, 19, "Rámcová dohoda — drobné opravy", 14, nil, false],
      [20, 4, 4, "Správa webového sídla mesta", 13, "12900.00", false],
      [21, 4, 16, "Výsadba stromoradia", 12, "21500.00", false],
      [22, 4, 25, "Odvoz odpadu z cintorínov — import z CRZ", 3, "12800.00", true],
      [23, 5, 9, "Rekonštrukcia telocvične", 11, "213000.00", false],
      [24, 6, 6, "Právne služby — rámcová zmluva", 15, "15600.00", false],
      [25, 6, 21, "Modernizácia školskej počítačovej učebne", 13, "31200.00", false],
      [26, 7, 13, "Zber a odvoz komunálneho odpadu — dodatok", 3, "54000.00", false],
      [27, 8, 3, "Oprava mostíka — import z CRZ", 11, "64500.00", true],
      [28, 8, 17, "Údržba detských ihrísk", 12, "17300.00", false],
      [29, 9, 10, "Údržba zelene — rámcová dohoda", 12, nil, false],
      [30, 10, 5, "Čistenie a údržba mestských fontán", 12, "5200.00", false],
      [31, 11, 8, "Dodávka lavičiek a smetných košov", 13, "9800.00", false],
      [32, 11, 22, "Prevádzka verejného WiFi", 13, "14900.00", false],
      [33, 0, 5, "Dodávka a montáž kamerového systému", 13, "18400.00", false]
    ]
    # Rows whose record may already exist on a host with a hand-curated
    # version (DEMO-2026-010 is the play-equipment contract the
    # participation demo links to and the public screenshots show): an
    # existing one is left exactly as it is (title, amount, dates, state)
    # and only gets the missing parties, matched by role alone so the
    # host's own contractor name never grows a second contractor party.
    stat_preserved = [10]
    stat_rows.each do |row|
      number, back, day, title, supplier, amount, mirror = row
      month_start = today.beginning_of_month << back
      signed = [month_start + (day - 1), month_start.end_of_month, today].min
      published_at = [signed.in_time_zone.change(hour: 12) + 1.day, Time.current].min
      ref = format("DEMO-2026-%03d", number)
      kept = nil
      if stat_preserved.include?(number)
        kept = Decidim::ContractsSk::Contract.find_by(organization: organization, reference: ref)
      end
      crz_id = 900_000_000 + (mirror ? 200 : 100) + number
      content = {
        subject_matter: "Fiktívna ukážková zmluva pre demonštráciu štatistík",
        amount: amount && BigDecimal(amount), signed_on: signed, effective_from: signed + 1,
        published_at: published_at, crz_url: "https://crz.gov.sk/zmluva/#{crz_id}/", source_id: crz_id
      }
      if kept
        contracts[ref] = kept
      elsif mirror
        seed.call(
          ref: ref, title: title, state: "published", **content,
          source: "crz", import_status: "succeeded", imported_at: Time.current,
          checksum: Digest::SHA256.hexdigest("demo-#{crz_id}")
        )
      else
        filed_on = [signed + 3, today].min
        seed.call(
          ref: ref, title: title, state: "published", redaction_confirmed: true, **content,
          crz_published_on: filed_on, crz_filed_at: [filed_on.in_time_zone.change(hour: 8), Time.current].min
        )
      end
      name, address = stat_suppliers.fetch(supplier)
      parties = [["object", "Mesto Demo (objekt zmluvy)", "00000001", "Hlavná 1, 811 01 Bratislava"],
                 ["contractor", name, format("%08d", supplier), address]]
      parties.each do |role, party_name, ico, party_address|
        match = kept ? { role: role } : { role: role, name: party_name }
        contracts.fetch(ref).parties.find_or_create_by!(match) do |p|
          p.name = party_name
          p.ico = ico
          p.address = party_address
        end
      end
    end

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
    puts "  statistics demo (#118): DEMO-2026-010..033 — published, spread over the last 12 months, " \
         "7 repeat contractors, 2 without an amount, 3 CRZ mirrors"
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
