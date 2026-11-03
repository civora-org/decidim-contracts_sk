# frozen_string_literal: true

# ---------------------------------------------------------------------------
# :db command specs for the P6 redaction integration of
# civora-org/civora-platform#211: confirming the redaction of a contract made
# from a template promotes its CURRENT generated publication PDF to the
# contract's publishable Document; a stale (superseded) copy never is;
# regenerating withdraws the promoted copy together with the confirmation;
# manual uploads and contracts without a generated copy behave as before.
# Synthetic data only, the Fake PDF converter stands in for LibreOffice.
#
# Each guard example was mutation-checked (the guard commented out, the
# example went red, the guard restored).
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::Admin::ConfirmRedaction, :db do
  include_context "with a contract template"

  let(:generated) { Decidim::ContractsSk::GeneratedDocument }
  let(:audit_class) { Decidim::ContractsSk::AuditEvent }
  let!(:contract) { generate }

  def generate(overrides = {}, record: nil)
    Decidim::ContractsSk::Admin::GenerateFromTemplate.call(
      build_form(overrides), template: template, user: author, organization: organization, contract: record
    )[:ok]
  end

  def confirm(contract, user: author)
    outcome = nil
    described_class.call(contract, user: user) do
      on(:ok) { outcome = :ok }
      on(:invalid) { outcome = :invalid }
    end
    outcome
  end

  def current_publication_pdf(contract)
    contract.generated_documents.current.find_by!(variant: "publication", file_format: "pdf")
  end

  describe "promoting the publication copy" do
    it "turns the current publication PDF into the contract's contract-kind Document and audits it" do
      copy = current_publication_pdf(contract)

      expect(confirm(contract)).to eq(:ok)

      contract.reload
      expect(contract.redaction_confirmed_at).to be_present
      document = contract.documents.sole
      expect(document).to have_attributes(kind: "contract", title: "Contract (publication version)",
                                          content_type: "application/pdf")
      expect(document.file.download).to eq(copy.file.download)
      expect(copy.reload.promoted_document).to eq(document)
      expect(audit_class.where(target: contract).pluck(:action))
        .to include("contract.publication_copy_promoted", "contract.redaction_confirmed")
    end

    it "promotes the internal copy never: only the publication PDF becomes a Document" do
      confirm(contract)

      internal = contract.generated_documents.where(variant: "internal")
      expect(internal.pluck(:promoted_document_id).compact).to be_empty
      expect(contract.documents.map { |d| d.file.download }).not_to include(
        contract.generated_documents.find_by!(variant: "internal", file_format: "pdf").file.download
      )
    end

    it "lets the person who generated and submitted confirm: redaction confirmation has no four-eyes rule" do
      contract.update_columns(decidim_submitted_by_id: author.id)

      expect(confirm(contract, user: author)).to eq(:ok)
      expect(contract.reload.documents.count).to eq(1)
    end

    it "promotes on an approved contract too (the confirmable window)" do
      contract.update_columns(state: "approved")

      expect(confirm(contract)).to eq(:ok)
      expect(contract.reload.documents.count).to eq(1)
    end

    it "refuses to promote a file that no longer matches its recorded checksum, and stamps nothing" do
      current_publication_pdf(contract).update_columns(checksum: "0" * 64)

      expect(confirm(contract)).to eq(:invalid)

      expect(contract.reload.redaction_confirmed_at).to be_nil
      expect(contract.documents).to be_empty
      expect(audit_class.where(action: %w[contract.redaction_confirmed contract.publication_copy_promoted])).to be_empty
    end
  end

  describe "a copy that already has its Document" do
    it "does not create a second one" do
      copy = current_publication_pdf(contract)
      existing = contract.documents.build(title: "Už je", kind: "contract")
      existing.attach_file!(copy.file.blob)
      copy.update!(promoted_document: existing)

      expect(confirm(contract)).to eq(:ok)

      expect(contract.reload.documents.sole).to eq(existing)
      expect(audit_class.where(action: "contract.publication_copy_promoted")).to be_empty
    end
  end

  describe "a stale copy" do
    it "is never promoted: after regenerating, only the new publication PDF is" do
      old_copy = current_publication_pdf(contract)
      generate({ "predmet" => "Predaj pozemku parc. č. 2/2" }, record: contract)
      new_copy = current_publication_pdf(contract.reload)

      expect(old_copy.reload.status).to eq("superseded")
      expect(confirm(contract)).to eq(:ok)

      expect(old_copy.reload.promoted_document).to be_nil
      expect(new_copy.reload.promoted_document).to eq(contract.documents.sole)
      expect(contract.documents.sole.file.download).to eq(new_copy.file.download)
    end

    it "is not promoted when no current copy exists (all superseded), as for a manual contract" do
      generated.where(contract: contract).update_all(status: "superseded")

      expect(confirm(contract)).to eq(:ok)

      expect(contract.reload.documents).to be_empty
      expect(generated.where(contract: contract).pluck(:promoted_document_id).compact).to be_empty
    end

    it "is withdrawn by regenerating after a confirmation: the promoted Document goes with the cleared stamp" do
      confirm(contract)
      promoted = contract.reload.documents.sole

      generate({ "predmet" => "Predaj pozemku parc. č. 3/3" }, record: contract)

      expect(contract.reload.redaction_confirmed_at).to be_nil
      expect(contract.documents).to be_empty
      expect(Decidim::ContractsSk::Document.exists?(promoted.id)).to be(false)
      expect(generated.where(contract: contract).pluck(:promoted_document_id).compact).to be_empty

      expect(confirm(contract)).to eq(:ok)
      expect(contract.reload.documents.sole.file.download).to eq(current_publication_pdf(contract).file.download)
    end

    it "cannot be confirmed twice: a second confirmation promotes nothing more" do
      expect(confirm(contract)).to eq(:ok)
      expect(confirm(contract)).to eq(:invalid)

      expect(contract.reload.documents.count).to eq(1)
    end
  end

  describe "manual uploads and manual contracts" do
    it "keeps a manually uploaded document next to the promoted one, through confirmation and regeneration" do
      manual = contract.documents.build(title: "Príloha", kind: "annex")
      manual.attach_file!(io: StringIO.new("manual"), filename: "priloha.txt", content_type: "text/plain")

      confirm(contract)
      expect(contract.reload.documents.pluck(:kind)).to match_array(%w[annex contract])

      generate({ "predmet" => "Predaj pozemku parc. č. 4/4" }, record: contract)
      expect(contract.reload.documents.sole).to eq(manual)
    end

    it "changes nothing for a contract without a generated copy" do
      plain = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "RUCNE-1"))

      expect(confirm(plain)).to eq(:ok)

      expect(plain.reload.redaction_confirmed_at).to be_present
      expect(plain.documents).to be_empty
      expect(audit_class.where(target: plain).pluck(:action)).to eq(["contract.redaction_confirmed"])
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
