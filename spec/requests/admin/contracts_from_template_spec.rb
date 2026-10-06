# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for "new contract from template" (civora-org/civora-platform
# #127): the prefilled new-contract form, the copy-on-create draft with its
# object party and audit row, and the guarantees that a template never
# publishes anything or bypasses the workflow. :db only (CONTRACTS_SK_DB=1),
# in-memory SQLite. Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"
require "nokogiri"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin new contract from a template", :db, type: :request do
  let(:resolver_roles) { %i[editor] }
  let(:other_org) { Decidim::Organization.create! }
  let(:template) do
    Decidim::ContractsSk::Template.create!(
      organization: organization, name: "Rental of premises", title_pattern: "Rental - ",
      subject_matter: "Rental of municipal premises.", currency: "EUR",
      object_party_name: "Mesto Demo", object_party_ico: "00000001", object_party_address: "Main 1"
    )
  end

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  before do
    migrate_engine_schema!
    template

    controller = Decidim::ContractsSk::Admin::ContractsController
    allow_any_instance_of(controller).to receive(:current_user).and_return(author)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
  end

  def unauthorized
    "You are not authorized to perform this action."
  end

  def contract_class
    Decidim::ContractsSk::Contract
  end

  def audit_class
    Decidim::ContractsSk::AuditEvent
  end

  def create_from_template(template_id: template.id, **contract_overrides)
    params = { title: "Rental - Shop 4", reference: "ZP-2026-100", subject_matter: "Rental of municipal premises.",
               currency: "EUR" }.merge(contract_overrides)
    post "/admin/contracts", params: { template_id: template_id, contract: params }
  end

  describe "the new-contract form" do
    it "offers blank and every template as choices, the blank one current" do
      Decidim::ContractsSk::Template.create!(organization: organization, name: "Works")
      Decidim::ContractsSk::Template.create!(organization: other_org, name: "Theirs")

      get "/admin/contracts/new"

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      choices = doc.css(".cs-admin-chips a")
      expect(choices.map { |a| a.text.strip }).to eq(["Blank contract", "Rental of premises", "Works"])
      expect(choices.first["aria-current"]).to eq("true")
      expect(choices.first["class"]).not_to include("cs-admin-choice--idle")
      expect(choices.drop(1)).to all(satisfy { |a| a["class"].include?("cs-admin-choice--idle") })
      expect(choices[1]["href"]).to eq("/admin/contracts/new?template_id=#{template.id}")
      expect(response.body).not_to include("Theirs")
      expect(doc.at_css("#contract_title")["value"].to_s).to eq("")
      expect(doc.at_css("input[name='template_id']")).to be_nil
    end

    it "shows no chooser when the organization has no templates" do
      template.destroy!

      get "/admin/contracts/new"

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css(".cs-admin-chips")).to be_empty
    end

    it "prefills title, subject matter and currency from the picked template and carries its id" do
      get "/admin/contracts/new", params: { template_id: template.id }

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("#contract_title")["value"]).to eq("Rental - ")
      expect(doc.at_css("#contract_subject_matter").text.strip).to eq("Rental of municipal premises.")
      expect(doc.at_css("#contract_currency option[selected]").text).to eq("EUR")
      expect(doc.at_css("#contract_reference")["value"].to_s).to eq("")
      expect(doc.at_css("#contract_amount")["value"].to_s).to eq("")
      expect(doc.at_css("input[type=hidden][name='template_id']")["value"]).to eq(template.id.to_s)
      expect(doc.css(".cs-admin-chips a").find { |a| a["aria-current"] == "true" }.text).to eq("Rental of premises")
      expect(response.body).to include("Mesto Demo, 00000001")
      expect(contract_class.count).to eq(0)
    end

    it "404s for a template of another organization, an unknown id and a malformed id (never a silent blank form)" do
      foreign = Decidim::ContractsSk::Template.create!(organization: other_org, name: "Theirs")

      [foreign.id, 0, "abc"].each do |id|
        expect { get "/admin/contracts/new", params: { template_id: id } }
          .to raise_error(ActiveRecord::RecordNotFound), "template_id=#{id}"
      end
    end

    it "treats a blank template_id as a blank form" do
      get "/admin/contracts/new", params: { template_id: "" }

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("#contract_title")["value"].to_s).to eq("")
    end
  end

  describe "creating the draft" do
    it "creates a draft with the submitted values, copies the object party and audits it" do
      expect { create_from_template }
        .to change(contract_class, :count).by(1)
        .and change(Decidim::ContractsSk::Party, :count).by(1)
        .and change(audit_class, :count).by(1)

      expect(response).to redirect_to("/admin/contracts")
      contract = contract_class.sole
      expect(contract.state).to eq("draft")
      expect(contract.published_at).to be_nil
      expect(contract.title).to eq("Rental - Shop 4")
      expect(contract.parties.sole.attributes.values_at("role", "name", "ico", "address"))
        .to eq(["object", "Mesto Demo", "00000001", "Main 1"])
      expect(audit_class.last.action).to eq("contract.create_from_template")
      expect(audit_class.last.target).to eq(contract)
    end

    it "never publishes or advances anything: no transition rows, no published_at, draft only" do
      create_from_template

      expect(audit_class.pluck(:action)).to eq(["contract.create_from_template"])
      expect(contract_class.pluck(:state, :published_at)).to eq([["draft", nil]])
    end

    it "keeps the form's edits over the template's prefill, and a later template edit does not change the contract" do
      create_from_template(title: "Edited title", subject_matter: "Edited subject")
      template.update!(title_pattern: "Changed", object_party_name: "Renamed")

      contract = contract_class.sole
      expect(contract.title).to eq("Edited title")
      expect(contract.subject_matter).to eq("Edited subject")
      expect(contract.parties.sole.name).to eq("Mesto Demo")
    end

    it "creates a plain draft with no party and no template audit row when no template is picked" do
      expect { post "/admin/contracts", params: { contract: { title: "Blank", reference: "ZP-1" } } }
        .to change(contract_class, :count).by(1)

      expect(Decidim::ContractsSk::Party.count).to eq(0)
      expect(audit_class.count).to eq(0)
    end

    it "404s for a foreign template id without creating anything" do
      foreign = Decidim::ContractsSk::Template.create!(organization: other_org, name: "Theirs",
                                                       object_party_name: "Foreign Town")

      expect { create_from_template(template_id: foreign.id) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(contract_class.count).to eq(0)
      expect(Decidim::ContractsSk::Party.count).to eq(0)
    end

    it "re-renders the form with the chosen template kept when the draft is invalid, creating nothing" do
      expect { create_from_template(reference: "") }.not_to change(contract_class, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("input[type=hidden][name='template_id']")["value"]).to eq(template.id.to_s)
      expect(doc.at_css("#contract_title")["value"]).to eq("Rental - Shop 4")
      expect(Decidim::ContractsSk::Party.count).to eq(0)
      expect(audit_class.count).to eq(0)
    end

    it "keeps the duplicate-reference rejection and leaves no orphan party or audit row" do
      create_from_template
      expect { create_from_template }.not_to change(contract_class, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Decidim::ContractsSk::Party.count).to eq(1)
      expect(audit_class.count).to eq(1)
    end

    context "when the user is a reviewer" do
      let(:resolver_roles) { %i[reviewer] }

      it "is denied the form, the template prefill and the create, writing nothing" do
        get "/admin/contracts/new", params: { template_id: template.id }
        expect(flash[:alert]).to eq(unauthorized)

        expect { create_from_template }.not_to change(contract_class, :count)
        expect(flash[:alert]).to eq(unauthorized)
        expect(Decidim::ContractsSk::Party.count).to eq(0)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
