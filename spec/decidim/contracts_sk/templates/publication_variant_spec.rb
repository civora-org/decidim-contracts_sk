# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations, RSpec/MultipleDescribes
# civora-org/civora-platform#211.
RSpec.describe Decidim::ContractsSk::Templates::PublicationVariant do
  let(:hidden) { "[osobné údaje – skryté]" }
  let(:values) do
    {
      cislo_zmluvy: "VZ-1",
      kupujuci_meno: "Ján Testovací",
      "kupujuci_rc" => "000000/0000",
      polozky: [{ nazov: "A", osoba: "Eva Fiktívna" }],
      priloha: nil
    }
  end

  it "replaces each personal value with the fixed block" do
    result = described_class.values_for(values, %i[kupujuci_meno kupujuci_rc])
    expect(result[:kupujuci_meno]).to eq(hidden)
    expect(result["kupujuci_rc"]).to eq(hidden)
  end

  it "collects the non-blank personal leaves, including those in table rows" do
    keys = %w[kupujuci_meno kupujuci_rc kupujuci_adresa osoba]
    found = described_class.personal_values(values.merge(kupujuci_adresa: " "), keys)
    expect(found).to contain_exactly("Ján Testovací", "000000/0000", "Eva Fiktívna")
  end

  it "leaves the other values alone" do
    result = described_class.values_for(values, [:kupujuci_meno])
    expect(result[:cislo_zmluvy]).to eq("VZ-1")
    expect(result[:polozky].first[:nazov]).to eq("A")
  end

  it "matches keys as strings or symbols, whichever way they are given" do
    expect(described_class.values_for(values, %w[kupujuci_meno])[:kupujuci_meno]).to eq(hidden)
    expect(described_class.values_for(values, [:kupujuci_rc])["kupujuci_rc"]).to eq(hidden)
  end

  it "reaches into table-row loops" do
    result = described_class.values_for(values, [:osoba])
    expect(result[:polozky].first).to eq(nazov: "A", osoba: hidden)
  end

  it "replaces a whole nested group under a personal key, leaf by leaf" do
    nested = { zakaznik: { meno: "Ján", adresa: %w[a b] }, iny: "x" }
    expect(described_class.values_for(nested,
                                      [:zakaznik])).to eq(zakaznik: { meno: hidden, adresa: [hidden, hidden] },
                                                          iny: "x")
  end

  it "keeps nil and blank values as they are" do
    result = described_class.values_for({ meno: nil, rc: "  ", adresa: "" }, %i[meno rc adresa])
    expect(result).to eq(meno: nil, rc: "  ", adresa: "")
  end

  it "does not mutate its input" do
    original = Marshal.load(Marshal.dump(values))
    described_class.values_for(values, [:kupujuci_meno])
    expect(values).to eq(original)
  end

  it "uses the placeholder the spike verified" do
    expect(described_class::PLACEHOLDER).to eq("[osobné údaje – skryté]")
  end
end

RSpec.describe Decidim::ContractsSk::Templates::Words do
  it "writes a formatted amount in Slovak words" do
    expect(described_class.for_amount("3 062,50")).to eq("tritisícšesťdesiatdva eur a päťdesiat centov")
  end

  it "accepts a BigDecimal and an Integer" do
    expect(described_class.for_amount(BigDecimal("2"))).to eq("dve eurá")
    expect(described_class.for_amount(1)).to eq("jedno euro")
  end

  it "rejects text that is not an amount" do
    expect { described_class.for_amount("abc") }.to raise_error(ArgumentError)
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/MultipleDescribes
