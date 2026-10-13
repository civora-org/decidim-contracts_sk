# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin contract page (GET /admin/contracts/:id) and the
# plain-language pass around it: the step indicator per state (which step is
# current, whose turn it is), the next-step controls per role (four-eyes
# included), the facts, the collapsed rarely-needed links, tenancy, and the
# data-quality filters the admin home links to (?missing=, ?deadline=unfiled).
# DB-backed (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin contract page", :db, type: :request do
  let(:me) { Decidim::User.create!(organization: organization, name: "Mia Reviewer") }
  let(:colleague) { Decidim::User.create!(organization: organization, name: "Colin Colleague") }
  let(:author) { colleague }
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:resolver_roles) { %i[editor reviewer] }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    seam = Decidim::ContractsSk.allow_self_review
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
    example.run
    Decidim::ContractsSk.role_resolver = original
    Decidim::ContractsSk.allow_self_review = seam
  end

  before do
    migrate_engine_schema!

    controller = Decidim::ContractsSk::Admin::ContractsController
    allow_any_instance_of(controller).to receive(:current_user).and_return(me)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
  end

  def contract!(state, **extra)
    contract_class.create!(contract_attributes(reference: "ZP-SH-#{contract_class.count + 1}", state: state,
                                               title: "Cesta k lesu").merge(extra))
  end

  # Parsed per call: examples that issue several requests must see the latest.
  def doc
    Nokogiri::HTML(response.body)
  end

  def steps
    doc.css("ol.cs-steps li").to_h do |li|
      [li.at_css(".cs-steps__label").text.gsub(/\(.*?\)/m, "").squish.sub(/ returned for changes\z/, ""),
       li["class"][/cs-steps__step--(\w+)/, 1]]
    end
  end

  def buttons
    doc.css("#cs-next-step input[type=submit], #cs-next-step button, #cs-next-step a.button, #cs-next-step summary")
       .map { |node| node["value"] || node.text.squish }
  end

  describe "the step indicator" do
    {
      "draft" => { "Draft" => "current", "Check" => "upcoming", "Approved" => "upcoming",
                   "Published" => "upcoming", "Filed in CRZ" => "upcoming" },
      "in_review" => { "Draft" => "done", "Check" => "current", "Approved" => "upcoming",
                       "Published" => "upcoming", "Filed in CRZ" => "upcoming" },
      "approved" => { "Draft" => "done", "Check" => "done", "Approved" => "current",
                      "Published" => "upcoming", "Filed in CRZ" => "upcoming" },
      "published" => { "Draft" => "done", "Check" => "done", "Approved" => "done",
                       "Published" => "current", "Filed in CRZ" => "upcoming" }
    }.each do |state, expected|
      it "marks the current step for a #{state} record" do
        record = contract!(state)

        get "/admin/contracts/#{record.id}"

        expect(response).to have_http_status(:ok)
        expect(steps).to eq(expected)
        expect(doc.css("li[aria-current=step]").size).to eq(1)
      end
    end

    it "keeps a returned draft on the first step and flags it" do
      record = contract!("returned", review_reason: "Fix the amount", reviewed_at: Time.current)

      get "/admin/contracts/#{record.id}"

      expect(steps).to include("Draft" => "current", "Check" => "upcoming")
      expect(doc.at_css(".cs-steps__flag").text).to eq("returned for changes")
      expect(response.body).to include("Fix the amount")
    end

    it "marks every step done once the CRZ filing is confirmed" do
      record = contract!("published", crz_filed_at: Time.current)

      get "/admin/contracts/#{record.id}"

      expect(steps.values.uniq).to eq(["done"])
      expect(doc.css("li[aria-current=step]")).to be_empty
      expect(response.body).to include("Done: the contract is published in the catalogue and filed in the CRZ.")
    end

    it "stops at the check for a rejected record" do
      record = contract!("rejected", review_reason: "Not lawful", reviewed_at: Time.current)

      get "/admin/contracts/#{record.id}"

      expect(steps).to include("Draft" => "done", "Rejected" => "stopped")
      expect(response.body).to include("Not lawful")
    end

    it "shows no process for a CRZ mirror" do
      record = contract!("published", source: Decidim::ContractsSk::CrzImport::Mapper::SOURCE)

      get "/admin/contracts/#{record.id}"

      expect(response).to have_http_status(:ok)
      expect(doc.css("ol.cs-steps")).to be_empty
    end

    it "never relies on colour alone: every step carries a marker and a screen-reader word" do
      record = contract!("in_review")

      get "/admin/contracts/#{record.id}"

      expect(doc.css(".cs-steps__marker").map { |m| m.text.strip }).to eq(["✓", "2", "3", "4", "5"])
      expect(doc.css(".cs-steps__step .cs-admin-sr-only").map { |n| n.text.squish }).to eq(
        ["(done)", "(current step)", "(not yet)", "(not yet)", "(not yet)"]
      )
    end
  end

  describe "whose turn it is" do
    it "says it is the person's turn when they can act, and not otherwise" do
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      theirs = contract!("in_review", decidim_submitted_by_id: colleague.id)
      own = contract!("in_review", decidim_submitted_by_id: me.id)

      get "/admin/contracts/#{theirs.id}"
      expect(response.body).to include("Your turn")

      get "/admin/contracts/#{own.id}"
      expect(response.body).not_to include("Your turn")
      expect(response.body).to include("someone other than the person who submitted it reviews the contract")
    end
  end

  describe "the next step per role" do
    it "offers a reviewer approve, return and reject on a record submitted by someone else" do
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      record = contract!("in_review", decidim_submitted_by_id: colleague.id)

      get "/admin/contracts/#{record.id}"

      expect(buttons.uniq).to contain_exactly("Approve", "Return for changes", "Reject")
      expect(doc.css("#cs-next-step textarea[required]").size).to eq(2)
    end

    it "offers the submitter none of the judgment controls (four-eyes)" do
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[editor reviewer] }
      record = contract!("in_review", decidim_submitted_by_id: me.id)

      get "/admin/contracts/#{record.id}"

      expect(doc.at_css("#cs-next-step")).to be_nil
    end

    it "offers an editor to submit a draft and to edit it, but a reviewer neither" do
      draft = contract!("draft")

      get "/admin/contracts/#{draft.id}"
      expect(buttons).to eq(["Submit for review"])
      expect(doc.css("a").map { |a| a["href"] }).to include("/admin/contracts/#{draft.id}/edit")

      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      get "/admin/contracts/#{draft.id}"
      expect(doc.at_css("#cs-next-step")).to be_nil
      expect(doc.css("a").map { |a| a["href"] }).not_to include("/admin/contracts/#{draft.id}/edit")
    end

    it "explains why the redaction confirmation is needed and holds the form for an approved, unstamped record" do
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[editor] }
      record = contract!("approved")

      get "/admin/contracts/#{record.id}"

      expect(buttons).to eq(["Publish"])
      expect(response.body).to include("Before publishing, first confirm that personal data is hidden (below).")
      expect(response.body).to include("A published contract is public")
      expect(doc.css("form[action$='/confirm_redaction']").size).to eq(1)
    end

    it "offers the CRZ filing confirmation for a published, unfiled editorial record to editors only" do
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[editor] }
      record = contract!("published")

      get "/admin/contracts/#{record.id}"
      expect(doc.css("a").map { |a| a["href"] }).to include("/admin/contracts/#{record.id}/crz_filing")

      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      get "/admin/contracts/#{record.id}"
      expect(doc.css("a").map { |a| a["href"] }).not_to include("/admin/contracts/#{record.id}/crz_filing")
    end
  end

  describe "the facts and the collapsed rest" do
    it "shows the amount, dates and parties, and marks what is missing" do
      record = contract!("draft", amount: 1250.5, currency: "EUR", signed_on: Date.new(2026, 3, 31),
                                  subject_matter: "Reconstruction of a forest road")
      record.parties.create!(role: "contractor", name: "Stavby s. r. o.", ico: "00000001")
      empty = contract!("draft")

      get "/admin/contracts/#{record.id}"
      expect(response.body).to include("1250.5 EUR", "Reconstruction of a forest road", "Stavby s. r. o.", "00000001")

      get "/admin/contracts/#{empty.id}"
      expect(doc.css(".cs-show__fact dd").map { |d| d.text.squish }).to include("missing")
    end

    it "keeps notes, history, parties and amendments inside a closed details block" do
      record = contract!("draft")

      get "/admin/contracts/#{record.id}"

      more = doc.at_css("details#cs-show-more")
      expect(more["open"]).to be_nil
      expect(more.css("a").map { |a| a["href"] }).to include(
        "/admin/contracts/#{record.id}/notes", "/admin/contracts/#{record.id}/parties",
        "/admin/contracts/#{record.id}/amendments"
      )
    end

    it "is tenant-scoped: another organization's record is a 404" do
      foreign = Decidim::Organization.create!
      stranger = Decidim::User.create!(organization: foreign, name: "Frank Foreign")
      record = contract!("draft", organization: foreign, author: stranger)

      expect { get "/admin/contracts/#{record.id}" }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "denies a signed-in user without an engine role" do
      record = contract!("draft")
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { [] }

      get "/admin/contracts/#{record.id}"

      expect(response).to have_http_status(:redirect)
      expect(response.body).not_to include("Cesta k lesu")
    end
  end

  describe "the list stays short and plain" do
    it "shows one visible action per row and keeps the rest in a collapsed block" do
      record = contract!("draft")

      get "/admin/contracts"

      row = doc.at_css("tbody tr")
      expect(row.at_css("td a").text).to eq("Cesta k lesu")
      expect(row.at_css("td a")["href"]).to eq("/admin/contracts/#{record.id}")
      open_button = row.at_css("td.table-list__actions > form button, td.table-list__actions > form input")
      expect(open_button.to_s).to include("Open")
      expect(row.at_css("details.cs-row-more")["open"]).to be_nil
    end

    it "collapses the filters, the CRZ lookup and the imports, but keeps the search visible" do
      get "/admin/contracts"

      expect(doc.at_css("input[name=q]")).not_to be_nil
      expect(doc.at_css("details.cs-admin-filters")["open"]).to be_nil
      expect(doc.at_css("details#cs-admin-tools")["open"]).to be_nil
      expect(doc.at_css("details#cs-admin-tools form[action$='/import_crz']")).not_to be_nil
    end

    it "opens the filters by itself when one is in use" do
      get "/admin/contracts", params: { source: "editorial" }

      expect(doc.at_css("details.cs-admin-filters")["open"]).not_to be_nil
    end
  end

  describe "the lists the admin home links to" do
    def references
      response.body.scan(/ZP-SH-\d+/).uniq.sort
    end

    it "lists editable records without an amount for ?missing=amount, and nothing else" do
      lacking = contract!("draft", signed_on: Date.current)
      contract!("draft", amount: 5, signed_on: Date.current)
      contract!("in_review", signed_on: Date.current)
      contract!("published")

      get "/admin/contracts", params: { missing: "amount" }

      expect(references).to eq([lacking.reference])
      expect(response.body).to include("Showing drafts without an amount.")
    end

    it "lists editable records without a signing date for ?missing=signed_on" do
      lacking = contract!("returned", amount: 5)
      contract!("draft", amount: 5, signed_on: Date.current)

      get "/admin/contracts", params: { missing: "signed_on" }

      expect(references).to eq([lacking.reference])
    end

    it "falls back to the default view on a garbage ?missing= value" do
      contract!("draft", amount: 5)

      get "/admin/contracts", params: { missing: "bogus" }

      expect(references.size).to eq(1)
      expect(response.body).not_to include("Showing drafts")
    end

    it "lists every tracked, unfiled editorial record for ?deadline=unfiled" do
      open = contract!("published")
      contract!("published", crz_filed_at: Time.current)
      contract!("published", source: Decidim::ContractsSk::CrzImport::Mapper::SOURCE)
      contract!("rejected")

      get "/admin/contracts", params: { deadline: "unfiled", state: "published" }

      expect(references).to eq([open.reference])
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
