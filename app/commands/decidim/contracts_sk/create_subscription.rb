# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Starts an e-mail alert subscription (civora-org/civora-platform#121):
    # normalizes the posted search through the catalogue's own query object,
    # applies the per-address cap and the duplicate rules, and creates an
    # UNCONFIRMED row with a fresh confirmation token. Sending the
    # confirmation e-mail is the caller's job (the controller), only for the
    # :created status.
    #
    #   result = CreateSubscription.call(organization:, email:, params:, locale:)
    #   result.status   # :created | :invalid | :already_confirmed | :limit
    #
    # The caller shows the SAME page for :created, :already_confirmed and
    # :limit, so the response never tells a stranger whether an address is
    # already subscribed. Only :invalid (a malformed address, or a search the
    # alerts cannot serve) is reported back.
    class CreateSubscription
      Result = Data.define(:status, :subscription, :token)

      def self.call(...)
        new(...).call
      end

      def initialize(organization:, email:, params:, locale:)
        @organization = organization
        @email = email
        @params = params
        @locale = locale
      end

      def call
        token = Subscription.generate_token
        subscription = build(token)
        return Result.new(:invalid, subscription, nil) unless subscription.valid?

        Subscription.transaction { persist(subscription, token) }
      end

      private

      attr_reader :organization, :email, :params, :locale

      def build(token)
        Subscription.new(organization: organization, email: email.to_s[0, Subscription::EMAIL_MAX_LENGTH + 1],
                         filter_params: filter_params, locale: locale, token_digest: Subscription.digest(token))
      end

      # The catalogue's normalization, without the sort (a digest is always
      # newest first): an invalid value is dropped, a reversed range swapped,
      # so the stored search is exactly what the catalogue would apply.
      def filter_params
        CatalogueQuery.new(scope: Contract.none, params: params).to_params.except("sort")
      end

      def persist(subscription, token)
        same_address = Subscription.where(organization: organization, email: subscription.email)
        same_search = same_address.detect { |other| other.filter_params == subscription.filter_params }

        return Result.new(:already_confirmed, same_search, nil) if same_search&.confirmed?

        # A pending duplicate is replaced (a resend: fresh token, fresh
        # expiry clock) and does not count toward the cap.
        same_search&.destroy!
        return Result.new(:limit, nil, nil) if same_address.count >= Subscription::MAX_PER_EMAIL

        subscription.save!
        Result.new(:created, subscription, token)
      end
    end
  end
end
