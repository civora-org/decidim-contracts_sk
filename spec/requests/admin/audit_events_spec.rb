# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the read-only admin audit-trail viewer
# (civora-org/civora-platform#92), run against the Stage-1 dummy harness
# (spec/dummy mounts the engine at "/").
#
# Two layers, one file — the same discipline as the admin contracts CRUD
# spec:
#
# * The default (offline, DB-free) group pins the DENIED paths. The harness'
#   Devise-ish seam (current_user / current_organization) is stubbed
#   per-example with allow_any_instance_of, and the engine role resolver is
#   swapped on the config-time seam. The :read gate opens the action before
#   any record lookup, so no DB connection is ever needed for the denials.
#
# * The :db group (CONTRACTS_SK_DB=1) pins the allowed paths against the
#   real migrations on an in-memory SQLite adapter; there the seam carries
#   REAL Decidim::Organization / Decidim::User records so the events'
#   explicit tenancy/actor columns can persist.
#
# Flash-key discipline: the harness' authenticate_user! redirects with the
# distinct literal key :dummy_authentication_required, while NeedsPermission's
# denial handler uses :alert — every denial example proves WHICH gate fired.
#
# Unknown action strings are legal fixture input (the model validates
# presence and length only); the viewer degrades them to the humanized
# fallback, so the markers below use underscore forms whose humanized
# labels are asserted verbatim.
#
# Synthetic data only (ZP-2026-00x references, no real PII).
#
# Cop note: allow_any_instance_of is the approved seam for this harness (the
# Devise-ish methods live on the controllers; request specs cannot inject
# substitutes into the framework's instantiation path), so the cop is
# disabled file-wide along with the dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Stand-in for a signed-in user in the offline group: only the swapped role
# resolver reads it (via engine_roles); the Devise-ish seam just needs a
# non-nil current_user.
FakeAuditViewer = Struct.new(:engine_roles, keyword_init: true)

# Status, redirect target and flash semantics are asserted per example by
# design: every denial must prove which gate fired, and every success must
# prove exactly what rendered.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin audit-trail viewer", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  # Swaps the config-time role seam for an engine_roles-driven resolver for
  # the duration of each example (same pattern as the permissions specs).
  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [])
    controller = Decidim::ContractsSk::Admin::AuditEventsController
    user = FakeAuditViewer.new(engine_roles: roles)

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous visitor with the auth flash, not the permission flash" do
      get "/admin/audit_events"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user with the permission flash" do
      sign_in(roles: [])
      get "/admin/audit_events"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end
  end

  describe "allowed paths", :db do
    let(:author) { Decidim::User.create!(organization: organization) }
    let(:resolver_roles) { %i[editor] }

    # Role control per group: the resolver stays fixed per example, which
    # keeps the signed-in user a plain persistence record (the events'
    # actor column target) while the role decision is explicit.
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    before do
      migrate_engine_schema!

      # Both admin controllers the examples drive: the viewer itself, and
      # the contracts controller behind the edit page's audit-trail link.
      [Decidim::ContractsSk::Admin::AuditEventsController,
       Decidim::ContractsSk::Admin::ContractsController].each do |controller|
        allow_any_instance_of(controller).to receive(:current_user).and_return(author)
        allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
        allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
      end
    end

    def create_contract!(overrides = {})
      # Generated references live in their own namespace and are unique per
      # example (the :db harness rebuilds the schema per example), so an
      # example creating several contracts never trips the (organization,
      # reference) uniqueness validation.
      reference = "ZP-AUTO-#{Decidim::ContractsSk::Contract.count + 1}"
      Decidim::ContractsSk::Contract.create!(contract_attributes(reference: reference).merge(overrides))
    end

    # One audited event; `attrs` may carry action/target/organization/
    # actor/created_at overrides. Without an explicit target a fresh
    # contract is created, so every event's polymorphic target stays
    # consistent with its organization unless the example says otherwise.
    def create_event!(attrs = {})
      Decidim::ContractsSk::AuditEvent.create!(
        {
          action: "contract.submit",
          target: attrs.fetch(:target) { create_contract! },
          organization: organization,
          actor: author
        }.merge(attrs)
      )
    end

    it "admits an editor and a reviewer alike (the :read gate is role-any)" do
      create_event!(action: "contract.publish")

      %i[editor reviewer].each do |role|
        Decidim::ContractsSk.role_resolver = ->(_user, _context) { [role] }

        get "/admin/audit_events"

        expect(response).to have_http_status(:ok), "#{role} must read the audit trail"
        expect(response.body).to include("Audit trail")
      end
    end

    it "lists the organization's events newest-first, id as the same-second tiebreaker" do
      create_event!(action: "order_first", created_at: Time.current - 2.days)
      # ONE captured timestamp for both rows: identical created_at is the
      # whole point — the id must break the tie deterministically.
      same_moment = Time.current - 1.hour
      second = create_event!(action: "order_second", created_at: same_moment)
      third = create_event!(action: "order_third", created_at: same_moment)

      get "/admin/audit_events"

      expect(response).to have_http_status(:ok)
      # second and third share the same second, so the higher id (third,
      # created later) sorts first — a total order across page boundaries.
      expect(second.id).to be < third.id
      body = response.body
      expect(body.index("Order third")).to be < body.index("Order second")
      expect(body.index("Order second")).to be < body.index("Order first")
    end

    it "hides another organization's events (tenancy is explicit on the rows)" do
      foreign_org = Decidim::Organization.create!
      foreign_author = Decidim::User.create!(organization: foreign_org)
      foreign_contract = create_contract!(organization: foreign_org, reference: "ZP-2026-012")
      create_event!(action: "order_mine")
      create_event!(action: "order_foreign", target: foreign_contract,
                    organization: foreign_org, actor: foreign_author)

      get "/admin/audit_events"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Order mine")
      expect(response.body).not_to include("Order foreign")
    end

    it "filters to one contract's events through the contract_id param, with the banner and back link" do
      contract_a = create_contract!(title: "Bridge repair", reference: "ZP-2026-010")
      contract_b = create_contract!(title: "Road works", reference: "ZP-2026-011")
      create_event!(action: "contract.submit", target: contract_a)
      create_event!(action: "contract.archive", target: contract_a)
      create_event!(action: "contract.redaction_confirmed", target: contract_b)

      get "/admin/audit_events", params: { contract_id: contract_a.id }

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Showing audit events for: Bridge repair")
        expect(response.body).to include("Show all events")
        expect(response.body).to include("Submit for review")
        expect(response.body).to include("Archive")
        expect(response.body).not_to include("Redaction confirmed")
        expect(response.body).not_to include("Road works")
      end
    end

    it "raises RecordNotFound for a foreign or nonexistent contract_id (scoped lookup)" do
      foreign_org = Decidim::Organization.create!
      foreign = create_contract!(organization: foreign_org, reference: "ZP-2026-013")

      expect do
        get "/admin/audit_events", params: { contract_id: foreign.id }
      end.to raise_error(ActiveRecord::RecordNotFound)

      expect do
        get "/admin/audit_events", params: { contract_id: foreign.id + 100_000 }
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "renders the deleted-target label for an event whose contract row is gone, with a 200" do
      gone = create_contract!(title: "Vanished record")
      create_event!(action: "contract.submit", target: gone)
      gone.destroy!

      get "/admin/audit_events"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Record no longer exists")
        expect(response.body).not_to include("Vanished record")
      end
    end

    it "renders the decision reason only for a live decision-state contract with a review_reason" do
      returned = create_contract!(state: "returned", review_reason: "Fix the amount breakdown",
                                  reviewed_at: Time.current)
      create_event!(action: "contract.return", target: returned)
      drafted = create_contract!(state: "draft", review_reason: "Stale leftover", reviewed_at: Time.current)
      create_event!(action: "contract.submit", target: drafted)

      get "/admin/audit_events"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Fix the amount breakdown")
        expect(response.body).not_to include("Stale leftover")
      end
    end

    it "renders the localized self-review labels for the _self actions (civora-org/civora-platform#123)" do
      %w[approve_self return_self reject_self].each do |suffix|
        create_event!(action: "contract.#{suffix}")
      end

      get "/admin/audit_events"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Approved (self-review)")
        expect(response.body).to include("Returned (self-review)")
        expect(response.body).to include("Rejected (self-review)")
        expect(response.body).not_to include("Approve self")
      end
    end

    it "degrades an unknown action string to the humanized fallback without raising" do
      create_event!(action: "mystery_future_action")

      get "/admin/audit_events"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mystery future action")
    end

    it "labels an amendment-target event through the amendment's version and parent contract" do
      contract = create_contract!
      amendment = Decidim::ContractsSk::Amendment.create!(
        contract: contract,
        organization: organization,
        author: author,
        version: 2,
        summary: "Adjusted scope"
      )
      create_event!(action: "amendment.publish", target: amendment)

      get "/admin/audit_events"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include("Amendment published")
        expect(response.body).to include("Amendment v2")
        expect(response.body).to include(%(href="/admin/contracts/#{contract.id}/amendments"))
      end
    end

    it "paginates at 25 per page with the remainder on page 2" do
      contract = create_contract!
      30.times do |i|
        create_event!(action: format("bulk_event_%02d", i), target: contract)
      end

      get "/admin/audit_events"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Page 1 of 2")
      # The humanized fallback renders "Bulk event 00".."Bulk event 29"
      # (only the first word is capitalized).
      expect(response.body.scan(/event \d{2}/i).size).to eq(25)

      get "/admin/audit_events", params: { page: "2" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Page 2 of 2")
      expect(response.body.scan(/event \d{2}/i).size).to eq(5)
    end

    it "renders the localized empty state when the organization has no events yet" do
      get "/admin/audit_events"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No audit events have been recorded yet.")
    end

    it "renders the audit-trail link on the contract edit page" do
      contract = create_contract!

      get "/admin/contracts/#{contract.id}/edit"

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include(%(href="/admin/audit_events?contract_id=#{contract.id}"))
        expect(response.body).to include("Audit trail")
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
