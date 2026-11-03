# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the organization header screen (civora-org/civora-platform
# #211, P6): /admin/organization_profile, the allowlisted JSON header that
# document generation fills into every contract. Organization admins only;
# every change is audited by KEY, never by value. :db only
# (CONTRACTS_SK_DB=1), in-memory SQLite, synthetic data only.
#
# Each guard example was mutation-checked (the guard commented out, the
# example went red, the guard restored): the permission rule, the command's
# actor re-check, the tenant scoping and the keys-only audit.
# ---------------------------------------------------------------------------

require "spec_helper"
require "nokogiri"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
RSpec.describe "admin organization header", :db, type: :request do
  let(:controller) { Decidim::ContractsSk::Admin::ApplicationController }
  let(:unauthorized) { "You are not authorized to perform this action." }
  let(:profile_class) { Decidim::ContractsSk::ContractOrganizationProfile }
  let(:audit_class) { Decidim::ContractsSk::AuditEvent }
  let(:other_org) { Decidim::Organization.create! }
  let(:resolver_roles) { [] }
  let(:acting_user) do
    Decidim::User.create!(organization: organization, email: "admin@example.org", name: "Ada Admin",
                          nickname: "ada", admin: true, admin_terms_accepted_at: Time.current,
                          confirmed_at: Time.current)
  end
  let(:valid_header) do
    { "official_name" => "Obec Vzorová", "seat" => "Námestie Vzorové 1", "ico" => "00000000",
      "iban" => "SK00 0000 0000 0000 0000 0000", "statutory_name" => "Jana Vzorová" }
  end

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  before do
    migrate_engine_schema!
    allow_any_instance_of(controller).to receive(:current_user).and_return(acting_user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
  end

  def html
    Nokogiri::HTML(response.body)
  end

  def stored
    profile_class.find_by(organization: organization)
  end

  describe "who may open it" do
    let(:requests) do
      [[:get, "/admin/organization_profile"], [:get, "/admin/organization_profile/new"],
       [:get, "/admin/organization_profile/edit"],
       [:post, "/admin/organization_profile"], [:patch, "/admin/organization_profile"],
       [:delete, "/admin/organization_profile"]]
    end

    before { profile_class.create!(organization: organization, header: { "ico" => "11111111" }) }

    {
      "an editor" => { admin: false, roles: %i[editor] },
      "a reviewer" => { admin: false, roles: %i[reviewer] },
      "an organization admin who has not accepted the admin terms" => { admin: true, terms: false,
                                                                        roles: %i[editor reviewer] },
      "a plain user without any role" => { admin: false, roles: [] }
    }.each do |label, setup|
      context "with #{label}" do
        let(:resolver_roles) { setup[:roles] }
        let(:acting_user) do
          Decidim::User.create!(organization: organization, email: "someone@example.org", name: "Some One",
                                nickname: "someone", admin: setup[:admin],
                                admin_terms_accepted_at: (Time.current if setup.fetch(:terms, setup[:admin])),
                                confirmed_at: Time.current)
        end

        it "refuses every action and changes nothing" do
          requests.each do |verb, path|
            public_send(verb, path, params: { organization_profile: { ico: "22222222" } })

            expect(response).to have_http_status(:found), "#{verb} #{path}"
            expect(flash[:alert]).to eq(unauthorized), "#{verb} #{path}"
          end

          expect(stored.header).to eq("ico" => "11111111")
          expect(audit_class.count).to eq(0)
        end
      end
    end
  end

  describe "an organization admin" do
    it "sees the empty state and the way to fill in the header" do
      get "/admin/organization_profile"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("not filled in yet")
      expect(html.css("a[href='/admin/organization_profile/new']")).not_to be_empty
    end

    it "redirects new to edit when a header exists and edit to new when none does" do
      get "/admin/organization_profile/edit"
      expect(response).to redirect_to("/admin/organization_profile/new")

      profile_class.create!(organization: organization, header: { "ico" => "11111111" })
      get "/admin/organization_profile/new"
      expect(response).to redirect_to("/admin/organization_profile/edit")
    end

    it "renders one labelled text field per allowed header key" do
      get "/admin/organization_profile/new"

      names = html.css("input[type=text]").pluck("name")
      expect(names).to match_array(profile_class::HEADER_KEYS.map { |key| "organization_profile[#{key}]" })
      expect(html.css("label").size).to be >= profile_class::HEADER_KEYS.size
    end

    it "creates the header, drops blanks and trims, and audits keys only" do
      post "/admin/organization_profile",
           params: { organization_profile: valid_header.merge("dic" => "  ", "seat" => "  Námestie Vzorové 1 ") }

      expect(response).to redirect_to("/admin/organization_profile")
      expect(stored.header).to eq(valid_header)
      events = audit_class.order(:id)
      expect(events.map(&:action)).to eq(%w[official_name seat ico iban statutory_name].map { |key|
        "organization_profile.changed.#{key}"
      })
      expect(events.map(&:target)).to all(eq(stored))
      expect(events.map(&:actor)).to all(eq(acting_user))
      serialized = events.map(&:attributes).to_s
      valid_header.each_value { |value| expect(serialized).not_to include(value) }
    end

    it "shows the stored values and audits only the keys that changed on update" do
      profile_class.create!(organization: organization, header: valid_header)

      patch "/admin/organization_profile",
            params: { organization_profile: valid_header.merge("ico" => "12345678", "bic" => "TESTSKBX",
                                                               "statutory_name" => "") }

      expect(response).to redirect_to("/admin/organization_profile")
      expect(stored.header).to eq(valid_header.except("statutory_name").merge("ico" => "12345678", "bic" => "TESTSKBX"))
      expect(audit_class.order(:id).map(&:action))
        .to eq(%w[organization_profile.changed.ico organization_profile.changed.bic
                  organization_profile.changed.statutory_name])
      expect(audit_class.pluck(:action).join).not_to include("12345678")

      get "/admin/organization_profile"
      expect(response.body).to include("Obec Vzorová").and include("12345678")
    end

    it "writes no audit row when an update changes nothing" do
      profile_class.create!(organization: organization, header: valid_header)

      patch "/admin/organization_profile", params: { organization_profile: valid_header }

      expect(response).to redirect_to("/admin/organization_profile")
      expect(audit_class.count).to eq(0)
    end

    it "rejects a malformed IČO or IBAN with a message on the field, keeping what was typed and storing nothing" do
      post "/admin/organization_profile",
           params: { organization_profile: { official_name: "Obec Vzorová", ico: "12AB", iban: "nonsense" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("The IČO must have eight digits.")
      expect(response.body).to include("The IBAN does not have a valid shape.")
      expect(html.at_css("input[name='organization_profile[official_name]']")["value"]).to eq("Obec Vzorová")
      expect(html.at_css("input[name='organization_profile[ico]']")["aria-invalid"]).to eq("true")
      expect(profile_class.count).to eq(0)
      expect(audit_class.count).to eq(0)
    end

    it "rejects an empty form and an over-long value" do
      post "/admin/organization_profile", params: { organization_profile: { ico: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Fill in at least one field.")

      post "/admin/organization_profile", params: { organization_profile: { seat: "x" * 256 } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("The value is too long")
      expect(profile_class.count).to eq(0)
    end

    it "ignores keys outside the allowlist" do
      post "/admin/organization_profile",
           params: { organization_profile: { ico: "00000000", admin: "true", decidim_organization_id: other_org.id } }

      expect(stored.header).to eq("ico" => "00000000")
      expect(profile_class.where(organization: other_org)).to be_empty
    end

    it "ignores a malformed parameter shape" do
      post "/admin/organization_profile", params: { organization_profile: "ico=00000000" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(profile_class.count).to eq(0)
    end

    it "removes the header with one audit row and no value in it" do
      profile = profile_class.create!(organization: organization, header: valid_header)

      delete "/admin/organization_profile"

      expect(response).to redirect_to("/admin/organization_profile")
      expect(profile_class.count).to eq(0)
      event = audit_class.sole
      expect(event.action).to eq("organization_profile.removed")
      expect([event.target_type, event.target_id]).to eq([profile_class.name, profile.id])
    end

    it "never touches another organization's header" do
      foreign = profile_class.create!(organization: other_org, header: { "ico" => "99999999" })

      post "/admin/organization_profile", params: { organization_profile: { ico: "00000000" } }
      patch "/admin/organization_profile", params: { organization_profile: { ico: "12345678" } }
      delete "/admin/organization_profile"

      expect(foreign.reload.header).to eq("ico" => "99999999")
      expect(stored).to be_nil
    end

    it "shows the audit rows in the audit trail with the field name and no value" do
      post "/admin/organization_profile", params: { organization_profile: { ico: "00000000" } }
      allow(Decidim::ContractsSk).to receive(:role_resolver).and_return(->(_user, _context) { [:editor] })

      get "/admin/audit_events"

      expect(response.body).to include("Municipality header: field changed: Company ID (IČO)")
      expect(response.body).not_to include("00000000")
    end
  end

  describe "the command's own actor check" do
    it "refuses a user who is not an organization admin of the organization, even if called directly" do
      form = Decidim::ContractsSk::Admin::OrganizationProfileForm.new(ico: "00000000")
      outsider = Decidim::User.create!(organization: other_org, admin: true, admin_terms_accepted_at: Time.current)
      outcome = nil

      Decidim::ContractsSk::Admin::SaveOrganizationProfile.call(form, organization: organization, user: outsider) do
        on(:invalid) { outcome = :invalid }
      end

      expect(outcome).to eq(:invalid)
      expect(profile_class.count).to eq(0)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
