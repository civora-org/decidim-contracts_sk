# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the effectiveness status of a contract that must be
# published in the CRZ (civora-org/civora-platform#202): the line on the
# admin contract page, the column in the admin list, and the optional agreed
# later effectiveness date in the form (saved on create and update).
# DB-backed (CONTRACTS_SK_DB=1). Time frozen at 2026-10-13. Synthetic data.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin contract effectiveness", :db, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:contract_class) { Decidim::ContractsSk::Contract }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[editor reviewer] }
    travel_to(Time.utc(2026, 10, 13, 8)) { example.run }
    Decidim::ContractsSk.role_resolver = original
  end

  before do
    migrate_engine_schema!

    controller = Decidim::ContractsSk::Admin::ContractsController
    allow_any_instance_of(controller).to receive(:current_user).and_return(author)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
  end

  def contract!(reference, **extra)
    contract_class.create!(contract_attributes({ reference: reference, state: "published",
                                                 signed_on: Date.new(2026, 8, 1) }.merge(extra)))
  end

  def fact(label)
    Nokogiri::HTML(response.body).css(".cs-show__fact").find { |node| node.at_css("dt")&.text == label }
  end

  describe "the contract page" do
    it "says an unfiled contract is not yet effective" do
      get "/admin/contracts/#{contract!("ZP-E-1").id}"

      expect(fact("Effectiveness").text).to include("Not yet effective")
      expect(fact("Effectiveness").text).to include("not confirmed as filed in the CRZ")
    end

    it "says a filed contract is effective from the day after publication" do
      record = contract!("ZP-E-2", crz_filed_at: Time.utc(2026, 9, 1), crz_published_on: Date.new(2026, 9, 1))

      get "/admin/contracts/#{record.id}"

      expect(fact("Effectiveness").text).to include("Effective from 2026-09-02")
      expect(fact("Agreed later effectiveness date")).to be_nil
    end

    it "respects an agreed later date: not yet effective until then, and shows the agreed date" do
      record = contract!("ZP-E-3", crz_filed_at: Time.utc(2026, 9, 1), crz_published_on: Date.new(2026, 9, 1),
                                   agreed_effective_on: Date.new(2026, 11, 1))

      get "/admin/contracts/#{record.id}"

      expect(fact("Effectiveness").text).to include("Not yet effective")
      expect(fact("Effectiveness").text).to include("2026-11-01")
      expect(fact("Agreed later effectiveness date").text).to include("2026-11-01")
    end

    it "shows no effectiveness line for a CRZ mirror" do
      record = contract!("ZP-E-4", source: "crz", source_id: "900000001")

      get "/admin/contracts/#{record.id}"

      expect(fact("Effectiveness")).to be_nil
    end
  end

  describe "the list" do
    it "has an Effectiveness column: warning label when not effective, plain label when effective, empty otherwise" do
      contract!("ZP-E-1")
      contract!("ZP-E-2", crz_filed_at: Time.utc(2026, 9, 1), crz_published_on: Date.new(2026, 9, 1))
      contract!("ZP-E-3", source: "crz", source_id: "900000001")

      get "/admin/contracts"
      rows = Nokogiri::HTML(response.body).css("tbody tr")
      cells = rows.to_h { |row| [row.css("td")[1].text.strip, row.css("td")[4]] }

      expect(response.body).to include("Effectiveness</th>")
      expect(cells.fetch("ZP-E-1").at_css("span.label.warning").text).to eq("Not yet effective")
      expect(cells.fetch("ZP-E-2").at_css("span.label").text).to eq("Effective")
      expect(cells.fetch("ZP-E-2").at_css("span.warning")).to be_nil
      expect(cells.fetch("ZP-E-3").text.strip).to be_empty
    end
  end

  describe "the form" do
    let(:base) { { title: "Road", reference: "ZP-E-9", signed_on: "2026-08-01" } }

    it "offers the optional field with its hint" do
      get "/admin/contracts/new"

      expect(response.body).to include('id="contract_agreed_effective_on"')
      expect(response.body).to include("takes effect later than the day after publication")
    end

    it "saves the agreed date on create and on update, and clears it when left blank" do
      post "/admin/contracts", params: { contract: base.merge(agreed_effective_on: "2026-12-01") }
      record = contract_class.find_by!(reference: "ZP-E-9")
      expect(record.agreed_effective_on).to eq(Date.new(2026, 12, 1))

      patch "/admin/contracts/#{record.id}", params: { contract: base.merge(agreed_effective_on: "2027-01-15") }
      expect(record.reload.agreed_effective_on).to eq(Date.new(2027, 1, 15))

      patch "/admin/contracts/#{record.id}", params: { contract: base.merge(agreed_effective_on: "") }
      expect(record.reload.agreed_effective_on).to be_nil
    end

    it "pre-fills the edit page with the stored agreed date" do
      record = contract!("ZP-E-8", state: "draft", agreed_effective_on: Date.new(2026, 12, 1))

      get "/admin/contracts/#{record.id}/edit"

      expect(Nokogiri::HTML(response.body).at_css("#contract_agreed_effective_on")["value"]).to eq("2026-12-01")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
