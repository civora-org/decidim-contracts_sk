# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Config-seam spec for Decidim::ContractsSk.stale_after
# (civora-org/civora-platform#88, ADR-008 decision 4).
#
# Pins the safe default and the documented assignment shapes. The freshness
# comparison in ApplicationHelper#mirror_stale? normalizes the setting
# through #to_i, so hosts may assign Integer seconds or an
# ActiveSupport::Duration ("12.hours") — both are legal, and the seam
# behaves exactly like the role_resolver seam: config-time only.
# ---------------------------------------------------------------------------

require "spec_helper"

RSpec.describe Decidim::ContractsSk do
  describe "stale_after config seam (civora-org/civora-platform#88)" do
    after do
      # Restore the engine default so no example leaks an override into
      # later examples (the seam is a plain accessor, like role_resolver).
      described_class.stale_after = 172_800
    end

    it "defaults to 172800 seconds — 48 h, twice the recommended nightly sync cadence" do
      expect(described_class.stale_after).to eq(172_800)
    end

    it "accepts an ActiveSupport::Duration assignment" do
      described_class.stale_after = 12.hours

      # The helper compares through #to_i, so the Duration form normalizes
      # to the same seconds.
      expect(described_class.stale_after.to_i).to eq(12 * 3600)
    end
  end
end
