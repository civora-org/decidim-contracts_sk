# frozen_string_literal: true

# Deterministic demo-data builder for the :db spec groups (CONTRACTS_SK_DB=1).
#
# Complements contracts_sk_db_helpers.rb: that file owns the schema boot and
# the org/user stand-ins, this one owns realistic multi-record fixtures —
# contracts across every lifecycle state, with parties, documents (metadata
# shape only by default; pass attach: true for a real blob) and amendments.
# Everything derives from the shared `organization` / `author` lets, so runs
# stay hermetic per example.
#
# All data is fictional: no real persons, companies or IČO values.
module ContractsSkDemoData
  FICTIONAL_PARTIES = {
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
  }.freeze

  # Creates one contract per lifecycle state for the shared organization and
  # returns them keyed by reference. Cross-tenant control record included.
  def demo_contracts(across_states: true)
    @demo_contracts ||= {}
    return @demo_contracts if @demo_contracts.any?

    by_ref = {
      "DEMO-2026-001" => { state: "draft", title: "Rekonštrukcia komunikácie Hlavná ulica" },
      "DEMO-2026-002" => { state: "in_review", title: "Dodávka IT vybavenia pre mestský úrad" },
      "DEMO-2026-003" => { state: "returned", title: "Údržba verejnej zelene 2026" },
      "DEMO-2026-004" => { state: "approved", title: "Prevádzka mestského informačného strediska" },
      "DEMO-2026-005" => { state: "rejected", title: "Marketingové služby (odmietnuté)" },
      "DEMO-2026-006" => { state: "published", title: "Zber a odvoz odpadu v meste" },
      "DEMO-2026-007" => { state: "archived", title: "Archivovaná zmluva 2024" }
    }

    by_ref.each_with_index do |(reference, attrs), i|
      @demo_contracts[reference] = Decidim::ContractsSk::Contract.create!(
        contract_attributes(
          reference: reference,
          title: attrs[:title],
          state: across_states ? attrs[:state] : "draft",
          subject_matter: "Demo predmet zmluvy č. #{i + 1}",
          amount: BigDecimal("10000.00") + i,
          signed_on: Date.new(2026, 1, 1) + i,
          effective_from: Date.new(2026, 2, 1)
        ).tap do |h|
          if h[:state] == "published"
            h[:published_at] = Time.zone.parse("2026-03-01T09:00:00Z") + i
            h[:crz_url] = "https://crz.gov.sk/demo-#{reference.downcase}"
          end
        end
      )
    end

    @demo_contracts
  end

  def demo_contract(reference = "DEMO-2026-006")
    demo_contracts.fetch(reference)
  end

  def demo_parties!
    FICTIONAL_PARTIES.each do |reference, parties|
      contract = demo_contracts.fetch(reference)
      parties.each do |attrs|
        contract.parties.create!(attrs)
      end
    end
  end

  # kind defaults to "contract"; pass attach: "sample.pdf" to also attach a
  # real blob from spec/fixtures/files (requires migrate_active_storage_schema!,
  # already run by the :db harness).
  def demo_documents!(attach: nil)
    contract = demo_contract
    [
      { title: "Zmluvný dokument", kind: "contract" },
      { title: "Príloha č. 1 — cenník", kind: "annex" }
    ].map do |attrs|
      doc = contract.documents.create!(attrs)
      doc.attach_file!(fixture_file(attach || "sample-notes.txt")) if attach != false
      doc.reload
    end
  end

  def demo_amendments!
    contract = demo_contract
    [1, 2].map { |v| contract.amendments.create!(version: v, summary: "Demo zmena č. #{v}") }
  end

  private

  def fixture_file(name)
    path = File.join(engine_root, "spec", "fixtures", "files", name)
    File.open(path)
  end
end

RSpec.configure { |config| config.include ContractsSkDemoData, :db }
