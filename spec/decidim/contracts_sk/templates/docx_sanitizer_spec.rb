# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, Layout/LineLength
# One example per sanitising guard (civora-org/civora-platform#211).
RSpec.describe Decidim::ContractsSk::Templates::DocxSanitizer do
  include DocxFixtures

  def sanitize(bytes) = described_class.call(bytes)

  def entries(bytes) = DocxFixtures.read_zip(bytes)

  def body_xml(bytes) = entries(bytes).fetch("word/document.xml").force_encoding("UTF-8")

  def docx(body = DocxFixtures.para(DocxFixtures.text("Ahoj")), **) = DocxFixtures.docx(body, **)

  describe "metadata" do
    subject(:clean) { sanitize(DocxFixtures.synthetic_template) }

    it "blanks creator, lastModifiedBy and title in docProps/core.xml" do
      core = entries(clean).fetch("docProps/core.xml").force_encoding("UTF-8")
      expect(core).not_to include("Fiktívny")
      expect(core).not_to include("Vzorová zmluva")
      expect(core).to include("<dc:creator></dc:creator>").or include("<dc:creator/>")
    end

    it "blanks Company in docProps/app.xml" do
      app = entries(clean).fetch("docProps/app.xml").force_encoding("UTF-8")
      expect(app).not_to include("Metadátová")
      expect(app).to include("Application")
    end

    it "blanks subject, keywords, description, Manager, and drops TitlesOfParts" do
      core = DocxFixtures.default_core.sub("</cp:coreProperties>",
                                           "<dc:subject>Tajná téma</dc:subject><cp:keywords>kľúč</cp:keywords><dc:description>Poznámka autora</dc:description><cp:lastModifiedBy>Posledný Editor</cp:lastModifiedBy></cp:coreProperties>")
      app = DocxFixtures.default_app.sub("</Properties>",
                                         "<Manager>Fiktívny Šéf</Manager><TitlesOfParts><vt:vector xmlns:vt=\"x\">Názov súboru</vt:vector></TitlesOfParts></Properties>")
      xml = all_text(sanitize(docx(core: core, app: app)))
      %w[Tajná kľúč Poznámka Posledný Fiktívny Názov].each { |leak| expect(xml).not_to include(leak) }
    end

    it "removes docProps/custom.xml with its content type override" do
      custom = %(<Properties xmlns="x"><property name="Autor">Fiktívny Úradník</property></Properties>)
      bytes = docx(parts: { "docProps/custom.xml" => custom },
                   overrides: '<Override PartName="/docProps/custom.xml" ContentType="application/vnd.openxmlformats-officedocument.custom-properties+xml"/>')
      result = sanitize(bytes)
      expect(entries(result)).not_to have_key("docProps/custom.xml")
      expect(all_text(result)).not_to include("custom.xml")
    end

    it "removes the thumbnail part and the relationship that points to it" do
      rels = DocxFixtures.package_rels.sub("</Relationships>",
                                           %(<Relationship Id="rId9" Type="x/thumbnail" Target="docProps/thumbnail.jpeg"/></Relationships>))
      result = sanitize(docx(parts: { "docProps/thumbnail.jpeg" => "jpegbytes", "_rels/.rels" => rels }))
      expect(entries(result)).not_to have_key("docProps/thumbnail.jpeg")
      expect(entries(result).fetch("_rels/.rels")).not_to include("thumbnail")
    end

    it "removes customXml parts and the relationship that points to them" do
      rel = %(<Relationship Id="rId9" Type="#{DocxFixtures::OD}/customXml" Target="../customXml/item1.xml"/>)
      parts = { "customXml/item1.xml" => "<a>Fiktívny Úradník</a>",
                "customXml/_rels/item1.xml.rels" => "<Relationships/>" }
      result = sanitize(docx(doc_rels: rel, parts: parts))
      expect(entries(result).keys.grep(/customXml/)).to be_empty
      expect(entries(result).fetch("word/_rels/document.xml.rels")).not_to include("customXml")
    end

    it "removes the people part (author names) and the comments parts" do
      parts = { "word/people.xml" => "<w15:people xmlns:w15='x'/>", "word/comments.xml" => "<w:comments xmlns:w='#{DocxFixtures::W}'/>",
                "word/commentsExtended.xml" => "<x/>" }
      rels = parts.keys.each_with_index.map do |k, i|
        %(<Relationship Id="rId#{i + 5}" Type="x/y" Target="#{k.delete_prefix("word/")}"/>)
      end.join
      result = sanitize(docx(doc_rels: rels, parts: parts))
      expect(entries(result).keys.grep(%r{word/(people|comments)})).to be_empty
      expect(entries(result).fetch("word/_rels/document.xml.rels")).not_to match(/people|comments/)
    end
  end

  describe "comments" do
    it "removes comment anchors from the body but keeps the text" do
      body = '<w:p><w:commentRangeStart w:id="0"/><w:r><w:t>kept</w:t></w:r><w:commentRangeEnd w:id="0"/><w:r><w:commentReference w:id="0"/></w:r></w:p>'
      xml = body_xml(sanitize(docx(body)))
      expect(xml).to include("kept")
      expect(xml).not_to match(/comment(Range|Reference)/)
    end
  end

  describe "revisions" do
    let(:body) do
      "<w:p><w:r><w:t>base </w:t></w:r>" \
        '<w:ins w:id="1" w:author="Fiktívny Revízor" w:date="2026-01-01T00:00:00Z"><w:r><w:t>accepted</w:t></w:r></w:ins>' \
        '<w:del w:id="2" w:author="Fiktívny Revízor" w:date="2026-01-01T00:00:00Z"><w:r><w:delText>dropped</w:delText></w:r></w:del></w:p>'
    end

    it "accepts insertions and drops deletions" do
      xml = body_xml(sanitize(docx(body)))
      expect(xml).to include("accepted")
      expect(xml).not_to include("dropped")
    end

    it "leaves no revision element and no revision author behind" do
      xml = body_xml(sanitize(docx(body)))
      expect(xml).not_to match(/<w:(ins|del|moveFrom|moveTo)\b/)
      expect(xml).not_to include("Revízor")
    end

    it "drops formatting-change records (rPrChange) with their old properties" do
      run = '<w:r><w:rPr><w:b/><w:rPrChange w:id="3" w:author="Fiktívny Revízor"><w:rPr/></w:rPrChange></w:rPr><w:t>x</w:t></w:r>'
      xml = body_xml(sanitize(docx("<w:p>#{run}</w:p>")))
      expect(xml).not_to include("rPrChange")
      expect(xml).to include("<w:b/>")
    end

    it "removes a table row marked as deleted" do
      row = lambda { |text, tr_pr|
        "<w:tr><w:trPr>#{tr_pr}</w:trPr><w:tc><w:p><w:r><w:t>#{text}</w:t></w:r></w:p></w:tc></w:tr>"
      }
      table = "<w:tbl>#{row.call("alive", "")}#{row.call("dead", '<w:del w:id="9" w:author="A"/>')}</w:tbl>"
      xml = body_xml(sanitize(docx(table)))
      expect(xml).to include("alive")
      expect(xml).not_to include("dead")
    end

    it "unwraps a smart-tag style w:customXml element but keeps its text" do
      body = '<w:customXml w:element="osoba"><w:p><w:r><w:t>inside</w:t></w:r></w:p></w:customXml>'
      xml = body_xml(sanitize(docx(body)))
      expect(xml).to include("inside")
      expect(xml).not_to include("customXml")
    end
  end

  describe "hidden text" do
    it "removes hidden runs" do
      body = "<w:p><w:r><w:t>shown</w:t></w:r><w:r><w:rPr><w:vanish/></w:rPr><w:t>secret</w:t></w:r></w:p>"
      xml = body_xml(sanitize(docx(body)))
      expect(xml).to include("shown")
      expect(xml).not_to include("secret")
    end

    it "keeps a run whose w:vanish is switched off" do
      body = '<w:p><w:r><w:rPr><w:vanish w:val="0"/></w:rPr><w:t>visible</w:t></w:r></w:p>'
      expect(body_xml(sanitize(docx(body)))).to include("visible")
    end

    it "keeps a hidden run that carries a field marker, so no field is cut in half" do
      body = "<w:p>#{DocxFixtures.merge("=x").sub("<w:r>", "<w:r><w:rPr><w:vanish/></w:rPr>")}</w:p>"
      xml = body_xml(sanitize(docx(body)))
      expect(xml.scan("fldCharType").size).to eq(3)
    end

    it "cleans headers and footers as well" do
      header = %(<w:hdr xmlns:w="#{DocxFixtures::W}"><w:p><w:r><w:rPr><w:vanish/></w:rPr><w:t>hidden header</w:t></w:r></w:p></w:hdr>)
      result = sanitize(docx(parts: { "word/header1.xml" => header }))
      expect(entries(result).fetch("word/header1.xml")).not_to include("hidden header")
    end
  end

  describe "the result" do
    it "is idempotent" do
      once = sanitize(DocxFixtures.synthetic_template)
      expect(entries(sanitize(once))).to eq(entries(once))
    end

    it "keeps merge fields and still lints clean and fills" do
      clean = sanitize(DocxFixtures.synthetic_template)
      expect(Decidim::ContractsSk::Templates::TemplateLinter.call(clean)).to be_ok
      expect(Decidim::ContractsSk::Templates::TemplateLinter.call(clean).merge_fields)
        .to eq(Decidim::ContractsSk::Templates::TemplateLinter.call(DocxFixtures.synthetic_template).merge_fields)
    end

    it "fails closed on a part it cannot parse instead of emitting an unclean package" do
      expect { sanitize(docx(parts: { "word/header1.xml" => "<w:hdr" })) }
        .to raise_error(Decidim::ContractsSk::Templates::Xml::Malformed)
    end

    it "raises Package::Error on bytes that are not a zip" do
      expect { sanitize("nope") }.to raise_error(Decidim::ContractsSk::Templates::Package::Error)
    end
  end

  def all_text(bytes) = DocxFixtures.all_xml(bytes)
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, Layout/LineLength
