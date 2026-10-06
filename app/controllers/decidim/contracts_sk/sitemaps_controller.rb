# frozen_string_literal: true

module Decidim
  module ContractsSk
    # XML sitemap of the catalogue's contract pages (civora-org/civora-platform
    # #122): GET /sitemap.xml under the engine's mount. Read-only and
    # authentication-free like the catalogue.
    #
    # Scope: the SAME own-records scope as the open-data export and the Atom
    # feed (PublicCatalogue#open_data_scope): the current organization's
    # lifecycle-published records, CRZ mirrors left out. A mirror is a
    # link-only pointer at someone else's register, whose canonical page
    # lives at crz.gov.sk; listing it would ask search engines to index a
    # duplicate of that page under this organization's name. The mirror's
    # own page stays reachable and shareable (and is labelled "Externally
    # confirmed"); it is just not advertised. Drafts, archived records and
    # other organizations' records never appear.
    #
    # The protocol caps one file at 50 000 URLs: the oldest records come
    # first (stable ids), and a catalogue past the cap would need a sitemap
    # index, which is deliberately out of scope until one exists.
    class SitemapsController < Decidim::ContractsSk::ApplicationController
      include Decidim::ContractsSk::PublicCatalogue

      SITEMAP_LIMIT = 50_000

      def show
        @contracts = open_data_scope.reorder(:id).limit(SITEMAP_LIMIT).select(:id, :updated_at)
      end
    end
  end
end
