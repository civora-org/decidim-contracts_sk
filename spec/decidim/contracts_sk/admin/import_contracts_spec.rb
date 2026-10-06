# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for Admin::ImportContracts (civora-org/civora-platform#129), against
# the real migrations on in-memory SQLite (CONTRACTS_SK_DB=1). The command
# takes a validated Preview; it must create DRAFTS only, in one transaction,
# with one audit row per record, and refuse anything the preview rejects.
# Fictional data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# Each example pins one scenario with several related expectations by design.
# rubocop:disable RSpec/ExampleLength

RSpec.describe Decidim::ContractsSk::Admin::ImportContracts, :db do
  let(:header) { "reference,title,amount,party_roles,party_icos,party_names" }
  let(:csv) do
    "#{header}\nDEMO-1,Cesta,100.50,object | contractor,00000001 | 00000002,Obec Ukážková | Cesty Demo s.r.o.\n" \
      "DEMO-2,Most,,,,\n"
  end
  let(:preview) { Decidim::ContractsSk::SpreadsheetImport::Preview.new(csv, organization: organization) }
  let(:contract_model) { Decidim::ContractsSk::Contract }

  before { migrate_engine_schema! }

  def run(subject_preview = preview, user: author, org: organization)
    outcome = nil
    described_class.call(subject_preview, user: user, organization: org) do
      on(:ok) { |contracts| outcome = [:ok, contracts] }
      on(:invalid) { outcome = [:invalid] }
    end
    outcome
  end

  it "creates every row as a draft authored by the acting user, with its parties" do
    status, contracts = run

    aggregate_failures do
      expect(status).to eq(:ok)
      expect(contracts.map(&:reference)).to eq(%w[DEMO-1 DEMO-2])
      expect(contracts).to all(have_attributes(state: "draft", author: author, source: "editorial",
                                               published_at: nil, redaction_confirmed_at: nil,
                                               decidim_submitted_by_id: nil, crz_filed_at: nil))
      expect(contracts.first.amount).to eq(BigDecimal("100.50"))
      expect(contracts.first.parties.order(:id).map { |p| [p.role, p.ico, p.name] })
        .to eq([["object", "00000001", "Obec Ukážková"], ["contractor", "00000002", "Cesty Demo s.r.o."]])
    end
  end

  it "writes exactly one contract.imported_from_file audit row per record, by the actor" do
    _, contracts = run
    events = Decidim::ContractsSk::AuditEvent.order(:id)

    aggregate_failures do
      expect(events.map(&:action)).to eq(["contract.imported_from_file"] * 2)
      expect(events.map(&:target)).to eq(contracts)
      expect(events.map(&:actor).uniq).to eq([author])
      expect(events.map(&:organization).uniq).to eq([organization])
    end
  end

  it "refuses a preview that is not importable and writes nothing (all-or-nothing)" do
    bad = Decidim::ContractsSk::SpreadsheetImport::Preview.new("#{csv}DEMO-3,,,,,\n", organization: organization)

    aggregate_failures do
      expect(run(bad)).to eq([:invalid])
      expect(contract_model.count).to eq(0)
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end
  end

  it "is idempotent: a second run of the same file is refused (references taken) and adds nothing" do
    run
    again = Decidim::ContractsSk::SpreadsheetImport::Preview.new(csv, organization: organization)

    aggregate_failures do
      expect(run(again)).to eq([:invalid])
      expect(contract_model.count).to eq(2)
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(2)
    end
  end

  it "rolls the whole batch back when a reference is taken between preview and write" do
    stale = preview # validated while the organization held neither reference
    contract_model.create!(contract_attributes(reference: "DEMO-2"))

    aggregate_failures do
      expect(run(stale)).to eq([:invalid])
      expect(contract_model.pluck(:reference)).to eq(["DEMO-2"])
      expect(Decidim::ContractsSk::Party.count).to eq(0)
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end
  end

  it "refuses an actor from another organization (fail-closed tenancy)" do
    outsider = Decidim::User.create!(organization: Decidim::Organization.create!)

    aggregate_failures do
      expect(run(user: outsider)).to eq([:invalid])
      expect(contract_model.count).to eq(0)
    end
  end
end
# rubocop:enable RSpec/ExampleLength
