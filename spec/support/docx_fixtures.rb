# frozen_string_literal: true

require "stringio"
require "zip"

# Builds small, synthetic .docx packages in memory for the contract-template
# specs (civora-org/civora-platform#211). Everything is invented: no real
# person, town or contract data. Uses rubyzip directly, independent of the
# engine's own Package, so a bug there cannot hide itself.
module DocxFixtures
  W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
  OD = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  FIXTURE_DIR = File.expand_path("../fixtures/files/contract_templates", __dir__)

  module_function

  def synthetic_template
    File.binread(File.join(FIXTURE_DIR, "synthetic-template.docx"))
  end

  def read_zip(bytes)
    Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
      return zip.reject(&:directory?).to_h { |e| [e.name, e.get_input_stream.read] }
    end
  end

  def write_zip(entries)
    Zip::OutputStream.write_buffer(StringIO.new(+"".b)) do |zip|
      entries.each do |name, data|
        zip.put_next_entry(name)
        zip.write(data)
      end
    end.string
  end

  # Copies the synthetic template and lets the block edit the entries Hash.
  def mutate(bytes = synthetic_template)
    entries = read_zip(bytes)
    yield entries
    write_zip(entries)
  end

  def text(value) = %(<w:r><w:t xml:space="preserve">#{value}</w:t></w:r>)
  def para(*runs) = "<w:p>#{runs.join}</w:p>"

  # A complex field the way Word writes it.
  def field(instruction, result = "x")
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>' \
      "<w:r><w:instrText xml:space=\"preserve\"> #{instruction} </w:instrText></w:r>" \
      '<w:r><w:fldChar w:fldCharType="separate"/></w:r>' \
      "<w:r><w:t>#{result}</w:t></w:r>" \
      '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
  end

  def merge(name) = field("MERGEFIELD #{name} \\* MERGEFORMAT", "«#{name}»")

  # A minimal valid package around +body+. +parts+ adds or overrides entries;
  # +overrides+ are extra [Content_Types] Override elements, +doc_rels+ extra
  # Relationship elements for word/document.xml.
  def docx(body, parts: {}, overrides: "", doc_rels: "", core: nil, app: nil)
    entries = {
      "[Content_Types].xml" => content_types(overrides),
      "_rels/.rels" => package_rels,
      "word/document.xml" => document(body),
      "word/_rels/document.xml.rels" => %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="#{REL_NS}">#{doc_rels}</Relationships>),
      "docProps/core.xml" => core || default_core,
      "docProps/app.xml" => app || default_app
    }
    write_zip(entries.merge(parts))
  end

  def document(body)
    %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="#{W}" xmlns:r="#{OD}"><w:body>#{body}</w:body></w:document>)
  end

  def content_types(overrides = "")
    %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>#{overrides}</Types>)
  end

  def package_rels
    %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="#{REL_NS}"><Relationship Id="rId1" Type="#{OD}/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>)
  end

  def default_core
    %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Vzorová zmluva</dc:title><dc:creator>Fiktívny Autor</dc:creator></cp:coreProperties>)
  end

  def default_app
    %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Synthetic</Application></Properties>)
  end

  # All text of every XML entry, joined: handy for "this string is gone" checks.
  def all_xml(bytes)
    read_zip(bytes).select { |name, _| name.end_with?(".xml", ".rels") }.values.join(" ").force_encoding("UTF-8")
  end
end
