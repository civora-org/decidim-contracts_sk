# frozen_string_literal: true

require_relative "contracts_sk/version"

module Decidim
  module ContractsSk
    class Error < StandardError; end

    # Fixed page size for the paginated listings (admin index and public
    # catalogue). A constant, not config: the listings render the same
    # pagination surface everywhere, so there is nothing to tune yet.
    CONTRACTS_PER_PAGE = 25
  end
end

require_relative "contracts_sk/contract_lifecycle"
require_relative "contracts_sk/role_resolver"
require_relative "contracts_sk/menu"

# The CRZ import ETL (ADR-008, civora-org/civora-platform#86): pure-Ruby
# layers over the transport seam — no Rails constants touched at load time
# (the mapper resolves the Contract model lazily, at call time). The
# upsert command lives in app/commands and reaches these through the
# autoloader.
require_relative "contracts_sk/crz_import/transport"
require_relative "contracts_sk/crz_import/mapper"
require_relative "contracts_sk/crz_import/client"
require_relative "contracts_sk/crz_import/sync"

require_relative "contracts_sk/engine" if defined?(Rails)
