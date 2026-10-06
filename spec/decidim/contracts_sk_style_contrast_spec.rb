# frozen_string_literal: true

require "spec_helper"

# WCAG 2.1 AA contrast guard for the engine-owned `.cs-` style partials
# (civora-org/civora-platform#133). The grey #8f9db0 sat at 2.76:1 on white;
# it must not come back as a text colour or as a graphic fill. Pure file
# parsing: ERB tags are stripped, so no DB or host is needed.
RSpec.describe "engine style partials: colour contrast" do # rubocop:disable RSpec/DescribeClass
  # Values known to fail on white (below 3:1 for graphics, below 4.5:1 for text).
  known_failing = %w[#8f9db0].freeze
  partials = Dir[File.expand_path("../../app/views/decidim/contracts_sk/shared/_*styles.html.erb", __dir__)]

  def css_of(path)
    File.read(path).gsub(/<%.*?%>/m, "").gsub(%r{/\*.*?\*/}m, "")
  end

  def luminance(hex)
    r, g, b = hex.delete("#").scan(/../).map do |pair|
      v = pair.hex / 255.0
      v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4
    end
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def ratio(one, two)
    lo, hi = [luminance(one), luminance(two)].minmax
    (hi + 0.05) / (lo + 0.05)
  end

  def hex_of(value)
    value = value.strip.downcase
    return value if value.match?(/\A#\h{6}\z/)

    "##{value.delete("#").chars.map { |c| c * 2 }.join}" if value.match?(/\A#\h{3}\z/)
  end

  it "finds the style partials" do
    expect(partials.size).to be >= 3
  end

  partials.each do |path|
    describe File.basename(path) do
      it "never uses a known failing colour in any declaration" do
        found = css_of(path).scan(/#\h{3,6}\b/).map(&:downcase) & known_failing
        expect(found).to be_empty
      end

      it "keeps every literal `color:` at 4.5:1 on white and on the #f1f4f8 tint" do
        literals = css_of(path).scan(/(?<![-\w])color:\s*(#\h{3,6})\s*[;}]/).flatten.filter_map { |v| hex_of(v) }.uniq
        weak = literals.select { |c| ratio(c, "#ffffff") < 4.5 || ratio(c, "#f1f4f8") < 4.5 }
        expect(weak).to be_empty
      end
    end
  end
end
