# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Specs for the spreadsheet import's dry run (civora-org/civora-platform#129):
# per-row validation reusing the contract and party forms, plus the hostile
# input guards. The default group is offline (no organization, so no
# duplicate lookup against the database); the :db group pins the reference
# collisions with existing records. Fictional data only.
# ---------------------------------------------------------------------------

require "spec_helper"

# Each example pins one scenario with several related expectations by design.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

RSpec.describe Decidim::ContractsSk::SpreadsheetImport::Preview do
  let(:header) { "reference,title,subject_matter,amount,currency,signed_on,effective_from,crz_url" }

  def preview_of(*lines, head: header, organization: nil)
    described_class.new(([head] + lines).join("\n") << "\n", organization: organization)
  end

  def row_errors(*lines, **options)
    preview_of(*lines, **options).rows.map(&:errors)
  end

  describe "a valid file" do
    it "is importable and builds the contract form per row, with strict casts" do
      preview = preview_of("DEMO-1,Cesta,Oprava,\"1250,50\",eur,12.3.2026,2026-03-20,https://example.org/z")
      form = preview.rows.first.contract_form

      aggregate_failures do
        expect(preview).to be_importable
        expect(form.amount).to eq(BigDecimal("1250.50"))
        expect(form).to have_attributes(currency: "EUR", signed_on: Date.new(2026, 3, 12),
                                        effective_from: Date.new(2026, 3, 20))
      end
    end

    it "treats optional cells as absent: no amount, default currency" do
      form = preview_of("DEMO-1,Cesta,,,,,,").rows.first.contract_form

      expect(form).to have_attributes(amount: nil, currency: "EUR", signed_on: nil, subject_matter: nil)
    end

    it "reads the shipped sample (round-trip shape of the export) with parties" do
      path = File.expand_path("../../../fixtures/files/spreadsheet_import/sample-contracts.csv", __dir__)
      preview = described_class.new(File.binread(path), organization: nil)

      aggregate_failures do
        expect(preview).to be_importable
        expect(preview.rows.map { |row| row.party_forms.map(&:name) })
          .to eq([["Obec Ukážková", "Cesty Demo s.r.o."], ["Obec Ukážková", "Papier Demo a.s."], []])
        expect(preview.rows.first.party_forms.map(&:role)).to eq(%w[object contractor])
      end
    end

    it "defaults a party without a role to the contractor" do
      preview = preview_of("DEMO-1,Cesta,,,,,,,00000002,Cesty Demo s.r.o.", head: "#{header},party_icos,party_names")

      expect(preview).to be_importable
      expect(preview.rows.first.party_forms.map { |p| [p.role, p.ico] }).to eq([%w[contractor 00000002]])
    end
  end

  describe "per-row validation (the contract form's rules, reported with the line)" do
    it "reports a missing title and a missing reference" do
      errors = row_errors(",Cesta,,,,,,", "DEMO-2,,,,,,,")

      expect(errors).to eq([["reference: can't be blank"], ["title: can't be blank"]])
    end

    it "rejects bad amounts: garbage, thousands separators, scientific notation, negative, oversized" do
      %w[abc 1e5 -5 12345678901.00].push("1 250,50", "1.250,50").each do |amount|
        preview = preview_of("DEMO-1,Cesta,,\"#{amount}\",,,,")

        expect(preview.rows.first.errors).not_to be_empty, "amount #{amount.inspect} must be refused"
      end
    end

    it "rejects a currency outside the allowlist and a non-http CRZ link" do
      errors = row_errors("DEMO-1,Cesta,,,USD,,,", "DEMO-2,Cesta,,,,,,javascript:alert(1)").flatten

      expect(errors.map { |e| e.split(":").first }).to eq(%w[currency crz_url])
    end

    it "rejects unparsable and impossible dates instead of silently dropping them" do
      errors = row_errors("DEMO-1,Cesta,,,,2026-31-02,,", "DEMO-2,Cesta,,,,,tomorrow,", "DEMO-3,Cesta,,,,0001-01-01,,")

      expect(errors.flatten.map { |e| e.split(":").first }).to eq(%w[signed_on effective_from signed_on])
    end

    it "rejects over-long fields" do
      expect(row_errors("DEMO-1,#{"t" * 256},,,,,,").first.first).to start_with("title:")
    end

    it "reports party problems with the party number" do
      head = "#{header},party_roles,party_icos,party_names"
      row = preview_of("DEMO-1,Cesta,,,,,,,object | boss,00000001 | 123,Obec | Firma", head: head).rows.first

      expect(row.errors.map { |e| e.split(":").first }.uniq).to eq(["Party 2, role", "Party 2, ico"])
    end

    it "refuses party lists of different lengths" do
      head = "#{header},party_icos,party_names"

      expect(row_errors("DEMO-1,Cesta,,,,,,,00000001,Obec | Firma", head: head).first.first)
        .to start_with("party_roles and party_icos")
    end

    it "caps the number of parties per row" do
      head = "#{header},party_names"
      names = (1..11).map { |i| "Firma #{i}" }.join(" | ")

      expect(row_errors("DEMO-1,Cesta,,,,,,,\"#{names}\"", head: head).first).to include("More than 10 parties")
    end

    it "reports cells beyond the header width" do
      expect(row_errors("DEMO-1,Cesta,,,,,,,surplus").first).to include("The row has more cells than the header row")
    end

    it "keeps the line number of each row for the report" do
      preview = preview_of("DEMO-1,Cesta,,,,,,", "", "DEMO-2,,,,,,,")

      expect(preview.rows.map(&:line)).to eq([2, 4])
      expect(preview.invalid_rows.map(&:line)).to eq([4])
    end
  end

  describe "hostile cells" do
    it "refuses formula-looking text in every free-text column" do
      %w[= + - @].each do |trigger|
        errors = row_errors("DEMO-1,#{trigger}cmd,,,,,,", "#{trigger}ref,Cesta,,,,,,", "DEMO-3,Cesta,#{trigger}x,,,,,")

        expect(errors.flatten.size).to eq(3), "trigger #{trigger.inspect}"
      end
    end

    it "refuses a formula behind whitespace, a tab, or in a party name" do
      head = "#{header},party_names"

      aggregate_failures do
        expect(row_errors("DEMO-1,\"\t=1+1\",,,,,,", head: head).flatten.first)
          .to start_with("title: starts with a formula")
        expect(row_errors("DEMO-1,Cesta,,,,,,,Obec | +SUM(A1)", head: head).flatten.first)
          .to start_with("party_names: starts with a formula")
      end
    end

    it "accepts text that merely contains a trigger character" do
      expect(preview_of("DEMO-1,Cesta a ďalšia = zmluva - dodatok,,,,,,")).to be_importable
    end

    it "refuses control characters and bidi overrides, but allows a newline in a quoted cell" do
      aggregate_failures do
        expect(row_errors("DEMO-1,\"a\u0001b\",,,,,,").flatten.first).to start_with("title: contains control")
        expect(row_errors("DEMO-1,\"a‮b\",,,,,,").flatten.first).to start_with("title: contains control")
        expect(preview_of("DEMO-1,Cesta,\"dva\nriadky\",,,,,")).to be_importable
      end
    end

    it "keeps markup inert as plain text (escaped at render time)" do
      preview = preview_of("DEMO-1,\"<script>alert(1)</script>\",,,,,,")

      expect(preview).to be_importable
    end
  end

  describe "file-level problems" do
    it "is never importable and builds no rows" do
      preview = described_class.new("nazov\nx\n", organization: nil)

      expect(preview).not_to be_importable
      expect(preview.rows).to be_empty
      expect(preview.problems.map(&:code)).to eq([:missing_headers])
    end

    it "is not importable with no rows (empty file)" do
      expect(described_class.new("", organization: nil)).not_to be_importable
    end

    it "is not importable when one row of many is invalid (all-or-nothing)" do
      preview = preview_of("DEMO-1,Cesta,,,,,,", "DEMO-2,,,,,,,", "DEMO-3,Most,,,,,,")

      expect(preview).not_to be_importable
      expect(preview.invalid_rows.size).to eq(1)
    end
  end

  describe "round trip with the open-data CSV export (docs/open-data.md)", :db do
    let(:record_class) { Decidim::ContractsSk::OpenData::ContractRecord }
    let(:source) do
      contract = Decidim::ContractsSk::Contract.create!(
        contract_attributes(reference: "DEMO-RT-1", title: "Oprava cesty", subject_matter: "Povrch",
                            amount: BigDecimal("1250.5"), signed_on: Date.new(2026, 3, 12),
                            effective_from: Date.new(2026, 3, 20), state: "published")
      )
      contract.parties.create!(role: "object", name: "Obec Ukážková", ico: "00000001")
      contract.parties.create!(role: "contractor", name: "Cesty Demo s.r.o.", ico: "00000002")
      contract
    end

    before { migrate_engine_schema! }

    def export_text(contract, decimal_comma: false, col_sep: ",")
      record = record_class.new(contract, url: "https://example.org/zmluvy/1")
      CSV.generate(col_sep: col_sep) do |csv|
        csv << record_class::FIELDS
        csv << record.csv_row(decimal_comma: decimal_comma)
      end
    end

    def reimport(text)
      other = Decidim::Organization.create!
      described_class.new(text, organization: other).rows.first
    end

    it "reads the default profile back to the same field values and parties" do
      row = reimport(export_text(source))
      form = row.contract_form

      expect(row.errors).to eq([])
      expect(form).to have_attributes(reference: "DEMO-RT-1", title: "Oprava cesty", amount: BigDecimal("1250.50"),
                                      signed_on: Date.new(2026, 3, 12), effective_from: Date.new(2026, 3, 20))
      expect(row.party_forms.map { |p| [p.role, p.ico, p.name] })
        .to eq([["contractor", "00000002", "Cesty Demo s.r.o."], ["object", "00000001", "Obec Ukážková"]])
    end

    it "reads the Excel profile (semicolon, decimal comma) as well" do
      row = reimport(export_text(source, decimal_comma: true, col_sep: ";"))

      expect(row.errors).to eq([])
      expect(row.contract_form.amount).to eq(BigDecimal("1250.50"))
    end

    it "reads an export-neutralized cell back as plain text with its apostrophe (never formula-shaped)" do
      source.update!(title: "=1+1")
      row = reimport(export_text(source))

      expect([row.errors, row.contract_form.title]).to eq([[], "'=1+1"])
    end
  end

  describe "duplicate references", :db do
    before { migrate_engine_schema! }

    it "flags a repeat inside the file with the first line, never the first occurrence" do
      errors = row_errors("DEMO-1,Cesta,,,,,,", "DEMO-2,Most,,,,,,", "DEMO-1,Znova,,,,,,", organization: organization)

      expect(errors).to eq([[], [], ["reference: repeated, first used on line 2"]])
    end

    it "flags a reference the organization already holds, and only its own organization" do
      Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "DEMO-1"))
      other = Decidim::Organization.create!

      aggregate_failures do
        expect(row_errors("DEMO-1,Cesta,,,,,,", organization: organization))
          .to eq([["reference: this reference already exists in your organization"]])
        expect(row_errors("DEMO-1,Cesta,,,,,,", organization: other)).to eq([[]])
      end
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
