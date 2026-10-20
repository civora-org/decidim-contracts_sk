# Spike: redaction verification. Usage: bundle exec ruby verify.rb DIR
# DIR holds full.docx/full.pdf, publication.docx/.pdf, publication-noattach.docx/.pdf
require "pdf/reader"
require "zip"

# FAKE personal values and FAKE metadata strings (all invented for this spike).
PERSONAL = ["Ján Testovací", "Testovací", "Ulica Nepravá 99", "Neexistujúce Mesto", "000000/0000"].freeze
METADATA = ["Fiktívny Úradník", "Metadátový", "Fiktívna Spoločnosť", "Metadátová"].freeze
SECRETS = (PERSONAL + METADATA).freeze
# A value that wraps across lines or table cells is not a contiguous substring in pdf-reader's
# text, so the verifier also checks each word of 4+ characters on its own (found in the spike).
TOKENS = SECRETS.flat_map { |v| v.split(/[\s,]+/) }.select { |t| t.length >= 4 || t.match?(%r{\d/\d}) }.uniq.freeze
HIDDEN = "[osobné údaje – skryté]".freeze
dir = ARGV.fetch(0)

def norm(str) = str.unicode_normalize(:nfc).gsub(/\s+/, " ")

def pdf_text(path)
  reader = PDF::Reader.new(path)
  [norm(reader.pages.map(&:text).join(" ")), reader.info.to_h.transform_values(&:to_s), reader.page_count]
end

def docx_text(path)
  out = +""
  Zip::File.open(path) do |zip|
    zip.each { |entry| out << " " << entry.get_input_stream.read.force_encoding("UTF-8") unless entry.directory? }
  end
  norm(out)
end

fail_count = 0
check = lambda do |label, ok|
  puts format("%-4s %s", ok ? "PASS" : "FAIL", label)
  fail_count += 1 unless ok
end

# Positive control: the unredacted PDF must contain the values, else extraction proves nothing.
full_text, = pdf_text(File.join(dir, "full.pdf"))
PERSONAL.each { |s| check.call("control: full.pdf text contains #{s.inspect}", full_text.include?(s)) if s != "Neexistujúce Mesto" }
%w[Neexistujúce Mesto].each { |t| check.call("control: full.pdf text contains wrapped token #{t.inspect}", full_text.include?(t)) }
check.call("control: full.pdf contains 'Obec Vzorová' (diacritics extract)", full_text.include?("Obec Vzorová"))

%w[publication publication-noattach].each do |name|
  text, info, pages = pdf_text(File.join(dir, "#{name}.pdf"))
  puts "-- #{name}.pdf: #{pages} page(s), Info=#{info.slice(:Author, :Creator, :Producer, :Title).inspect}"
  check.call("#{name}.pdf shows the fixed block (#{text.scan(HIDDEN).size}x)", text.include?(HIDDEN))
  (SECRETS + TOKENS).uniq.each { |s| check.call("#{name}.pdf text has no #{s.inspect}", !text.include?(s)) }
  check.call("#{name}.pdf Info dict has no author/company", SECRETS.none? { |s| info.values.join(" ").include?(s) })
  dtext = docx_text(File.join(dir, "#{name}.docx"))
  SECRETS.each { |s| check.call("#{name}.docx (all parts incl. docProps) has no #{s.inspect}", !dtext.include?(s)) }
end

# Negative control for the metadata strip: the filled-but-unsanitized docx still carries it.
check.call("control: full.docx still carries the fake author (sanitizer is what removes it)",
           METADATA.any? { |s| docx_text(File.join(dir, "full.docx")).include?(s) })

na, = pdf_text(File.join(dir, "publication-noattach.pdf"))
check.call("optional block removed when attachment is nil", !na.include?("Rozpočet prác") && !na.include?("príloha"))
pub, = pdf_text(File.join(dir, "publication.pdf"))
check.call("optional block present when attachment given", pub.include?("Rozpočet prác"))
check.call("repeated field filled everywhere (header + body x2 = 3)", pub.scan("VZ-2026-001").size >= 3)
check.call("table loop filled (3 rows)", %w[Materiál Práca Doprava].all? { |w| pub.include?(w) })
check.call("no unresolved merge markers", [pub, full_text].none? { |t| t.include?("«") || t.include?("MERGEFIELD") })
puts(fail_count.zero? ? "ALL PASS" : "#{fail_count} FAILED")
exit(fail_count.zero? ? 0 : 1)
