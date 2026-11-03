# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for "new contract from a template with Word/PDF"
# (civora-org/civora-platform#211): the chooser, the dynamic form, the
# generation, regenerating, the downloads, and the guarantee that no public page
# ever links a generated file. :db only (CONTRACTS_SK_DB=1), in-memory SQLite,
# the Fake PDF converter. Synthetic data only.
#
# Each guard example was mutation-checked (the guard commented out, the
# example went red, the guard restored).
# ---------------------------------------------------------------------------

require "spec_helper"
require "nokogiri"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
RSpec.describe "admin contract from a contract template", :db, type: :request do
  include_context "with a contract template"

  let(:resolver_roles) { %i[editor] }
  let(:signed_in_user) { author }
  let(:other_org) { Decidim::Organization.create! }
  let(:unauthorized) { "You are not authorized to perform this action." }
  let(:entry_class) { Decidim::ContractsSk::ContractTemplateEntry }
  let(:contract_class) { Decidim::ContractsSk::Contract }
  let(:document_class) { Decidim::ContractsSk::GeneratedDocument }

  around do |example|
    original = Decidim::ContractsSk.role_resolver
    Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
    example.run
    Decidim::ContractsSk.role_resolver = original
  end

  before do
    template
    controller = Decidim::ContractsSk::Admin::ApplicationController
    allow_any_instance_of(controller).to receive(:current_user).and_return(signed_in_user)
    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(!signed_in_user.nil?)
    allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
  end

  def params_for(overrides = {}, title: "Kúpna zmluva - parcela 1/1")
    { entry: { title: title, values: TemplateGenerationHelpers.valid_params(overrides) } }
  end

  def create_via_form(overrides = {})
    post "/admin/contract_templates/#{template.id}/entry", params: params_for(overrides)
  end

  def html
    Nokogiri::HTML(response.body)
  end

  def counts
    [contract_class.count, entry_class.count, document_class.count,
     Decidim::ContractsSk::AuditEvent.count, Decidim::ContractsSk::ReferenceCounter.count]
  end

  describe "the chooser" do
    it "lists the active templates of the organization, the newest version of each lineage" do
      newer = build_template(organization: organization, lineage_key: template.lineage_key, version: 2)
      newer.update!(name: "Kúpna zmluva v2")
      build_template(organization: organization, lineage_key: "koncept", status: "draft").update!(name: "Koncept")
      build_template(organization: organization, lineage_key: "stara", status: "archived").update!(name: "Stará")
      build_template(organization: other_org, lineage_key: "cudzia").update!(name: "Cudzia šablóna")

      get "/admin/contract_templates"

      expect(response).to have_http_status(:ok)
      names = html.css("th.cs-admin-template-name").map { |node| node.text.strip }
      expect(names).to eq(["Kúpna zmluva v2"])
      expect(response.body).not_to include("Koncept", "Stará", "Cudzia")
      expect(html.css("td.table-list__actions a").pluck("href"))
        .to eq(["/admin/contract_templates/#{newer.id}/entry/new"])
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "shows an empty state with the way out when there is no active template" do
      template.update!(status: "archived")

      get "/admin/contract_templates"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("There is no active template yet.")
      expect(html.css("table")).to be_empty
    end

    it "is offered on the contracts list only when an active template exists" do
      get "/admin/contracts"
      expect(html.css("a").map { |a| a["href"] }).to include("/admin/contract_templates")

      template.update!(status: "archived")
      get "/admin/contracts"
      expect(html.css("a").map { |a| a["href"] }).not_to include("/admin/contract_templates")
    end

    it "is refused for a reviewer, who cannot create contracts" do
      allow(Decidim::ContractsSk).to receive(:role_resolver).and_return(->(_user, _context) { [:reviewer] })

      get "/admin/contract_templates"

      expect(response).to have_http_status(:found)
      expect(flash[:alert]).to eq(unauthorized)
    end
  end

  describe "the form" do
    it "is built from the template fields, grouped, with the header read-only" do
      get "/admin/contract_templates/#{template.id}/entry/new"

      expect(response).to have_http_status(:ok)
      keys = html.css("input[name^='entry[values]'], textarea[name^='entry[values]']").pluck("name")
      expect(keys).to eq(%w[predmet kupujuci_meno kupujuci_adresa suma_celkom plocha datum_ucinnosti datum_podpisu]
                           .map { |key| "entry[values][#{key}]" })
      expect(html.css("legend").map do |l|
        l.text.strip
      end).to eq(["Subject of the contract", "Buyer", "Price and payment", "Dates"])
      expect(html.at_css("#entry_title")["value"]).to eq("Kúpna zmluva")
      header = html.at_css("dl.cs-admin-header-facts").text
      expect(header).to include("Obec Vzorová", "00000000")
      expect(html.css("dl.cs-admin-header-facts input")).to be_empty
      expect(html.css("input[name*='cislo_zmluvy'], input[name*='org_'], input[name*='suma_slovom']")).to be_empty
    end

    it "marks personal fields, hints formats and prepares the amount-in-words preview" do
      get "/admin/contract_templates/#{template.id}/entry/new"

      expect(html.at_css("#entry_values_kupujuci_meno_hint").text).to include("hidden in the version for publication")
      expect(html.at_css("#entry_values_datum_podpisu")["placeholder"]).to eq("1. 1. 2026")
      money = html.at_css("#entry_values_suma_celkom")
      expect(money["data-cs-words-url"]).to eq("/admin/contract_templates/amount_in_words")
      expect(money["data-cs-words-target"]).to eq("entry_values_suma_celkom_words")
      expect(html.at_css("#entry_values_suma_celkom_words")["aria-live"]).to eq("polite")
      expect(html.at_css("input[type=submit]")["class"]).to include("button__secondary")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "warns when the municipality header is incomplete" do
      profile.update!(header: { "official_name" => "Obec Vzorová" })

      get "/admin/contract_templates/#{template.id}/entry/new"

      expect(response.body).to include("not filled in", "header is incomplete")
    end

    it "404s for a draft, archived, foreign or unknown template" do
      draft = build_template(organization: organization, lineage_key: "d", status: "draft")
      archived = build_template(organization: organization, lineage_key: "a", status: "archived")
      foreign = build_template(organization: other_org, lineage_key: "f")

      [draft.id, archived.id, foreign.id, 0].each do |id|
        expect { get "/admin/contract_templates/#{id}/entry/new" }
          .to raise_error(ActiveRecord::RecordNotFound), "template #{id}"
        expect { post "/admin/contract_templates/#{id}/entry", params: params_for }
          .to raise_error(ActiveRecord::RecordNotFound), "template #{id}"
      end
    end

    it "is refused for a reviewer" do
      allow(Decidim::ContractsSk).to receive(:role_resolver).and_return(->(_user, _context) { [:reviewer] })

      get "/admin/contract_templates/#{template.id}/entry/new"
      expect(flash[:alert]).to eq(unauthorized)

      expect { create_via_form }.not_to(change { counts })
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "needs a signed-in user" do
      base = Decidim::ContractsSk::Admin::ApplicationController
      allow_any_instance_of(base).to receive(:current_user).and_return(nil)
      allow_any_instance_of(base).to receive(:user_signed_in?).and_return(false)

      expect { create_via_form }.not_to(change { counts })
      expect(response).to have_http_status(:found)
      expect(flash[:alert]).not_to eq(unauthorized)
    end
  end

  describe "generating" do
    it "creates the draft with its documents and lands on the contract page" do
      create_via_form

      contract = contract_class.sole
      expect(response).to redirect_to("/admin/contracts/#{contract.id}")
      expect(flash[:notice]).to eq("The contract is ready. The documents are below.")
      expect(contract.state).to eq("draft")
      expect(contract.template_entry.generated_documents.count).to eq(4)

      follow_redirect!
      links = html.css("#cs-template-documents a[href*='generated_documents']").map { |a| [a.text.strip, a["href"]] }
      expect(links.map(&:first)).to eq(["Internal contract (Word)", "Internal contract (PDF)",
                                        "Version for publication (PDF)"])
      expect(links.map(&:last)).to all(match(%r{\A/admin/contracts/#{contract.id}/generated_documents/\d+\z}))
      expect(html.at_css("#cs-template-documents").text).to include("Internal number: 1/")
    end

    it "keeps the typed values and names the broken field when the form is invalid" do
      expect { create_via_form("suma_celkom" => "3.062", "predmet" => "") }.not_to(change { counts })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(html.at_css("#entry_values_suma_celkom")["value"]).to eq("3.062")
      expect(html.at_css("#entry_values_kupujuci_meno")["value"]).to eq("Ján Testovací")
      expect(html.at_css("#entry_values_suma_celkom_error").text).to include("could not be read")
      expect(html.at_css("#entry_values_predmet_error").text).to include("required")
      expect(html.at_css("#entry_values_suma_celkom")["aria-invalid"]).to eq("true")
      expect(html.css(".flash.alert li").size).to eq(2)
    end

    it "never takes the template, the organization or unknown fields from the request" do
      other = build_template(organization: other_org, lineage_key: "cudzia")
      payload = params_for({ "neznamy_kluc" => "x", "org_nazov" => "Podvrh s.r.o.", "cislo_zmluvy" => "99/1999" })
      payload[:entry].merge!(contract_template_id: other.id, organization_id: other_org.id)
      payload.merge!(contract_template_id: other.id, organization_id: other_org.id)

      post "/admin/contract_templates/#{template.id}/entry", params: payload

      contract = contract_class.sole
      expect(contract.organization).to eq(organization)
      expect(contract.template_entry.contract_template).to eq(template)
      expect(contract.template_entry.values.keys).not_to include("neznamy_kluc", "org_nazov", "cislo_zmluvy")
      expect(contract.template_entry.internal_number).to match(%r{\A1/\d{4}\z})
      internal = contract.template_entry.generated_documents.find_by!(variant: "internal", file_format: "docx")
      docx = DocxFixtures.read_zip(internal.file.download)
      xml = docx.fetch("word/document.xml").force_encoding("UTF-8")
      expect(xml).not_to include("Podvrh")
      expect(xml).to include("Obec Vzorová")
    end

    it "stores nothing and says so when the publication copy would leak" do
      Decidim::ContractsSk.pdf_converter = lambda do |_docx|
        Decidim::ContractsSk::Templates::MinimalPdf.build(lines: ["Kupujuci: Jan Testovaci"], info: {})
      end

      expect { create_via_form }.not_to(change { counts })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to include("would have revealed personal data", "nothing was saved")
      expect(html.at_css("#entry_values_kupujuci_meno")["value"]).to eq("Ján Testovací")
    end

    it "stores nothing when the PDF conversion fails" do
      Decidim::ContractsSk.pdf_converter = ->(_docx) { raise Decidim::ContractsSk::Templates::PdfConverter::ConverterUnavailable }

      expect { create_via_form }.not_to(change { counts })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to include("could not be converted to PDF")
    end

    it "names the missing header details" do
      profile.update!(header: { "official_name" => "Obec Vzorová" })

      expect { create_via_form }.not_to(change { counts })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to include("Company ID (IČO)", "Nothing was saved")
    end

    it "does not log the typed values" do
      logged = StringIO.new
      logger = ActiveSupport::Logger.new(logged)
      original = Rails.logger
      Rails.logger = logger
      begin
        create_via_form
      ensure
        Rails.logger = original
      end

      expect(logged.string).not_to include("Testovací", "Nepravá")
    end
  end

  describe "regenerating" do
    let!(:contract) do
      post "/admin/contract_templates/#{template.id}/entry", params: params_for
      contract_class.sole
    end

    it "shows the saved values, personal ones included, and is never cached" do
      get "/admin/contracts/#{contract.id}/template_entry/edit"

      expect(response).to have_http_status(:ok)
      expect(html.at_css("#entry_values_kupujuci_meno")["value"]).to eq("Ján Testovací")
      expect(html.at_css("#entry_values_suma_celkom")["value"]).to eq("3 062,50")
      expect(html.at_css("#entry_values_datum_ucinnosti")["value"]).to eq("1. 1. 2027")
      expect(html.at_css("#entry_title")["value"]).to eq("Kúpna zmluva - parcela 1/1")
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "generates again: same number, previous files superseded, confirmation cleared" do
      contract.update!(redaction_confirmed_at: Time.current)

      patch "/admin/contracts/#{contract.id}/template_entry",
            params: params_for({ "kupujuci_meno" => "Jana Skúšobná" }, title: "Nový názov")

      expect(response).to redirect_to("/admin/contracts/#{contract.id}")
      entry = contract.template_entry.reload
      expect(entry.internal_number).to match(%r{\A1/\d{4}\z})
      expect(entry.personal_values["kupujuci_meno"]).to eq("Jana Skúšobná")
      expect(entry.generated_documents.group(:status).count).to eq("current" => 4, "superseded" => 4)
      expect(contract.reload.title).to eq("Nový názov")
      expect(contract.redaction_confirmed_at).to be_nil
    end

    it "refuses a contract that left the editable states" do
      contract.update_columns(state: "approved")

      get "/admin/contracts/#{contract.id}/template_entry/edit"
      expect(flash[:alert]).to eq(unauthorized)

      expect { patch "/admin/contracts/#{contract.id}/template_entry", params: params_for }.not_to(change { counts })
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "does not offer the regenerate button to a reviewer, who can still download" do
      allow(Decidim::ContractsSk).to receive(:role_resolver).and_return(->(_user, _context) { [:reviewer] })

      get "/admin/contracts/#{contract.id}"

      hrefs = html.css("#cs-template-documents a").pluck("href")
      expect(hrefs.size).to eq(3)
      expect(hrefs).not_to include("/admin/contracts/#{contract.id}/template_entry/edit")
    end

    it "404s for a contract without an entry and for another organization's contract" do
      plain = contract_class.create!(contract_attributes(reference: "RUCNE-1"))
      foreign = contract_class.create!(contract_attributes(reference: "X-1", organization: other_org,
                                                           author: Decidim::User.create!(organization: other_org)))

      [plain.id, foreign.id].each do |id|
        expect { get "/admin/contracts/#{id}/template_entry/edit" }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "shows no documents section on a contract that was not made from a template" do
      plain = contract_class.create!(contract_attributes(reference: "RUCNE-2"))

      get "/admin/contracts/#{plain.id}"

      expect(response).to have_http_status(:ok)
      expect(html.css("#cs-template-documents")).to be_empty
    end
  end

  describe "downloads" do
    let!(:contract) do
      post "/admin/contract_templates/#{template.id}/entry", params: params_for
      contract_class.sole
    end
    let(:documents) { contract.template_entry.generated_documents }

    def doc(variant, format, status: "current")
      documents.find_by!(variant: variant, file_format: format, status: status)
    end

    it "serves the internal Word and PDF and the publication PDF as no-store attachments" do
      { [doc("internal", "docx"), "wordprocessingml"] => "interna.docx",
        [doc("internal", "pdf"), "application/pdf"] => "interna.pdf",
        [doc("publication", "pdf"), "application/pdf"] => "zverejnenie.pdf" }.each do |(record, type), suffix|
        get "/admin/contracts/#{contract.id}/generated_documents/#{record.id}"

        expect(response).to have_http_status(:ok)
        expect(response.media_type + response.content_type).to include(type)
        expect(response.headers["Content-Disposition"]).to start_with("attachment").and(include(suffix))
        expect(response.headers["Cache-Control"]).to include("no-store")
        expect(response.body.b).to eq(record.file.download.b)
      end
    end

    it "does not serve the publication Word intermediate, superseded files or other contracts' files" do
      intermediate = doc("publication", "docx")
      expect { get "/admin/contracts/#{contract.id}/generated_documents/#{intermediate.id}" }
        .to raise_error(ActiveRecord::RecordNotFound)

      old = doc("internal", "pdf")
      patch "/admin/contracts/#{contract.id}/template_entry", params: params_for({ "predmet" => "Zmena" })
      other = contract_class.create!(contract_attributes(reference: "RUCNE-3"))

      [[contract.id, old.id], [other.id, doc("internal", "pdf").id]].each do |cid, id|
        expect { get "/admin/contracts/#{cid}/generated_documents/#{id}" }
          .to raise_error(ActiveRecord::RecordNotFound), "contract #{cid} document #{id}"
      end
    end

    it "serves any engine role holder, and nobody else" do
      allow(Decidim::ContractsSk).to receive(:role_resolver).and_return(->(_user, _context) { [:reviewer] })
      get "/admin/contracts/#{contract.id}/generated_documents/#{doc("internal", "pdf").id}"
      expect(response).to have_http_status(:ok)

      allow(Decidim::ContractsSk).to receive(:role_resolver).and_return(->(_user, _context) { [] })
      get "/admin/contracts/#{contract.id}/generated_documents/#{doc("internal", "pdf").id}"
      expect(response).to have_http_status(:found)
      expect(flash[:alert]).to eq(unauthorized)
    end

    it "does not serve a contract of another organization" do
      foreign_user = Decidim::User.create!(organization: other_org)
      Decidim::ContractsSk::ContractOrganizationProfile.create!(organization: other_org,
                                                                header: organization_profile_header)
      foreign_template = build_template(organization: other_org, lineage_key: "cudzia")
      foreign_form = build_form({}, for_template: foreign_template)
      foreign = Decidim::ContractsSk::Admin::GenerateFromTemplate.call(
        foreign_form, template: foreign_template, user: foreign_user, organization: other_org
      )[:ok]
      foreign_doc = foreign.template_entry.generated_documents.find_by!(variant: "internal", file_format: "pdf")

      expect { get "/admin/contracts/#{foreign.id}/generated_documents/#{foreign_doc.id}" }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "the amount in words" do
    it "spells a Slovak amount and answers empty text for anything unreadable" do
      get "/admin/contract_templates/amount_in_words", params: { amount: "3 062,50" }
      expect(response.parsed_body).to eq("words" => "tritisícšesťdesiatdva eur a päťdesiat centov")

      ["", "abc", "3.062", "-5", "99999999999999"].each do |value|
        get "/admin/contract_templates/amount_in_words", params: { amount: value }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq("words" => ""), value
      end
    end

    it "is refused for a reviewer" do
      allow(Decidim::ContractsSk).to receive(:role_resolver).and_return(->(_user, _context) { [:reviewer] })

      get "/admin/contract_templates/amount_in_words", params: { amount: "1" }

      expect(flash[:alert]).to eq(unauthorized)
    end
  end

  describe "the public pages" do
    let!(:contract) do
      post "/admin/contract_templates/#{template.id}/entry", params: params_for
      contract_class.sole.tap { |c| c.update_columns(state: "published", published_at: Time.current) }
    end

    it "never link a generated file, on the register, the record or the feeds" do
      [Decidim::ContractsSk::ContractsController, Decidim::ContractsSk::OpenDataController,
       Decidim::ContractsSk::FeedsController, Decidim::ContractsSk::SitemapsController].each do |klass|
        allow_any_instance_of(klass).to receive(:current_organization).and_return(organization)
      end
      document_ids = contract.template_entry.generated_documents.pluck(:id)
      expect(document_ids.size).to eq(4)

      ["/", "/#{contract.id}", "/export.json", "/export.csv", "/feed.atom", "/sitemap.xml"].each do |path|
        get path
        expect(response).to have_http_status(:ok), path

        body = response.body
        expect(body).not_to include("generated_document", "zmluva-1-", "interna.", "zverejnenie."), path
        expect(body).not_to include("Testovací", "Nepravá"), path
        document_ids.each { |id| expect(body).not_to match(%r{/generated_documents/#{id}\b}), path }
      end
    end

    it "have no route that serves a generated document" do
      id = contract.template_entry.generated_documents.first.id

      ["/#{contract.id}/generated_documents/#{id}", "/generated_documents/#{id}",
       "/contracts/#{contract.id}/generated_documents/#{id}"].each do |path|
        expect { get path }.to raise_error(ActionController::RoutingError), path
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
