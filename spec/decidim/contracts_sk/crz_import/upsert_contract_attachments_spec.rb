# frozen_string_literal: true

require "spec_helper"

# Attachment links through the import (civora-org/civora-platform#189):
# create, update, remove on re-sync, unchanged no-op, hostile names dropped.
# :db, SQLite, no network.
# rubocop:disable RSpec/MultipleExpectations, RSpec/DescribeMethod
RSpec.describe Decidim::ContractsSk::CrzImport::UpsertContract, "attachments", :db do
  include_context "with the CRZ scope configured"

  before { migrate_engine_schema! }

  def att(id, overrides = {})
    { "id" => id, "title" => "Príloha #{id}", "file_name" => nil, "file_size" => nil,
      "scan_file_name" => "#{id}.pdf", "scan_file_size" => 1000, "changed_at" => "2026-10-09T14:55:08Z" }
      .merge(overrides)
  end

  def import(attachments)
    record = Decidim::ContractsSk::CrzImport::Mapper.map(crz_payload("801", "attachments" => attachments))
    described_class.call(record, organization: organization, actor: author)
  end

  def contract
    Decidim::ContractsSk::Contract.find_by!(source_id: "801")
  end

  def files
    contract.crz_attachments.pluck(:kind, :file_name)
  end

  it "creates the link rows with the mirror" do
    import([att(21), att(22, "file_name" => "23.pdf")])

    expect(files).to eq([%w[scan 21.pdf], %w[text 23.pdf], %w[scan 22.pdf]])
    expect(contract.crz_attachments.first.url).to eq("https://www.crz.gov.sk/data/att/21.pdf")
  end

  it "stores nothing for hostile names" do
    import([att(21, "scan_file_name" => "../../x.pdf", "file_name" => "javascript:alert(1)")])

    expect(contract.crz_attachments.count).to eq(0)
  end

  it "adds, changes and removes links on re-sync" do
    import([att(21), att(22)])
    import([att(22, "title" => "Premenovaná"), att(24)])

    expect(files).to eq([%w[scan 22.pdf], %w[scan 24.pdf]])
    expect(contract.crz_attachments.first.title).to eq("Premenovaná")
  end

  it "removes every link when CRZ drops all attachments" do
    import([att(21)])
    import([])

    expect(contract.crz_attachments.count).to eq(0)
  end

  it "writes nothing for an unchanged payload" do
    import([att(21)])
    row_id = contract.crz_attachments.first.id
    import([att(21)])

    expect(contract.crz_attachments.pluck(:id)).to eq([row_id])
  end

  it "leaves links alone for a hand-built record without an :attachments key" do
    import([att(21)])
    record = Decidim::ContractsSk::CrzImport::Mapper.map(crz_payload("801", "subject" => "Zmenený predmet"))
    record.delete(:attachments)
    described_class.call(record, organization: organization, actor: author)

    expect(contract.crz_attachments.count).to eq(1)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/DescribeMethod
