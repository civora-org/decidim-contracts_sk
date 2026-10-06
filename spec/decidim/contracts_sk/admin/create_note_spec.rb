# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for CreateNote (civora-org/civora-platform#128), run
# against the real migrations on in-memory SQLite. Outcomes are asserted on
# the events hash Decidim::Command.call returns. Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::CreateNote, :db do
  before { migrate_engine_schema! }

  let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }
  let(:form) { Decidim::ContractsSk::Admin::NoteForm.new(body: "Lawyer, please check section 4.") }
  let(:note_class) { Decidim::ContractsSk::Note }
  let(:audit_class) { Decidim::ContractsSk::AuditEvent }

  it "appends a note authored by the user and writes one audit row without the body" do
    events = nil

    expect { events = described_class.call(form, contract, user: author) }
      .to change(note_class, :count).by(1)
      .and change(audit_class, :count).by(1)

    expect(events).to have_key(:ok)
    note = events[:ok]
    expect(note.contract).to eq(contract)
    expect(note.author).to eq(author)
    expect(note.body).to eq("Lawyer, please check section 4.")

    audit = audit_class.last
    expect(audit.action).to eq("contract.note_added")
    expect(audit.target).to eq(contract)
    expect(audit.actor).to eq(author)
    expect(audit.attributes.values.map(&:to_s).join(" ")).not_to include("Lawyer, please")
  end

  it "accepts notes on every lifecycle state, including published (notes survive publication)" do
    Decidim::ContractsSk::ContractLifecycle::STATES.each_with_index do |state, index|
      record = Decidim::ContractsSk::Contract.create!(contract_attributes(state: state.to_s, reference: "ZP-#{index}"))

      expect(described_class.call(form, record, user: author)).to have_key(:ok), "state #{state}"
    end
  end

  it "broadcasts :invalid and writes nothing for an invalid form" do
    blank = Decidim::ContractsSk::Admin::NoteForm.new(body: " ")

    expect do
      expect(described_class.call(blank, contract, user: author)).to have_key(:invalid)
    end.not_to(change { [note_class.count, audit_class.count] })
  end

  it "refuses an author of another organization, inside the lock, writing nothing" do
    foreigner = Decidim::User.create!(organization: Decidim::Organization.create!)

    expect do
      expect(described_class.call(form, contract, user: foreigner)).to have_key(:invalid)
    end.not_to(change { [note_class.count, audit_class.count] })
  end

  it "refuses a stale contract that was removed in the meantime (the lock reloads the row)" do
    stale = Decidim::ContractsSk::Contract.find(contract.id)
    Decidim::ContractsSk::Contract.where(id: contract.id).delete_all

    expect do
      expect(described_class.call(form, stale, user: author)).to have_key(:invalid)
    end.not_to change(note_class, :count)
  end

  it "rolls the note back when the audit row fails (atomic)" do
    allow(audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

    expect do
      expect(described_class.call(form, contract, user: author)).to have_key(:invalid)
    end.not_to change(note_class, :count)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
