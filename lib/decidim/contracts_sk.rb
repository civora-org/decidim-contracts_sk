# frozen_string_literal: true

require_relative "contracts_sk/version"

module Decidim
  module ContractsSk
    class Error < StandardError; end

    # Fixed page size for the paginated listings (admin index and public
    # catalogue). A constant, not config: the listings render the same
    # pagination surface everywhere, so there is nothing to tune yet.
    CONTRACTS_PER_PAGE = 25

    # The 8-digit IČO, defined once (party validation, the supplier route
    # constraint, the supplier controller and helper). The unanchored
    # pattern is what a route constraint needs (Rails refuses anchors
    # there); the anchored format is what everything else matches against.
    ICO_PATTERN = /\d{8}/
    ICO_FORMAT = /\A\d{8}\z/ # the same pattern, anchored (kept literal: Party's spec pins it)
  end
end

require_relative "contracts_sk/contract_lifecycle"
require_relative "contracts_sk/role_resolver"
require_relative "contracts_sk/self_review"
require_relative "contracts_sk/stale_after"
require_relative "contracts_sk/notification_candidates"
require_relative "contracts_sk/transition_notification"
require_relative "contracts_sk/crz_deadline"
require_relative "contracts_sk/link_targets"
require_relative "contracts_sk/crz_scope"
require_relative "contracts_sk/menu"

# The CRZ import ETL (ADR-008, civora-org/civora-platform#86): pure-Ruby
# layers over the transport seam — no Rails constants touched at load time
# (the mapper resolves the Contract model lazily, at call time). The
# upsert command lives in app/commands and reaches these through the
# autoloader.
require_relative "contracts_sk/crz_import/transport"
require_relative "contracts_sk/crz_import/mapper"
require_relative "contracts_sk/crz_import/client"
require_relative "contracts_sk/crz_import/filing_comparison"
require_relative "contracts_sk/crz_import/filing_lookup"
require_relative "contracts_sk/crz_import/sync"
require_relative "contracts_sk/crz_import/prune"
require_relative "contracts_sk/crz_import/backfill_published_on"

require_relative "contracts_sk/engine" if defined?(Rails)
