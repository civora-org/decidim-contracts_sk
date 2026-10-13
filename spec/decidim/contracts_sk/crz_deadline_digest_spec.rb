# frozen_string_literal: true

# ---------------------------------------------------------------------------
# The morning CRZ deadline digest (civora-org/civora-platform#202): the
# mailer's content, the delivery service (who gets it, nothing due -> nothing
# sent, per-organization scoping, fail-soft) and the rake task. DB-backed,
# synthetic data only. "Today" is passed in, so no clock is involved.
# ---------------------------------------------------------------------------

require "spec_helper"
require "rake"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
RSpec.describe "CRZ deadline digest", :db do # rubocop:disable RSpec/DescribeClass
  include ActiveSupport::Testing::TimeHelpers

  let(:today) { Date.new(2026, 10, 13) }
  let(:host) { "zmluvy.example.org" }
  let(:service) { Decidim::ContractsSk::DeliverCrzDeadlineDigest }
  let(:mailer) { Decidim::ContractsSk::CrzDeadlineDigestMailer }

  before do
    migrate_engine_schema!
    organization.update!(host: host, default_locale: "en", name: { "en" => "Green Village", "sk" => "Obec Zelená" })
    ActionMailer::Base.deliveries.clear
  end

  def user!(email, org: organization, **attrs)
    Decidim::User.create!({ organization: org, email: email, confirmed_at: Time.utc(2026, 1, 1) }.merge(attrs))
  end

  def contract!(reference, org: organization, **overrides)
    Decidim::ContractsSk::Contract.create!(
      contract_attributes({ organization: org, reference: reference, title: "Title #{reference}",
                            state: "published", signed_on: Date.new(2026, 6, 1) }.merge(overrides))
    )
  end

  def recipients_of_deliveries
    ActionMailer::Base.deliveries.flat_map(&:to).sort
  end

  describe "the mailer" do
    subject(:mail) { mailer.digest(user!("ref@example.org"), organization, contracts, contracts.size, today: today) }

    let(:overdue) { contract!("ZP-OVERDUE", signed_on: Date.new(2026, 6, 1)) }
    let(:soon) { contract!("ZP-SOON", signed_on: Date.new(2026, 7, 20)) }
    let(:contracts) { [overdue, soon] }
    let(:html) { mail.body.decoded }

    it "is addressed to the one recipient, with the organization in the subject" do
      expect(mail.to).to eq(["ref@example.org"])
      expect(mail.cc).to be_blank
      expect(mail.bcc).to be_blank
      expect(mail.subject).to eq("CRZ deadlines: contracts not yet effective - Green Village")
    end

    it "groups overdue and due-soon contracts, saying each is not effective until published in the CRZ" do
      expect(html).to include("Overdue: 1").and include("Deadline within 14 days: 1")
      expect(html).to include("Title ZP-OVERDUE").and include("no. ZP-OVERDUE")
      expect(html).to include("Title ZP-SOON")
      expect(html).to include("2026-09-01")
      expect(html.scan("Not effective until published in the CRZ.").size).to eq(2)
      expect(html).to include("not legal advice")
    end

    it "links each contract on the organization's host, in the recipient's locale" do
      expect(html).to include(%(href="http://#{host}/admin/contracts/#{overdue.id}?locale=en"))
      expect(html).to include(%(href="http://#{host}/admin/contracts/#{soon.id}?locale=en"))
    end

    it "carries titles and references only: no party, amount or subject matter" do
      overdue.update!(amount: BigDecimal("987654.32"), subject_matter: "Secret subject matter")
      overdue.parties.create!(role: "contractor", name: "Hidden Supplier s.r.o.", ico: "12345678")

      text = mailer.digest(user!("other@example.org"), organization, [overdue.reload], 1, today: today).body.decoded

      expect(text).not_to include("987654")
      expect(text).not_to include("Secret subject matter")
      expect(text).not_to include("Hidden Supplier")
    end

    it "escapes hostile titles and references" do
      overdue.update!(title: "<script>alert(1)</script>", reference: "<b>REF</b>")

      text = mailer.digest(user!("esc@example.org"), organization, [overdue.reload], 1, today: today).body.decoded

      expect(text).to include("&lt;script&gt;alert(1)&lt;/script&gt;").and include("&lt;b&gt;REF&lt;/b&gt;")
      expect(text).not_to include("<script>")
    end

    it "points to the overview when more contracts exist than are listed" do
      text = mailer.digest(user!("more@example.org"), organization, contracts, 25, today: today).body.decoded

      expect(text).to include("And more in the contracts list: 23")
      expect(text).to include(%(href="http://#{host}/admin?locale=en"))
    end

    it "renders in Slovak for a Slovak-speaking recipient" do
      organization.update!(default_locale: "sk")
      sk_mail = mailer.digest(user!("sk@example.org"), organization.reload, contracts, 2, today: today)

      expect(sk_mail.subject).to eq("Lehoty CRZ: zmluvy zatiaľ neúčinné - Obec Zelená")
      expect(sk_mail.body.decoded).to include("Po lehote: 1").and include("Do zverejnenia v CRZ nie je účinná.")
    end
  end

  describe "the delivery service" do
    it "sends one mail to each admin and each editor, and to nobody else" do
      contract!("ZP-1")
      user!("admin@example.org", admin: true)
      editor = user!("editor@example.org")
      Decidim::ContractsSk::UserRole.create!(user: editor, organization: organization, role: "editor")
      reviewer = user!("reviewer@example.org")
      Decidim::ContractsSk::UserRole.create!(user: reviewer, organization: organization, role: "reviewer")
      user!("citizen@example.org")

      summary = service.call(organization: organization, today: today)

      expect(recipients_of_deliveries).to eq(%w[admin@example.org editor@example.org])
      expect([summary.contracts, summary.recipients, summary.delivered, summary.failed]).to eq([1, 2, 2, 0])
    end

    it "skips unconfirmed, blocked and deleted admins" do
      contract!("ZP-1")
      user!("ok@example.org", admin: true)
      user!("unconfirmed@example.org", admin: true, confirmed_at: nil)
      user!("blocked@example.org", admin: true, blocked: true)
      user!("deleted@example.org", admin: true, deleted_at: Time.utc(2026, 2, 1))

      service.call(organization: organization, today: today)

      expect(recipients_of_deliveries).to eq(%w[ok@example.org])
    end

    it "sends nothing when no contract is overdue or near its deadline" do
      user!("admin@example.org", admin: true)
      contract!("FAR", signed_on: Date.new(2026, 10, 1))
      contract!("FILED", crz_filed_at: Time.utc(2026, 7, 1))
      contract!("MIRROR", source: "crz", source_id: "900000001")
      contract!("ARCHIVED", state: "archived")

      summary = service.call(organization: organization, today: today)

      expect(ActionMailer::Base.deliveries).to be_empty
      expect([summary.contracts, summary.delivered]).to eq([0, 0])
    end

    it "scopes recipients and contracts to the organization" do
      other = Decidim::Organization.create!(host: "other.example.org", default_locale: "en")
      contract!("MINE")
      contract!("THEIRS", org: other, author: user!("author@other.example.org", org: other))
      user!("mine@example.org", admin: true)
      user!("theirs@other.example.org", org: other, admin: true)

      service.call(organization: organization, today: today)

      expect(recipients_of_deliveries).to eq(%w[mine@example.org])
      body = ActionMailer::Base.deliveries.first.body.decoded
      expect(body).to include("Title MINE")
      expect(body).not_to include("Title THEIRS")
    end

    it "sends nothing to another organization that has nothing due" do
      other = Decidim::Organization.create!(host: "other.example.org", default_locale: "en")
      user!("theirs@other.example.org", org: other, admin: true)
      contract!("MINE")

      service.call(organization: other, today: today)

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "caps the listed contracts and reports the rest" do
      stub_const("#{service}::LIST_LIMIT", 2)
      user!("admin@example.org", admin: true)
      3.times { |i| contract!("ZP-#{i}", signed_on: Date.new(2026, 6, 1) + i) }

      service.call(organization: organization, today: today)

      body = ActionMailer::Base.deliveries.first.body.decoded
      expect(body.scan("Not effective until published").size).to eq(2)
      expect(body).to include("And more in the contracts list: 1")
    end

    it "is fail-soft: one failing recipient is counted and does not stop the others" do
      contract!("ZP-1")
      bad = user!("bad@example.org", admin: true)
      user!("good@example.org", admin: true)
      logger = instance_double(Logger, error: nil)
      allow(mailer).to receive(:digest).and_wrap_original do |original, user, *args, **kwargs|
        raise "smtp down" if user.id == bad.id

        original.call(user, *args, **kwargs)
      end

      summary = service.call(organization: organization, today: today, logger: logger)

      expect(recipients_of_deliveries).to eq(%w[good@example.org])
      expect([summary.delivered, summary.failed]).to eq([1, 1])
      expect(logger).to have_received(:error).with(/user #{bad.id} failed: RuntimeError/)
      expect(logger).not_to have_received(:error).with(/bad@example.org/)
    end
  end

  describe "decidim_contracts_sk:crz_deadline_digest" do
    before do
      Rake.application = Rake::Application.new
      load File.join(engine_root, "lib", "tasks", "decidim_contracts_sk_crz_deadline_digest.rake")
      Rake::Task.define_task(:environment)
      travel_to(Time.utc(2026, 10, 13, 8))
    end

    def run_task(*args)
      task = Rake::Task["decidim_contracts_sk:crz_deadline_digest"]
      task.reenable
      task.invoke(*args)
    end

    it "sends for the given organization and prints counts, never an address" do
      contract!("ZP-1")
      user!("admin@example.org", admin: true)

      expect { run_task(organization.id.to_s) }
        .to output("organization #{organization.id}: contracts=1 recipients=1 delivered=1 failed=0\n").to_stdout
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "skips organizations other than the given one" do
      other = Decidim::Organization.create!(host: "other.example.org")
      user!("theirs@other.example.org", org: other, admin: true)
      contract!("MINE")

      expect { run_task(organization.id.to_s) }
        .to output("organization #{organization.id}: contracts=1 recipients=0 delivered=0 failed=0\n").to_stdout
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "runs for every organization without an argument and sends nothing when nothing is due" do
      other = Decidim::Organization.create!(host: "other.example.org")

      expect { run_task }.to output(/organization #{organization.id}:.*\norganization #{other.id}:/m).to_stdout
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
