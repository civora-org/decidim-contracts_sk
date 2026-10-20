# Spike: fill the synthetic template with sablon, in a full and a redacted (publication) variant.
# Usage: bundle exec ruby fill.rb TEMPLATE.docx OUT_DIR
require "sablon"
require "zip"
require "fileutils"

HIDDEN = "[osobné údaje – skryté]".freeze
PERSON = { kupujuci_meno: "Ján Testovací", kupujuci_adresa: "Ulica Nepravá 99, 000 00 Neexistujúce Mesto", kupujuci_rc: "000000/0000" }.freeze

def context(redact:, attachment: true)
  person = redact ? PERSON.transform_values { HIDDEN } : PERSON
  {
    org_nazov: "Obec Vzorová", org_ico: "00000000", org_adresa: "Námestie Vzorové 1, 000 00 Vzorová",
    cislo_zmluvy: "VZ-2026-001", predmet: "Oprava fiktívnej lavičky", datum_ucinnosti: "1. 1. 2027",
    polozky: [{ nazov: "Materiál", suma: "120,00" }, { nazov: "Práca", suma: "80,00" }, { nazov: "Doprava", suma: "20,00" }],
    suma_celkom: "220,00", suma_slovom: "dvestodvadsať eur",
    priloha: attachment ? { nazov: "Rozpočet prác" } : nil
  }.merge(person)
end

# Metadata strip: drop creator/lastModifiedBy/Company by rewriting the docProps parts.
def sanitize(path)
  tmp = "#{path}.tmp"
  Zip::File.open(path) do |zin|
    Zip::OutputStream.open(tmp) do |zout|
      zin.each do |e|
        next if e.directory?

        data = e.get_input_stream.read
        case e.name
        when "docProps/core.xml" then data = data.gsub(%r{<dc:creator>.*?</dc:creator>|<cp:lastModifiedBy>.*?</cp:lastModifiedBy>}m, "")
        when "docProps/app.xml" then data = data.gsub(%r{<Company>.*?</Company>|<Manager>.*?</Manager>}m, "")
        end
        zout.put_next_entry(e.name)
        zout.write(data)
      end
    end
  end
  FileUtils.mv(tmp, path)
end

template, out = ARGV
FileUtils.mkdir_p(out)
Sablon.template(File.expand_path(template)).render_to_file(File.join(out, "full.docx"), context(redact: false))
Sablon.template(File.expand_path(template)).render_to_file(File.join(out, "publication.docx"), context(redact: true))
Sablon.template(File.expand_path(template)).render_to_file(File.join(out, "publication-noattach.docx"), context(redact: true, attachment: false))
%w[publication publication-noattach].each { |n| sanitize(File.join(out, "#{n}.docx")) }
puts "ok"
