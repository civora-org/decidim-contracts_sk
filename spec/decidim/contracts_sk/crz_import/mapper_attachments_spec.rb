# frozen_string_literal: true

require "spec_helper"

# Attachment mapping (civora-org/civora-platform#189), offline. The first
# example uses the shape of the real ekosystem payload of CRZ 12919048
# (a scan only, no text version, no sizes).
# rubocop:disable RSpec/DescribeMethod, RSpec/MultipleExpectations, RSpec/ExampleLength
RSpec.describe Decidim::ContractsSk::CrzImport::Mapper, "attachments" do
  def map_attachments(attachments)
    described_class.map("id" => 1, "attachments" => attachments)[:attachments]
  end

  it "maps a scan-only attachment of the real payload shape" do
    rows = map_attachments([{ "id" => 12_919_049, "contract_id" => 1, "title" => "Dohoda_26_40_010",
                              "file_name" => nil, "file_size" => nil, "changed_at" => "2026-10-09T14:55:08.000000Z",
                              "scan_file_name" => "7065995.pdf", "scan_file_size" => nil }])

    expect(rows).to eq([{ crz_id: "12919049", title: "Dohoda_26_40_010", kind: "scan",
                          file_name: "7065995.pdf", file_size: nil,
                          changed_at: Time.utc(2026, 10, 9, 14, 55, 8) }])
  end

  it "yields a text and a scan row for an attachment carrying both, with sizes" do
    rows = map_attachments([{ "id" => 5, "title" => "Zmluva", "file_name" => "11.pdf", "file_size" => 2048,
                              "scan_file_name" => "12.pdf", "scan_file_size" => "4096" }])

    expect(rows.map { |row| [row[:kind], row[:file_name], row[:file_size]] })
      .to eq([["text", "11.pdf", 2048], ["scan", "12.pdf", 4096]])
  end

  it "drops malformed file names, keeping a valid sibling" do
    rows = map_attachments([{ "id" => 1, "title" => "x", "file_name" => "../etc/passwd",
                              "scan_file_name" => "javascript:alert(1)" },
                            { "id" => 2, "title" => "ok", "file_name" => "9.pdf", "scan_file_name" => "9.exe" }])

    expect(rows.map { |row| row[:file_name] }).to eq(["9.pdf"])
  end

  it "is tolerant of absent, non-array and junk attachments, garbage sizes and dates" do
    expect(map_attachments(nil)).to eq([])
    expect(map_attachments("nope")).to eq([])
    expect(map_attachments(["junk", 3, nil])).to eq([])
    junk = { "id" => 1, "file_name" => "1.pdf", "file_size" => "-5", "changed_at" => "0000-00-00" }
    row = map_attachments([junk]).first
    expect(row).to include(file_size: nil, changed_at: nil, title: nil)
  end

  it "keeps the checksum a digest of the whole payload, so an attachment change changes it" do
    one = described_class.map("id" => 1, "attachments" => [{ "id" => 1, "scan_file_name" => "1.pdf" }])
    two = described_class.map("id" => 1, "attachments" => [])
    expect(one[:checksum]).not_to eq(two[:checksum])
  end
end
# rubocop:enable RSpec/DescribeMethod, RSpec/MultipleExpectations, RSpec/ExampleLength
