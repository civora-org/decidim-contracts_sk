# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin home, "What needs doing today" (civora-org/
# civora-platform #126, reworked as a task list), run against the Stage-1 dummy harness (spec/dummy mounts the engine
# at "/"), so the page lives at /admin.
#
# Two layers, one file (the audit-trail viewer spec's discipline):
#
# * The default (offline, DB-free) group pins the DENIED paths: the :read
#   gate opens the action before any query, so no DB connection is needed.
# * The :db group (CONTRACTS_SK_DB=1) pins everything the page renders —
#   which tasks each role sees (reviewer, editor, both, nobody), the
#   four-eyes exclusion, the single button per task and where it points, the
#   counts matching the filtered index they link to, the "all done" state,
#   tenancy isolation and a query count that does not grow with the rows.
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

    # The task <li> by DOM id, or nil when it is not rendered.
    def task(key)
      Nokogiri::HTML(body).at_css("#today-#{key}")
    end

    def task_button(key)
      task(key)&.at_css("a.button")
    end

    describe "access" do
      it "renders for an editor-only and a reviewer-only role holder" do
        %i[editor reviewer].each do |role|
          Decidim::ContractsSk.role_resolver = ->(_user, _context) { [role] }

          get "/admin"

          expect(response).to have_http_status(:ok), "#{role} must reach the home"
          expect(body).to include("What needs doing today")
        end
      end

      it "denies a signed-in user without an engine role with the permission flash" do
        Decidim::ContractsSk.role_resolver = ->(_user, _context) { [] }

        get "/admin"

        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq(unauthorized)
      end

      it "renders the engine-owned admin layout hooks and the style block exactly once, with no inline styles" do
        create_contract!

        get "/admin"

        expect(body).to include(%(class="cs-admin-actions"))
        expect(body.scan(".cs-admin-actions { display: flex").size).to eq(1)
        expect(body).not_to include(%(style="display))
      end
    end

    describe "the review task (reviewer)" do
      let(:resolver_roles) { %i[reviewer] }

      it "counts what waits for the person, with one button to the filtered list" do
        2.times { |i| queue_item!("Queue other #{i}") }

        get "/admin"

        expect(task("review").text).to include("2 contracts are waiting for your review")
        button = task_button("review")
        expect(button.text.strip).to eq("Review")
        expect(button["href"]).to eq("/admin/contracts?state=in_review&submitter=others")
        expect(task("review").css("a.button").size).to eq(1)
      end

      it "goes straight to the contract page when exactly one record waits" do
        record = queue_item!("Only one")

        get "/admin"

        expect(task("review").text).to include("1 contract is waiting for your review")
        expect(task("review").text).to include("Only one")
        expect(task_button("review")["href"]).to eq("/admin/contracts/#{record.id}")
      end

      it "respects four-eyes: the person's own submissions are not theirs to review" do
        queue_item!("Queue own", submitter: me)
        queue_item!("Queue theirs")

        get "/admin"

        expect(task("review").text).to include("1 contract is waiting")
        expect(body).not_to include("Queue own")
      end

      it "counts a legacy record without a submitter stamp" do
        queue_item!("Queue legacy", submitter: nil)

        get "/admin"

        expect(task("review").text).to include("1 contract is waiting")
      end

      it "lists the person's own submissions again when the host enables self-review" do
        Decidim::ContractsSk.allow_self_review = true
        record = queue_item!("Queue own", submitter: me)

        get "/admin"

        expect(task("review").text).to include("1 contract is waiting")
        expect(task_button("review")["href"]).to eq("/admin/contracts/#{record.id}")
      end

      it "shows nothing else: no returned drafts, publishing, filing or data nudges for a reviewer" do
        returned_item!("Returned mine")
        approved_item!("Approved one")
        create_contract!(title: "No amount")

        get "/admin"

        %w[returned publish confirm-filing missing-amount missing-signed-on].each do |key|
          expect(task(key)).to be_nil, "#{key} must not be a reviewer's task"
        end
        expect(body).to include("All done")
      end
    end

    describe "the editor's tasks" do
      let(:resolver_roles) { %i[editor] }

      it "shows returned drafts submitted by the person, not other people's, and no review task" do
        returned_item!("Returned mine")
        returned_item!("Returned theirs", submitter: colleague)
        queue_item!("Queue hidden")

        get "/admin"

        expect(task("returned").text).to include("1 draft was returned to you with a comment")
        expect(task("returned").text).to include("Returned mine")
        expect(body).not_to include("Returned theirs")
        expect(task_button("returned").text.strip).to eq("Edit")
        expect(task("review")).to be_nil
      end

      it "counts approved records waiting to be published and how many still lack the redaction confirmation" do
        approved_item!("Approved a", redaction_confirmed_at: Time.current)
        approved_item!("Approved b")

        get "/admin"

        expect(task("publish").text).to include("2 approved contracts are waiting to be published")
        expect(task("publish").text).to include("1 still lacks the personal-data confirmation.")
        expect(task_button("publish")["href"]).to eq("/admin/contracts?state=approved")
      end

      it "asks to confirm the CRZ filing of published, unfiled editorial records only" do
        create_contract!(title: "Published open", state: "published", published_at: Time.current)
        create_contract!(title: "Published filed", state: "published", published_at: Time.current,
                         crz_filed_at: Time.current)
        create_contract!(title: "Mirror", state: "published", published_at: Time.current,
                         source: Decidim::ContractsSk::CrzImport::Mapper::SOURCE)

        get "/admin"

        expect(task("confirm-filing").text).to include("1 published contract is waiting for its CRZ filing")
        expect(task_button("confirm-filing").text.strip).to eq("Confirm filing")
        expect(task_button("confirm-filing")["href"]).to match(%r{\A/admin/contracts/\d+/crz_filing\z})
      end

      it "nudges about drafts without an amount or a signing date, linking to the matching lists" do
        create_contract!(title: "Has both", amount: 10, signed_on: Date.current)
        create_contract!(title: "No amount", signed_on: Date.current)
        create_contract!(title: "Neither one")
        create_contract!(title: "Published no amount", state: "published", published_at: Time.current)

        get "/admin"

        expect(task("missing-amount").text).to include("2 drafts have no amount")
        expect(task("missing-signed-on").text).to include("1 draft has no signing date")
        expect(task_button("missing-amount")["href"]).to eq("/admin/contracts?missing=amount")
        expect(task_button("missing-signed-on").text.strip).to eq("Fill in")
      end
    end

    describe "CRZ deadline tasks (urgent)" do
      it "gives each record its own next step for this person, most overdue first" do
        draft = create_contract!(title: "Late draft", signed_on: overdue_signed_on - 1.month)
        published = create_contract!(title: "Late published", state: "published", published_at: Time.current,
                                     signed_on: overdue_signed_on)
        waiting = queue_item!("Late in review", signed_on: due_soon_signed_on)

        get "/admin"

        expect(task("crz-overdue-#{draft.id}").text).to include("Late draft")
        expect(task_button("crz-overdue-#{draft.id}").text.strip).to eq("Prepare the CRZ handoff")
        expect(task_button("crz-overdue-#{draft.id}")["href"]).to eq("/admin/contracts/#{draft.id}/edit#crz-handoff")
        expect(task_button("crz-overdue-#{published.id}").text.strip).to eq("Confirm filing")
        expect(task_button("crz-due-soon-#{waiting.id}").text.strip).to eq("Review")
        expect(body.index("Late draft")).to be < body.index("Late published")
        expect(body).to include("CRZ deadline is near")
      end

      it "words a deadline with days left" do
        later = create_contract!(title: "Later one", signed_on: due_soon_signed_on)

        get "/admin"

        expect(task("crz-due-soon-#{later.id}").text).to include("must be filed within 5 days")
      end

      it "shows a reviewer only the records they can judge, never a draft they cannot act on" do
        Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
        create_contract!(title: "Late draft", signed_on: overdue_signed_on)
        mine = queue_item!("Late own", submitter: me, signed_on: overdue_signed_on)
        theirs = queue_item!("Late theirs", signed_on: overdue_signed_on)

        get "/admin"

        expect(body).not_to include("Late draft")
        expect(task("crz-overdue-#{mine.id}")).to be_nil
        expect(task_button("crz-overdue-#{theirs.id}").text.strip).to eq("Review")
      end

      it "keeps CRZ mirrors, filed and terminal records out" do
        mirror_source = Decidim::ContractsSk::CrzImport::Mapper::SOURCE
        create_contract!(title: "Mirror late", source: mirror_source, signed_on: overdue_signed_on)
        create_contract!(title: "Filed late", crz_filed_at: Time.current, signed_on: overdue_signed_on)
        create_contract!(title: "Rejected late", state: "rejected", signed_on: overdue_signed_on)

        get "/admin"

        expect(body).not_to include("Mirror late", "Filed late", "Rejected late")
      end

      it "lists at most five and links the rest to the unfiled list" do
        7.times { |i| create_contract!(title: format("Late row %<n>d", n: i), signed_on: overdue_signed_on) }

        get "/admin"

        expect(body.scan(/Late row \d/).uniq.size).to eq(5)
        expect(body).to include("and 2 more contracts with a deadline coming up")
        expect(body).to include(%(href="/admin/contracts?deadline=unfiled"))
      end
    end

    describe "who sees what" do
      it "shows an editor and reviewer both groups of tasks, each with exactly one button" do
        queue_item!("Queue other")
        returned_item!("Returned mine")

        get "/admin"

        Nokogiri::HTML(body).css(".cs-today__task").each do |item|
          expect(item.css("a.button").size).to eq(1)
        end
        expect(task("review")).not_to be_nil
        expect(task("returned")).not_to be_nil
      end

      it "never shows another organization's records or counts them" do
        foreign_org = Decidim::Organization.create!
        foreign_user = Decidim::User.create!(organization: foreign_org, name: "Frank Foreign")
        queue_item!("Foreign queue", organization: foreign_org, author: foreign_user, submitter: foreign_user)
        returned_item!("Foreign returned", organization: foreign_org, author: foreign_user, submitter: me)
        create_contract!(title: "Foreign overdue", organization: foreign_org, author: foreign_user,
                         signed_on: overdue_signed_on)
        queue_item!("Queue item mine")

        get "/admin"

        expect(body).not_to include("Foreign")
        expect(task("review").text).to include("1 contract is waiting")
        expect(task("returned")).to be_nil
      end
    end

    describe "the empty state" do
      it "says everything is done when nothing waits for the person" do
        get "/admin"

        expect(body).to include("All done")
        expect(body).to include("Nothing is waiting for you today.")
        expect(Nokogiri::HTML(body).css(".cs-today__task")).to be_empty
      end

      it "does not claim everything is done while a task exists" do
        queue_item!("Queue other")

        get "/admin"

        expect(body).not_to include("All done")
      end
    end

    describe "counts match the filtered index" do
      before do
        controller = Decidim::ContractsSk::Admin::ContractsController
        allow_any_instance_of(controller).to receive_messages(current_user: me, user_signed_in?: true,
                                                              current_organization: organization)
      end

      it "links each many-record task to a list with exactly the counted rows" do
        3.times { |i| queue_item!("Queue other #{i}") }
        queue_item!("Queue own", submitter: me)
        2.times { |i| returned_item!("Returned mine #{i}", amount: 5, signed_on: Date.current) }
        returned_item!("Returned theirs", submitter: colleague, amount: 5, signed_on: Date.current)
        2.times { |i| create_contract!(title: "Gap #{i}") }
        create_contract!(title: "Complete", amount: 5, signed_on: Date.current)

        get "/admin"
        keys = %w[review returned missing-amount]
        links = keys.to_h { |key| [key, task_button(key)["href"]] }
        counts = keys.to_h { |key| [key, task(key).text[/\d+/].to_i] }

        get links["review"]
        expect(body.scan(/Queue other \d/).uniq.size).to eq(counts["review"])
        expect(body).not_to include("Queue own")
        get links["returned"]
        expect(body.scan(/Returned mine \d/).uniq.size).to eq(counts["returned"])
        get links["missing-amount"]
        expect(body.scan(/Gap \d/).uniq.size).to eq(counts["missing-amount"])
        expect(body).not_to include("Complete")
        expect(counts).to eq("review" => 3, "returned" => 2, "missing-amount" => 2)
      end
    end

    describe "the rarely needed things stay one click away" do
      it "keeps the all-contracts overview and the recent changes collapsed" do
        create_event!(action: "contract.publish")

        get "/admin"
        doc = Nokogiri::HTML(body)

        expect(doc.at_css("details#today-overview")).not_to be_nil
        expect(doc.at_css("details#today-overview")["open"]).to be_nil
        expect(doc.at_css("details#today-recent-activity")["open"]).to be_nil
        expect(body).to include("Contracts by state")
        expect(body).to include("Recent activity")
      end

      it "renders a dangling audit target (class no longer loads) as the deleted-target label, not a 500" do
        event = create_event!(action: "contract.publish")
        Decidim::ContractsSk::AuditEvent.where(id: event.id)
                                        .update_all(target_type: "Decidim::ContractsSk::Ghost")

        get "/admin"

        expect(response).to have_http_status(:ok)
        expect(body).to include("Record no longer exists")
      end

      it "offers the home from the contracts index" do
        controller = Decidim::ContractsSk::Admin::ContractsController
        allow_any_instance_of(controller).to receive_messages(current_user: me, user_signed_in?: true,
                                                              current_organization: organization)

        get "/admin/contracts"

        expect(body).to include(%(href="/admin"))
        expect(body).to include("What needs doing today")
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
        end
      end

      it "runs the same number of queries with two rows per kind as with six" do
        # Two or more records per kind: a one-record task also loads the
        # record to link straight to it, which is one more (bounded) query.
        seed_rows(2)
        get "/admin" # warm-up: first-request schema/cache work is not under test
        with_two = count_queries { get "/admin" }

        seed_rows(4)
        with_six = count_queries { get "/admin" }

        # One COUNT per task kind plus one capped list for the deadlines; the
        # per-record permission checks read the loaded rows, no further query.
        expect(with_six).to eq(with_two)
        expect(with_two).to be < 40
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
