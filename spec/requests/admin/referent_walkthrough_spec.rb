# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the fixes that came out of the 3. 11. 2026 walkthrough of
# the admin as a real referent (one example group per finding where the
# behaviour is not already pinned in the page's own spec file):
#
# #5  the admin home offers "New contract from a template" next to "New
#     contract", only to someone who may create one and only when the
#     organization has an active template;
# #7  a lifecycle step lands on the contract (not the list) with a message
#     naming what happened, and falls back to the list when the actor can no
#     longer read the record;
# #4  a publish the server refuses (redaction not confirmed) comes back to the
#     contract with the reason;
# #1  "back to the contract" links never point at the edit page of a record
#     that is no longer editable (it answers "not authorized").
#
# DB-backed (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "referent walkthrough fixes", :db, type: :request do
  let(:me) { Decidim::User.create!(organization: organization, name: "Mia Editor") }
  let(:colleague) { Decidim::User.create!(organization: organization, name: "Colin Colleague") }
  let(:author) { colleague }
  let(:resolver_roles) { %i[editor] }
  let(:contract_class) { Decidim::ContractsSk::Contract }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  before do
    migrate_engine_schema!

    base = Decidim::ContractsSk::Admin::ApplicationController
    allow_any_instance_of(base).to receive(:current_user).and_return(me)
    allow_any_instance_of(base).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(base).to receive(:current_organization).and_return(organization)
  end

  def contract!(state, **extra)
    contract_class.create!(contract_attributes(reference: "ZP-RW-#{contract_class.count + 1}", state: state)
                                              .merge(extra))
  end

  def links
    Nokogiri::HTML(response.body).css("a").to_h { |a| [a["href"], a.text.squish] }
  end

  def template!(status: "active")
    Decidim::ContractsSk::ContractTemplate.create!(organization: organization, lineage_key: "kupna-#{status}",
                                                   version: 1, name: "Kúpna zmluva", status: status)
  end

  describe "the admin home offers a contract from a template (#5)" do
    it "shows the link next to \"New contract\" when there is an active template" do
      template!

      get "/admin"

      expect(links).to include("/admin/contract_templates" => "New contract from a template",
                               "/admin/contracts/new" => "New contract")
    end

    it "shows no such link when the organization has no active template" do
      template!(status: "archived")

      get "/admin"

      expect(links).to include("/admin/contracts/new")
      expect(links).not_to include("/admin/contract_templates")
    end

    it "shows it to nobody who cannot create contracts" do
      template!
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }

      get "/admin"

      expect(response).to have_http_status(:ok)
      expect(links).not_to include("/admin/contract_templates")
    end
  end

  describe "a lifecycle step stays on the contract (#7)" do
    {
      submit: ["draft", "The contract was submitted for review."],
      archive: ["published", "The contract was archived."]
    }.each do |event, (state, message)|
      it "lands on the contract page with the #{event} message" do
        record = contract!(state)

        post "/admin/contracts/#{record.id}/#{event}"

        expect(response).to redirect_to("/admin/contracts/#{record.id}")
        expect(flash[:notice]).to eq(message)
      end
    end

    it "publishes an approved, redaction-confirmed contract and says so" do
      record = contract!("approved", redaction_confirmed_at: Time.current)

      post "/admin/contracts/#{record.id}/publish"

      expect(response).to redirect_to("/admin/contracts/#{record.id}")
      expect(flash[:notice]).to eq("The contract is published in the catalogue.")
    end

    it "falls back to the list when the actor can no longer read the record" do
      record = contract!("draft")
      allow_any_instance_of(Decidim::ContractsSk::Admin::ContractsController)
        .to receive(:allowed_to?).and_wrap_original do |original, action, *rest, **options|
          action == :read ? false : original.call(action, *rest, **options)
        end

      post "/admin/contracts/#{record.id}/submit"

      expect(contract_class.find(record.id).state).to eq("in_review")
      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:notice]).to eq("The contract was submitted for review.")
    end
  end

  describe "a refused publish comes back to the contract (#4)" do
    it "redirects to the contract page, with the reason, when the redaction is not confirmed" do
      record = contract!("approved")

      post "/admin/contracts/#{record.id}/publish"

      expect(response).to redirect_to("/admin/contracts/#{record.id}")
      expect(flash[:alert]).to include("first confirm that personal data is hidden")
      expect(record.reload.state).to eq("approved")
    end
  end

  describe "back links never lead to a page the person may not open (#1)" do
    {
      "notes" => "/admin/contracts/%<id>d/notes",
      "amendments" => "/admin/contracts/%<id>d/amendments",
      "parties" => "/admin/contracts/%<id>d/parties"
    }.each do |name, template|
      it "points the #{name} page of a published contract back to the contract, not its edit page" do
        record = contract!("published")

        get format(template, id: record.id)

        expect(response).to have_http_status(:ok)
        expect(links).to include("/admin/contracts/#{record.id}")
        expect(links).not_to include("/admin/contracts/#{record.id}/edit")
      end
    end
  end

  describe "the CRZ number box on the import form takes a pasted CRZ address (#3)" do
    it "reads the id out of the address" do
      allow(Decidim::ContractsSk::CrzImport::Sync).to receive(:import_one).and_return(:unchanged)

      post "/admin/contracts/import_crz", params: { source_id: "https://www.crz.gov.sk/zmluva/12851898/" }

      expect(Decidim::ContractsSk::CrzImport::Sync)
        .to have_received(:import_one).with(hash_including(source_id: "12851898"))
    end

    it "still refuses an address on another site" do
      allow(Decidim::ContractsSk::CrzImport::Sync).to receive(:import_one)

      post "/admin/contracts/import_crz", params: { source_id: "https://evil.example/zmluva/12851898/" }

      expect(Decidim::ContractsSk::CrzImport::Sync).not_to have_received(:import_one)
      expect(flash[:alert]).to be_present
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
