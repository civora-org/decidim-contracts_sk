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
#   - object/contractor parties, documents (metadata + attached demo files
#     from the engine's spec/fixtures/files), and numbered amendments.
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

    seed = lambda do |ref:, title:, state:, **content|
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
      record.published_at = Time.current if state == "published" && record.published_at.blank?
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
      amount: BigDecimal("22100.00"), signed_on: Date.new(2026, 2, 2),
      effective_from: Date.new(2026, 3, 1)
    )

    seed.call(
      ref: "DEMO-2026-004", title: "Prevádzka mestského informačného strediska",
      state: "approved",
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
      state: "published",
      subject_matter: "Zber a odvoz komunálneho odpadu na území mesta",
      amount: BigDecimal("96800.00"), signed_on: Date.new(2025, 12, 15),
      effective_from: Date.new(2026, 1, 1),
      crz_url: "https://crz.gov.sk/demo-ukazkovy-zaznam"
    )

    seed.call(
      ref: "DEMO-2026-007", title: "Archivovaná zmluva — holičske služby 2024",
      state: "archived",
      subject_matter: "Príklad archivovaného záznamu",
      amount: BigDecimal("5000.00")
    )

    # Cross-tenant control record: must be invisible (404) from the seeded org.
    Decidim::ContractsSk::Contract.find_or_create_by!(organization: other_org, reference: "DEMO-OTHER-001") do |c|
      c.title = "Zmluva inej organizácie"
      c.state = "published"
      c.author = author
      c.published_at = Time.current
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

    contracts.fetch("DEMO-2026-006").amendments.find_or_create_by!(version: 1) do |a|
      a.summary = "Zmena cenníka pre separovaný odpad"
    end
    contracts.fetch("DEMO-2026-001").amendments.find_or_create_by!(version: 1) do |a|
      a.summary = "Prvá demonštračná zmena"
    end

    # Audit-trail samples for the terminal-state records (find_or_create keeps
    # the task idempotent; the model itself is append-only).
    Decidim::ContractsSk::AuditEvent.find_or_create_by!(
      organization: organization, actor: admin, target: rejected, action: "reject"
    )

    puts "Seeded demo data for organization ##{organization.id}:"
    contracts.each_value { |c| puts "  [#{c.state}] #{c.reference} — #{c.title}" }
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
