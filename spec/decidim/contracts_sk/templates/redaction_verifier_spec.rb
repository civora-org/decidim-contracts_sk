# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, Layout/LineLength, RSpec/MultipleMemoizedHelpers
# Planted-leak specs (civora-org/civora-platform#211). Every name, number and
# address is invented. The verifier must catch each plant and fail closed.
RSpec.describe Decidim::ContractsSk::Templates::RedactionVerifier do
  include DocxFixtures

  let(:name) { "Ján Testovací" }
  let(:rc) { "000000/0000" }
  let(:address) { "Ulica Nepravá 99, 000 00 Neexistujúce Mesto" }
  let(:personal) { [name, rc, address] }
  let(:hidden) { "[osobné údaje – skryté]" }

  def pdf(name) = File.binread(File.join(DocxFixtures::FIXTURE_DIR, name))

  def docx(body = DocxFixtures.para(DocxFixtures.text("Zmluva č. 1")), **) = DocxFixtures.docx(body, **)

  def para(text) = DocxFixtures.para(DocxFixtures.text(text))

  def verify(docx_bytes, values = personal, **)
    described_class.call(docx_bytes: docx_bytes, personal_values: values, **)
  end

  def locations(result) = result.leaks.map(&:location).uniq

  def clean_core = DocxFixtures.default_core.sub("<dc:creator>Fiktívny Autor</dc:creator>", "<dc:creator></dc:creator>")

  describe "a clean document" do
    it "passes" do
      result = verify(docx(para("Kupujúci: #{hidden}"), core: clean_core))
      expect(result).to be_ok
      expect(result.leaks).to be_empty
      expect(result.errors).to be_empty
    end

    it "passes the redacted PDF fixture together with the docx" do
      result = verify(docx(para(hidden), core: clean_core), pdf_bytes: pdf("redacted.pdf"))
      expect(result).to be_ok
    end

    it "does not flag a common word such as 'Mesto' on its own" do
      result = verify(docx(para("Mesto Žilina, ulica Hlavná"), core: clean_core), [address])
      expect(result).to be_ok
    end

    it "does not flag short words of a multi-word value" do
      result = verify(docx(para("Jan sa stretol s Ing. Máriou"), core: clean_core), ["Jan Ing Mária Kováčová"])
      expect(result.leaks.map(&:kind)).not_to include(:value)
    end
  end

  describe "planted docx leaks" do
    it "finds a name in a free-text paragraph" do
      result = verify(docx(para("Podľa dohody s pánom Ján Testovací sa dielo odovzdá."), core: clean_core))
      expect(result).not_to be_ok
      expect(result.leaks).to include(have_attributes(location: "docx:word/document.xml", value_index: 0, kind: :value))
    end

    it "finds a rodné číslo written with the slash" do
      result = verify(docx(para("RČ: 000000/0000"), core: clean_core))
      expect(result.leaks.map(&:value_index)).to include(1)
    end

    it "finds a rodné číslo written without the slash when the value has it" do
      result = verify(docx(para("RČ: 0000000000"), core: clean_core))
      expect(result.leaks.map(&:value_index)).to include(1)
    end

    it "finds a rodné číslo written with the slash when the value has none" do
      result = verify(docx(para("RČ: 000000/0000"), core: clean_core), ["0000000000"])
      expect(result).not_to be_ok
    end

    it "finds a rodné číslo with a 3-digit suffix (pre-1954) in both forms" do
      expect(verify(docx(para("999999/999"), core: clean_core), ["999999999"])).not_to be_ok
      expect(verify(docx(para("999999999"), core: clean_core), ["999999/999"])).not_to be_ok
    end

    it "finds the creator left in docProps/core.xml" do
      result = verify(docx(para(hidden)), ["Fiktívny Autor"])
      expect(locations(result)).to eq(["docx:docProps/core.xml"])
    end

    it "finds the company left in docProps/app.xml" do
      app = DocxFixtures.default_app.sub("</Properties>", "<Company>Fiktívna Spoločnosť s.r.o.</Company></Properties>")
      result = verify(docx(para(hidden), core: clean_core, app: app), ["Fiktívna Spoločnosť s.r.o."])
      expect(locations(result)).to eq(["docx:docProps/app.xml"])
    end

    it "finds a value split across runs" do
      body = DocxFixtures.para(DocxFixtures.text("Ján Test"), DocxFixtures.text("ov"),
                               "<w:r><w:rPr><w:b/></w:rPr><w:t>ací</w:t></w:r>")
      expect(verify(docx(body, core: clean_core)).leaks.map(&:value_index)).to include(0)
    end

    it "finds a value split across a field result and a text run" do
      body = DocxFixtures.para(DocxFixtures.field("MERGEFIELD =x \\* MERGEFORMAT", "Ján"),
                               DocxFixtures.text(" Testovací"))
      expect(verify(docx(body, core: clean_core)).leaks.map(&:value_index)).to include(0)
    end

    it "ignores case, spacing and diacritics" do
      expect(verify(docx(para("JAN   testovaci"), core: clean_core)).leaks.map(&:value_index)).to include(0)
    end

    it "sees a non-breaking space and a zero-width character inside the value" do
      expect(verify(docx(para("Ján Testo​vací"), core: clean_core)).leaks.map(&:value_index)).to include(0)
    end

    it "finds one word of a multi-word value on its own (the surname)" do
      result = verify(docx(para("Podpísal: Testovací"), core: clean_core))
      expect(result.leaks).to include(have_attributes(kind: :word, value_index: 0))
    end

    it "finds a street name inside a differently ordered address" do
      result = verify(docx(para("bytom Nepravá, Neexistujúce"), core: clean_core))
      expect(result.leaks).to include(have_attributes(kind: :word, value_index: 2))
    end

    it "finds a leak in a header, a footer and a footnote" do
      xml = ->(tag, text) { %(<w:#{tag} xmlns:w="#{DocxFixtures::W}">#{para(text)}</w:#{tag}>) }
      parts = { "word/header1.xml" => xml.call("hdr", name), "word/footer1.xml" => xml.call("ftr", rc),
                "word/footnotes.xml" => xml.call("footnotes", address) }
      result = verify(docx(para(hidden), parts: parts, core: clean_core))
      expect(locations(result)).to include("docx:word/header1.xml", "docx:word/footer1.xml", "docx:word/footnotes.xml")
    end

    it "finds a leak in a table cell, a text box and deleted text" do
      body = "<w:tbl><w:tr><w:tc>#{para(name)}</w:tc></w:tr></w:tbl>"
      expect(verify(docx(body, core: clean_core))).not_to be_ok
      expect(verify(docx(%(<w:p><w:r><w:pict><w:txbxContent>#{para(name)}</w:txbxContent></w:pict></w:r></w:p>),
                         core: clean_core))).not_to be_ok
      deleted = %(<w:p><w:del w:id="1"><w:r><w:delText>#{name}</w:delText></w:r></w:del></w:p>)
      expect(verify(docx(deleted, core: clean_core))).not_to be_ok
    end

    it "finds a leak in an attribute value (alt text) and in an XML comment" do
      alt = %(<w:p><w:r><wp:docPr xmlns:wp="x" id="1" name="a" descr="#{name}"/></w:r></w:p>)
      expect(verify(docx(alt, core: clean_core))).not_to be_ok
      expect(verify(docx(parts: { "customXml/item1.xml" => "<!-- #{name} --><a/>" }, core: clean_core))).not_to be_ok
    end

    it "finds a leak in a custom XML part and in a comments part" do
      expect(verify(docx(parts: { "customXml/item1.xml" => "<a>#{name}</a>" }, core: clean_core))).not_to be_ok
      comments = %(<w:comments xmlns:w="#{DocxFixtures::W}"><w:comment w:id="0" w:author="x">#{para(name)}</w:comment></w:comments>)
      expect(verify(docx(parts: { "word/comments.xml" => comments }, core: clean_core))).not_to be_ok
    end

    it "does not put the personal value into the result" do
      result = verify(docx(para(name), core: clean_core))
      expect(result.inspect).not_to include("Testovací")
      expect(result.inspect).not_to include("Ján")
    end
  end

  describe "planted PDF leaks" do
    let(:clean_docx) { docx(para(hidden), core: clean_core) }

    it "finds a value that wraps over two lines and a rodné číslo in the page text" do
      result = verify(clean_docx, pdf_bytes: pdf("leaky_text.pdf"))
      expect(locations(result)).to all(start_with("pdf:"))
      expect(result.leaks.map(&:value_index)).to include(0, 1)
    end

    it "finds the per-word match when the value is wrapped" do
      result = verify(clean_docx, ["Ján Testovací Fiktívny"], pdf_bytes: pdf("leaky_text.pdf"))
      expect(result.leaks).to include(have_attributes(kind: :word))
    end

    it "finds an author left in the PDF Info dictionary" do
      result = verify(clean_docx, ["Fiktívny Autor Metadátový"], pdf_bytes: pdf("leaky_info.pdf"))
      expect(locations(result)).to include("pdf:info")
    end

    it "finds a name split by a page break, which no single page contains" do
      result = verify(clean_docx, ["Ján Testovací"], pdf_bytes: pdf("leaky_split_pages.pdf"))
      expect(locations(result)).to include("pdf:text")
    end

    it "reports the page of the leak" do
      result = verify(clean_docx, pdf_bytes: pdf("leaky_text.pdf"))
      expect(locations(result)).to include("pdf:page 1")
    end
  end

  describe "failing closed" do
    it "is not ok when there are no personal values to check" do
      result = verify(docx, [])
      expect(result).not_to be_ok
      expect(result.errors.map(&:code)).to eq([:no_personal_values])
    end

    it "treats a list of blank values as empty" do
      expect(verify(docx, ["", "  ", nil]).errors.map(&:code)).to eq([:no_personal_values])
    end

    it "is not ok for bytes that are not a docx" do
      result = verify("not a zip")
      expect(result).not_to be_ok
      expect(result.errors.map(&:code)).to eq([:not_a_zip])
    end

    it "is not ok for nil input" do
      expect(verify(nil)).not_to be_ok
    end

    it "is not ok for a zip that is no docx" do
      expect(verify(DocxFixtures.write_zip("a.txt" => "x")).errors.map(&:code)).to eq([:not_a_docx])
    end

    it "is not ok when a part cannot be inspected (an opaque binary)" do
      result = verify(docx(parts: { "word/embeddings/object1.bin" => "binary" }, core: clean_core))
      expect(result.errors.map(&:code)).to eq([:unscannable_part])
    end

    it "is not ok when an XML part is malformed" do
      result = verify(docx(parts: { "word/header1.xml" => "<w:hdr" }, core: clean_core))
      expect(result.errors.map(&:code)).to eq([:malformed_xml])
    end

    it "does not mind image parts it cannot read as text" do
      expect(verify(docx(parts: { "word/media/image1.png" => "png" }, core: clean_core))).to be_ok
    end

    it "is not ok when the PDF is not a PDF" do
      expect(verify(docx(core: clean_core), pdf_bytes: "garbage").errors.map(&:code)).to eq([:pdf_unreadable])
    end

    it "is not ok when the PDF has no extractable text" do
      expect(verify(docx(core: clean_core), pdf_bytes: pdf("no_text.pdf")).errors.map(&:code)).to eq([:pdf_no_text])
    end

    it "is not ok when the docx is clean but the PDF leaks" do
      result = verify(docx(para(hidden), core: clean_core), pdf_bytes: pdf("leaky_text.pdf"))
      expect(result).not_to be_ok
    end

    it "never raises on hostile input" do
      expect { verify("\xFF\xFE".b, pdf_bytes: "%PDF-1.4\n\xFF".b) }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, Layout/LineLength, RSpec/MultipleMemoizedHelpers
