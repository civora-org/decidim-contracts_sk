# frozen_string_literal: true

require "spec_helper"

# Deterministic output (civora-org/civora-platform#211): zip entries must not
# carry the wall-clock time, or two generate calls can differ by a DOS tick.
RSpec.describe Decidim::ContractsSk::Templates::Package do
  let(:entries) { { "[Content_Types].xml" => "<Types/>", "word/document.xml" => "<w:document/>" } }

  it "writes identical bytes when the clock crosses a 2-second boundary" do
    t0 = Time.utc(2026, 5, 1, 12, 0, 0)
    ticks = 0
    allow(Time).to receive(:now) { t0 + (ticks += 5) }
    first = described_class.write(entries)
    expect(described_class.write(entries)).to eq(first)
  end

  it "round-trips the entries" do
    expect(described_class.read(described_class.write(entries))).to eq(entries)
  end
end
