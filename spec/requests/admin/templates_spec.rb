# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Request specs for the admin contract templates CRUD (civora-org/civora-
# platform#127), against the Stage-1 dummy harness. Two layers, mirroring
# notes_spec.rb: an offline group for the anonymous bounce and a :db group
# (CONTRACTS_SK_DB=1) for roles, tenancy, validation and rendering on
# in-memory SQLite. Synthetic data only.
# ---------------------------------------------------------------------------

require "spec_helper"
require "nokogiri"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
RSpec.describe "admin contract templates", type: :request do
  let(:unauthorized) { "You are not authorized to perform this action." }

  describe "anonymous access (offline)" do
    it "bounces anonymous requests on every verb with the auth flash, not the permission flash" do
      [[:get, "/admin/templates"], [:get, "/admin/templates/new"], [:post, "/admin/templates"],
       [:get, "/admin/templates/1/edit"], [:patch, "/admin/templates/1"],
       [:delete, "/admin/templates/1"]].each do |verb, path|
        public_send(verb, path)

        expect(response).to redirect_to("/"), "#{verb} #{path}"
        expect(flash[:dummy_authentication_required]).to be_present
      end
    end
  end

  describe "role holders and tenancy", :db do
    let(:resolver_roles) { %i[editor] }
    let(:template_class) { Decidim::ContractsSk::Template }
    let(:template_params) do
      { name: "Rental of premises", title_pattern: "Rental - ", subject_matter: "Rental of municipal premises.",
        currency: "EUR", object_party_name: "Mesto Demo", object_party_ico: "00000001",
        object_party_address: "Main 1" }
    end

    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    before do
      migrate_engine_schema!

      admin = Decidim::ContractsSk::Admin
      [admin::TemplatesController, admin::ContractsController].each do |controller|
        allow_any_instance_of(controller).to receive(:current_user).and_return(author)
        allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
        allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
      end
    end

    def create_template(overrides = {})
      template_class.create!({ organization: organization, name: "Works" }.merge(overrides))
    end

    describe "who may manage templates" do
      it "lets an editor list, create, edit and remove" do
        template = create_template

        get "/admin/templates"
        expect(response).to have_http_status(:ok)

        expect { post "/admin/templates", params: { template: template_params } }
          .to change(template_class, :count).by(1)
        expect(response).to redirect_to("/admin/templates")
        expect(flash[:notice]).to eq("Template created.")

        patch "/admin/templates/#{template.id}", params: { template: { name: "Works v2" } }
        expect(response).to redirect_to("/admin/templates")
        expect(template.reload.name).to eq("Works v2")

        expect { delete "/admin/templates/#{template.id}" }.to change(template_class, :count).by(-1)
        expect(response).to redirect_to("/admin/templates")
        expect(flash[:notice]).to eq("Template removed.")
      end
    end

    %i[reviewer none].each do |role|
      context "when the user is #{role == :none ? "roleless" : "a reviewer"}" do
        let(:resolver_roles) { role == :none ? [] : [role] }

        it "denies every verb with the permission flash and writes nothing" do
          template = create_template

          [[:get, "/admin/templates"], [:get, "/admin/templates/new"],
           [:get, "/admin/templates/#{template.id}/edit"]].each do |verb, path|
            public_send(verb, path)
            expect(response).to have_http_status(:found), "#{verb} #{path}"
            expect(flash[:alert]).to eq(unauthorized)
          end

          expect { post "/admin/templates", params: { template: template_params } }
            .not_to change(template_class, :count)
          expect(flash[:alert]).to eq(unauthorized)

          patch "/admin/templates/#{template.id}", params: { template: { name: "Tampered" } }
          expect(flash[:alert]).to eq(unauthorized)
          expect(template.reload.name).to eq("Works")

          expect { delete "/admin/templates/#{template.id}" }.not_to change(template_class, :count)
          expect(flash[:alert]).to eq(unauthorized)
        end
      end
    end

    describe "organization scoping" do
      let(:other_org) { Decidim::Organization.create! }

      it "lists only the signed-in organization's templates" do
        create_template(name: "Mine")
        template_class.create!(organization: other_org, name: "Theirs")

        get "/admin/templates"

        expect(response.body).to include("Mine")
        expect(response.body).not_to include("Theirs")
      end

      it "hides another organization's template from edit, update and destroy (404)" do
        foreign = template_class.create!(organization: other_org, name: "Theirs")

        expect { get "/admin/templates/#{foreign.id}/edit" }.to raise_error(ActiveRecord::RecordNotFound)
        expect { patch "/admin/templates/#{foreign.id}", params: { template: { name: "Hijacked" } } }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect { delete "/admin/templates/#{foreign.id}" }.to raise_error(ActiveRecord::RecordNotFound)
        expect(foreign.reload.name).to eq("Theirs")
      end

      it "creates in the current organization and ignores an organization smuggled through params" do
        post "/admin/templates",
             params: { template: template_params.merge(decidim_organization_id: other_org.id,
                                                       organization_id: other_org.id) }

        expect(template_class.sole.decidim_organization_id).to eq(organization.id)
      end

      it "allows the same name in two organizations" do
        template_class.create!(organization: other_org, name: "Rental of premises")

        expect { post "/admin/templates", params: { template: template_params } }
          .to change(template_class, :count).by(1)
      end
    end

    describe "validation" do
      it "re-renders the form with errors and keeps the typed values for an invalid create" do
        invalid = template_params.merge(name: "", object_party_ico: "12")

        expect { post "/admin/templates", params: { template: invalid } }.not_to change(template_class, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to eq("The template could not be created.")
        doc = Nokogiri::HTML(response.body)
        expect(doc.css(".flash.alert li").size).to be >= 2
        expect(doc.at_css("#template_object_party_address")["value"]).to eq("Main 1")
      end

      it "names the duplicate-name error on the form" do
        create_template(name: "Rental of premises")

        post "/admin/templates", params: { template: template_params }

        expect(response).to have_http_status(:unprocessable_entity)
        messages = Nokogiri::HTML(response.body).css(".flash.alert li").map(&:text).join
        expect(messages).to include("Name has already been taken")
      end

      it "rejects an unsupported currency and an over-long name" do
        post "/admin/templates", params: { template: template_params.merge(currency: "USD") }
        expect(response).to have_http_status(:unprocessable_entity)

        post "/admin/templates", params: { template: template_params.merge(name: "n" * 256) }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(template_class.count).to eq(0)
      end

      it "re-renders the edit form on an invalid update and leaves the template unchanged" do
        template = create_template

        patch "/admin/templates/#{template.id}", params: { template: { name: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to eq("The template could not be updated.")
        expect(template.reload.name).to eq("Works")
      end

      it "survives a malformed template param without a 500" do
        expect { post "/admin/templates", params: { template: "oops" } }.not_to change(template_class, :count)

        expect(response).to have_http_status(:unprocessable_entity).or have_http_status(:bad_request)
      end
    end

    describe "rendering" do
      it "renders the empty state with the new-template entry" do
        get "/admin/templates"

        doc = Nokogiri::HTML(response.body)
        expect(response.body).to include("No templates have been created yet.")
        expect(doc.css("a.button[href='/admin/templates/new']").size).to eq(1)
        expect(doc.css("table")).to be_empty
      end

      it "renders one row per template with the party, a use entry, and edit/remove controls" do
        template = create_template(name: "Rental", title_pattern: "Rental - ", object_party_name: "Mesto Demo",
                                   object_party_ico: "00000001")
        create_template(name: "Bare")

        get "/admin/templates"

        doc = Nokogiri::HTML(response.body)
        rows = doc.css("table.table-list tbody tr")
        expect(rows.size).to eq(2)
        expect(rows.map { |row| row.at_css("td").text.strip }).to eq(%w[Bare Rental])

        rental = rows.last
        expect(rental.text).to include("Mesto Demo")
        expect(rental.text).to include("00000001")
        use = rental.at_css("form[action='/admin/contracts/new'][method='get']")
        expect(use.at_css("input[name='template_id']")["value"]).to eq(template.id.to_s)
        expect(use.at_css("button, input[type=submit]")["class"]).to include("button__secondary")
        expect(rental.css("form[action='/admin/templates/#{template.id}/edit'][method='get']").size).to eq(1)
        remove = rental.at_css("form[action='/admin/templates/#{template.id}'] input[name='_method'][value='delete']")
        expect(remove).not_to be_nil
        expect(rows.first.text).to include("None")
      end

      it "renders the template form with labelled fields, the required name and the IČO hint" do
        get "/admin/templates/new"

        doc = Nokogiri::HTML(response.body)
        expect(response).to have_http_status(:ok)
        expect(doc.css("form.form.form-defaults").size).to eq(1)
        expect(doc.css("label[for='template_name']").size).to eq(1)
        expect(doc.at_css("#template_name")["required"]).to eq("required")
        expect(doc.at_css("#template_object_party_ico")["aria-describedby"]).to eq("template_object_party_ico_hint")
        expect(doc.css("select#template_currency option").map(&:text)).to eq(%w[EUR])
        expect(doc.css("textarea#template_subject_matter").size).to eq(1)
        expect(doc.css("input[type=submit].button.button__secondary").size).to eq(1)
        expect(doc.css("input[name*='organization']")).to be_empty
      end

      it "prefills the edit form from the template" do
        template = create_template(name: "Rental", object_party_name: "Mesto Demo", object_party_ico: "00000001")

        get "/admin/templates/#{template.id}/edit"

        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css("#template_name")["value"]).to eq("Rental")
        expect(doc.at_css("#template_object_party_ico")["value"]).to eq("00000001")
        expect(response.body).to include("only to contracts created from this template afterwards")
      end

      it "offers the templates entry on the contracts index to editors only" do
        get "/admin/contracts"
        expect(Nokogiri::HTML(response.body).css("a.button[href='/admin/templates']").size).to eq(1)
      end
    end
  end

  describe "the templates entry for a reviewer", :db do
    around do |example|
      original = Decidim::ContractsSk.role_resolver
      Decidim::ContractsSk.role_resolver = ->(_user, _context) { %i[reviewer] }
      example.run
      Decidim::ContractsSk.role_resolver = original
    end

    it "is not offered on the contracts index" do
      migrate_engine_schema!
      controller = Decidim::ContractsSk::Admin::ContractsController
      allow_any_instance_of(controller).to receive(:current_user).and_return(author)
      allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
      allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)

      get "/admin/contracts"

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css("a[href='/admin/templates']")).to be_empty
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance
