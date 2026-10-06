# frozen_string_literal: true

module Decidim
  module ContractsSk
    # E-mail alerts for new contracts matching a catalogue search
    # (civora-org/civora-platform#121): the public, anonymous side. No
    # sign-in is required (and a signed-in visitor is treated exactly like an
    # anonymous one: the address is confirmed either way).
    #
    # Flow: #create stores an UNCONFIRMED subscription and e-mails a
    # confirmation link; the link opens #confirmation, a page with a button,
    # and only its POST (#confirm) confirms, so a mail scanner that opens the
    # link cannot opt anybody in. Every e-mail carries an unsubscribe link
    # that works the same way (#cancellation page, #unsubscribe POST deletes
    # the row); #unsubscribe also answers the one-click POST that mail
    # clients send for the List-Unsubscribe-Post header (no CSRF token there:
    # the signed token in the URL is the credential).
    #
    # Privacy: the response to #create never reveals whether an address is
    # already subscribed (same page for a new, a confirmed and a capped
    # address); nothing about the address or the IP is stored or logged; the
    # pages carry the token in the URL, so they are noindex, no-store and
    # send no Referer. Every token lookup is scoped to the current
    # organization.
    class SubscriptionsController < Decidim::ContractsSk::ApplicationController
      include Decidim::ContractsSk::PublicCatalogue

      helper Decidim::ContractsSk::CatalogueHelper
      helper Decidim::ContractsSk::SubscriptionsHelper

      # The one-click unsubscribe POST of a mail client has no session and no
      # CSRF token; the signed token in the URL authorizes it.
      skip_forgery_protection only: :unsubscribe

      before_action :private_page_headers
      before_action :load_confirmation_subscription, only: %i[confirmation confirm]
      before_action :load_unsubscribe_subscription, only: %i[cancellation unsubscribe]

      def new
        # No sort: a digest is always newest first.
        @query = catalogue_query.with(sort: nil)
        @email = nil
      end

      def create
        @query = posted_query
        return render_message(:throttled, :too_many_requests) unless allowed_by_throttle?

        result = CreateSubscription.call(organization: current_organization, email: posted_email_param,
                                         params: posted_filters, locale: I18n.locale.to_s)
        case result.status
        when :invalid then render_invalid(result)
        when :created then send_confirmation(result)
        else render_message(:sent) # :already_confirmed, :limit: indistinguishable on purpose
        end
      end

      def confirmation
        @query = CatalogueQuery.new(scope: Contract.none, params: @subscription.filter_params)
      end

      def confirm
        case @subscription.confirm!
        when :expired then render_message(:invalid_link, :not_found)
        else render_message(:confirmed)
        end
      end

      def cancellation; end

      def unsubscribe
        @subscription.destroy!
        render_message(:unsubscribed)
      end

      private

      def allowed_by_throttle?
        SubscriptionThrottle.default.allow?(email: posted_email, ip: request.remote_ip)
      end

      def private_page_headers
        response.headers["Cache-Control"] = "no-store"
        response.headers["Referrer-Policy"] = "no-referrer"
      end

      # A String or nothing: an array or hash param is no address.
      def posted_email_param
        params[:email].is_a?(String) ? params[:email] : ""
      end

      def posted_email
        posted_email_param.strip.downcase
      end

      # Only the catalogue's own filter keys, and never the sort (a digest is
      # always newest first), from the POST body.
      def posted_filters
        request.request_parameters.slice(*(CatalogueQuery::PARAM_KEYS - [:sort]).map(&:to_s))
      end

      def posted_query
        CatalogueQuery.new(scope: Contract.none, params: posted_filters)
      end

      def render_invalid(result)
        @email = result.subscription.email
        @error = result.subscription.errors.key?(:filter_params) ? :search : :email
        render :new, status: :unprocessable_entity
      end

      # The confirmation goes out synchronously (deliver_now): the raw token
      # must not be written into a job queue. A failure removes the row again
      # and says so, instead of promising a mail that was never sent.
      def send_confirmation(result)
        SubscriptionMailer.confirmation(result.subscription, result.token).deliver_now
        render_message(:sent)
      rescue StandardError => e
        result.subscription.destroy
        Rails.logger.error("[contracts_sk] subscription confirmation mail failed: #{e.class}")
        render_message(:unavailable, :service_unavailable)
      end

      def render_message(key, status = :ok)
        @message = key
        render :message, status: status
      end

      def load_confirmation_subscription
        @subscription = scoped_subscriptions.find_by_token(params[:token])
        # An expired, still unconfirmed row is as good as gone: purge it now.
        if @subscription&.expired?
          @subscription.destroy
          @subscription = nil
        end
        render_message(:invalid_link, :not_found) unless @subscription
      end

      def load_unsubscribe_subscription
        @subscription = scoped_subscriptions.find_by_unsubscribe_token(params[:token])
        render_message(:invalid_link, :not_found) unless @subscription
      end

      def scoped_subscriptions
        Subscription.where(organization: current_organization)
      end
    end
  end
end
