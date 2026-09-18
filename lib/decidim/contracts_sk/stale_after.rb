# frozen_string_literal: true

module Decidim
  # Engine for Slovak public contracts workflow and catalogue.
  module ContractsSk
    # Config-time freshness threshold for CRZ-mirrored catalogue records
    # (ADR-008 decision 4): a mirror is presented as stale once its last
    # successful sync (imported_at) is older than this setting, or when the
    # import stamped import_status="failed" (docs/crz-import.md's
    # stale-fallback signal). The public UI never implies real-time
    # accuracy — the threshold only decides when the stale notice appears.
    #
    # The host assigns +Decidim::ContractsSk.stale_after+ in an initializer
    # at config time, mirroring the role_resolver seam. Both Integer seconds
    # and ActiveSupport::Duration are legal assignments ("48.hours"); every
    # comparison normalizes through #to_i, so either shape works. The default
    # is 172_800 seconds (48 h = 2x the recommended nightly sync cadence from
    # docs/crz-import.md): a mirror misses at most one extra sync cycle
    # before the catalogue starts warning readers.
    #
    # Config-time only: never mutate this setting at request time.
    class << self
      attr_accessor :stale_after
    end

    self.stale_after = 172_800
  end
end
