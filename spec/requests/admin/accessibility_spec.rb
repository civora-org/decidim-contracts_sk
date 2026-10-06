# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Accessibility regressions on the engine admin (civora-org/civora-platform
# #133, WCAG 2.1 AA / EN 301 549): table headers and names, the active-chip
# state and the accessible names of repeated per-row controls. Each example
# pins one attribute or structure the axe-core / keyboard audit asked for.
# DB-backed (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin accessibility markup (#133)", :db, type: :request do
  let(:doc) { Nokogiri::HTML(response.body) }
  let(:me) { Decidim::User.create!(organization: organization, name: "Mia Editor") }
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:author) { me }
  let(:draft) do
    contract_class.create!(contract_attributes(title: "Cesta k lesu", reference: "ZP-A11Y-001", state: "draft"))
  end

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[editor reviewer] }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  before do
    migrate_engine_schema!
    draft

    [Decidim::ContractsSk::Admin::ContractsController, Decidim::ContractsSk::Admin::PartiesController,
     Decidim::ContractsSk::Admin::AuditEventsController, Decidim::ContractsSk::Admin::DashboardController,
     Decidim::ContractsSk::Admin::TemplatesController].each do |controller|
      allow_any_instance_of(controller).to receive(:current_user).and_return(me)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end
  end

  def header_cells
    doc.css("table thead th")
  end

  describe "contracts index" do
    before { get "/admin/contracts" }

    it "scopes every column header and gives the actions column a screen-reader name" do
      expect(header_cells).not_to be_empty
      expect(header_cells.map { |th| th["scope"] }.uniq).to eq(["col"])
      actions = header_cells.last
      expect(actions.text.strip).to eq("Actions")
      expect(actions.at_css("span.cs-admin-sr-only")).not_to be_nil
      expect(header_cells.reject { |th| th.text.strip.present? }).to be_empty
    end

    it "names the table by the page heading" do
      title_id = doc.at_css("h1")["id"]

      expect(title_id).to eq("cs-contracts-title")
      expect(doc.at_css("table.table-list")["aria-labelledby"]).to eq(title_id)
    end

    it "marks the active state chip with aria-current and no other chip" do
      get "/admin/contracts", params: { state: "draft" }

      current = doc.css(".contracts-sk__counter[aria-current]")
      expect(current.map { |chip| chip.text.strip }).to eq(["Draft (1)"])
    end

    it "marks the All chip when no state is selected" do
      current = doc.css(".contracts-sk__counter[aria-current]")

      expect(current.map { |chip| chip.text.strip }).to eq(["All (1)"])
    end

    it "marks the active deadline chip" do
      get "/admin/contracts", params: { deadline: "overdue" }

      current = doc.css(".contracts-sk__counter[aria-current]").map { |chip| chip.text.strip }
      expect(current.size).to eq(2)
      expect(current.grep(/overdue/i)).not_to be_empty
    end

    it "names each per-row control after its record, visible label first" do
      row = doc.at_css("tbody tr")
      names = row.css("a[aria-label], input[aria-label], summary[aria-label]").map { |el| el["aria-label"] }

      expect(names).to include("Edit contract: Cesta k lesu")
      expect(names.grep(/\ASubmit for review: Cesta k lesu\z/)).not_to be_empty
      expect(names).to include("Privacy redaction: Cesta k lesu")
      expect(names).to all(end_with(": Cesta k lesu"))
    end
  end

  describe "other admin tables" do
    it "scopes headers and names the audit-trail table" do
      Decidim::ContractsSk::AuditEvent.create!(action: "contract.submit", target: draft, organization: organization,
                                               actor: me)

      get "/admin/audit_events"

      expect(header_cells.map { |th| th["scope"] }.uniq).to eq(["col"])
      expect(doc.at_css("table")["aria-labelledby"]).to eq("cs-audit-title")
      expect(doc.at_css("#cs-audit-title")).not_to be_nil
    end

    it "scopes the parties table headers and names it by the page heading" do
      draft.parties.create!(role: "contractor", name: "Dodávateľ s.r.o.")

      get "/admin/contracts/#{draft.id}/parties"

      expect(header_cells.map { |th| th["scope"] }.uniq).to eq(["col"])
      expect(doc.at_css("table")["aria-labelledby"]).to eq("cs-parties-title")
      expect(doc.at_css("h1#cs-parties-title")).not_to be_nil
      expect(header_cells.reject { |th| th.text.strip.present? }).to be_empty
    end

    it "scopes the edit page's documents and links tables and names each by its heading" do
      draft.documents.create!(title: "Scan", kind: "annex")
      draft.links.create!(target_type: "Decidim::Accountability::Result", target_id: 12)

      get "/admin/contracts/#{draft.id}/edit"

      tables = doc.css("table.table-list")
      expect(tables.size).to eq(2)
      expect(tables.map { |t| t["aria-labelledby"] }).to eq(%w[cs-documents-title cs-links-title])
      expect(tables.flat_map { |t| t.css("thead th").map { |th| th["scope"] } }.uniq).to eq(["col"])
      %w[cs-documents-title cs-links-title].each { |id| expect(doc.at_css("##{id}")).not_to be_nil }
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
