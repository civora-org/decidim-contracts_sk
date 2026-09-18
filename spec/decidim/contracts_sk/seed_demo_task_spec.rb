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
    # the cross-tenant control record.
    expect { run_seed! }.to change(Decidim::ContractsSk::Contract, :count).by(10)

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
