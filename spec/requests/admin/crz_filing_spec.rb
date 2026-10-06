# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin CRZ filing confirmation (civora-org/
# civora-platform#125), run against the Stage-1 dummy harness (spec/dummy
# mounts the engine at "/") and the real migrations on in-memory SQLite.
# The verification fetch is stubbed at the Client boundary (Client.new);
# the real FilingLookup, FilingComparison, command and locks run.
#
# Flash-key discipline (as in crz_import_spec.rb): the harness'
# authenticate_user! redirects with the literal key
# :dummy_authentication_required, while NeedsPermission's denial handler
# uses :alert — every denial proves WHICH gate fired.
#
# Synthetic data only ("Obec Ukážková", fake IČO patterns), no real PII.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
RSpec.describe "admin CRZ filing confirmation", :db, type: :request do
  include_context "with the CRZ scope configured"

  let(:unauthorized) { "You are not authorized to perform this action." }
  let(:client_class) { Decidim::ContractsSk::CrzImport::Client }
  let(:client) { instance_double(client_class) }
  let(:crz_id) { "2142424" }
  let(:payload) { crz_payload(crz_id, "status_id" => 2, "published_at" => "2026-04-20") }
  let(:token) { Decidim::ContractsSk::CrzImport::Mapper.checksum(payload) }
  let(:resolver_roles) { %i[editor] }
  let(:path) { "/admin/contracts/#{contract.id}/crz_filing" }
  let(:contract) do
    record = Decidim::ContractsSk::Contract.create!(
      contract_attributes(reference: "UKÁŽKA-2026/#{crz_id}", state: "published", amount: BigDecimal("1043.68"))
    )
    record.parties.create!(role: "object", name: "Obec Ukážková", ico: "00000001")
    record.parties.create!(role: "contractor", name: "Demo Dodávky s.r.o.", ico: "00000002")
    record
  end

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
    example.run
  ensure
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in_as(user = author)
    controller = Decidim::ContractsSk::Admin::ContractsController

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
  end

  before do
    migrate_engine_schema!
    allow(client_class).to receive(:new).and_return(client)
    allow(client).to receive(:contract).with(crz_id).and_return(payload)
  end

  describe "denied paths" do
    it "bounces an anonymous visitor with the auth flash, not the permission flash" do
      get path

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    %i[reviewer none].each do |role|
      context "when the user is #{role == :none ? "roleless" : role}" do
        let(:resolver_roles) { role == :none ? [] : [role] }

        it "denies GET and POST with the permission flash and writes nothing" do
          sign_in_as

          get path
          expect(response).to redirect_to(role == :none ? "/" : "/admin")
          expect(flash[:alert]).to eq(unauthorized)

          post path, params: { crz_id: crz_id, checksum: token }
          expect(response).to redirect_to(role == :none ? "/" : "/admin")
          expect(flash[:alert]).to eq(unauthorized)
          expect(contract.reload.crz_filed_at).to be_nil
          expect(client).not_to have_received(:contract)
        end
      end
    end

    it "denies an editor on a record that is not published (the permission window)" do
      sign_in_as
      contract.update_columns(state: "draft")

      get path

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "denies an editor on an already filed record" do
      sign_in_as
      contract.update_columns(crz_filed_at: Time.current)

      post path, params: { crz_id: crz_id, checksum: token }

      expect(response).to redirect_to("/admin")
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "answers 404 for another organization's contract (tenant scope)" do
      sign_in_as
      other = Decidim::Organization.create!
      foreign = Decidim::ContractsSk::Contract.create!(
        contract_attributes(organization: other, reference: "ZP-FOREIGN", state: "published")
      )

      expect { get "/admin/contracts/#{foreign.id}/crz_filing" }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "GET preview" do
    before { sign_in_as }

    it "renders the CRZ id field inside a Decidim form-defaults form with the label above" do
      get path

      html = Nokogiri::HTML(response.body)
      expect(html.css("form.form-defaults .form__wrapper > label[for='crz_id'] + input#crz_id")).not_to be_empty
    end

    it "renders the CRZ id form without any network call when no id is given" do
      get path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Record filing in CRZ")
      expect(response.body).to include("name=\"crz_id\"")
      expect(response.body).not_to include("name=\"checksum\"")
      expect(client).not_to have_received(:contract)
    end

    it "refuses a non-numeric id before any network call" do
      get path, params: { crz_id: "12/34" }

      expect(response).to have_http_status(:ok)
      expect(flash[:alert]).to eq("Enter the numeric CRZ contract id.")
      expect(client).not_to have_received(:contract)
    end

    it "renders the side-by-side comparison with the confirm form (token + id, no reason on a clean match)" do
      get path, params: { crz_id: crz_id }

      body = response.body
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(body).to include("UKÁŽKA-2026/2142424")
        expect(body.scan("label success").size).to eq(3)
        expect(body).to include("name=\"checksum\"")
        expect(body).to include(token)
        expect(body).to include("Published in CRZ on")
        expect(body).to include("20")
        expect(body).to include("https://crz.gov.sk/zmluva/2142424/")
        expect(body).not_to include("name=\"reason\"")
        expect(contract.reload.crz_filed_at).to be_nil
        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
      end
    end

    it "shows the mismatch and the required reason field when a row differs" do
      contract.update!(amount: BigDecimal("999.00"))

      get path, params: { crz_id: crz_id }

      aggregate_failures do
        expect(response.body).to include("label alert")
        expect(response.body).to include("Mismatch")
        expect(response.body).to include("name=\"reason\"")
        expect(response.body).to include("maxlength=\"1000\"")
      end
    end

    it "shows the lag-aware not-found wording" do
      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::NotFoundError)

      get path, params: { crz_id: crz_id }

      expect(flash[:alert]).to eq("No CRZ contract with id 2142424 was found. The data source may lag the CRZ " \
                                  "by about a day — try again later.")
      expect(response.body).not_to include("name=\"checksum\"")
    end

    it "flashes the source-unavailable alert on a network failure" do
      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::TransportError)

      get path, params: { crz_id: crz_id }

      expect(flash[:alert]).to include("The CRZ data source is unavailable")
    end

    it "shows the withdrawn and the out-of-scope refusals" do
      allow(client).to receive(:contract).with(crz_id).and_return(payload.merge("status_id" => 4))
      get path, params: { crz_id: crz_id }
      expect(flash[:alert]).to include("cancelled or withdrawn")

      allow(client).to receive(:contract).with(crz_id)
                                         .and_return(payload.merge("contracting_authority_cin" => "00 000 009",
                                                                   "supplier_cin" => "00 000 008"))
      get path, params: { crz_id: crz_id }
      expect(flash[:alert]).to include("does not involve this organization")
    end
  end

  describe "POST confirm" do
    before { sign_in_as }

    it "files the record on a full match: notice flash, linked fields, record stays editorial" do
      post path, params: { crz_id: crz_id, checksum: token }

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:notice]).to eq("Filing of contract 2142424 in CRZ confirmed and linked.")
      contract.reload
      expect(contract.crz_filed_at).to be_present
      expect(contract.source).to eq("editorial")
      expect(contract.source_id).to eq(crz_id)
      expect(contract.crz_published_on).to eq(Date.new(2026, 4, 20))
    end

    it "files an override with the reason and flashes the override notice" do
      contract.update!(amount: BigDecimal("999.00"))

      post path, params: { crz_id: crz_id, checksum: token, reason: "Amount corrected in CRZ." }

      expect(response).to redirect_to("/admin/contracts")
      expect(flash[:notice]).to include("despite differences")
      expect(contract.reload.crz_filing_reason).to eq("Amount corrected in CRZ.")
    end

    it "sends a missing reason back to the preview of the same id, changing nothing" do
      contract.update!(amount: BigDecimal("999.00"))

      post path, params: { crz_id: crz_id, checksum: token }

      expect(response).to redirect_to("#{path}?crz_id=#{crz_id}")
      expect(flash[:alert]).to include("enter the reason")
      expect(contract.reload.crz_filed_at).to be_nil
    end

    it "sends a stale token back to the preview" do
      post path, params: { crz_id: crz_id, checksum: "old-token" }

      expect(response).to redirect_to("#{path}?crz_id=#{crz_id}")
      expect(flash[:alert]).to include("changed since you compared")
      expect(contract.reload.crz_filed_at).to be_nil
    end

    it "flashes a network failure, leaving the record and the audit trail untouched" do
      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::TransportError)

      post path, params: { crz_id: crz_id, checksum: token }

      expect(response).to redirect_to(path)
      expect(flash[:alert]).to include("data source is unavailable")
      expect(contract.reload.crz_filed_at).to be_nil
      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
    end

    it "refuses a non-numeric id before any network call" do
      post path, params: { crz_id: "abc", checksum: token }

      expect(response).to redirect_to(path)
      expect(client).not_to have_received(:contract)
    end

    it "reports an id already linked to another record" do
      Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-HOLDER", source_id: crz_id))

      post path, params: { crz_id: crz_id, checksum: token }

      expect(response).to redirect_to(path)
      expect(flash[:alert]).to include("already linked")
    end
  end

  describe "index entry point" do
    before { sign_in_as }

    it "links the filing page for a published, unfiled editorial record and hides it once filed" do
      contract

      get "/admin/contracts"
      expect(response.body).to include("Record CRZ filing")
      expect(response.body).to include("/admin/contracts/#{contract.id}/crz_filing")

      # A GET button_to (a form control, <button> or submit input), never an <a class="button">:
      # decidim-admin's `.table-list td a` colour rule makes link text in a
      # table cell invisible on a secondary-background button.
      html = Nokogiri::HTML(response.body)
      expect(html.css("td.table-list__actions form[action$='/crz_filing'][method='get'] .button")).not_to be_empty
      expect(html.css("td.table-list__actions a.button")).to be_empty
      expect(html.css("form.form-defaults .form__wrapper > label[for='source_id'] + input#source_id")).not_to be_empty

      contract.update_columns(crz_filed_at: Time.current)
      get "/admin/contracts"
      expect(response.body).not_to include("/admin/contracts/#{contract.id}/crz_filing")
    end

    it "does not offer the link to a reviewer" do
      contract
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }

      get "/admin/contracts"

      expect(response.body).not_to include("/crz_filing")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
