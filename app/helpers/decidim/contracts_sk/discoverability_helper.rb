# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Page titles, meta descriptions and Open Graph tags of the public pages
    # (civora-org/civora-platform#122). Everything goes through Decidim's own
    # meta-tag mechanism (Decidim::MetaTagsHelper#add_decidim_meta_tags, whose
    # values decidim-core's _head partial renders as <title>, description,
    # og:*/twitter:* tags): the helpers here only decide WHAT each page says.
    #
    # Privacy rules baked in:
    #
    # * a description names only the contractors that have an IČO (the same
    #   rule as the supplier links: a party without one is never profiled),
    #   and never the subject matter, which is free text a clerk typed;
    # * a mirrored CRZ record is labelled "Externally confirmed" in both its
    #   title and its description (ADR-002 rule 1).
    #
    # Needs ApplicationHelper's format_amount / imported_contract? and
    # FeedHelper's feed_organization_name (both mixed into the public
    # controllers' views) plus decidim-core's MetaTagsHelper.
    module DiscoverabilityHelper
      include Decidim::ContractsSk::FeedHelper

      # How many named suppliers a description carries: a snippet is about
      # 150 characters long, and a long list is no more useful in it.
      META_SUPPLIER_LIMIT = 3

      # Registers title, description and canonical URL with Decidim, and the
      # two tags Decidim does not render itself (see below).
      def contracts_meta_tags(title:, description:, url: nil)
        add_decidim_meta_tags(title: title, description: description, url: url)
        # decidim-core's _head renders the description only as og:/twitter:
        # tags and never as the plain <meta name="description"> search
        # engines read, and has no og:site_name: both come from here, the
        # description straight from Decidim's own accessor so the two never
        # differ.
        content_for :header_snippets, safe_join([
                                                  tag.meta(name: "description", content: decidim_meta_description),
                                                  tag.meta(property: "og:site_name", content: feed_organization_name)
                                                ], "\n")
      end

      # The catalogue: the organisation-wide intro, and the page number
      # from page 2 on so that paginated pages do not share one title. The
      # og:url is rebuilt from the normalized filters and the page, never
      # echoed from the request, so foreign query params never reach it.
      def catalogue_meta_tags(page)
        title = t("decidim.contracts_sk.contracts.index.title")
        title = "#{title} - #{t("decidim.contracts_sk.meta.page", page: page)}" if page > 1
        contracts_meta_tags(title: title, description: t("decidim.contracts_sk.contracts.index.intro"),
                            url: contracts_url(catalogue_meta_url_params(page)))
      end

      def contract_meta_tags(contract)
        title = t("decidim.contracts_sk.meta.contract.title", title: contract.title, reference: contract.reference)
        contracts_meta_tags(title: title, description: contract_meta_description(contract),
                            url: contract_url(contract))
        add_decidim_page_title(t("decidim.contracts_sk.provenance.badge")) if imported_contract?(contract)
      end

      # Reference, amount, contractors with an IČO; "Externally confirmed"
      # last for a CRZ mirror.
      def contract_meta_description(contract)
        meta = "decidim.contracts_sk.meta.contract"
        [
          t("#{meta}.reference", reference: contract.reference),
          (t("#{meta}.amount", amount: format_amount(contract.amount, contract.currency)) if contract.amount.present?),
          meta_suppliers_text(contract),
          (t("decidim.contracts_sk.provenance.badge") if imported_contract?(contract))
        ].compact_blank.join(". ")
      end

      def supplier_meta_tags(name:, ico:, count:)
        contracts_meta_tags(
          title: t("decidim.contracts_sk.meta.supplier.title", name: name, ico: ico),
          description: t("decidim.contracts_sk.meta.supplier.description", name: name, ico: ico, count: count),
          url: supplier_url(ico: ico)
        )
      end

      def statistics_meta_tags
        contracts_meta_tags(title: t("decidim.contracts_sk.statistics.show.title"),
                            description: t("decidim.contracts_sk.statistics.show.lead"),
                            url: statistics_url)
      end

      private

      def catalogue_meta_url_params(page)
        params = catalogue_query.to_params.symbolize_keys
        page > 1 ? params.merge(page: page) : params
      end

      # "Suppliers: A (IČO 1), B (IČO 2)" over the first contractors that
      # carry an IČO, in the association's order (the page's own parties list uses it too); nil when none does.
      def meta_suppliers_text(contract)
        suppliers = contract.parties.to_a.select { |party| party.role == "contractor" && party.ico.present? }
                            .first(META_SUPPLIER_LIMIT)
        return if suppliers.empty?

        list = suppliers.map do |party|
          t("decidim.contracts_sk.meta.contract.supplier", name: party.name, ico: party.ico)
        end
        t("decidim.contracts_sk.meta.contract.suppliers", suppliers: list.join(", "))
      end
    end
  end
end
