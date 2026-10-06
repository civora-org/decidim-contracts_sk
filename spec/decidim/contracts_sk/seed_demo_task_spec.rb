# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Spec for the demo-seed rake task (civora-org/civora-platform#88): the two
# synthetic CRZ-imported records (DEMO-2026-008 fresh mirror, DEMO-2026-009
# deliberately stale mirror) and the idempotency of their imported_at stamp.
#
# Harness: the :db group boots the dummy app, so the task's `:environment`
# dependency is satisfied with a no-op stand-in task and the REAL task file
# is loaded into an isolated Rake application (a fresh Rake::Application per
# example keeps the loaded namespace from leaking between examples). The
# shared :db support extends the organization/user stand-in tables with the
# columns the task writes (see contracts_sk_db_helpers.rb).
#
# Cop note: the describe targets a rake task (no class), and the examples
# deliberately pin several related facts each — the same dense-assertion
# stance as the request specs.
#
# rubocop:disable RSpec/DescribeClass, RSpec/MultipleExpectations, RSpec/ExampleLength
# ---------------------------------------------------------------------------

require "spec_helper"
require "rake"
require "digest"

RSpec.describe "decidim_contracts_sk:seed_demo demo seed task", :db do
  before do
    migrate_engine_schema!

    Rake.application = Rake::Application.new
    load File.join(engine_root, "lib", "tasks", "decidim_contracts_sk_seed_demo.rake")
    Rake::Task.define_task(:environment)
  end

  def run_seed!
    task = Rake::Task["decidim_contracts_sk:seed_demo"]
    task.reenable
    task.invoke(organization.id.to_s)
  end

  it "creates the imported demo records with full provenance and parties" do
    # The two imported records on top of the seven lifecycle states plus
    # the cross-tenant control record, plus the 24 statistics-demo records
    # (#118).
    expect { run_seed! }.to change(Decidim::ContractsSk::Contract, :count).by(34)

    fresh = Decidim::ContractsSk::Contract.find_by!(reference: "DEMO-2026-008")
    stale = Decidim::ContractsSk::Contract.find_by!(reference: "DEMO-2026-009")
    aggregate_failures do
      expect(fresh.state).to eq("published")
      expect(fresh.source).to eq("crz")
      expect(fresh.source_id).to eq("900000001")
      expect(fresh.import_status).to eq("succeeded")
      expect(fresh.checksum).to eq(Digest::SHA256.hexdigest("demo-900000001"))
      expect(fresh.imported_at).to be_present
      expect(fresh.crz_url).to eq("https://crz.gov.sk/zmluva/900000001/")
      expect(fresh.parties.map(&:role)).to contain_exactly("object", "contractor")

      # The stale mirror carries the same provenance shape, but its
      # import timestamp sits well beyond the default 48 h stale_after.
      expect(stale.source).to eq("crz")
      expect(stale.source_id).to eq("900000002")
      expect(stale.import_status).to eq("succeeded")
      expect(stale.imported_at).to be < 48.hours.ago
    end
  end

  # Statistics demo (civora-org/civora-platform#118): the page must look real
  # on the seeded organization, and re-seeding must not duplicate anything.
  describe "the statistics demo records (civora-org/civora-platform#118)" do
    include ActiveSupport::Testing::TimeHelpers

    let(:stats_refs) { (10..33).map { |n| format("DEMO-2026-%03d", n) } }
    let(:records) { Decidim::ContractsSk::Contract.where(reference: stats_refs) }

    around { |example| travel_to(Time.zone.local(2026, 10, 15, 12)) { example.run } }

    it "seeds 24 published records, none dated in the future, with the intended mix" do
      run_seed!

      expect(records.count).to eq(24)
      expect(records.map(&:state).uniq).to eq(["published"])
      expect(records.map(&:signed_on).max).to be <= Date.new(2026, 10, 15)
      expect(records.where(amount: nil).count).to eq(2)
      expect(records.where(source: "crz").count).to eq(3)
      expect(records.where(source: "crz").pluck(:import_status).uniq).to eq(["succeeded"])
      expect(records.where.not(source: "crz").pluck(:redaction_confirmed_at)).to all(be_present)
      expect(records.where.not(source: "crz").pluck(:crz_filed_at)).to all(be_present)
    end

    it "gives the statistics page a populated twelve-month trend and repeat suppliers with valid IČOs" do
      run_seed!
      stats = Decidim::ContractsSk::CatalogueStatistics.new(
        scope: Decidim::ContractsSk::Contract.where(organization: organization).published,
        time_zone: Time.zone, today: Date.new(2026, 10, 15)
      ).call

      expect(stats.months.size).to eq(12)
      expect(stats.months.count { |row| row.count.positive? }).to eq(12)
      expect(stats.crz.count).to be >= 3
      expect(stats.top_by_count.size).to eq(7)
      expect(stats.top_by_count.map(&:ico)).to all(match(Decidim::ContractsSk::ICO_FORMAT))
      expect(stats.top_by_count.map(&:count).max).to be > 3
      expect(stats.top_by_amount.fetch("EUR").first.ico).not_to eq(stats.top_by_count.first.ico)
    end

    it "seeds DEMO-2026-010 as the play-equipment contract" do
      run_seed!

      record = Decidim::ContractsSk::Contract.find_by!(reference: "DEMO-2026-010")
      expect(record.title).to eq("Dodávka a montáž herných prvkov na detské ihriská")
      expect(record.amount).to eq(BigDecimal("23600.00"))
      expect([record.state, record.source]).to eq(%w[published editorial])
      expect(record.parties.where(role: "contractor").count).to eq(1)
    end

    it "leaves an existing DEMO-2026-010 and its contractor untouched on a re-seed" do
      run_seed!
      record = Decidim::ContractsSk::Contract.find_by!(reference: "DEMO-2026-010")
      record.update_columns(amount: BigDecimal("1.00"), signed_on: Date.new(2026, 1, 2))
      record.parties.find_by!(role: "contractor").update_columns(name: "Hostiteľský dodávateľ s.r.o.")

      run_seed!

      record.reload
      expect([record.title, record.amount, record.signed_on]).to eq(
        ["Dodávka a montáž herných prvkov na detské ihriská", BigDecimal("1.00"), Date.new(2026, 1, 2)]
      )
      expect(record.parties.where(role: "contractor").pluck(:name)).to eq(["Hostiteľský dodávateľ s.r.o."])
      expect(record.parties.count).to eq(2)
    end

    it "is idempotent: a second run adds no contracts or parties" do
      run_seed!

      counts = -> { [Decidim::ContractsSk::Contract.count, Decidim::ContractsSk::Party.count] }

      expect { run_seed! }.not_to(change { counts.call })
    end

    it "keeps the admin CRZ deadline chips untouched (the new records are filed or mirrors)" do
      run_seed!

      statuses = records.map(&:crz_deadline_status).uniq

      expect(statuses).to eq([:untracked])
    end

    it "keeps the same references when re-seeded on a later day, sliding the dates" do
      run_seed!
      first = records.order(:reference).pluck(:reference, :signed_on)
      travel_to(Time.zone.local(2026, 11, 20, 12))
      run_seed!

      expect(records.order(:reference).pluck(:reference)).to eq(first.map(&:first))
      expect(records.order(:reference).pluck(:signed_on)).not_to eq(first.map(&:last))
    end
  end

  # CRZ deadline demo (civora-org/civora-platform#124): DEMO-2026-003 is
  # signed relative to the seeding day so its deadline is 7 days away. The
  # dates include month ends and a leap day, where plain date subtraction
  # is off; where a clamp gap makes exactly 7 unreachable (no signing date
  # has that deadline) the record lands on the next reachable day, still
  # inside the 14-day window.
  describe "the CRZ deadline demo record (civora-org/civora-platform#124)" do
    include ActiveSupport::Testing::TimeHelpers

    [
      Date.new(2026, 10, 3), Date.new(2026, 11, 30), Date.new(2027, 1, 31), Date.new(2027, 2, 28),
      Date.new(2027, 5, 22), Date.new(2027, 5, 31), Date.new(2027, 8, 31), Date.new(2028, 2, 29), Date.new(2028, 5, 22)
    ].each do |day|
      it "is due soon with the deadline on or just after today + 7 when seeded on #{day}" do
        travel_to(day.in_time_zone.change(hour: 12)) do
          run_seed!

          record = Decidim::ContractsSk::Contract.find_by!(reference: "DEMO-2026-003")
          reachable = (record.signed_on - 10.days..record.signed_on + 10.days)
                      .map { |signed| signed + Decidim::ContractsSk.crz_deadline }
          expected = reachable.include?(day + 7) ? 7 : (reachable.select { |d| d > day + 7 }.min - day).to_i

          expect(record.crz_days_left(today: day)).to eq(expected)
          expect(record.crz_deadline_status(today: day)).to eq(:due_soon)
          expect(record).to be_in(Decidim::ContractsSk::Contract.crz_due_soon(day))
        end
      end
    end

    it "demonstrates every badge: overdue, due soon and deadline unknown" do
      travel_to(Time.zone.local(2026, 10, 3, 12)) do
        run_seed!

        status = ->(ref) { Decidim::ContractsSk::Contract.find_by!(reference: ref).crz_deadline_status }
        expect(status.call("DEMO-2026-001")).to eq(:unknown)
        expect(status.call("DEMO-2026-002")).to eq(:overdue)
        expect(status.call("DEMO-2026-003")).to eq(:due_soon)
        expect(status.call("DEMO-2026-004")).to eq(:overdue)
        expect(status.call("DEMO-2026-006")).to eq(:untracked)
        expect(status.call("DEMO-2026-008")).to eq(:untracked)
      end
    end

    it "re-signs DEMO-2026-003 on a re-seed so the demo can be refreshed" do
      travel_to(Time.zone.local(2026, 10, 3, 12)) { run_seed! }
      first = Decidim::ContractsSk::Contract.find_by!(reference: "DEMO-2026-003").signed_on

      travel_to(Time.zone.local(2026, 10, 20, 12)) { run_seed! }

      expect(Decidim::ContractsSk::Contract.find_by!(reference: "DEMO-2026-003").signed_on).to be > first
    end
  end

  describe "the contract templates (civora-org/civora-platform#127)" do
    it "seeds three fictional templates with a valid object-party skeleton in the seeded organization only" do
      run_seed!

      templates = Decidim::ContractsSk::Template.all.to_a
      expect(templates.size).to eq(3)
      expect(templates.map(&:decidim_organization_id).uniq).to eq([organization.id])
      expect(templates.map(&:name)).to include("Nájomná zmluva – nebytové priestory", "Zmluva o dielo")
      expect(templates).to all(be_valid)
      expect(templates.map(&:party_skeleton)).to all(include(role: "object", ico: "00000001"))
    end

    it "is idempotent and leaves an editor-changed template alone on a re-seed" do
      run_seed!
      Decidim::ContractsSk::Template.find_by!(name: "Zmluva o dielo").update!(subject_matter: "Edited by an editor")

      expect { run_seed! }.not_to change(Decidim::ContractsSk::Template, :count)
      expect(Decidim::ContractsSk::Template.find_by!(name: "Zmluva o dielo").subject_matter)
        .to eq("Edited by an editor")
    end
  end

  it "resets any submitter stamp on re-seed (four-eyes, civora-org/civora-platform#123)" do
    run_seed!
    contract = Decidim::ContractsSk::Contract.find_by!(reference: "DEMO-2026-002")
    contract.update!(decidim_submitted_by_id: contract.author.id)

    run_seed!

    expect(contract.reload.decidim_submitted_by_id).to be_nil
  end

  it "never refreshes imported_at on re-seed (the new-record guard, issue #88)" do
    run_seed!
    stamped = %w[DEMO-2026-008 DEMO-2026-009].index_with do |ref|
      Decidim::ContractsSk::Contract.find_by!(reference: ref).imported_at
    end

    run_seed!

    # Re-seeding upserts the records but must not refresh freshness
    # metadata — the stale demo would silently heal itself otherwise.
    aggregate_failures do
      stamped.each do |ref, imported_at|
        expect(Decidim::ContractsSk::Contract.find_by!(reference: ref).imported_at).to eq(imported_at)
      end
      expect(Decidim::ContractsSk::Contract.where(reference: %w[DEMO-2026-008 DEMO-2026-009]).count).to eq(2)
    end
  end
end

# rubocop:enable RSpec/DescribeClass, RSpec/MultipleExpectations, RSpec/ExampleLength
