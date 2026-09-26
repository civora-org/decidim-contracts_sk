# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Config-seam spec for the contract link target resolver
# (M01-87, civora-org/civora-platform#87).
#
# Pins the safe defaults (nothing supported, nothing resolved), the
# documented assignment shapes and the fail-closed resolution contract of
# Decidim::ContractsSk.resolve_link_target. The seam behaves exactly like
# the role_resolver / stale_after seams: config-time only — every example
# restores the ambient values, so no override leaks into later examples.
# ---------------------------------------------------------------------------

require "spec_helper"

# Minimal link stand-in for the resolution examples: only what
# resolve_link_target reads. Kept at the top level (mirroring the
# permissions specs' SpecUser/SpecContract) so no constant leaks inside an
# example group.
SpecLink = Struct.new(:target_type, :target, keyword_init: true)

# Several examples deliberately hold several related expectations (the
# normalization and fail-closed matrices), and the resolver-argument capture
# example stretches past the line budget, exceeding the default limits.
# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength

RSpec.describe Decidim::ContractsSk do
  describe "supported_link_target_types config seam" do
    after do
      # Restore the engine default so no example leaks an override into
      # later examples (the seam is a plain accessor, like role_resolver).
      described_class.supported_link_target_types = []
    end

    it "defaults to the empty vocabulary — the standalone engine links nothing" do
      expect(described_class.supported_link_target_types).to eq([])
      expect(described_class.supported_link_target_types).to be_frozen
    end

    it "normalizes a host assignment to frozen Strings" do
      described_class.supported_link_target_types = [:"Decidim::Accountability::Result", "Decidim::ParticipatoryProcess"]

      expect(described_class.supported_link_target_types)
        .to eq(["Decidim::Accountability::Result", "Decidim::ParticipatoryProcess"])
      expect(described_class.supported_link_target_types).to all(be_a(String))
      expect(described_class.supported_link_target_types).to be_frozen
    end

    it "normalizes nil to the empty frozen vocabulary" do
      described_class.supported_link_target_types = nil

      expect(described_class.supported_link_target_types).to eq([])
      expect(described_class.supported_link_target_types).to be_frozen
    end
  end

  describe "link_target_resolver config seam" do
    after do
      described_class.link_target_resolver = ->(_link) { nil }
    end

    it "defaults to resolving nothing" do
      link = SpecLink.new(target_type: "Decidim::Accountability::Result", target: Object.new)
      described_class.supported_link_target_types = ["Decidim::Accountability::Result"]

      expect(described_class.link_target_resolver.call(link)).to be_nil
      expect(described_class.resolve_link_target(link)).to be_nil
    end
  end

  describe ".resolve_link_target" do
    let(:target) { Object.new }
    let(:resolver_result) { { label: "Result 12", url: "https://host/results/12" } }

    before do
      described_class.supported_link_target_types = ["Decidim::Accountability::Result"]
      described_class.link_target_resolver = ->(_link) { resolver_result }
    end

    after do
      described_class.link_target_resolver = ->(_link) { nil }
      described_class.supported_link_target_types = []
    end

    it "resolves a supported, present target through the seam" do
      link = SpecLink.new(target_type: "Decidim::Accountability::Result", target: target)

      expect(described_class.resolve_link_target(link)).to eq(
        label: "Result 12", url: "https://host/results/12"
      )
    end

    it "passes the link itself to the resolver" do
      received = nil
      described_class.link_target_resolver = lambda do |link|
        received = link
        resolver_result
      end
      link = SpecLink.new(target_type: "Decidim::Accountability::Result", target: target)

      described_class.resolve_link_target(link)

      expect(received).to eq(link)
    end

    it "hides a target whose type is outside the whitelist" do
      link = SpecLink.new(target_type: "Decidim::User", target: target)

      expect(described_class.resolve_link_target(link)).to be_nil
    end

    it "hides a dangling target (the polymorphic row is gone)" do
      link = SpecLink.new(target_type: "Decidim::Accountability::Result", target: nil)

      expect(described_class.resolve_link_target(link)).to be_nil
    end

    it "hides a link the resolver answers nil for" do
      described_class.link_target_resolver = ->(_link) { nil }
      link = SpecLink.new(target_type: "Decidim::Accountability::Result", target: target)

      expect(described_class.resolve_link_target(link)).to be_nil
    end

    it "hides a resolver result of the wrong shape" do
      described_class.link_target_resolver = ->(_link) { "Result 12" }
      link = SpecLink.new(target_type: "Decidim::Accountability::Result", target: target)

      expect(described_class.resolve_link_target(link)).to be_nil
    end

    it "hides a resolver result without a label" do
      described_class.link_target_resolver = ->(_link) { { label: "", url: "https://host" } }
      link = SpecLink.new(target_type: "Decidim::Accountability::Result", target: target)

      expect(described_class.resolve_link_target(link)).to be_nil
    end

    it "allows a label without a URL (renders as plain text)" do
      described_class.link_target_resolver = ->(_link) { { label: "Result 12", url: nil } }
      link = SpecLink.new(target_type: "Decidim::Accountability::Result", target: target)

      expect(described_class.resolve_link_target(link)).to eq(label: "Result 12", url: nil)
    end

    it "fails closed when the resolver raises (never leaks internals)" do
      described_class.link_target_resolver = ->(_link) { raise "host resolver bug" }
      link = SpecLink.new(target_type: "Decidim::Accountability::Result", target: target)

      expect(described_class.resolve_link_target(link)).to be_nil
    end

    it "answers nil for a blank link" do
      expect(described_class.resolve_link_target(nil)).to be_nil
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
