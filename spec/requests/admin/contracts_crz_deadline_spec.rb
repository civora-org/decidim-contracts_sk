# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the CRZ publication deadline surface of the admin
# contracts pages (§ 47a OZ, civora-org/civora-platform#124): the per-row
# badge, the deadline filter, the counters next to the state chips and the
# edit page's deadline line. DB-backed (CONTRACTS_SK_DB=1, in-memory SQLite).
#
# Time is frozen with travel_to (2026-06-01 noon, application time zone);
# every signed_on below is chosen relative to that day:
#   signed 2026-03-01 -> deadline 2026-06-01 (0 days left, due today)
#   signed 2026-03-02 -> 2026-06-02 (1 day), 03-04 -> 06-04 (3), 03-08 -> 06-08 (7),
#   signed 2026-03-15 -> 2026-06-15 (14, the due-soon edge), 03-16 -> 06-16 (15, ok),
#   signed 2026-02-15 -> 2026-05-15 (overdue).
# Slovak plurals need the rails-i18n rule a Decidim host provides; the
# harness swaps a Pluralization backend in for the Slovak examples only.
# ---------------------------------------------------------------------------

require "spec_helper"
require "rails_i18n/common_pluralizations/west_slavic"

# Dense assertions per example by design (a rendered page's whole story);
# allow_any_instance_of is the harness' approved seam for the Devise-ish
# controller methods (see contracts_spec.rb).
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin contracts CRZ deadline tracking", :db, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:resolver_roles) { %i[editor] }
  let(:contract_class) { Decidim::ContractsSk::Contract }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
    travel_to(Time.zone.local(2026, 6, 1, 12)) { example.run }
    Decidim::ContractsSk.role_resolver = original
  end

  before do
    migrate_engine_schema!

    controller = Decidim::ContractsSk::Admin::ContractsController
    allow_any_instance_of(controller).to receive(:current_user).and_return(author)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
  end

  def create_contract!(overrides = {})
    contract_class.create!(contract_attributes(overrides))
  end

  def references_in(body)
    body.scan(/ZP-DL-\d+/).uniq.sort
  end

  # Runs the block with a Pluralization-enabled backend that knows the
  # Slovak (cs/sk West Slavic) rule, under the :sk locale.
  def with_slovak(&block)
    original = I18n.backend
    I18n.backend = Class.new(I18n::Backend::Simple) { include I18n::Backend::Pluralization }.new
    I18n.backend.store_translations(:sk, RailsI18n::Pluralization::WestSlavic.with_locale(:sk)[:sk])
    I18n.with_locale(:sk, &block)
  ensure
    I18n.backend = original
  end

  def seed_deadline_set!
    create_contract!(reference: "ZP-DL-001", signed_on: Date.new(2026, 2, 15)) # overdue
    create_contract!(reference: "ZP-DL-002", signed_on: Date.new(2026, 3, 8), state: "returned") # 7 left
    create_contract!(reference: "ZP-DL-003", signed_on: Date.new(2026, 3, 15))               # 14 left
    create_contract!(reference: "ZP-DL-004", signed_on: Date.new(2026, 3, 16))               # 15 left, ok
    create_contract!(reference: "ZP-DL-005", signed_on: nil)                                 # unknown
    create_contract!(reference: "ZP-DL-006", signed_on: Date.new(2026, 1, 1),
                     crz_filed_at: Time.current, state: "published") # filed
    create_contract!(reference: "ZP-DL-007", signed_on: Date.new(2026, 1, 1),
                     source: "crz", source_id: "900000001", state: "published") # mirror
    create_contract!(reference: "ZP-DL-008", signed_on: Date.new(2026, 1, 1), state: "rejected") # terminal
  end

  describe "the deadline filter" do
    before { seed_deadline_set! }

    it "shows exactly the overdue tracked rows for deadline=overdue" do
      get "/admin/contracts", params: { deadline: "overdue" }

      expect(response).to have_http_status(:ok)
      expect(references_in(response.body)).to eq(%w[ZP-DL-001])
    end

    it "shows exactly the rows with 0..14 days left for deadline=due_soon" do
      get "/admin/contracts", params: { deadline: "due_soon" }

      expect(response).to have_http_status(:ok)
      expect(references_in(response.body)).to eq(%w[ZP-DL-002 ZP-DL-003])
    end

    it "falls back to the default view on a garbage deadline value" do
      get "/admin/contracts", params: { deadline: "bogus" }

      expect(response).to have_http_status(:ok)
      expect(references_in(response.body).size).to eq(8)
    end

    it "composes with the state and q filters" do
      get "/admin/contracts", params: { deadline: "due_soon", state: "returned" }
      expect(references_in(response.body)).to eq(%w[ZP-DL-002])

      get "/admin/contracts", params: { deadline: "due_soon", q: "ZP-DL-003" }
      expect(references_in(response.body)).to eq(%w[ZP-DL-003])
    end

    it "is tenant-scoped: another organization's overdue record is neither shown nor counted" do
      foreign = Decidim::Organization.create!
      contract_class.create!(organization: foreign, author: author, title: "Foreign", reference: "ZP-DL-900",
                             signed_on: Date.new(2026, 1, 1))

      get "/admin/contracts", params: { deadline: "overdue" }

      expect(references_in(response.body)).to eq(%w[ZP-DL-001])
      expect(response.body).to include("CRZ overdue (1)")
    end

    it "uses the filtered empty state when the deadline filter matches nothing" do
      contract_class.where(reference: %w[ZP-DL-001]).delete_all

      get "/admin/contracts", params: { deadline: "overdue" }

      expect(response.body).to include("No contracts match the current filters.")
    end

    it "carries the deadline filter in the pagination links" do
      stub_const("Decidim::ContractsSk::CONTRACTS_PER_PAGE", 1)

      get "/admin/contracts", params: { deadline: "due_soon" }

      expect(references_in(response.body).size).to eq(1)
      expect(response.body).to include("deadline=due_soon")
      expect(response.body).to include("page=2")
    end

    it "pre-selects the active deadline in the filter select" do
      get "/admin/contracts", params: { deadline: "overdue" }

      expect(response.body).to include(%(<option selected="selected" value="overdue">))
    end
  end

  describe "the counters" do
    before { seed_deadline_set! }

    it "count the unfiltered tenant scope, ignoring the active filter" do
      get "/admin/contracts", params: { state: "returned" }

      expect(response.body).to include("CRZ due within 14 days (2)")
      expect(response.body).to include("CRZ overdue (1)")
    end

    it "link to the deadline filter while preserving the other normalized params" do
      get "/admin/contracts", params: { state: "draft", q: "ZP", source: "bogus", deadline: "bogus" }

      body = response.body
      chip = body[%r{<a[^>]*>CRZ overdue \(1\)</a>}]
      expect(chip).to include("deadline=overdue")
      expect(chip).to include("state=draft")
      expect(chip).to include("q=ZP")
      expect(chip).not_to include("source=")
      expect(chip).not_to include("bogus")
    end

    it "marks the active deadline chip and keeps the deadline on the state chips" do
      get "/admin/contracts", params: { deadline: "overdue" }

      expect(response.body[%r{<a[^>]*>CRZ overdue \(1\)</a>}]).to include("contracts-sk__counter--active")
      expect(response.body[%r{<a[^>]*>Draft \(\d+\)</a>}]).to include("deadline=overdue")
    end

    it "render zero counts" do
      contract_class.delete_all

      get "/admin/contracts"

      expect(response.body).to include("CRZ due within 14 days (0)")
      expect(response.body).to include("CRZ overdue (0)")
    end
  end

  describe "the row badge" do
    it "renders Decidim label badges: alert when overdue, warning inside 14 days, plain beyond" do
      seed_deadline_set!

      get "/admin/contracts"

      body = response.body
      expect(body).to include("CRZ deadline</th>")
      expect(body).to include(%(<span class="label alert">Overdue</span>))
      expect(body).to include(%(<span class="label warning">7 days</span>))
      expect(body).to include(%(<span class="label warning">14 days</span>))
      expect(body).to include(%(<span class="label">15 days</span>))
      expect(body).to include("Deadline unknown")
      expect(body).to include(%(<span class="sr-only">Deadline unknown — add signing date</span>))
      expect(body).to include(%(<span aria-hidden="true">\u2014</span>))
    end

    it "renders due today, singular and the Slovak plural forms" do
      create_contract!(reference: "ZP-DL-101", signed_on: Date.new(2026, 3, 1))
      create_contract!(reference: "ZP-DL-102", signed_on: Date.new(2026, 3, 2))
      create_contract!(reference: "ZP-DL-103", signed_on: Date.new(2026, 3, 4))
      create_contract!(reference: "ZP-DL-104", signed_on: Date.new(2026, 3, 8))
      create_contract!(reference: "ZP-DL-105", signed_on: Date.new(2026, 2, 1))

      get "/admin/contracts"
      expect(response.body).to include(%(<span class="label warning">Due today</span>))
      expect(response.body).to include(%(<span class="label warning">1 day</span>))

      with_slovak { get "/admin/contracts" }
      aggregate_failures do
        expect(response.body).to include(%(<span class="label warning">Dnes</span>))
        expect(response.body).to include(%(<span class="label warning">1 deň</span>))
        expect(response.body).to include(%(<span class="label warning">3 dni</span>))
        expect(response.body).to include(%(<span class="label warning">7 dní</span>))
        expect(response.body).to include(%(<span class="label alert">Po termíne</span>))
        expect(response.body).to include("Lehota CRZ</th>")
      end
    end

    it "renders no badge for filed, mirror and terminal rows" do
      create_contract!(reference: "ZP-DL-201", signed_on: Date.new(2026, 1, 1),
                       crz_filed_at: Time.current, state: "published")
      create_contract!(reference: "ZP-DL-202", signed_on: Date.new(2026, 1, 1), source: "crz",
                       source_id: "900000001", state: "published")
      create_contract!(reference: "ZP-DL-203", signed_on: Date.new(2026, 1, 1), state: "archived")

      get "/admin/contracts"

      expect(response.body).not_to include("label alert")
      expect(response.body).not_to include("label warning")
      expect(response.body).not_to include("Deadline unknown")
    end

    it "counts a typed crz_url without a filing confirmation as not filed (#125)" do
      create_contract!(reference: "ZP-DL-301", signed_on: Date.new(2026, 1, 1),
                       crz_url: "https://crz.gov.sk/zmluva/1/")

      get "/admin/contracts"

      expect(response.body).to include(%(<span class="label alert">Overdue</span>))
    end
  end

  describe "the edit page deadline line" do
    it "shows the deadline date and the days left for a tracked record" do
      record = create_contract!(reference: "ZP-DL-401", signed_on: Date.new(2026, 3, 8))

      get "/admin/contracts/#{record.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("CRZ filing deadline: 2026-06-08 (7 days left)")
    end

    it "shows the due-today and overdue wordings" do
      today_record = create_contract!(reference: "ZP-DL-402", signed_on: Date.new(2026, 3, 1))
      late = create_contract!(reference: "ZP-DL-403", signed_on: Date.new(2026, 2, 15))

      get "/admin/contracts/#{today_record.id}/edit"
      expect(response.body).to include("CRZ filing deadline: 2026-06-01 (due today)")

      get "/admin/contracts/#{late.id}/edit"
      expect(response.body).to include("CRZ filing deadline passed on 2026-05-15 (17 days overdue)")
    end

    it "prompts for the signing date when it is missing" do
      record = create_contract!(reference: "ZP-DL-404", signed_on: nil)

      get "/admin/contracts/#{record.id}/edit"

      expect(response.body).to include("CRZ filing deadline unknown — add signing date")
    end

    it "renders nothing for a record confirmed as filed" do
      record = create_contract!(reference: "ZP-DL-405", signed_on: Date.new(2026, 3, 8),
                                crz_filed_at: Time.current)

      get "/admin/contracts/#{record.id}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("CRZ filing deadline")
    end

    it "reads the persisted record, not the rejected form values, after a failed update" do
      record = create_contract!(reference: "ZP-DL-406", signed_on: Date.new(2026, 3, 8))
      create_contract!(reference: "ZP-DL-900")

      # The duplicate reference passes the form and fails only at the
      # model (update! raises RecordInvalid with the values assigned), so
      # this exercises update_failed's restore_attributes.
      patch "/admin/contracts/#{record.id}",
            params: { contract: { title: "Road-REJECTED", reference: "ZP-DL-900", signed_on: "2026-01-01" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("CRZ filing deadline: 2026-06-08 (7 days left)")
      expect(response.body).to include("Road-REJECTED")
      expect(record.reload.signed_on).to eq(Date.new(2026, 3, 8))
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
