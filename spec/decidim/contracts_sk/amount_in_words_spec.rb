# frozen_string_literal: true

require "spec_helper"

# Golden specs for the Slovak "slovom" helper (civora-org/civora-platform#211).
# Pure Ruby and deterministic; grammar rules are documented on the module.
RSpec.describe Decidim::ContractsSk::AmountInWords do
  def words(value)
    described_class.call(BigDecimal(value.to_s))
  end

  {
    "0" => "nula eur",
    "1" => "jedno euro",
    "2" => "dve eurá",
    "3" => "tri eurá",
    "4" => "štyri eurá",
    "5" => "päť eur",
    "11" => "jedenásť eur",
    "21" => "dvadsaťjeden eur",
    "22" => "dvadsaťdva eur",
    "100" => "sto eur",
    "101" => "stojeden eur",
    "200" => "dvesto eur",
    "999" => "deväťstodeväťdesiatdeväť eur",
    "1000" => "tisíc eur",
    "1001" => "tisícjeden eur",
    "2000" => "dvetisíc eur",
    "21000" => "dvadsaťjedentisíc eur",
    "22000" => "dvadsaťdvetisíc eur",
    "100000" => "stotisíc eur",
    "200000" => "dvestotisíc eur",
    "1000000" => "jeden milión eur",
    "2000000" => "dva milióny eur",
    "5000000" => "päť miliónov eur",
    "21000000" => "dvadsaťjeden miliónov eur",
    "1000000000" => "jedna miliarda eur",
    "2000000000" => "dve miliardy eur",
    "5000000000" => "päť miliárd eur",
    "3062.50" => "tritisícšesťdesiatdva eur a päťdesiat centov",
    "1234567.89" => "jeden milión dvestotridsaťštyritisícpäťstošesťdesiatsedem eur a osemdesiatdeväť centov",
    "0.01" => "nula eur a jeden cent",
    "0.02" => "nula eur a dva centy",
    "0.05" => "nula eur a päť centov",
    "1.01" => "jedno euro a jeden cent",
    "2.04" => "dve eurá a štyri centy",
    "0.21" => "nula eur a dvadsaťjeden centov",
    "9999999999.99" => "deväť miliárd deväťstodeväťdesiatdeväť miliónov " \
                       "deväťstodeväťdesiatdeväťtisícdeväťstodeväťdesiatdeväť eur a deväťdesiatdeväť centov"
  }.each do |amount, expected|
    it "renders #{amount} as #{expected.inspect}" do
      expect(words(amount)).to eq(expected)
    end
  end

  it "accepts an Integer" do
    expect(described_class.call(200)).to eq("dvesto eur")
  end

  it "accepts the engine maximum" do
    expect { described_class.call(Decidim::ContractsSk::Contract::MAX_AMOUNT) }.not_to raise_error
  end

  it "rejects one cent above the engine maximum" do
    expect { described_class.call(Decidim::ContractsSk::Contract::MAX_AMOUNT + BigDecimal("0.01")) }
      .to raise_error(ArgumentError)
  end

  it "rejects invalid input" do
    bad_values = [nil, "12", 1.5, BigDecimal("-0.01"), -1, BigDecimal("1.005"),
                  BigDecimal("NaN"), BigDecimal("Infinity")]
    bad_values.each do |bad|
      expect { described_class.call(bad) }.to raise_error(ArgumentError), "expected #{bad.inspect} to raise"
    end
  end
end
