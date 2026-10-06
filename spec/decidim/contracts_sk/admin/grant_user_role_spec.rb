# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for GrantUserRole (M03-06-D, civora-org/civora-platform
# #111, parent #95), run against the real migrations on in-memory SQLite.
# Outcomes are asserted on the events hash Decidim::Command.call returns.
# Synthetic data only: example.org addresses, no real people.
#
# The in-lock guards (actor demoted, target blocked after admission) are
# exercised deterministically, without threads: a wrapper around the lock
# query's User.where(id: ...) call changes the row right before the lock
# is taken - exactly the window a concurrent request would hit.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::GrantUserRole, :db do
  before { migrate_engine_schema! }

  def role_class = Decidim::ContractsSk::UserRole
  def audit_class = Decidim::ContractsSk::AuditEvent
  def form_class = Decidim::ContractsSk::Admin::UserRoleForm

  let(:admin) do
    Decidim::User.create!(organization: organization, email: "admin@example.org", name: "Ada Admin",
                          admin: true, admin_terms_accepted_at: Time.current)
  end
  let(:target) do
    Decidim::User.create!(organization: organization, email: "person@example.org", name: "Pat Person")
  end
  let(:form) { form_class.new(email: target.email, role: "editor") }

  def run(a_form = form, actor_user: admin, org: organization)
    described_class.call(a_form, organization: org, actor: actor_user)
  end

  # Runs the block's side effect right before the lock query
  # (User.where(id: ...)) executes, once.
  def before_lock_query
    fired = false
    allow(Decidim::User).to receive(:where).and_wrap_original do |original, *args, **kwargs|
      params = args.first
      if !fired && ((params.is_a?(Hash) && params.key?(:id)) || kwargs.key?(:id))
        fired = true
        yield
      end
      original.call(*args, **kwargs)
    end
  end

  it "creates the role and exactly one audit row (actor, target user, organization, action)" do
    events = nil

    expect { events = run }
      .to change(role_class, :count).by(1)
      .and change(audit_class, :count).by(1)

    expect(events).to have_key(:ok)
    role = events[:ok]
    expect(role).to have_attributes(user: target, organization: organization, role: "editor")

    audit = audit_class.last
    expect(audit).to have_attributes(action: "user_role.grant_editor", target: target, actor: admin,
                                     organization: organization)
  end

  it "writes the role into the action for each engine role" do
    Decidim::ContractsSk::ContractLifecycle::ROLES.each do |role|
      run(form_class.new(email: target.email, role: role.to_s))

      expect(audit_class.where(action: "user_role.grant_#{role}", target: target).count).to eq(1)
    end
  end

  it "keeps emails and names out of the audit row entirely" do
    run

    values = audit_class.last.attributes.values.map(&:to_s).join(" ")
    expect(values).not_to include(target.email)
    expect(values).not_to include(target.name)
    expect(values).not_to include(admin.email)
    expect(values).not_to include(admin.name)
  end

  it "normalizes the email (case and padding) before the lookup" do
    target
    padded = form_class.new(email: "  PERSON@Example.org ", role: "reviewer")

    expect(run(padded)).to have_key(:ok)
  end

  it "lets one user hold both roles" do
    run
    expect(run(form_class.new(email: target.email, role: "reviewer"))).to have_key(:ok)

    expect(role_class.where(user: target).pluck(:role)).to contain_exactly("editor", "reviewer")
  end

  it "broadcasts :invalid and writes nothing for an invalid form" do
    bad = form_class.new(email: target.email, role: "admin")

    expect do
      expect(run(bad)).to have_key(:invalid)
    end.not_to(change { [role_class.count, audit_class.count] })
    expect(bad.errors).to include(:role)
  end

  describe "unknown targets answer with one generic error on :email" do
    let(:message) { "No user with this email in this organization." }

    def expect_generic_refusal(a_form)
      expect do
        expect(run(a_form)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })

      expect(a_form.errors[:email]).to eq([message])
    end

    it "for an email nobody has" do
      expect_generic_refusal(form_class.new(email: "nobody@example.org", role: "editor"))
    end

    it "for a user of ANOTHER organization" do
      other_org = Decidim::Organization.create!
      foreign = Decidim::User.create!(organization: other_org, email: "foreign@example.org")

      expect_generic_refusal(form_class.new(email: foreign.email, role: "editor"))
    end

    it "for a blocked, deleted or managed user" do
      { "blocked@example.org" => { blocked: true }, "deleted@example.org" => { deleted_at: Time.current },
        "managed@example.org" => { managed: true } }.each do |email, attrs|
        Decidim::User.create!({ organization: organization, email: email }.merge(attrs))

        expect_generic_refusal(form_class.new(email: email, role: "editor"))
      end
    end
  end

  describe "idempotency" do
    it "answers :invalid for a role the user already holds, writing no role row and no audit row" do
      run

      expect do
        expect(run).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })

      expect(role_class.where(user: target, role: "editor").count).to eq(1)
    end

    it "rescues a concurrent duplicate caught only by the unique index, writing nothing" do
      allow(role_class).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

      expect do
        expect(run).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end
  end

  describe "who may grant (defense in depth; the permission layer is checked at admission)" do
    let(:editor_reviewer) do
      Decidim::User.create!(organization: organization, email: "holder@example.org", name: "Hal Holder")
    end

    before do
      role_class.create!(user: editor_reviewer, organization: organization, role: "editor")
      role_class.create!(user: editor_reviewer, organization: organization, role: "reviewer")
    end

    it "refuses a non-admin holding both engine roles granting to another user" do
      expect do
        expect(run(actor_user: editor_reviewer)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "refuses a non-admin role holder granting THEMSELVES (self-grant)" do
      own = form_class.new(email: editor_reviewer.email, role: "editor")
      role_class.where(user: editor_reviewer, role: "editor").destroy_all

      expect do
        expect(run(own, actor_user: editor_reviewer)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "refuses an organization admin who has not accepted the admin terms" do
      admin.update!(admin_terms_accepted_at: nil)

      expect do
        expect(run).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "refuses an admin of ANOTHER organization" do
      other_org = Decidim::Organization.create!
      foreign_admin = Decidim::User.create!(organization: other_org, admin: true,
                                            admin_terms_accepted_at: Time.current)

      expect do
        expect(run(actor_user: foreign_admin)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "refuses a missing actor" do
      expect do
        expect(run(actor_user: nil)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "lets an organization admin grant themselves (the admin default already holds both roles)" do
      own = form_class.new(email: admin.email, role: "reviewer")

      expect(run(own)).to have_key(:ok)
      expect(audit_class.last).to have_attributes(target: admin, actor: admin)
    end
  end

  describe "race safety (guards re-read inside the lock)" do
    it "refuses when the actor was demoted after admission, even though the in-memory copy is still an admin" do
      stale_admin = Decidim::User.find(admin.id)
      before_lock_query { admin.update_columns(admin: false) }

      expect(stale_admin).to be_admin
      expect do
        expect(run(actor_user: stale_admin)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "refuses when the target was blocked after the lookup" do
      form
      before_lock_query { target.update_columns(blocked: true) }

      expect do
        expect(run).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "refuses when the target was moved to another organization after the lookup" do
      form
      other_org = Decidim::Organization.create!
      before_lock_query { target.update_columns(decidim_organization_id: other_org.id) }

      expect do
        expect(run).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "rolls the role back when the audit row cannot be written (one transaction)" do
      allow(audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect do
        expect(run).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
