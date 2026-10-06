# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for RevokeUserRole (M03-06-D, civora-org/civora-platform
# #111, parent #95), run against the real migrations on in-memory SQLite.
# Synthetic data only. The stale-object and demoted-actor cases are
# deterministic (no threads): a second instance changes the database
# between the load and the command call.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::RevokeUserRole, :db do
  before { migrate_engine_schema! }

  def role_class = Decidim::ContractsSk::UserRole
  def audit_class = Decidim::ContractsSk::AuditEvent

  let(:admin) do
    Decidim::User.create!(organization: organization, email: "admin@example.org", name: "Ada Admin",
                          admin: true, admin_terms_accepted_at: Time.current)
  end
  let(:holder) do
    Decidim::User.create!(organization: organization, email: "holder@example.org", name: "Hal Holder")
  end
  let!(:user_role) { role_class.create!(user: holder, organization: organization, role: "reviewer") }

  def run(role = user_role, actor_user: admin)
    described_class.call(role, actor: actor_user)
  end

  it "deletes the role and writes exactly one audit row targeting the affected user" do
    events = nil

    expect { events = run }
      .to change(role_class, :count).by(-1)
      .and change(audit_class, :count).by(1)

    expect(events).to have_key(:ok)
    expect(audit_class.last).to have_attributes(action: "user_role.revoke_reviewer", target: holder, actor: admin,
                                                organization: organization)
  end

  it "keeps emails and names out of the audit row" do
    run

    values = audit_class.last.attributes.values.map(&:to_s).join(" ")
    [holder.email, holder.name, admin.email, admin.name].each { |secret| expect(values).not_to include(secret) }
  end

  it "revokes only the named role of a user holding both" do
    other = role_class.create!(user: holder, organization: organization, role: "editor")

    run

    expect(role_class.where(user: holder)).to contain_exactly(other)
  end

  describe "idempotency" do
    it "answers :invalid for a row already revoked (stale in-memory copy), writing no audit row" do
      stale = role_class.find(user_role.id)
      run

      expect do
        expect(run(stale)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end
  end

  describe "who may revoke (defense in depth)" do
    let(:other_holder) do
      Decidim::User.create!(organization: organization, email: "other@example.org", name: "Olga Other")
    end

    before do
      %w[editor reviewer].each { |role| role_class.create!(user: other_holder, organization: organization, role: role) }
    end

    it "refuses a non-admin holding both engine roles revoking another user's role" do
      expect do
        expect(run(actor_user: other_holder)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "refuses a non-admin role holder revoking THEIR OWN role (self-revoke)" do
      own = role_class.find_by!(user: other_holder, role: "editor")

      expect do
        expect(run(own, actor_user: other_holder)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "refuses an organization admin who has not accepted the admin terms" do
      admin.update!(admin_terms_accepted_at: nil)

      expect do
        expect(run).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "refuses an admin of ANOTHER organization" do
      foreign_admin = Decidim::User.create!(organization: Decidim::Organization.create!, admin: true,
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

    it "lets an organization admin revoke a role stored for themselves" do
      own = role_class.create!(user: admin, organization: organization, role: "editor")

      expect(run(own)).to have_key(:ok)
      expect(audit_class.last).to have_attributes(target: admin, actor: admin)
    end
  end

  describe "race safety (guards re-read inside the lock)" do
    it "refuses when the actor was demoted after admission, though the in-memory copy is still an admin" do
      stale_admin = Decidim::User.find(admin.id)
      admin.update_columns(admin: false)

      expect(stale_admin).to be_admin
      expect do
        expect(run(actor_user: stale_admin)).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "rolls the deletion back when the audit row cannot be written (one transaction)" do
      allow(audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect do
        expect(run).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end

    it "rolls the audit row back when the deletion fails (one transaction)" do
      allow(user_role).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)

      expect do
        expect(run).to have_key(:invalid)
      end.not_to(change { [role_class.count, audit_class.count] })
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
