# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Spec for `decidim_contracts_sk:templates:import[org_id,path,lineage_key,name]`
# (civora-org/civora-platform#211): the real task file runs in an isolated Rake
# application over the :db harness (`:environment` stubbed, like the other task
# specs). Synthetic files only.
# ---------------------------------------------------------------------------

require "spec_helper"
require "rake"
require "tmpdir"

# rubocop:disable RSpec/DescribeClass, RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/NoExpectationExample
RSpec.describe "decidim_contracts_sk:templates:import", :db do
  let(:template_class) { Decidim::ContractsSk::ContractTemplate }
  let(:dir) { Dir.mktmpdir("cs-import") }
  let(:path) { File.join(dir, "kupna.docx") }

  before do
    migrate_engine_schema!
    File.binwrite(path, TemplateGenerationHelpers.template_docx)
    Rake.application = Rake::Application.new
    load File.join(engine_root, "lib", "tasks", "decidim_contracts_sk_templates.rake")
    Rake::Task.define_task(:environment)
  end

  after do
    FileUtils.rm_rf(dir)
    FileUtils.rm_rf(active_storage_root)
  end

  def run_task(*args)
    task = Rake::Task["decidim_contracts_sk:templates:import"]
    task.reenable
    task.invoke(*args)
  end

  # Runs the task and returns what it printed.
  def import(org_id: organization.id.to_s, file: path, lineage: "kupna-zmluva", name: "Kúpna zmluva")
    printed = $stdout
    $stdout = StringIO.new
    run_task(org_id, file, lineage, name)
    $stdout.string
  ensure
    $stdout = printed
  end

  def fields_by_key(template)
    template.fields.index_by(&:key)
  end

  it "creates an active template whose fields and types come from the merge field names" do
    expect(import).to match(/is active with 11 fields/)

    template = template_class.sole
    expect(template.organization).to eq(organization)
    expect([template.lineage_key, template.version, template.status, template.name])
      .to eq(["kupna-zmluva", 1, "active", "Kúpna zmluva"])
    expect(template.source_filename).to eq("kupna.docx")
    expect(template.source_checksum).to match(/\A\h{64}\z/)
    expect(template.file).to be_attached

    fields = fields_by_key(template)
    expect(fields.transform_values(&:field_type)).to include(
      "org_nazov" => "org_header", "org_ico" => "org_header", "suma_celkom" => "money",
      "datum_ucinnosti" => "date", "datum_podpisu" => "date", "predmet" => "text",
      "cislo_zmluvy" => "text", "suma_slovom" => "text"
    )
    expect(fields.values.map(&:personal_data)).to all(be(false))
    expect(fields.values.map(&:position)).to eq((0..10).to_a)
  end

  it "stores the sanitized file, not the upload as it came" do
    core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' \
           '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ' \
           'xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>Fiktívny Autor</dc:creator></cp:coreProperties>'
    File.binwrite(path, DocxFixtures.docx(DocxFixtures.para(DocxFixtures.merge("=predmet")), core: core))
    uploaded = DocxFixtures.read_zip(File.binread(path)).fetch("docProps/core.xml").force_encoding("UTF-8")
    expect(uploaded).to include("Fiktívny Autor")

    import

    stored = DocxFixtures.read_zip(template_class.sole.file.download)
    expect(stored.fetch("docProps/core.xml").force_encoding("UTF-8")).not_to include("Fiktívny Autor")
    expect(stored.fetch("word/document.xml")).to include("MERGEFIELD =predmet")
  end

  it "marks person fields from the sidecar and applies labels, groups, types and required" do
    File.write("#{path}.fields.yml", <<~YAML)
      person: [kupujuci_meno, kupujuci_adresa]
      required: [predmet, kupujuci_meno]
      types: { plocha: number, predmet: long_text }
      labels: { kupujuci_meno: "Kupujúci - meno" }
      groups: { kupujuci_meno: kupujuci, kupujuci_adresa: kupujuci }
    YAML

    expect(import).to match(/kupujuci_meno: person \(personal\) \(required\)/)

    fields = fields_by_key(template_class.sole)
    expect(fields["kupujuci_meno"]).to have_attributes(field_type: "person", personal_data: true, required: true,
                                                       label: "Kupujúci - meno", group_key: "kupujuci")
    expect(fields["kupujuci_adresa"]).to have_attributes(field_type: "person", personal_data: true, required: false)
    expect(fields["plocha"].field_type).to eq("number")
    expect(fields["predmet"]).to have_attributes(field_type: "long_text", required: true)
    expect(fields["org_ico"].required).to be(false)
  end

  it "stores the sidecar's group headings on the fields of each group, with diacritics" do
    File.write("#{path}.fields.yml", <<~YAML)
      groups: { kupujuci_meno: kupujuci, kupujuci_adresa: kupujuci, suma_celkom: cena }
      group_labels: { kupujuci: "Kupujúci", cena: "Cena a platba" }
    YAML

    import

    fields = fields_by_key(template_class.sole)
    expect(fields.values_at("kupujuci_meno", "kupujuci_adresa").map(&:group_label)).to eq(%w[Kupujúci Kupujúci])
    expect(fields["suma_celkom"].group_label).to eq("Cena a platba")
    expect(fields["predmet"]).to have_attributes(group_key: nil, group_label: nil)
  end

  it "stores the counterparty parts the sidecar declares and none otherwise" do
    File.write("#{path}.fields.yml", "person: [kupujuci_meno]\ncounterparty: { name: kupujuci_meno }\n")

    import

    fields = fields_by_key(template_class.sole)
    expect(fields["kupujuci_meno"].party_part).to eq("name")
    expect(fields.except("kupujuci_meno").values.map(&:party_part)).to all(be_nil)
    expect(template_class.sole.counterparty_fields.keys).to eq(["name"])
  end

  it "creates no counterparty part without a counterparty setting" do
    import

    expect(fields_by_key(template_class.sole).values.map(&:party_part)).to all(be_nil)
  end

  it "leaves group_label empty when the sidecar gives no group headings" do
    File.write("#{path}.fields.yml", "groups: { kupujuci_meno: kupujuci }\n")

    import

    expect(fields_by_key(template_class.sole)["kupujuci_meno"].group_label).to be_nil
  end

  it "can mark every field required" do
    File.write("#{path}.fields.yml", "required: all\n")

    import

    fields = fields_by_key(template_class.sole)
    expect(fields["predmet"].required).to be(true)
    expect(fields["org_ico"].required).to be(false)
    expect(fields.values_at("cislo_zmluvy", "suma_slovom").map(&:required)).to eq([false, false])
  end

  it "creates the next version on a re-import and archives the older active one" do
    import
    first = template_class.sole

    expect(import).to match(/kupna-zmluva v2/)

    expect(first.reload.status).to eq("archived")
    expect(template_class.order(:version).pluck(:version, :status)).to eq([[1, "archived"], [2, "active"]])
  end

  it "does not touch another organization's lineage of the same key" do
    other = Decidim::Organization.create!
    import
    import(org_id: other.id.to_s)

    expect(template_class.where(organization: other).sole.version).to eq(1)
    expect(template_class.where(organization: organization).sole.status).to eq("active")
  end

  it "produces a template the generator can use end to end" do
    Decidim::ContractsSk.pdf_converter = Decidim::ContractsSk::Templates::PdfConverter::Fake.new
    Decidim::ContractsSk::ContractOrganizationProfile.create!(
      organization: organization, header: { "official_name" => "Obec Vzorová", "ico" => "00000000" }
    )
    File.write("#{path}.fields.yml", "person: [kupujuci_meno, kupujuci_adresa]\nrequired: [predmet, suma_celkom]\n")
    import
    template = template_class.sole
    form = Decidim::ContractsSk::Admin::TemplateEntryForm.new(
      template: template, title: "Uvedená zmluva", values: TemplateGenerationHelpers.valid_params
    )

    events = Decidim::ContractsSk::Admin::GenerateFromTemplate.call(form, template: template, user: author,
                                                                          organization: organization)

    expect(events).to have_key(:ok)
    expect(events[:ok].template_entry.generated_documents.count).to eq(4)
  ensure
    Decidim::ContractsSk.pdf_converter = nil
  end

  describe "settings of the template row on a re-import" do
    it "carries the reference pattern over to the new version and says so" do
      import
      template_class.sole.update!(reference_pattern: "{N}/{YYYY} Odd.NsMaSB")

      printed = import

      expect(template_class.find_by(version: 2).reference_pattern).to eq("{N}/{YYYY} Odd.NsMaSB")
      expect(printed).to include("carried over from v1: reference_pattern={N}/{YYYY} Odd.NsMaSB")
    end

    it "inherits from the latest version, even when it is not the active one" do
      import
      template_class.sole.update!(reference_pattern: "A-{N}")
      import
      template_class.find_by(version: 2).update!(reference_pattern: "B-{N}", status: "archived")
      template_class.find_by(version: 1).update!(status: "active")

      import

      expect(template_class.find_by(version: 3).reference_pattern).to eq("B-{N}")
    end

    it "lets the sidecar's reference_pattern win over the previous version's" do
      import
      template_class.sole.update!(reference_pattern: "OLD-{N}")
      File.write("#{path}.fields.yml", "reference_pattern: \"NEW-{N}/{YYYY}\"\n")

      printed = import

      expect(template_class.find_by(version: 2).reference_pattern).to eq("NEW-{N}/{YYYY}")
      expect(printed).to include("carried over from v1: nothing to carry")
    end

    it "lets an empty sidecar value clear the pattern back to the default" do
      import
      template_class.sole.update!(reference_pattern: "OLD-{N}")
      File.write("#{path}.fields.yml", "reference_pattern: \"\"\n")

      import

      expect(template_class.find_by(version: 2).reference_pattern).to be_nil
    end

    it "sets the pattern on a first import from the sidecar and prints no carry-over line" do
      File.write("#{path}.fields.yml", "reference_pattern: \"ZM-{YYYY}-{N}\"\n")

      printed = import

      expect(template_class.sole.reference_pattern).to eq("ZM-{YYYY}-{N}")
      expect(printed).not_to include("carried over")
    end

    it "leaves the pattern empty when no version ever had one" do
      import
      printed = import

      expect(template_class.find_by(version: 2).reference_pattern).to be_nil
      expect(printed).to include("carried over from v1: nothing to carry")
    end

    it "does not inherit from another organization's lineage of the same key" do
      other = Decidim::Organization.create!
      import(org_id: other.id.to_s)
      template_class.where(organization: other).sole.update!(reference_pattern: "OTHER-{N}")

      import

      expect(template_class.where(organization: organization).sole.reference_pattern).to be_nil
    end

    it "continues the contract numbering across versions" do
      Decidim::ContractsSk.pdf_converter = Decidim::ContractsSk::Templates::PdfConverter::Fake.new
      Decidim::ContractsSk::ContractOrganizationProfile.create!(
        organization: organization, header: { "official_name" => "Obec Vzorová", "ico" => "00000000" }
      )
      File.write("#{path}.fields.yml",
                 "person: [kupujuci_meno, kupujuci_adresa]\nreference_pattern: \"{N}/{YYYY} X\"\n")
      generate = lambda do
        template = template_class.find_by!(status: "active")
        form = Decidim::ContractsSk::Admin::TemplateEntryForm.new(
          template: template, title: "Zmluva", values: TemplateGenerationHelpers.valid_params
        )
        Decidim::ContractsSk::Admin::GenerateFromTemplate.call(form, template: template, user: author,
                                                                     organization: organization)[:ok].reference
      end
      year = Time.zone.today.year

      import
      first = generate.call
      File.write("#{path}.fields.yml", "person: [kupujuci_meno, kupujuci_adresa]\n")
      import
      second = generate.call

      expect(template_class.find_by(status: "active").version).to eq(2)
      expect([first, second]).to eq(["1/#{year} X", "2/#{year} X"])
    ensure
      Decidim::ContractsSk.pdf_converter = nil
    end
  end

  describe "refusals" do
    def aborts_with(message, &block)
      expect(&block).to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        .and output(message).to_stderr
      expect(template_class.count).to eq(0)
    end

    it "needs all four arguments" do
      aborts_with(/missing arguments: name/) { run_task(organization.id.to_s, path, "kupna-zmluva") }
    end

    it "needs an existing organization and file" do
      aborts_with(/organization 0 not found/) { import(org_id: "0") }
      aborts_with(/file not found/) { import(file: File.join(dir, "nope.docx")) }
    end

    it "refuses a file that is not a .docx" do
      txt = File.join(dir, "kupna.txt")
      File.write(txt, "x")

      aborts_with(/not a \.docx file/) { import(file: txt) }
    end

    it "refuses a file the linter rejects, naming the reason and nothing else" do
      File.binwrite(path, DocxFixtures.mutate { |entries| entries["word/vbaProject.bin"] = "binary" })

      aborts_with(/the template is refused:\n\s+- \w+/) { import }
    end

    it "refuses a file that is not a package at all" do
      File.binwrite(path, "not a zip")

      aborts_with(/the template is refused/) { import }
    end

    it "refuses control fields, which the form cannot fill yet" do
      File.binwrite(path, TemplateGenerationHelpers.template_docx(
                            extra_body: DocxFixtures.para(DocxFixtures.merge("priloha:if")) +
                                        DocxFixtures.para(DocxFixtures.text("x")) +
                                        DocxFixtures.para(DocxFixtures.merge("priloha:endIf"))
                          ))

      aborts_with(/control fields are not supported by the form yet: priloha:if, priloha:endIf/) { import }
    end

    it "refuses merge field names that are not lowercase snake_case" do
      File.binwrite(path, DocxFixtures.docx(DocxFixtures.para(DocxFixtures.merge("=Meno Kupujúceho"))))

      aborts_with(/the template is refused/) { import }
    end

    it "refuses a sidecar that names unknown fields, settings or types" do
      File.write("#{path}.fields.yml", "person: [kupujuci_mneo]\n")
      aborts_with(/names fields the template does not have: kupujuci_mneo/) { import }

      File.write("#{path}.fields.yml", "persons: [predmet]\n")
      aborts_with(/unknown sidecar settings: persons/) { import }

      File.write("#{path}.fields.yml", "groups: { predmet: a }\ngroup_labels: { b: \"B\" }\n")
      aborts_with(/group_labels names groups no field uses: b/) { import }

      File.write("#{path}.fields.yml", "groups: { predmet: a }\ngroup_labels: { a: 5 }\n")
      aborts_with(/group_labels values must be text without control characters: a/) { import }

      File.write("#{path}.fields.yml", "groups: { predmet: a }\ngroup_labels: { a: \"x\\x01y\" }\n")
      aborts_with(/group_labels values must be text without control characters: a/) { import }

      File.write("#{path}.fields.yml", "group_labels: [just, a, list]\n")
      aborts_with(/group_labels must be a mapping/) { import }

      File.write("#{path}.fields.yml", "types: { predmet: blob }\n")
      aborts_with(/unknown field types in the sidecar: blob/) { import }

      File.write("#{path}.fields.yml", "- just\n- a list\n")
      aborts_with(/the sidecar must be a mapping/) { import }
    end

    it "refuses a malformed or privacy-breaking counterparty setting" do
      {
        "counterparty: [kupujuci_meno]\n" => /counterparty must be a mapping/,
        "counterparty: { ico: org_ico }\n" => /counterparty needs a name field/,
        "counterparty: { name: kupujuci_meno, zip: plocha }\n" => /unknown parts: zip/,
        "counterparty: { name: nema_pole }\n" => /counterparty names fields the template does not have: nema_pole/,
        "counterparty: { name: predmet, address: predmet }\n" => /uses a field twice/,
        "person: [kupujuci_meno, kupujuci_adresa]\ncounterparty: { name: kupujuci_meno, address: kupujuci_adresa }\n" =>
          /natural-person counterparty .* cannot also name ico or address/,
        "person: [kupujuci_adresa]\ncounterparty: { name: predmet, address: kupujuci_adresa }\n" =>
          /ico and address cannot be person fields: kupujuci_adresa/
      }.each do |yaml, message|
        File.write("#{path}.fields.yml", yaml)
        aborts_with(message) { import }
      end
      expect(template_class.count).to eq(0)
    end

    it "refuses a reference_pattern that is not plain text" do
      File.write("#{path}.fields.yml", "reference_pattern: [a]\n")
      aborts_with(/reference_pattern must be text/) { import }

      File.write("#{path}.fields.yml", "reference_pattern: \"x\\x01y\"\n")
      aborts_with(/reference_pattern must be text/) { import }
    end

    it "refuses an invalid lineage key without leaving a half-made template" do
      aborts_with(/could not save the template/) { import(lineage: "Zlý Kľúč") }
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/NoExpectationExample
