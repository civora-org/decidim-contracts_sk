# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Offline (DB-free) specs for the base helper's locale-aware formatters
# (civora-org/civora-platform#81): money, dates and the CRZ-handoff PDF's
# UTC-labelled generation stamp.
#
# The module is exercised through a plain includer class — the formatters
# are deliberately PORO-safe (I18n only, no view context), which is exactly
# what lets CrzHandoffPdf include the same module. Every example pins BOTH
# shipped locales by swapping I18n.locale explicitly and restoring it, so
# no state leaks between examples.
# ---------------------------------------------------------------------------

require "spec_helper"

RSpec.describe Decidim::ContractsSk::ApplicationHelper do
  # Plain includer: proves the module carries no view-context dependency.
  let(:helper) do
    Class.new do
      include Decidim::ContractsSk::ApplicationHelper
    end.new
  end

  def with_locale(locale)
    original = I18n.locale
    I18n.locale = locale
    yield
  ensure
    I18n.locale = original
  end

  describe "#format_amount" do
    it "groups thousands and comma-decimalizes under :sk with a regular space separator" do
      with_locale(:sk) do
        # The regular space is the documented decision (not a non-breaking
        # one): one plain string for both the HTML and the PDF render.
        expect(helper.format_amount(BigDecimal("1250.5"), "EUR")).to eq("1 250,50 EUR")
      end
    end

    it "groups large sk amounts every three digits" do
      with_locale(:sk) do
        expect(helper.format_amount(BigDecimal("1234567.891"), "EUR")).to eq("1 234 567,89 EUR")
      end
    end

    it "keeps the historical fixed-point en format verbatim" do
      with_locale(:en) do
        expect(helper.format_amount(BigDecimal("1250.50"), "EUR")).to eq("1250.5 EUR")
      end
    end

    it "adds no thousands grouping under :en" do
      with_locale(:en) do
        expect(helper.format_amount(BigDecimal("1234567.89"), "EUR")).to eq("1234567.89 EUR")
      end
    end

    it "never renders BigDecimal's scientific notation, in either locale" do
      aggregate_failures do
        with_locale(:en) { expect(helper.format_amount(BigDecimal("0.125e4"), "EUR")).to eq("1250.0 EUR") }
        with_locale(:sk) { expect(helper.format_amount(BigDecimal("0.125e4"), "EUR")).to eq("1 250,00 EUR") }
      end
    end

    it "renders the bare number when the currency is blank (the PDF's drop-the-row semantics)" do
      with_locale(:sk) do
        expect(helper.format_amount(BigDecimal("1250.5"), nil)).to eq("1 250,50")
      end
    end

    it "renders empty for a blank amount" do
      aggregate_failures do
        with_locale(:en) { expect(helper.format_amount(nil, "EUR")).to eq("") }
        with_locale(:sk) { expect(helper.format_amount("", "EUR")).to eq("") }
      end
    end
  end

  describe "#format_date" do
    it "keeps the ISO date under :en" do
      with_locale(:en) do
        expect(helper.format_date(Date.new(2026, 9, 1))).to eq("2026-09-01")
      end
    end

    it "renders the engine-shipped Slovak day.month.year format under :sk" do
      with_locale(:sk) do
        expect(helper.format_date(Date.new(2026, 9, 1))).to eq("01. 09. 2026")
      end
    end

    it "renders empty for a blank date" do
      expect(helper.format_date(nil)).to eq("")
    end
  end

  describe "#format_timestamp" do
    it "appends an explicit UTC label to an already-UTC moment" do
      expect(helper.format_timestamp(Time.utc(2026, 9, 27, 9, 53, 7)))
        .to eq("2026-09-27 09:53:07 UTC")
    end

    it "converts a non-UTC moment to UTC before formatting" do
      # 12:00 +03:00 IS 09:00 UTC — the label must be true, so the
      # conversion happens before the digits are rendered.
      expect(helper.format_timestamp(Time.new(2026, 9, 27, 12, 0, 0, "+03:00")))
        .to eq("2026-09-27 09:00:00 UTC")
    end

    it "renders empty for a blank timestamp" do
      expect(helper.format_timestamp(nil)).to eq("")
    end
  end
end
