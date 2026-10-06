# frozen_string_literal: true

module Decidim
  module ContractsSk
    # The two e-mails of the alert subscriptions (civora-org/civora-platform
    # #121), on Decidim's own mailer base and layout: the double opt-in
    # confirmation and the digest of newly published contracts.
    #
    # Every e-mail carries an unsubscribe link in the layout's footer slot
    # and the List-Unsubscribe / List-Unsubscribe-Post headers (RFC 2369 and
    # 8058: mail clients show their own one-click "Unsubscribe", which POSTs
    # to the same URL). The link is a signed id, so no raw token is kept.
    #
    # Escaping: the views interpolate with plain ERB (escaped) and never use
    # a `_html` translation or `html_safe` on a value that came from a
    # contract or from the reader's search. Parties are not rendered at all
    # (so no party without an IČO can appear). Subjects hold the
    # organization's name only.
    class SubscriptionMailer < Decidim::ApplicationMailer
      include Rails.application.routes.mounted_helpers

      helper Decidim::ContractsSk::ApplicationHelper
      helper Decidim::ContractsSk::CatalogueHelper

      def confirmation(subscription, token)
        compose(subscription, :confirmation) do
          @confirm_url = engine_url(:subscription_confirmation_url, token)
        end
      end

      def digest(subscription, contracts, total)
        compose(subscription, :digest) do
          @contracts = contracts
          @total = total
          @contract_urls = contracts.to_h { |contract| [contract.id, engine_url(:contract_url, contract)] }
          @more_url = engine_url(:contracts_url, subscription.filter_params.symbolize_keys) if total > contracts.size
        end
      end

      private

      def compose(subscription, kind)
        I18n.with_locale(subscription.locale) do
          prepare(subscription)
          yield
          mail(to: subscription.email,
               subject: t("decidim.contracts_sk.subscription_mailer.#{kind}.subject",
                          organization: organization_name(@organization)))
        end
      end

      # What every e-mail needs: the records, the search to restate, and the
      # unsubscribe link in both its places (the layout footer's slot reads
      # @unsubscribe_url; the headers are set here).
      def prepare(subscription)
        @subscription = subscription
        @organization = subscription.organization
        @query = CatalogueQuery.new(scope: Contract.none, params: subscription.filter_params)
        @unsubscribe_url = engine_url(:subscription_unsubscribe_url, subscription.unsubscribe_token)
        headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
        headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
      end

      # Absolute URL on the organization's host, in the subscriber's locale.
      def engine_url(helper, *args)
        options = args.extract_options!
        decidim_contracts_sk.public_send(helper, *args, **options, host: @organization.host,
                                                                   locale: @subscription.locale)
      end
    end
  end
end
