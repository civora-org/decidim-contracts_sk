# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for CreateContractFromTemplate (civora-org/civora-platform
# #127), run against the real migrations on in-memory SQLite. Outcomes are
# asserted on the events hash Decidim::Command.call returns. Synthetic data
# only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::CreateContractFromTemplate, :db do
  before { migrate_engine_schema! }

  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:audit_class) { Decidim::ContractsSk::AuditEvent }
  let(:template) do
    Decidim::ContractsSk::Template.create!(
      organization: organization, name: "Rental", title_pattern: "Rental - ",
      subject_matter: "Rental of premises.", currency: "EUR",
      object_party_name: "Mesto Demo", object_party_ico: "00000001", object_party_address: "Main 1"
    )
  end
  let(:form) do
    Decidim::ContractsSk::Admin::ContractForm.new(title: "Rental - Shop 4", reference: "ZP-2026-100",
                                                  subject_matter: "Edited subject.", currency: "EUR")
  end

  def call(record = template, user: author, org: organization, contract_form: form)
    described_class.call(contract_form, record, user: user, organization: org)
  end

  it "creates a plain draft with the form's values, the template's object party and one audit row" do
    events = nil

    expect { events = call }
      .to change(contract_class, :count).by(1)
      .and change(Decidim::ContractsSk::Party, :count).by(1)
      .and change(audit_class, :count).by(1)

    contract = events[:ok]
    expect(contract.state).to eq("draft")
    expect(contract.published_at).to be_nil
    expect(contract.author).to eq(author)
    expect(contract.organization).to eq(organization)
    # The form's (possibly edited) values win over the template's prefill.
    expect(contract.title).to eq("Rental - Shop 4")
    expect(contract.subject_matter).to eq("Edited subject.")

    party = contract.parties.sole
    expect([party.role, party.name, party.ico, party.address]).to eq(["object", "Mesto Demo", "00000001", "Main 1"])

    audit = audit_class.last
    expect(audit.action).to eq("contract.create_from_template")
    expect(audit.target).to eq(contract)
    expect(audit.actor).to eq(author)
    expect(audit.organization).to eq(organization)
  end

  it "creates no party for a template without a skeleton" do
    bare = Decidim::ContractsSk::Template.create!(organization: organization, name: "Bare")

    expect { call(bare) }.to change(contract_class, :count).by(1)
    expect(Decidim::ContractsSk::Party.count).to eq(0)
  end

  it "is copy-on-create: later template edits or removal never change the contract or its party" do
    contract = call[:ok]

    template.update!(object_party_name: "Renamed", subject_matter: "Changed", title_pattern: "Other")
    expect(contract.reload.subject_matter).to eq("Edited subject.")
    expect(contract.parties.sole.name).to eq("Mesto Demo")

    template.destroy!
    expect(contract_class.find(contract.id).parties.sole.name).to eq("Mesto Demo")
  end

  it "seeds the party from the post-lock template, not from a stale pre-loaded copy" do
    stale = Decidim::ContractsSk::Template.find(template.id)
    template.update!(object_party_name: "Merged Municipality")

    contract = call(stale)[:ok]

    expect(contract.parties.sole.name).to eq("Merged Municipality")
  end

  it "answers :invalid and writes nothing when the template was removed in the meantime" do
    stale = Decidim::ContractsSk::Template.find(template.id)
    Decidim::ContractsSk::Template.where(id: template.id).delete_all

    expect do
      expect(call(stale)).to have_key(:invalid)
    end.not_to(change { [contract_class.count, audit_class.count] })
  end

  it "refuses a template of another organization inside the lock, writing nothing" do
    foreign = Decidim::ContractsSk::Template.create!(organization: Decidim::Organization.create!, name: "Foreign")

    expect do
      expect(call(foreign)).to have_key(:invalid)
    end.not_to(change { [contract_class.count, Decidim::ContractsSk::Party.count, audit_class.count] })
  end

  it "refuses a user of another organization, writing nothing" do
    foreigner = Decidim::User.create!(organization: Decidim::Organization.create!)

    expect do
      expect(call(user: foreigner)).to have_key(:invalid)
    end.not_to(change { [contract_class.count, audit_class.count] })
  end

  it "answers :invalid and writes nothing for an invalid form" do
    blank = Decidim::ContractsSk::Admin::ContractForm.new(title: "", reference: "")

    expect do
      expect(call(contract_form: blank)).to have_key(:invalid)
    end.not_to(change { [contract_class.count, audit_class.count] })
  end

  it "rolls the contract and the party back when the audit row fails (atomic)" do
    allow(audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

    expect do
      expect(call).to have_key(:invalid)
    end.not_to(change { [contract_class.count, Decidim::ContractsSk::Party.count] })
  end

  it "rolls everything back on a duplicate reference (no orphan party, no audit row)" do
    contract_class.create!(contract_attributes(reference: "ZP-2026-100"))

    expect do
      expect(call).to have_key(:invalid)
    end.not_to(change { [contract_class.count, Decidim::ContractsSk::Party.count, audit_class.count] })
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
