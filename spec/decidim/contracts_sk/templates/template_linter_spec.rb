# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, Layout/LineLength
# One example per guard (civora-org/civora-platform#211). Synthetic packages only.
RSpec.describe Decidim::ContractsSk::Templates::TemplateLinter do
  include DocxFixtures

  def lint(bytes) = described_class.call(bytes)

  def body_with(*runs) = DocxFixtures.para(*runs)

  def docx(body = body_with(DocxFixtures.text("Ahoj")), **) = DocxFixtures.docx(body, **)

  describe "the synthetic template" do
    subject(:result) { lint(DocxFixtures.synthetic_template) }

    it "is clean" do
      expect(result).to be_ok
      expect(result.warnings).to be_empty
    end

    it "lists merge fields from body, table, header and footer, without the sablon marker" do
      expect(result.merge_fields).to include("kupujuci_rc", "p.nazov", "priloha.nazov", "org_ico")
      expect(result.merge_fields.count("cislo_zmluvy")).to eq(1)
    end

    it "keeps sablon control fields apart from the merge fields" do
      expect(result.control_fields).to contain_exactly("polozky:each(p)", "polozky:endEach", "priloha:if",
                                                       "priloha:endIf")
      expect(result.merge_fields.grep(/:/)).to be_empty
    end

    it "finds a field that lives only in the header" do
      header = %(<w:hdr xmlns:w="#{DocxFixtures::W}">#{DocxFixtures.para(DocxFixtures.merge("=hlavicka_pole"))}</w:hdr>)
      footer = %(<w:ftr xmlns:w="#{DocxFixtures::W}">#{DocxFixtures.para(DocxFixtures.merge("=paticka_pole"))}</w:ftr>)
      result = lint(docx(parts: { "word/header1.xml" => header, "word/footer1.xml" => footer }))
      expect(result.merge_fields).to contain_exactly("hlavicka_pole", "paticka_pole")
    end
  end

  describe "package guards" do
    it "rejects bytes that are not a zip" do
      expect(lint("not a zip").error_codes).to eq([:not_a_zip])
    end

    it "rejects nil" do
      expect(lint(nil).error_codes).to eq([:not_a_zip])
    end

    it "rejects a zip without word/document.xml" do
      bytes = DocxFixtures.write_zip("hello.txt" => "hi")
      expect(lint(bytes).error_codes).to eq([:not_a_docx])
    end

    it "rejects a package with too many entries" do
      stub_const("Decidim::ContractsSk::Templates::Package::MAX_ENTRIES", 3)
      bytes = docx(parts: { "a.txt" => "1", "b.txt" => "2" })
      expect(lint(bytes).error_codes).to eq([:too_many_entries])
    end

    it "rejects an oversized input" do
      stub_const("Decidim::ContractsSk::Templates::Package::MAX_INPUT_BYTES", 100)
      expect(lint(docx).error_codes).to eq([:too_large])
    end

    it "rejects an entry that inflates past the per-entry cap" do
      stub_const("Decidim::ContractsSk::Templates::Package::MAX_ENTRY_BYTES", 1_000)
      bytes = docx(parts: { "word/big.bin" => "0" * 5_000 })
      expect(lint(bytes).error_codes).to eq([:entry_too_large])
    end

    it "rejects a package whose entries add up past the total cap" do
      stub_const("Decidim::ContractsSk::Templates::Package::MAX_TOTAL_BYTES", 3_000)
      bytes = docx(parts: { "word/a.bin" => "0" * 2_000, "word/b.bin" => "0" * 2_000 })
      expect(lint(bytes).error_codes).to eq([:total_too_large])
    end

    it "stops a real zip bomb at the shipped caps (40 MB of zeros in a few KB)" do
      bomb = docx(parts: { "word/bomb.bin" => "\0" * (40 * 1024 * 1024) })
      expect(bomb.bytesize).to be < 200_000
      expect(lint(bomb).error_codes).to eq([:entry_too_large])
    end

    it "rejects a DOCTYPE (entity expansion, XXE) in any XML part" do
      xml = %(<?xml version="1.0"?><!DOCTYPE x [<!ENTITY a "b">]><w:document xmlns:w="#{DocxFixtures::W}"><w:body/></w:document>)
      bytes = docx(parts: { "word/document.xml" => xml })
      expect(lint(bytes).error_codes).to include(:doctype)
    end

    it "rejects malformed XML" do
      bytes = docx(parts: { "word/header1.xml" => "<w:hdr" })
      expect(lint(bytes).error_codes).to include(:malformed_xml)
    end
  end

  describe "forbidden content" do
    it "rejects a VBA project part" do
      bytes = docx(parts: { "word/vbaProject.bin" => "\x00" })
      expect(lint(bytes).error_codes).to include(:macros)
    end

    it "rejects a macro-enabled content type (.docm)" do
      types = DocxFixtures.content_types.sub("wordprocessingml.document.main+xml",
                                             "ms-word.document.macroEnabled.main+xml")
      bytes = docx(parts: { "[Content_Types].xml" => types })
      expect(lint(bytes).error_codes).to include(:macros)
    end

    it "rejects an OLE embedding part" do
      bytes = docx(parts: { "word/embeddings/oleObject1.bin" => "\x00" })
      expect(lint(bytes).error_codes).to include(:ole_embedding)
    end

    it "rejects an OLE relationship even when the part name looks harmless" do
      rel = %(<Relationship Id="rId9" Type="#{DocxFixtures::OD}/oleObject" Target="stuff/harmless.dat"/>)
      expect(lint(docx(doc_rels: rel)).error_codes).to include(:ole_embedding)
    end

    it "rejects an OLEObject element" do
      body = %(<w:p><w:r><w:object><o:OLEObject xmlns:o="urn:schemas-microsoft-com:office:office" Type="Embed"/></w:object></w:r></w:p>)
      expect(lint(docx(body)).error_codes).to include(:ole_embedding)
    end

    it "rejects an altChunk element" do
      expect(lint(docx(%(<w:altChunk r:id="rId9"/>))).error_codes).to include(:alt_chunk)
    end

    it "rejects an altChunk relationship" do
      rel = %(<Relationship Id="rId9" Type="#{DocxFixtures::OD}/aFChunk" Target="chunk.html"/>)
      expect(lint(docx(doc_rels: rel)).error_codes).to include(:alt_chunk)
    end

    it "rejects an external relationship" do
      rel = %(<Relationship Id="rId9" Type="#{DocxFixtures::OD}/hyperlink" Target="https://example.invalid/" TargetMode="External"/>)
      expect(lint(docx(doc_rels: rel)).error_codes).to include(:external_relationship)
    end

    it "rejects an external relationship in the package-level rels too" do
      rels = DocxFixtures.package_rels.sub("</Relationships>",
                                           %(<Relationship Id="rId9" Type="#{DocxFixtures::OD}/attachedTemplate" Target="file:///x.dotm" TargetMode="External"/></Relationships>))
      expect(lint(docx(parts: { "_rels/.rels" => rels })).error_codes).to include(:external_relationship)
    end
  end

  describe "fields" do
    it "rejects INCLUDETEXT" do
      body = body_with(DocxFixtures.field(%(INCLUDETEXT "file:///etc/passwd")))
      expect(lint(docx(body)).error_codes).to include(:disallowed_field)
    end

    it "rejects DDEAUTO" do
      body = body_with(DocxFixtures.field(%(DDEAUTO c:\\\\windows\\\\system32\\\\cmd.exe "/k calc.exe")))
      expect(lint(docx(body)).error_codes).to include(:disallowed_field)
    end

    it "rejects a simple field (fldSimple) of a disallowed type" do
      body = %(<w:p><w:fldSimple w:instr=" INCLUDEPICTURE &quot;x&quot; "><w:r><w:t>x</w:t></w:r></w:fldSimple></w:p>)
      expect(lint(docx(body)).error_codes).to include(:disallowed_field)
    end

    it "reads an instruction split over several instrText runs" do
      body = body_with(
        '<w:r><w:fldChar w:fldCharType="begin"/></w:r>',
        "<w:r><w:instrText>INCLUDE</w:instrText></w:r><w:r><w:instrText>TEXT x</w:instrText></w:r>",
        '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
      )
      expect(lint(docx(body)).error_codes).to include(:disallowed_field)
    end

    it "finds a disallowed field in a header" do
      header = %(<w:hdr xmlns:w="#{DocxFixtures::W}">#{DocxFixtures.para(DocxFixtures.field("INCLUDETEXT x"))}</w:hdr>)
      expect(lint(docx(parts: { "word/header1.xml" => header })).error_codes).to include(:disallowed_field)
    end

    it "allows PAGE and NUMPAGES" do
      body = body_with(DocxFixtures.field("PAGE"), DocxFixtures.field("NUMPAGES"))
      expect(lint(docx(body))).to be_ok
    end

    it "rejects MERGEFIELD FORMULA, the sign of a LibreOffice save" do
      body = body_with(DocxFixtures.field("MERGEFIELD FORMULA"))
      expect(lint(docx(body)).error_codes).to eq([:mangled_field])
    end

    it "rejects a merge field sablon would leave unfilled (no MERGEFORMAT)" do
      body = body_with(DocxFixtures.field("MERGEFIELD =name"))
      expect(lint(docx(body)).error_codes).to eq([:unsupported_merge_field])
    end

    it "rejects a merge field written without the sablon = marker" do
      body = body_with(DocxFixtures.merge("name"))
      expect(lint(docx(body)).error_codes).to eq([:unsupported_merge_field])
    end

    it "accepts the Word form of a merge field" do
      result = lint(docx(body_with(DocxFixtures.merge("=cislo"))))
      expect(result).to be_ok
      expect(result.merge_fields).to eq(["cislo"])
    end
  end

  describe "warnings" do
    it "warns on a comments part" do
      bytes = docx(parts: { "word/comments.xml" => %(<w:comments xmlns:w="#{DocxFixtures::W}"/>) })
      expect(lint(bytes).warning_codes).to include(:comments)
    end

    it "warns on comment anchors in the body" do
      body = %(<w:p><w:commentRangeStart w:id="0"/><w:r><w:t>x</w:t></w:r></w:p>)
      expect(lint(docx(body)).warning_codes).to include(:comments)
    end

    it "warns on tracked changes" do
      body = %(<w:p><w:ins w:id="1" w:author="A"><w:r><w:t>x</w:t></w:r></w:ins></w:p>)
      expect(lint(docx(body)).warning_codes).to include(:tracked_changes)
    end

    it "warns on hidden text" do
      body = %(<w:p><w:r><w:rPr><w:vanish/></w:rPr><w:t>secret</w:t></w:r></w:p>)
      expect(lint(docx(body)).warning_codes).to include(:hidden_text)
    end

    it "does not warn on w:vanish switched off" do
      body = %(<w:p><w:r><w:rPr><w:vanish w:val="0"/></w:rPr><w:t>x</w:t></w:r></w:p>)
      expect(lint(docx(body)).warning_codes).not_to include(:hidden_text)
    end

    it "warns on embedded media" do
      bytes = docx(parts: { "word/media/image1.png" => "png" })
      expect(lint(bytes).warning_codes).to include(:embedded_media)
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, Layout/LineLength
