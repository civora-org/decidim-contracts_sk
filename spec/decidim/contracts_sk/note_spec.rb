# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the internal review Note model (civora-org/civora-platform#128).
# The default run asserts structure only; the :db group runs against the real
# migrations on in-memory SQLite (CONTRACTS_SK_DB=1). Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Note do
  describe "class structure" do
    it "inherits from the engine's ApplicationRecord and maps to the prefixed table" do
      expect(described_class.superclass).to eq(Decidim::ContractsSk::ApplicationRecord)
      expect(described_class.table_name).to eq("decidim_contracts_sk_notes")
    end

    it "belongs to its contract and its author (by decidim_author_id)" do
      contract = described_class.reflect_on_association(:contract)
      author = described_class.reflect_on_association(:author)

      expect(contract.macro).to eq(:belongs_to)
      expect(author.macro).to eq(:belongs_to)
      expect(author.foreign_key).to eq("decidim_author_id")
    end

    it "caps the body at 2000 characters" do
      expect(described_class::MAX_BODY_LENGTH).to eq(2000)
    end
  end

  describe "contract association" do
    it "deletes notes with the contract without per-row destroy (append-only rows are readonly)" do
      reflection = Decidim::ContractsSk::Contract.reflect_on_association(:notes)

      expect(reflection.options[:dependent]).to eq(:delete_all)
    end
  end

  describe "behaviour", :db do
    before { migrate_engine_schema! }

    let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

    def build_note(overrides = {})
      described_class.new({ contract: contract, author: author, body: "Please check the VAT clause." }.merge(overrides))
    end

    it "persists a valid note with a creation timestamp" do
      note = build_note
      note.save!

      expect(note.reload.created_at).to be_present
      expect(contract.notes.reload).to contain_exactly(note)
    end

    it "requires a body, a contract and an author" do
      expect(build_note(body: "").valid?).to be(false)
      expect(build_note(body: nil).valid?).to be(false)
      expect(build_note(contract: nil).valid?).to be(false)
      expect(build_note(author: nil).valid?).to be(false)
    end

    it "accepts a body of exactly 2000 characters and rejects 2001 (length cap)" do
      expect(build_note(body: "a" * 2000).valid?).to be(true)

      over = build_note(body: "a" * 2001)
      expect(over.valid?).to be(false)
      expect(over.errors).to include(:body)
    end

    it "is append-only: update, update_columns and destroy raise on a persisted note" do
      note = build_note
      note.save!

      expect { note.update!(body: "edited") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { note.update_columns(body: "edited") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { note.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(note.reload.body).to eq("Please check the VAT clause.")
    end

    it "leaves with its contract (dependent delete_all bypasses the append-only guard)" do
      build_note.save!

      expect { contract.destroy! }.to change(described_class, :count).by(-1)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
