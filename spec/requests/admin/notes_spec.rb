# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin internal review notes (civora-org/civora-
# platform#128), against the Stage-1 dummy harness. Two layers, mirroring
# links_spec.rb: an offline group for the anonymous bounce and a :db group
# (CONTRACTS_SK_DB=1) for the allowed, validation, tenancy and rendering
# paths on in-memory SQLite. Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"
require "nokogiri"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin internal review notes", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  describe "anonymous access (offline)" do
    it "bounces an anonymous GET and POST with the auth flash, not the permission flash" do
      get "/admin/contracts/1/notes"
      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present

      post "/admin/contracts/1/notes", params: { note: { body: "x" } }
      expect(response).to redirect_to("/")
      expect(flash[:dummy_authentication_required]).to be_present
    end
  end

  describe "role holders and tenancy", :db do
    let(:resolver_roles) { %i[editor] }
    let(:note_class) { Decidim::ContractsSk::Note }
    let(:contract) { Decidim::ContractsSk::Contract.create!(contract_attributes) }

    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    before do
      migrate_engine_schema!

      admin = Decidim::ContractsSk::Admin
      [admin::NotesController, admin::ContractsController].each do |controller|
        allow_any_instance_of(controller).to receive(:current_user).and_return(author)
        allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
        allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
      end
    end

    def add_note(body, record = contract)
      post "/admin/contracts/#{record.id}/notes", params: { note: { body: body } }
    end

    it "appends a note for an editor, redirects to the thread and audits it" do
      expect { add_note("Asked the lawyer about clause 4.") }
        .to change(note_class, :count).by(1)
        .and change(Decidim::ContractsSk::AuditEvent, :count).by(1)

      expect(response).to redirect_to("/admin/contracts/#{contract.id}/notes")
      expect(flash[:notice]).to be_present
      note = contract.notes.sole
      expect(note.body).to eq("Asked the lawyer about clause 4.")
      expect(note.author).to eq(author)
      expect(Decidim::ContractsSk::AuditEvent.last.action).to eq("contract.note_added")
    end

    context "when the user is a reviewer only" do
      let(:resolver_roles) { %i[reviewer] }

      it "lets the reviewer read and add on an in-review record (which they cannot edit)" do
        record = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "in_review", reference: "ZP-7"))
        record.notes.create!(author: author, body: "Editor: please look at the amount.")

        get "/admin/contracts/#{record.id}/notes"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Editor: please look at the amount.")
        expect(response.body).not_to include("Back to the contract</a>")

        expect { add_note("Reviewer: amount confirmed.", record) }.to change(record.notes, :count).by(1)
      end
    end

    context "when the user holds no engine role" do
      let(:resolver_roles) { [] }

      it "denies both reading and adding, writing nothing" do
        get "/admin/contracts/#{contract.id}/notes"
        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq(unauthorized)

        expect { add_note("sneaky") }.not_to change(note_class, :count)
        expect(flash[:alert]).to eq(unauthorized)
      end
    end

    it "accepts notes on a published record (notes survive publication)" do
      published = Decidim::ContractsSk::Contract.create!(contract_attributes(state: "published", reference: "ZP-8"))

      expect { add_note("Post-publication remark.", published) }.to change(published.notes, :count).by(1)
    end

    it "rejects a blank body and keeps the thread unchanged" do
      expect { add_note("   ") }.not_to change(note_class, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to include("The note could not be added")
    end

    it "rejects a body over 2000 characters, keeps the typed text and accepts exactly 2000" do
      expect { add_note("b" * 2001) }.not_to change(note_class, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("b" * 2001)

      expect { add_note("c" * 2000) }.to change(note_class, :count).by(1)
    end

    it "ignores author and contract smuggled through params (only the body is admitted)" do
      other = Decidim::User.create!(organization: organization)
      other_contract = Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-9"))

      post "/admin/contracts/#{contract.id}/notes",
           params: { note: { body: "hello", decidim_author_id: other.id, contract_id: other_contract.id } }

      note = note_class.last
      expect(note.contract).to eq(contract)
      expect(note.author).to eq(author)
    end

    it "survives a malformed note param without a 500" do
      expect { post "/admin/contracts/#{contract.id}/notes", params: { note: "oops" } }
        .not_to change(note_class, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "hides another organization's contract from both verbs (scoped find raises)" do
      foreign = Decidim::ContractsSk::Contract.create!(
        contract_attributes(organization: Decidim::Organization.create!, reference: "ZP-F")
      )

      aggregate_failures do
        expect { get "/admin/contracts/#{foreign.id}/notes" }.to raise_error(ActiveRecord::RecordNotFound)
        expect { add_note("leak", foreign) }.to raise_error(ActiveRecord::RecordNotFound)
      end
      expect(note_class.count).to eq(0)
    end

    it "offers no edit or delete route for a note (append-only)" do
      note = contract.notes.create!(author: author, body: "fixed")

      expect { patch "/admin/contracts/#{contract.id}/notes/#{note.id}", params: { note: { body: "x" } } }
        .to raise_error(ActionController::RoutingError)
      expect { delete "/admin/contracts/#{contract.id}/notes/#{note.id}" }
        .to raise_error(ActionController::RoutingError)
      expect(note.reload.body).to eq("fixed")
    end

    describe "rendering" do
      it "renders the thread oldest first, escaped, with the author and no edit or remove control" do
        contract.notes.create!(author: author, body: "First <b>note</b>\nsecond line")
        contract.notes.create!(author: author, body: "Second note")

        get "/admin/contracts/#{contract.id}/notes"

        expect(response).to have_http_status(:ok)
        doc = Nokogiri::HTML(response.body)
        bodies = doc.css("#contract-notes .cs-admin-note-body").map(&:text)
        expect(bodies).to eq(["First <b>note</b>\nsecond line", "Second note"])
        expect(doc.css("#contract-notes .cs-admin-note-body b")).to be_empty
        expect(doc.css("#contract-notes form, #contract-notes button, #contract-notes input")).to be_empty
        expect(doc.css("textarea[name='note[body]'][maxlength='2000']").size).to eq(1)
        expect(response.body).to include("never published")
      end

      it "renders the empty state and the add form on an editor's edit page, with the panel" do
        get "/admin/contracts/#{contract.id}/edit"

        expect(response).to have_http_status(:ok)
        doc = Nokogiri::HTML(response.body)
        expect(doc.css("h2.card-title").map { |node| node.text.strip }).to include("Internal notes")
        expect(response.body).to include("No internal notes have been added to this contract yet.")
        expect(doc.css("form[action='/admin/contracts/#{contract.id}/notes'] textarea").size).to eq(1)
        expect(doc.css("form[action='/admin/contracts/#{contract.id}/notes'] input[type=submit].button").size).to eq(1)
      end

      it "lists existing notes on the edit page panel" do
        contract.notes.create!(author: author, body: "Lawyer says OK.")

        get "/admin/contracts/#{contract.id}/edit"

        expect(Nokogiri::HTML(response.body).css("#contract-notes .cs-admin-note-body").map(&:text))
          .to eq(["Lawyer says OK."])
      end

      it "links the notes page from every index row through a GET button" do
        contract

        get "/admin/contracts"

        doc = Nokogiri::HTML(response.body)
        form = doc.at_css("form[action='/admin/contracts/#{contract.id}/notes'][method=get]")
        expect(form).to be_present
        expect(form.at_css(".button.button__sm.button__secondary").to_s).to include("Notes")
      end

      it "labels the audit event in the audit trail" do
        add_note("Audited")
        audit_controller = Decidim::ContractsSk::Admin::AuditEventsController
        allow_any_instance_of(audit_controller).to receive(:current_user).and_return(author)
        allow_any_instance_of(audit_controller).to receive(:user_signed_in?).and_return(true)
        allow_any_instance_of(audit_controller).to receive(:current_organization).and_return(organization)

        get "/admin/audit_events"

        expect(response.body).to include("Internal note added")
        expect(response.body).not_to include("Audited")
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
