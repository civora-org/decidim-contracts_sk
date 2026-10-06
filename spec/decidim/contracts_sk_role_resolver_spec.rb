# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic specs for the DEFAULT role_resolver (admin roles UNION stored
# UserRole rows) and the default notification_candidates seam
# (M03-06-C, civora-org/civora-platform#110, parent #95). All :db — they run
# against the real migrations on in-memory SQLite (CONTRACTS_SK_DB=1) with
# the anonymous User/Organization stand-ins; no real names or emails.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
RSpec.describe Decidim::ContractsSk, ".role_resolver", :db do
  before do
    migrate_engine_schema!
    admin
  end

  let(:resolver) { described_class.role_resolver }
  let(:other_organization) { Decidim::Organization.create! }
  let(:accepted) { Time.zone.now }
  let(:admin) do
    Decidim::User.create!(organization: organization, admin: true, admin_terms_accepted_at: accepted,
                          confirmed_at: accepted)
  end
  let(:plain) { Decidim::User.create!(organization: organization, confirmed_at: accepted) }

  def grant(user, role, org = user.organization)
    Decidim::ContractsSk::UserRole.create!(user: user, organization: org, role: role)
  end

  def resolve(user, context = {})
    # A fresh object per call: the resolver memoizes per user object.
    resolver.call(Decidim::User.find(user.id), context)
  end

  def select_queries(&block)
    queries = []
    callback = lambda do |*, payload|
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].start_with?("SELECT")
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    queries
  end

  describe "role_resolver" do
    it "keeps granting every role to admins who accepted the terms" do
      expect(resolve(admin)).to eq(%i[editor reviewer])
    end

    it "grants nothing to an admin without accepted terms, even with stored rows ignored for admins" do
      unaccepted = Decidim::User.create!(organization: organization, admin: true)

      expect(resolve(unaccepted)).to eq([])
    end

    it "unions stored roles for a non-admin, in ContractLifecycle::ROLES order" do
      grant(plain, "reviewer")
      expect(resolve(plain)).to eq(%i[reviewer])

      grant(plain, "editor")
      expect(resolve(plain)).to eq(%i[editor reviewer])
    end

    it "grants a non-admin with no rows nothing" do
      expect(resolve(plain)).to eq([])
    end

    it "grants a non-admin nothing for a role stored in another organization" do
      foreign = Decidim::User.create!(organization: other_organization)
      grant(foreign, "editor")

      expect(resolve(plain)).to eq([])
      expect(resolve(foreign)).to eq(%i[editor])
    end

    it "ignores a stored role row outside the engine vocabulary" do
      Decidim::ContractsSk::UserRole.new(user: plain, organization: organization, role: "admin")
                                    .save!(validate: false)

      expect(resolve(plain)).to eq([])
    end

    it "ignores a row stored for a different organization than the user's own" do
      # Unreachable through the model (cross-tenant grants are invalid); written
      # below validation to pin the resolver's own tenant filter.
      Decidim::ContractsSk::UserRole.new(user: plain, organization: other_organization, role: "editor")
                                    .save!(validate: false)

      expect(resolve(plain)).to eq([])
    end

    it "ignores the context argument's type (organization, Hash, nil)" do
      grant(plain, "editor")

      [organization, other_organization, { contract: nil }, {}, nil].each do |context|
        expect(resolve(plain, context)).to eq(%i[editor])
      end
    end

    it "returns nothing for nil and for an unsaved user" do
      expect(resolver.call(nil, {})).to eq([])

      unsaved = Decidim::User.new(organization: organization)
      expect(select_queries { expect(resolver.call(unsaved, {})).to eq([]) }).to be_empty
    end

    it "skips the database entirely for admins" do
      user = Decidim::User.find(admin.id)

      expect(select_queries { resolver.call(user, {}) }).to be_empty
    end

    it "memoizes per user object: one query however often the resolver is called" do
      grant(plain, "reviewer")
      user = Decidim::User.find(plain.id)

      queries = select_queries { 20.times { resolver.call(user, {}) } }

      expect(queries.size).to eq(1)
    end

    it "does not share the memo between user objects (a fresh load sees new grants)" do
      user = Decidim::User.find(plain.id)
      expect(resolver.call(user, {})).to eq([])

      grant(plain, "editor")

      expect(resolver.call(user, {})).to eq([])
      expect(resolver.call(Decidim::User.find(plain.id), {})).to eq(%i[editor])
    end

    it "leaves a host-configured custom resolver untouched" do
      original = described_class.role_resolver
      described_class.role_resolver = ->(_user, _context) { [:reviewer] }
      grant(plain, "editor")

      expect(described_class.role_resolver.call(plain, {})).to eq([:reviewer])
    ensure
      described_class.role_resolver = original
    end
  end

  describe "notification_candidates" do
    let(:candidates) { described_class.notification_candidates.call(organization) }

    it "lists admins and users holding a stored reviewer role, nobody else" do
      reviewer = Decidim::User.create!(organization: organization, confirmed_at: accepted)
      editor = Decidim::User.create!(organization: organization, confirmed_at: accepted)
      grant(reviewer, "reviewer")
      grant(editor, "editor")
      plain

      expect(candidates).to contain_exactly(admin, reviewer)
    end

    it "excludes a reviewer of another organization" do
      foreign = Decidim::User.create!(organization: other_organization, confirmed_at: accepted)
      grant(foreign, "reviewer")

      expect(candidates).to contain_exactly(admin)
      expect(described_class.notification_candidates.call(other_organization)).to contain_exactly(foreign)
    end

    it "excludes unconfirmed, blocked and deleted reviewers" do
      unconfirmed = Decidim::User.create!(organization: organization)
      blocked = Decidim::User.create!(organization: organization, confirmed_at: accepted, blocked: true)
      deleted = Decidim::User.create!(organization: organization, confirmed_at: accepted, deleted_at: accepted)
      [unconfirmed, blocked, deleted].each { |user| grant(user, "reviewer") }

      expect(candidates).to contain_exactly(admin)
    end

    it "lists a user holding a reviewer row once, even when also an admin" do
      grant(admin, "reviewer")

      expect(candidates.to_a).to eq([admin])
    end

    it "makes a non-admin reviewer a recipient of submitted notices end to end" do
      reviewer = Decidim::User.create!(organization: organization, confirmed_at: accepted)
      grant(reviewer, "reviewer")
      grant(plain, "editor")
      contract = Decidim::ContractsSk::Contract.create!(contract_attributes)

      recipients = Decidim::ContractsSk::TransitionNotification
                   .recipients(event: :submit, contract: contract, actor: author)

      expect(recipients).to contain_exactly(admin, reviewer)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
