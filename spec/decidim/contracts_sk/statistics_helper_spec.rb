# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Offline specs for the statistics page's view helpers (civora-org/
# civora-platform#118): the supplier name's legal-form binding, the bar width
# and the locale-aware share. Synthetic names only.
# ---------------------------------------------------------------------------

require "spec_helper"

# rubocop:disable RSpec/MultipleExpectations
RSpec.describe Decidim::ContractsSk::StatisticsHelper do
  let(:view) do
    Class.new do
      include ActionView::Helpers::NumberHelper
      include Decidim::ContractsSk::ApplicationHelper
      include Decidim::ContractsSk::StatisticsHelper
    end.new
  end
  let(:nbsp) { " " }

  describe "#supplier_display_name" do
    it "binds the spaces of a spaced s. r. o. with non-breaking spaces" do
      expect(view.supplier_display_name("Stavba Demo s. r. o.")).to eq("Stavba Demo s.#{nbsp}r.#{nbsp}o.")
    end

    it "binds spol. s r. o. as one unit" do
      expect(view.supplier_display_name("Obchod Demo spol. s r. o."))
        .to eq("Obchod Demo spol.#{nbsp}s#{nbsp}r.#{nbsp}o.")
    end

    it "binds a. s., v. o. s. and k. s." do
      expect(view.supplier_display_name("Energie Demo a. s.")).to eq("Energie Demo a.#{nbsp}s.")
      expect(view.supplier_display_name("Právo Demo v. o. s.")).to eq("Právo Demo v.#{nbsp}o.#{nbsp}s.")
      expect(view.supplier_display_name("Servis Demo k. s.")).to eq("Servis Demo k.#{nbsp}s.")
    end

    it "keeps the ordinary space between the name and the suffix" do
      expect(view.supplier_display_name("Stavba Demo s. r. o.")).to start_with("Stavba Demo s.")
      expect(view.supplier_display_name("Stavba Demo s. r. o.")).to include("Demo s")
    end

    it "leaves names without a suffix and compact suffixes unchanged" do
      expect(view.supplier_display_name("Obec Ukážková")).to eq("Obec Ukážková")
      expect(view.supplier_display_name("Svetlá Demo, s.r.o.")).to eq("Svetlá Demo, s.r.o.")
      expect(view.supplier_display_name("Odpadové služby Demo a.s.")).to eq("Odpadové služby Demo a.s.")
    end

    it "only binds a suffix at the end of the name" do
      expect(view.supplier_display_name("a. s. Demo Group")).to eq("a. s. Demo Group")
    end

    it "tolerates nil" do
      expect(view.supplier_display_name(nil)).to eq("")
    end
  end

  describe "#bar_percent" do
    it "is zero for zero, proportional otherwise and never below the minimum for a non-zero value" do
      expect(view.bar_percent(0, 10)).to eq(0)
      expect(view.bar_percent(5, 10)).to eq(50.0)
      expect(view.bar_percent(1, 1000)).to eq(described_class::MIN_BAR_PERCENT)
      expect(view.bar_percent(3, 0)).to eq(0)
    end

    it "draws sub-one values (amounts below 1) instead of rounding them to nothing" do
      expect(view.bar_percent(BigDecimal("0.5"), BigDecimal("0.5"))).to eq(100.0)
      expect(view.bar_percent(BigDecimal("0.25"), BigDecimal("0.5"))).to eq(50.0)
      expect(view.bar_percent(BigDecimal("0.001"), BigDecimal("0.5"))).to eq(described_class::MIN_BAR_PERCENT)
      expect(view.bar_percent(BigDecimal("0"), BigDecimal("0.5"))).to eq(0)
    end
  end

  describe "#share_percent" do
    it "uses the locale's separator and a non-breaking space in sk" do
      I18n.with_locale(:sk) { expect(view.share_percent(1, 3)).to eq("33,3#{nbsp}%") }
      I18n.with_locale(:en) { expect(view.share_percent(1, 3)).to eq("33.3%") }
      I18n.with_locale(:en) { expect(view.share_percent(1, 0)).to eq("0.0%") }
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations
