# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Atom feed of the newest published contracts (civora-org/civora-platform
    # #120): GET /feed.atom, honouring the catalogue's filters over the SAME
    # own-records scope as the open-data export (PublicCatalogue#open_data_scope
    # — CRZ mirrors are link-only pointers to someone else's register and are
    # never re-published, here as little as in the export). The reader's sort
    # is ignored: a feed is "what is new", always newest first, capped at
    # FEED_LIMIT entries. Read-only and authentication-free like the
    # catalogue. No explicit caching headers: Rack::ETag (host middleware)
    # digests the small body, which is all a feed reader needs.
    class FeedsController < Decidim::ContractsSk::ApplicationController
      include Decidim::ContractsSk::PublicCatalogue

      FEED_LIMIT = 50

      helper Decidim::ContractsSk::CatalogueHelper
      helper Decidim::ContractsSk::FeedHelper

      def show
        # with(sort:) overrides whatever sort the reader passed; the derived
        # query's to_params then carries no sort, so every URL built from it
        # (self link, ids) is independent of it.
        @query = build_catalogue_query(open_data_scope).with(sort: CatalogueQuery::DEFAULT_SORT)
        @contracts = @query.results.limit(FEED_LIMIT).to_a
      end
    end
  end
end
