# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the role administration screens (civora-org/civora-
# platform#112, parent #95), run against the Stage-1 dummy harness (spec/dummy
# mounts the engine at "/", so the admin root is /admin).
#
# Two layers, one file - the discipline of the other admin request specs:
#
# * The offline, DB-free group pins every DENIED path. The :user_role
#   permission is checked before any record lookup, so no connection is
#   needed. Refusals follow civora-org/civora-platform#161: a non-admin
#   engine-role holder lands on the engine admin root (/admin) with the
#   "not authorized" flash, anyone else on the public catalogue (/) - never
#   on Decidim's /admin dashboard path of the real host.
#
# * The :db group (CONTRACTS_SK_DB=1) pins list, search, grant and revoke
#   against the real migrations on in-memory SQLite, with REAL user rows:
#   the privacy rules (no email on any page, no user dump, capped results),
#   tenant isolation and the generic failure.
#
# Synthetic data only: example.org addresses, invented names.
#
# Cop note: allow_any_instance_of is the approved seam for this harness (see
# parties_spec.rb), so the cop is disabled file-wide along with the
# dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Stand-in for a signed-in user in the offline group: the :user_role rule
# reads admin?/admin_terms_accepted?, the swapped role resolver reads
# engine_roles.
RoleAdminViewer = Struct.new(:engine_roles, :admin, :admin_terms_accepted, keyword_init: true) do
  def admin? = admin
  def admin_terms_accepted? = admin_terms_accepted
end

# MultipleMemoizedHelpers: the shared :db context already brings organization and author.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
RSpec.describe "admin role administration", type: :request do
  RSpec::Matchers.define_negated_matcher :not_change, :change

  let(:unauthorized) { "You are not authorized to perform this action." }
  let(:controller) { Decidim::ContractsSk::Admin::UserRolesController }

  # Every action of the screens as [verb, path, params]; none needs a record
  # because the permission check precedes every lookup.
  let(:actions) do
    {
      index: [:get, "/admin/user_roles", {}],
      new: [:get, "/admin/user_roles/new", {}],
      search: [:post, "/admin/user_roles/search", { q: "person" }],
      create: [:post, "/admin/user_roles", { user_id: 1, role: "editor" }],
      destroy: [:delete, "/admin/user_roles/1", {}]
    }
  end

  describe "denied paths (offline, DB-free)" do
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    def sign_in(user)
      allow_any_instance_of(controller).to receive(:current_user).and_return(user)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
    end

    it "bounces an anonymous visitor on every action with the auth flash, not the permission flash" do
      actions.each_value do |verb, path, params|
        public_send(verb, path, params: params)

        expect(response).to redirect_to("/")
        expect(flash[:dummy_authentication_required]).to be_present
        expect(flash[:alert]).to be_nil
      end
    end

    it "sends a non-admin holding both engine roles to the engine admin root on every action" do
      sign_in(RoleAdminViewer.new(engine_roles: %i[editor reviewer], admin: false, admin_terms_accepted: true))

      actions.each do |name, (verb, path, params)|
        public_send(verb, path, params: params)

        expect(response).to redirect_to("/admin"), "action #{name}"
        expect(flash[:alert]).to eq(unauthorized), "action #{name}"
      end
    end

    it "sends a roleless non-admin to the public catalogue on every action" do
      sign_in(RoleAdminViewer.new(engine_roles: [], admin: false, admin_terms_accepted: false))

      actions.each do |name, (verb, path, params)|
        public_send(verb, path, params: params)

        expect(response).to redirect_to("/"), "action #{name}"
        expect(flash[:alert]).to eq(unauthorized), "action #{name}"
      end
    end

    it "refuses an organization admin who has not accepted the admin terms" do
      sign_in(RoleAdminViewer.new(engine_roles: [], admin: true, admin_terms_accepted: false))

      actions.each do |name, (verb, path, params)|
        public_send(verb, path, params: params)

        expect(response).to have_http_status(:found), "action #{name}"
        expect(flash[:alert]).to eq(unauthorized), "action #{name}"
      end
    end
  end

  describe "allowed, privacy and tenant paths", :db do
    let(:admin) do
      Decidim::User.create!(organization: organization, email: "admin@example.org", name: "Ada Admin",
                            nickname: "ada", admin: true, admin_terms_accepted_at: Time.current,
                            confirmed_at: Time.current)
    end
    let(:other_organization) { Decidim::Organization.create! }
    let(:acting_user) { admin }

    def create_user!(name, nickname, email: "#{nickname}@example.org", org: organization, **attrs)
      Decidim::User.create!({ organization: org, email: email, name: name, nickname: nickname,
                              confirmed_at: Time.current }.merge(attrs))
    end

    def role_class = Decidim::ContractsSk::UserRole
    def audit_class = Decidim::ContractsSk::AuditEvent

    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { [] }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    before do
      migrate_engine_schema!

      allow_any_instance_of(controller).to receive(:current_user).and_return(acting_user)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    describe "the list" do
      it "shows an empty state and the admin-default note when nobody holds a stored role" do
        get "/admin/user_roles"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No roles have been granted yet.")
        expect(response.body).to include("Organization admins hold both roles automatically")
        expect(response.body).to include("Grant role")
      end

      it "lists holders with name, nickname and role, one revoke button per role, and never an email" do
        pat = create_user!("Pat Person", "pat", email: "pat.secret@example.org")
        role_class.create!(user: pat, organization: organization, role: "editor")
        role_class.create!(user: pat, organization: organization, role: "reviewer")

        get "/admin/user_roles"

        expect(response.body).to include("Pat Person").and include("pat")
        expect(response.body).to include("Editor, Reviewer")
        expect(response.body).to include("Revoke Editor").and include("Revoke Reviewer")
        expect(response.body.scan(%r{action="/admin/user_roles/\d+"}).length).to eq(2)
        expect(response.body).not_to include("pat.secret@example.org")
      end

      it "does not list another organization's holders" do
        stranger = create_user!("Sam Stranger", "sam", org: other_organization)
        role_class.create!(user: stranger, organization: other_organization, role: "editor")

        get "/admin/user_roles"

        expect(response.body).not_to include("Sam Stranger")
        expect(response.body).to include("No roles have been granted yet.")
      end
    end

    describe "the grant screen and the search" do
      before do
        create_user!("Pat Person", "pat", email: "pat.secret@example.org")
        create_user!("Quinn Quill", "quill")
      end

      it "renders only the search form on new - no user is listed" do
        get "/admin/user_roles/new"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Find a user by name, nickname or email")
        expect(response.body).not_to include("Pat Person")
        expect(response.body).not_to include("Quinn Quill")
        expect(response.body).not_to include("@example.org")
      end

      it "finds a user by name, nickname or email, and shows name and nickname, never the email" do
        { "pers" => "Pat Person", "QUILL" => "Quinn Quill", "pat.secret" => "Pat Person" }.each do |query, name|
          post "/admin/user_roles/search", params: { q: query }

          expect(response).to have_http_status(:ok), query
          expect(response.body).to include(name), query
          expect(response.body).not_to include("pat.secret@example.org"), query
          expect(response.body).not_to include("quill@example.org"), query
        end
      end

      it "offers one grant button per role, carrying the user id and no email" do
        post "/admin/user_roles/search", params: { q: "Pat" }

        expect(response.body).to include("Grant Editor").and include("Grant Reviewer")
        expect(response.body).to match(/name="user_id" value="\d+"/)
        expect(response.body).not_to include("@example.org")
      end

      it "omits a role the user already holds and says so when both are held" do
        pat = Decidim::User.find_by!(nickname: "pat")
        role_class.create!(user: pat, organization: organization, role: "editor")

        post "/admin/user_roles/search", params: { q: "Pat" }

        expect(response.body).to include("Grant Reviewer")
        expect(response.body).not_to include("Grant Editor")

        role_class.create!(user: pat, organization: organization, role: "reviewer")
        post "/admin/user_roles/search", params: { q: "Pat" }

        expect(response.body).to include("Holds both roles")
        expect(response.body).not_to include("Grant Editor")
        expect(response.body).not_to include("Grant Reviewer")
      end

      it "refuses a query under the minimum length with 422 and lists nobody" do
        post "/admin/user_roles/search", params: { q: "pa" }

        expect(response).to have_http_status(422)
        expect(response.body).to include("Enter at least 3 characters.")
        expect(response.body).not_to include("Pat Person")
      end

      it "treats a blank, padded-short or non-string query as too short" do
        [{ q: "" }, { q: "  p " }, { q: ["person"] }, { q: { a: "person" } }, {}].each do |params|
          post "/admin/user_roles/search", params: params

          expect(response).to have_http_status(422), params.inspect
          expect(response.body).not_to include("Pat Person"), params.inspect
        end
      end

      it "escapes LIKE wildcards, so a wildcard query cannot list everyone" do
        ["%%%", "___", "p_t"].each do |query|
          post "/admin/user_roles/search", params: { q: query }

          expect(response).to have_http_status(:ok), query
          expect(response.body).to include("No confirmed user of this organization matches."), query
        end
      end

      it "caps the query length before matching" do
        limit = Decidim::ContractsSk::Admin::UserRolesController::MAX_QUERY_LENGTH
        create_user!("Wide #{"w" * limit}", "widenick")

        post "/admin/user_roles/search", params: { q: "Wide #{"w" * limit}zzz" }

        expect(response.body).to include("<td>widenick</td>")
      end

      it "survives a NUL byte in the query" do
        post "/admin/user_roles/search", params: { q: "pat\u0000" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Pat Person")
      end

      it "excludes other organizations, unconfirmed, blocked, deleted and managed users" do
        create_user!("Pam Foreign", "pamf", org: other_organization)
        create_user!("Pam Unconfirmed", "pamu", confirmed_at: nil)
        create_user!("Pam Blocked", "pamb", blocked: true)
        create_user!("Pam Deleted", "pamd", deleted_at: Time.current)
        create_user!("Pam Managed", "pamm", managed: true)
        create_user!("Pam Fine", "pamx")

        post "/admin/user_roles/search", params: { q: "Pam" }

        expect(response.body).to include("Pam Fine")
        %w[Foreign Unconfirmed Blocked Deleted Managed].each do |word|
          expect(response.body).not_to include("Pam #{word}"), word
        end
      end

      it "caps the results" do
        (Decidim::ContractsSk::Admin::UserRolesController::RESULT_LIMIT + 5).times do |i|
          create_user!(format("Lot %02d", i), "lot#{i}")
        end

        post "/admin/user_roles/search", params: { q: "Lot " }

        expect(response.body.scan("Lot ").length).to eq(Decidim::ContractsSk::Admin::UserRolesController::RESULT_LIMIT)
      end
    end

    describe "granting" do
      let!(:pat) { create_user!("Pat Person", "pat") }

      it "grants the role, writes one audit row and redirects to the list with a flash" do
        expect { post "/admin/user_roles", params: { user_id: pat.id, role: "reviewer" } }
          .to change(role_class, :count).by(1)
          .and change(audit_class, :count).by(1)

        expect(response).to redirect_to("/admin/user_roles")
        expect(flash[:notice]).to eq("Reviewer role granted to Pat Person.")
        expect(role_class.last).to have_attributes(user: pat, role: "reviewer", organization: organization)
        expect(audit_class.last).to have_attributes(action: "user_role.grant_reviewer", target: pat, actor: admin)
      end

      it "fails generically, writing nothing, for an unknown, foreign, unconfirmed or blocked user" do
        foreign = create_user!("Fay Foreign", "fay", org: other_organization)
        unconfirmed = create_user!("Una Unconfirmed", "una", confirmed_at: nil)
        blocked = create_user!("Bo Blocked", "bo", blocked: true)

        [0, 999_999, foreign.id, unconfirmed.id, blocked.id].each do |id|
          expect { post "/admin/user_roles", params: { user_id: id, role: "editor" } }
            .not_to change(role_class, :count), "user_id #{id}"

          expect(response).to redirect_to("/admin/user_roles/new")
          expect(flash[:alert]).to eq("The role could not be granted.")
        end
        expect(audit_class.count).to eq(0)
      end

      it "fails generically for a role outside the vocabulary or a missing or non-scalar param" do
        [{ user_id: pat.id, role: "admin" }, { user_id: pat.id }, { role: "editor" },
         { user_id: [pat.id], role: "editor" }, { user_id: pat.id, role: ["editor"] }].each do |params|
          expect { post "/admin/user_roles", params: params }.not_to change(role_class, :count), params.inspect

          expect(response).to redirect_to("/admin/user_roles/new")
          expect(flash[:alert]).to eq("The role could not be granted.")
        end
      end

      it "fails generically on a duplicate grant, with no second audit row" do
        post "/admin/user_roles", params: { user_id: pat.id, role: "editor" }

        expect { post "/admin/user_roles", params: { user_id: pat.id, role: "editor" } }
          .to not_change(role_class, :count).and not_change(audit_class, :count)

        expect(flash[:alert]).to eq("The role could not be granted.")
      end

      it "grants nothing when the acting admin is no longer authorized inside the command lock" do
        allow_any_instance_of(controller).to receive(:enforce_permission_to)
        admin.update!(admin_terms_accepted_at: nil)

        expect { post "/admin/user_roles", params: { user_id: pat.id, role: "editor" } }
          .not_to change(role_class, :count)

        expect(flash[:alert]).to eq("The role could not be granted.")
      end
    end

    describe "revoking" do
      let!(:pat) { create_user!("Pat Person", "pat") }
      let!(:grant) { role_class.create!(user: pat, organization: organization, role: "editor") }

      it "revokes the role, writes one audit row and redirects with a flash" do
        expect { delete "/admin/user_roles/#{grant.id}" }
          .to change(role_class, :count).by(-1)
          .and change(audit_class, :count).by(1)

        expect(response).to redirect_to("/admin/user_roles")
        expect(flash[:notice]).to eq("Editor role revoked from Pat Person.")
        expect(audit_class.last).to have_attributes(action: "user_role.revoke_editor", target: pat, actor: admin)
      end

      it "raises RecordNotFound (a 404 on a host) for another organization's row and leaves it in place" do
        stranger = create_user!("Sam Stranger", "sam", org: other_organization)
        foreign = role_class.create!(user: stranger, organization: other_organization, role: "editor")

        expect { delete "/admin/user_roles/#{foreign.id}" }.to raise_error(ActiveRecord::RecordNotFound)

        expect(role_class.exists?(foreign.id)).to be(true)
        expect(audit_class.count).to eq(0)
      end

      it "raises RecordNotFound (a 404 on a host) for a row that is already gone" do
        grant.destroy!

        expect { delete "/admin/user_roles/#{grant.id}" }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "fails generically, with no audit row, when the acting admin lost authority inside the command lock" do
        allow_any_instance_of(controller).to receive(:enforce_permission_to)
        admin.update!(admin: false)

        expect { delete "/admin/user_roles/#{grant.id}" }.not_to change(role_class, :count)

        expect(response).to redirect_to("/admin/user_roles")
        expect(flash[:alert]).to eq("The role could not be revoked. It may already be revoked.")
        expect(audit_class.count).to eq(0)
      end
    end

    describe "a role holder who is not an organization admin" do
      let(:acting_user) { create_user!("Hana Holder", "hana") }

      before do
        Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[editor reviewer] }
      end

      it "is refused on every action, and a POST changes nothing" do
        pat = create_user!("Pat Person", "pat")
        grant = role_class.create!(user: pat, organization: organization, role: "editor")

        expect do
          actions.each_value { |verb, path, params| public_send(verb, path, params: params) }
          post "/admin/user_roles", params: { user_id: pat.id, role: "reviewer" }
          delete "/admin/user_roles/#{grant.id}"
        end.to not_change(role_class, :count).and not_change(audit_class, :count)

        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq(unauthorized)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
