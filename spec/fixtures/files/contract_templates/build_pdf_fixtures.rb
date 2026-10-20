# frozen_string_literal: true

# Builds the tiny synthetic PDFs used by the RedactionVerifier spec
# (civora-org/civora-platform#211). Everything is invented. Standard Helvetica
# (WinAnsi) is used so no font file is embedded or licensed; the values stay
# within WinAnsi (no c-caron, l-caron, ...). Run once, commit the output:
#
#   bundle exec ruby spec/fixtures/files/contract_templates/build_pdf_fixtures.rb
require "prawn"

Prawn::Fonts::AFM.hide_m17n_warning = true

DIR = __dir__
INFO = { Creator: "synthetic", Producer: "synthetic", CreationDate: Time.utc(2026, 1, 1) }.freeze

def build(name, info: {}, &block)
  Prawn::Document.generate(File.join(DIR, name), page_size: "A4", info: INFO.merge(info), &block)
end

# Redacted publication variant: only the fixed block, no personal value.
build("redacted.pdf") do |pdf|
  pdf.text "Zmluva o dielo c. VZ-2026-001"
  pdf.text "Kupujuci: [osobné údaje – skryté]"
  pdf.text "Rodne cislo: [osobné údaje – skryté]"
end

# Leaks a name, split over two lines, and a rodne cislo with the slash.
build("leaky_text.pdf") do |pdf|
  pdf.text "Zmluva o dielo c. VZ-2026-001"
  pdf.text "Kupujuci: Ján"
  pdf.text "Testovací"
  pdf.text "Rodne cislo: 000000/0000"
end

# Clean page text, an author name only in the Info dictionary.
build("leaky_info.pdf", info: { Author: "Fiktívny Autor Metadátový" }) do |pdf|
  pdf.text "Zmluva o dielo c. VZ-2026-001"
end

# A page without any text: nothing extractable, so nothing provable.
build("no_text.pdf", &:start_new_page)

# A name split by a page break: only the text of all pages together contains it.
build("leaky_split_pages.pdf") do |pdf|
  pdf.text "Zmluva o dielo c. VZ-2026-001"
  pdf.text "Kupujuci: Ján"
  pdf.start_new_page
  pdf.text "Testovací"
end
