# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin contracts index submitter filter
# (civora-org/civora-platform#126): the normalized ?submitter=me|others
# param the dashboard's review-queue and returned-to-me links point at.
# DB-backed (CONTRACTS_SK_DB=1, in-memory SQLite), same harness seam as the
# CRZ deadline filter spec.
# ---------------------------------------------------------------------------

require "spec_helper"

# Dense assertions per example by design; allow_any_instance_of is the
# harness' approved seam for the Devise-ish controller methods.
# rubocop:disable RSpec/MultipleExpectations, RSpec/AnyInstance
RSpec.describe "admin contracts submitter filter", :db, type: :request do
  let(:me) { Decidim::User.create!(organization: organization, name: "Mia Reviewer") }
  let(:colleague) { Decidim::User.create!(organization: organization, name: "Colin Colleague") }
  let(:author) { colleague }
  let(:contract_class) { Decidim::ContractsSk::Contract }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[editor reviewer] }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  before do
    migrate_engine_schema!

    controller = Decidim::ContractsSk::Admin::ContractsController
    allow_any_instance_of(controller).to receive(:current_user).and_return(me)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)

    contract_class.create!(contract_attributes(reference: "ZP-SB-001", state: "in_review",
                                               decidim_submitted_by_id: me.id))
    contract_class.create!(contract_attributes(reference: "ZP-SB-002", state: "in_review",
                                               decidim_submitted_by_id: colleague.id))
    contract_class.create!(contract_attributes(reference: "ZP-SB-003", state: "in_review",
                                               decidim_submitted_by_id: nil))
    contract_class.create!(contract_attributes(reference: "ZP-SB-004", state: "returned",
                                               decidim_submitted_by_id: me.id))
  end

  def references
    response.body.scan(/ZP-SB-\d+/).uniq.sort
  end

  it "shows only the user's own submissions for submitter=me" do
    get "/admin/contracts", params: { submitter: "me" }

    expect(references).to eq(%w[ZP-SB-001 ZP-SB-004])
  end

  it "shows everyone else's submissions, NULL stamps included, for submitter=others" do
    get "/admin/contracts", params: { submitter: "others" }

    expect(references).to eq(%w[ZP-SB-002 ZP-SB-003])
  end

  it "combines with the state filter (the dashboard queue link)" do
    get "/admin/contracts", params: { state: "in_review", submitter: "others" }

    expect(references).to eq(%w[ZP-SB-002 ZP-SB-003])
  end

  it "falls back to the default view on a garbage submitter value, without the filtered wording" do
    get "/admin/contracts", params: { submitter: "bogus" }

    expect(references).to eq(%w[ZP-SB-001 ZP-SB-002 ZP-SB-003 ZP-SB-004])
    expect(response.body).not_to include("No contracts match the current filters.")
  end

  it "treats an array-shaped submitter param as garbage (no 500)" do
    get "/admin/contracts", params: { submitter: %w[me others] }

    expect(response).to have_http_status(:ok)
    expect(references.size).to eq(4)
  end

  it "uses the filtered empty state when the filter matches nothing" do
    contract_class.where(decidim_submitted_by_id: me.id).delete_all

    get "/admin/contracts", params: { submitter: "me" }

    expect(response.body).to include("No contracts match the current filters.")
  end

  it "pre-selects the active submitter in the filter form and offers the three options" do
    get "/admin/contracts", params: { submitter: "others" }

    expect(response.body).to match(%r{<option selected="selected" value="others">Submitted by others</option>})
    expect(response.body).to include("Any submitter", "Submitted by me")
  end

  it "keeps the submitter filter on the state chips" do
    get "/admin/contracts", params: { submitter: "me" }

    expect(response.body).to include("submitter=me")
  end

  it "carries the submitter filter in the pagination links" do
    stub_const("Decidim::ContractsSk::CONTRACTS_PER_PAGE", 1)

    get "/admin/contracts", params: { submitter: "others" }

    expect(response.body).to include("submitter=others")
    expect(response.body).to include(%(rel="next"))
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/AnyInstance
