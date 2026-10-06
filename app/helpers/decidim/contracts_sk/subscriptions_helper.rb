# frozen_string_literal: true

module Decidim
  module ContractsSk
    # View helpers of the alert subscription pages (civora-org/civora-platform
    # #121). Needs DiscoverabilityHelper's contracts_meta_tags (mixed into the
    # public controllers through PublicCatalogue).
    module SubscriptionsHelper
      # Head of every subscription page: a title, and noindex. These pages are
      # utility pages (several carry a token in their URL), never search
      # results.
      def subscription_page_head(title)
        contracts_meta_tags(title: title, description: t("decidim.contracts_sk.subscriptions.form.intro"))
        content_for :header_snippets, tag.meta(name: "robots", content: "noindex")
      end
    end
  end
end
