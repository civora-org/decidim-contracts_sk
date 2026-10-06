# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Deterministic, offline specs for the grant-role form (M03-06-D,
# civora-org/civora-platform#111). Pure ActiveModel, no database.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Decidim::ContractsSk::Admin::UserRoleForm do
  def build_form(**attrs)
    described_class.new({ email: "person@example.org", role: "editor" }.merge(attrs))
  end

  it "is valid with an email and each engine role" do
    Decidim::ContractsSk::ContractLifecycle::ROLES.each do |role|
      expect(build_form(role: role.to_s)).to be_valid
    end
  end

  it "draws its role vocabulary from ContractLifecycle::ROLES" do
    expect(described_class::ROLES).to eq(Decidim::ContractsSk::ContractLifecycle::ROLES.map(&:to_s))
  end

  it "rejects a blank or whitespace-only email" do
    ["", "   ", nil].each do |blank|
      form = build_form(email: blank)

      expect(form).not_to be_valid
      expect(form.errors).to include(:email)
    end
  end

  it "rejects a role outside the vocabulary or blank" do
    ["admin", "", nil, "Editor"].each do |bad|
      form = build_form(role: bad)

      expect(form).not_to be_valid
      expect(form.errors).to include(:role)
    end
  end

  it "strips and downcases the email" do
    expect(build_form(email: "  Person@Example.ORG \n").email).to eq("person@example.org")
  end

  it "strips the role" do
    expect(build_form(role: " reviewer ").role).to eq("reviewer")
  end
end
# rubocop:enable RSpec/MultipleExpectations
