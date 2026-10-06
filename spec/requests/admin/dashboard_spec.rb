# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin overview / dashboard (civora-org/civora-platform
# #126), run against the Stage-1 dummy harness (spec/dummy mounts the engine
# at "/"), so the page lives at /admin.
#
# Two layers, one file (the audit-trail viewer spec's discipline):
#
# * The default (offline, DB-free) group pins the DENIED paths: the :read
#   gate opens the action before any query, so no DB connection is needed.
# * The :db group (CONTRACTS_SK_DB=1) pins everything the page renders —
#   per-role block visibility (editor-only, reviewer-only, both), the
#   four-eyes exclusion in the review queue, per-block empty states, the
#   filtered-index links and "Show all (N)" counts, tenancy isolation and a
#   query count that does not grow with the number of rows.
#
# Synthetic data only (ZP-2026-x references, no real PII).
#
# Cop note: allow_any_instance_of is the approved seam for this harness (the
# Devise-ish methods live on the controllers), so the cop is disabled
# file-wide along with the dense-assertion cops.
# ---------------------------------------------------------------------------

require "spec_helper"

# Stand-in for a signed-in user in the offline group: only the swapped role
# resolver reads it.
FakeDashboardViewer = Struct.new(:engine_roles, keyword_init: true)

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
RSpec.describe "admin dashboard", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  def sign_in(roles: [])
    controller = Decidim::ContractsSk::Admin::DashboardController
    user = FakeDashboardViewer.new(engine_roles: roles)

    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(nil)
  end

  describe "denied paths (offline, DB-free)" do
    it "bounces an anonymous visitor with the auth flash, not the permission flash" do
      get "/admin"

      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
      expect(flash[:alert]).to be_nil
    end

    it "denies a signed-in roleless user with the permission flash" do
      sign_in(roles: [])
      get "/admin"

      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq(unauthorized)
      expect(flash[:dummy_authentication_required]).to be_nil
    end

    it "no longer falls through to the public record lookup (/admin is the dashboard route)" do
      expect(Rails.application.routes.recognize_path("/admin")[:controller])
        .to eq("decidim/contracts_sk/admin/dashboard")
    end
  end

  describe "allowed paths", :db do
    let(:me) { Decidim::User.create!(organization: organization, name: "Mia Reviewer") }
    let(:colleague) { Decidim::User.create!(organization: organization, name: "Colin Colleague") }
    let(:author) { colleague }
    let(:viewer) { me }
    let(:resolver_roles) { %i[editor reviewer] }

    around do |example|
      original = Decidim::ContractsSk.role_resolver
      original_seam = Decidim::ContractsSk.allow_self_review
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
      example.run
      Decidim::ContractsSk.role_resolver = original
      Decidim::ContractsSk.allow_self_review = original_seam
    end

    before do
      migrate_engine_schema!

      controller = Decidim::ContractsSk::Admin::DashboardController
      allow_any_instance_of(controller).to receive(:current_user).and_return(viewer)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
    end

    def create_contract!(overrides = {})
      reference = "ZP-AUTO-#{Decidim::ContractsSk::Contract.count + 1}"
      Decidim::ContractsSk::Contract.create!(contract_attributes(reference: reference).merge(overrides))
    end

    def create_event!(attrs = {})
      Decidim::ContractsSk::AuditEvent.create!(
        { action: "contract.submit", target: attrs.fetch(:target) { create_contract! },
          organization: organization, actor: colleague }.merge(attrs)
      )
    end

    def queue_item!(title, submitter: colleague, **extra)
      create_contract!({ title: title, state: "in_review", decidim_submitted_by_id: submitter&.id }.merge(extra))
    end

    def returned_item!(title, submitter: me, **extra)
      create_contract!({ title: title, state: "returned", decidim_submitted_by_id: submitter&.id,
                         review_reason: "Please fix the amount", reviewed_at: Time.current }.merge(extra))
    end

    def approved_item!(title, **extra)
      create_contract!({ title: title, state: "approved" }.merge(extra))
    end

    # signed_on values placing a tracked record at a known spot of its CRZ
    # deadline (signed_on + 3 months).
    def overdue_signed_on
      Date.current - 6.months
    end

    def due_soon_signed_on
      (Date.current + 5.days) - 3.months
    end

    def body
      response.body
    end

    describe "access" do
      it "renders for an editor-only and a reviewer-only role holder" do
        %i[editor reviewer].each do |role|
          Decidim::ContractsSk.role_resolver = ->(_user, _context) { [role] }

          get "/admin"

          expect(response).to have_http_status(:ok), "#{role} must reach the overview"
          expect(body).to include("Overview")
        end
      end

      it "renders the engine-owned admin layout hooks and the style block exactly once" do
        create_contract!

        get "/admin"

        expect(body).to include(%(class="cs-admin-actions"), %(class="cs-admin-chips"))
        expect(body.scan(".cs-admin-actions {").size).to eq(1)
        expect(body).not_to include(%(style="display))
      end

      it "denies a signed-in user without an engine role with the permission flash" do
        Decidim::ContractsSk.role_resolver = ->(_user, _context) { [] }

        get "/admin"

        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq(unauthorized)
      end
    end

    describe "editor-only" do
      let(:resolver_roles) { %i[editor] }

      before do
        queue_item!("Queue item hidden")
        returned_item!("Returned item mine")
        approved_item!("Approved item one")
        create_contract!(title: "Overdue item one", signed_on: overdue_signed_on)
        create_event!(action: "contract.publish")
      end

      it "shows returned, approved, deadlines, counts and the audit trail, but no review queue" do
        get "/admin"

        expect(response).to have_http_status(:ok)
        aggregate_failures do
          expect(body).to include("Returned to me", "Returned item mine")
          expect(body).to include("Approved, ready to publish", "Approved item one")
          expect(body).to include("CRZ deadline overdue", "Overdue item one")
          expect(body).to include("Contracts by state")
          expect(body).to include("Recent activity", "Publish")
          expect(body).not_to include("Waiting for my review")
          expect(body).not_to include("Queue item hidden")
        end
      end
    end

    describe "reviewer-only" do
      let(:resolver_roles) { %i[reviewer] }

      before do
        queue_item!("Queue item other")
        returned_item!("Returned item mine")
        approved_item!("Approved item one")
        create_contract!(title: "Due soon item", signed_on: due_soon_signed_on)
        create_event!(action: "contract.approve")
      end

      it "shows the review queue, deadlines, counts and the audit trail, but no returned/approved blocks" do
        get "/admin"

        expect(response).to have_http_status(:ok)
        aggregate_failures do
          expect(body).to include("Waiting for my review", "Queue item other")
          expect(body).to include("Due soon item")
          expect(body).to include("Contracts by state")
          expect(body).to include("Recent activity")
          expect(body).not_to include("Returned to me")
          expect(body).not_to include("Returned item mine")
          expect(body).not_to include("Approved, ready to publish")
          expect(body).not_to include("Approved item one")
        end
      end
    end

    describe "editor and reviewer" do
      it "renders every block with its rows" do
        queue_item!("Queue item other")
        returned_item!("Returned item mine")
        approved_item!("Approved item one")
        create_contract!(title: "Overdue item one", signed_on: overdue_signed_on)
        create_contract!(title: "Due soon item", signed_on: due_soon_signed_on)

        get "/admin"

        aggregate_failures do
          ["Waiting for my review", "Queue item other", "Returned to me", "Returned item mine",
           "Approved, ready to publish", "Approved item one", "CRZ deadline overdue", "Overdue item one",
           "CRZ deadline within 14 days", "Due soon item", "Contracts by state", "Recent activity"].each do |text|
            expect(body).to include(text)
          end
        end
      end

      it "keeps the user's own in-review submission out of the queue (four-eyes rule)" do
        queue_item!("Queue item own", submitter: me)
        queue_item!("Queue item other")

        get "/admin"

        expect(body).to include("Queue item other")
        expect(body).not_to include("Queue item own")
      end

      it "lists the user's own submission once allow_self_review is on, and drops the submitter narrowing" do
        Decidim::ContractsSk.allow_self_review = true
        queue_item!("Queue item own", submitter: me)

        get "/admin"

        expect(body).to include("Queue item own")
        expect(body).to include(%(href="/admin/contracts?state=in_review"))
        expect(body).not_to include("submitter=others")
      end

      it "words the queue hint for self-review mode truthfully" do
        get "/admin"
        expect(body).to include("Your own submissions are not listed")

        Decidim::ContractsSk.allow_self_review = true
        get "/admin"
        expect(body).to include("Self-review is enabled")
        expect(body).not_to include("Your own submissions are not listed")
      end

      it "includes an in-review record with no submitter stamp (NULL) in the queue" do
        queue_item!("Queue item legacy", submitter: nil)

        get "/admin"

        expect(body).to include("Queue item legacy")
        expect(body).to include("Show all (1)")
      end

      it "names the submitter on each queue row" do
        queue_item!("Queue item other")

        get "/admin"

        expect(body).to include("Colin Colleague")
      end

      it "flags an approved record whose redaction is not confirmed" do
        approved_item!("Approved unconfirmed")
        approved_item!("Approved confirmed", redaction_confirmed_at: Time.current)

        get "/admin"

        expect(body.scan("Redaction not confirmed").size).to eq(1)
      end

      it "orders the queue oldest-first, the returned list newest-returned-first" do
        newer = queue_item!("Queue newer")
        older = queue_item!("Queue older")
        newer.update_columns(updated_at: 1.hour.ago)
        older.update_columns(updated_at: 3.days.ago)
        returned_item!("Returned early", reviewed_at: 5.days.ago)
        returned_item!("Returned late", reviewed_at: 1.day.ago)

        get "/admin"

        expect(body.index("Queue older")).to be < body.index("Queue newer")
        expect(body.index("Returned late")).to be < body.index("Returned early")
      end

      it "puts returned records without a review stamp after the stamped ones (portable NULLs-last)" do
        returned_item!("Returned unstamped", reviewed_at: nil)
        returned_item!("Returned stamped early", reviewed_at: 9.days.ago)
        returned_item!("Returned stamped late", reviewed_at: 1.day.ago)

        get "/admin"

        expect(body.index("Returned stamped late")).to be < body.index("Returned stamped early")
        expect(body.index("Returned stamped early")).to be < body.index("Returned unstamped")
      end

      it "orders the deadline lists by signing date, earliest first" do
        create_contract!(title: "Overdue later", signed_on: overdue_signed_on + 10.days)
        create_contract!(title: "Overdue earlier", signed_on: overdue_signed_on)

        get "/admin"

        expect(body.index("Overdue earlier")).to be < body.index("Overdue later")
      end

      it "shows the user's returned records only, not another submitter's" do
        returned_item!("Returned item mine")
        returned_item!("Returned item theirs", submitter: colleague)

        get "/admin"

        expect(body).to include("Returned item mine")
        expect(body).not_to include("Returned item theirs")
      end

      it "keeps CRZ mirrors, filed and terminal records out of the deadline lists" do
        create_contract!(title: "Overdue mirror", signed_on: overdue_signed_on, source: "crz", source_id: "900000001",
                         state: "published")
        create_contract!(title: "Overdue filed", signed_on: overdue_signed_on, crz_filed_at: Time.current)
        create_contract!(title: "Overdue archived", signed_on: overdue_signed_on, state: "archived")

        get "/admin"

        expect(body).not_to include("Overdue mirror", "Overdue filed", "Overdue archived")
      end
    end

    describe "links" do
      before do
        queue_item!("Queue item other")
        returned_item!("Returned item mine")
        approved_item!("Approved item one")
        create_contract!(title: "Overdue item one", signed_on: overdue_signed_on)
        create_contract!(title: "Due soon item", signed_on: due_soon_signed_on)
      end

      it "points every list at its filtered contracts index" do
        get "/admin"

        aggregate_failures do
          expect(body).to include(%(href="/admin/contracts?state=in_review&amp;submitter=others"))
          expect(body).to include(%(href="/admin/contracts?state=returned&amp;submitter=me"))
          expect(body).to include(%(href="/admin/contracts?state=approved"))
          expect(body).to include(%(href="/admin/contracts?deadline=overdue"))
          expect(body).to include(%(href="/admin/contracts?deadline=due_soon"))
          expect(body).to include(%(href="/admin/audit_events"))
        end
      end

      it "links each state count to its state filter, in lifecycle order with zeros" do
        get "/admin"

        Decidim::ContractsSk::ContractLifecycle::STATES.each do |state|
          expect(body).to include(%(href="/admin/contracts?state=#{state}"))
        end
        expect(body).to include("Archived (0)")
        expect(body).to include("In review (1)")
        expect(body.index("Draft (")).to be < body.index("Archived (")
      end

      it "links an editable record to its edit page and a non-editable one to the index narrowed to it" do
        draft = create_contract!(title: "Overdue editable", signed_on: overdue_signed_on)
        in_review = Decidim::ContractsSk::Contract.find_by!(title: "Queue item other")

        get "/admin"

        expect(body).to include(%(href="/admin/contracts/#{draft.id}/edit"))
        expect(body).not_to include(%(href="/admin/contracts/#{in_review.id}/edit"))
        expect(body).to include(%(href="/admin/contracts?q=#{in_review.reference}&amp;state=in_review"))
      end

      it "offers the overview from the contracts index and the audit trail" do
        controller_classes = [Decidim::ContractsSk::Admin::ContractsController,
                              Decidim::ContractsSk::Admin::AuditEventsController]
        controller_classes.each do |klass|
          allow_any_instance_of(klass).to receive_messages(current_user: me, user_signed_in?: true,
                                                           current_organization: organization)
        end

        get "/admin/contracts"
        expect(body).to include(%(href="/admin"))
        get "/admin/audit_events"
        expect(body).to include(%(href="/admin"))
      end
    end

    describe "counts match the filtered index" do
      before do
        controller = Decidim::ContractsSk::Admin::ContractsController
        allow_any_instance_of(controller).to receive_messages(current_user: me, user_signed_in?: true,
                                                              current_organization: organization)
      end

      it "makes Show all (N) equal to the rows of the linked index query" do
        3.times { |i| queue_item!("Queue other #{i}") }
        queue_item!("Queue own", submitter: me)
        queue_item!("Queue legacy", submitter: nil)
        2.times { |i| returned_item!("Returned mine #{i}") }
        returned_item!("Returned theirs", submitter: colleague)

        get "/admin"
        queue_count = body[/id="dashboard-review-queue".*?Show all \((\d+)\)/m, 1]
        returned_count = body[/id="dashboard-returned".*?Show all \((\d+)\)/m, 1]

        get "/admin/contracts", params: { state: "in_review", submitter: "others" }
        expect(body.scan(/Queue (?:other|legacy)[ \d]*</).size).to eq(queue_count.to_i)
        expect(body).not_to include("Queue own")
        get "/admin/contracts", params: { state: "returned", submitter: "me" }
        expect(body.scan(/Returned mine \d</).size).to eq(returned_count.to_i)
        expect(queue_count).to eq("4")
        expect(returned_count).to eq("2")
      end
    end

    describe "empty states" do
      it "renders a localized empty state for every visible block" do
        get "/admin"

        aggregate_failures do
          expect(body).to include("Nothing is waiting for your review.")
          expect(body).to include("None of your submissions has been returned.")
          expect(body).to include("No approved records are waiting to be published.")
          expect(body).to include("No CRZ deadlines are overdue.")
          expect(body).to include("No CRZ deadlines are due soon.")
          expect(body).to include("No contracts have been created yet.")
          expect(body).to include("No audit events have been recorded yet.")
        end
      end

      it "does not render the empty state of a block the role may not see" do
        Decidim::ContractsSk.role_resolver = ->(_user, _context) { [:editor] }

        get "/admin"

        expect(body).not_to include("Nothing is waiting for your review.")
        expect(body).to include("None of your submissions has been returned.")
      end
    end

    describe "limits" do
      it "caps a list at ten rows and links the full count" do
        12.times { |i| queue_item!(format("Queue row %<n>02d", n: i)) }

        get "/admin"

        expect(body.scan(/Queue row \d\d/).size).to eq(10)
        expect(body).to include("Show all (12)")
      end

      it "renders a dangling audit target (class no longer loads) as the deleted-target label, not a 500" do
        event = create_event!(action: "contract.publish")
        Decidim::ContractsSk::AuditEvent.where(id: event.id)
                                        .update_all(target_type: "Decidim::ContractsSk::Ghost")

        get "/admin"

        expect(response).to have_http_status(:ok)
        expect(body).to include("Record no longer exists")
      end

      it "shows only the last ten audit events, newest first" do
        contract = create_contract!
        12.times do |i|
          create_event!(action: format("order_%<n>02d", n: i), target: contract,
                        created_at: Time.current - (20 - i).minutes)
        end

        get "/admin"

        expect(body.scan(/Order \d\d/).size).to eq(10)
        expect(body.index("Order 11")).to be < body.index("Order 02")
        expect(body).not_to include("Order 01")
      end
    end

    describe "tenancy" do
      it "never lists or counts another organization's contracts or audit events" do
        foreign_org = Decidim::Organization.create!
        foreign_user = Decidim::User.create!(organization: foreign_org, name: "Frank Foreign")
        foreign = [
          queue_item!("Foreign queue", organization: foreign_org, author: foreign_user, submitter: foreign_user),
          returned_item!("Foreign returned", organization: foreign_org, author: foreign_user, submitter: me),
          approved_item!("Foreign approved", organization: foreign_org, author: foreign_user),
          create_contract!(title: "Foreign overdue", organization: foreign_org, author: foreign_user,
                           signed_on: overdue_signed_on)
        ]
        create_event!(action: "order_foreign", target: foreign.first, organization: foreign_org,
                      actor: foreign_user)
        queue_item!("Queue item mine")

        get "/admin"

        expect(body).to include("Queue item mine")
        expect(body).not_to include("Foreign")
        expect(body).not_to include("Order foreign")
        expect(body).to include("All (1)")
        expect(body).to include("In review (1)")
      end
    end

    describe "query count" do
      # Counts only real statements (no schema reflection, no savepoints).
      def count_queries(&block)
        count = 0
        counter = lambda do |_name, _start, _finish, _id, payload|
          next if %w[SCHEMA TRANSACTION].include?(payload[:name])
          next if payload[:sql].match?(/\A\s*(?:SAVEPOINT|RELEASE|BEGIN|COMMIT)/i)

          count += 1
        end
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
        count
      end

      def seed_rows(count)
        count.times do
          queue_item!("Queue row", submitter: colleague)
          returned_item!("Returned row")
          approved_item!("Approved row")
          create_contract!(title: "Overdue row", signed_on: overdue_signed_on)
          create_contract!(title: "Due soon row", signed_on: due_soon_signed_on)
          actor = Decidim::User.create!(organization: organization, name: "Act Or")
          create_event!(action: "contract.submit", actor: actor)
          create_amendment_event!(actor)
        end
      end

      # An amendment-targeted event: its label links through the amendment's
      # parent contract, the association the dashboard preloads.
      def create_amendment_event!(actor)
        amendment = Decidim::ContractsSk::Amendment.create!(
          contract: create_contract!(title: "Amended row"), version: 1, summary: "Extended deadline",
          organization: organization, author: colleague
        )
        create_event!(action: "amendment.publish", target: amendment, actor: actor)
      end

      it "runs the same number of queries with one row per block as with five" do
        seed_rows(1)
        get "/admin" # warm-up: first-request schema/cache work is not under test
        with_one = count_queries { get "/admin" }

        seed_rows(4)
        with_five = count_queries { get "/admin" }

        expect(body).to include("Amendment v1")
        expect(with_five).to eq(with_one)
        expect(with_one).to be < 30
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
