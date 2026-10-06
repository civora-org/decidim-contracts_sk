# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Delivers the e-mail alert digests of one organization
    # (civora-org/civora-platform#121). Run by the host's scheduler through
    # `decidim_contracts_sk:subscriptions:deliver` (docs/search-alerts.md).
    #
    # For every CONFIRMED subscription: the organization's own published
    # contracts (Contract.open_data, the scope of the export and the feed)
    # that entered the catalogue after the subscription's last_notified_at
    # and match its stored filters, evaluated by the catalogue's own
    # CatalogueQuery. One mail per subscription per run, at most
    # DIGEST_LIMIT contracts listed (newest first) and the total counted, so
    # a CRZ-sized batch publish is one mail, not hundreds. Nothing matching,
    # nothing sent.
    #
    # No duplicates: each subscription is handled under its row lock, and
    # last_notified_at moves to the window's end only after the mail left, so
    # a second run (or a concurrent one) finds an empty window. The window's
    # end is `now` minus SETTLE, so a record whose publishing transaction was
    # still committing is picked up by the next run, not skipped.
    #
    # Fail-soft: one subscription's failure (SMTP, a vanished row) is logged
    # by class and subscription id only (never the address or a payload),
    # counted, and does not stop the run; its window stays open, so the next
    # run retries it. Expired unconfirmed rows are purged first.
    class DeliverSubscriptionDigests
      DIGEST_LIMIT = 20
      SETTLE = 1.minute

      Summary = Data.define(:purged, :checked, :delivered, :failed)

      def self.call(...)
        new(...).call
      end

      def initialize(organization:, now: Time.current, logger: Rails.logger)
        @organization = organization
        @now = now
        @logger = logger
        @counts = { checked: 0, delivered: 0, failed: 0 }
      end

      def call
        purged = Subscription.purge_expired(@now)
        Subscription.confirmed.where(organization: @organization).find_each { |subscription| process(subscription) }
        Summary.new(purged: purged, **@counts)
      end

      private

      def cutoff
        @cutoff ||= @now - SETTLE
      end

      def process(subscription)
        @counts[:checked] += 1
        subscription.with_lock { deliver(subscription) }
      rescue ActiveRecord::RecordNotFound
        # Unsubscribed while the run was going: nothing to do.
      rescue StandardError => e
        @counts[:failed] += 1
        @logger.error("[contracts_sk] subscription #{subscription.id} digest failed: #{e.class}")
      end

      def deliver(subscription)
        return unless subscription.confirmed? && window_start(subscription) < cutoff

        send_digest(subscription)
        subscription.update!(last_notified_at: cutoff)
      end

      # One mail with the newest DIGEST_LIMIT matches and the total, or none.
      def send_digest(subscription)
        query = CatalogueQuery.new(scope: new_contracts(subscription), params: subscription.filter_params,
                                   time_zone: time_zone)
        total = query.relation.count
        return if total.zero?

        SubscriptionMailer.digest(subscription, query.results.limit(DIGEST_LIMIT).to_a, total).deliver_now
        @counts[:delivered] += 1
      end

      # Confirmation stamps last_notified_at; the fallback only guards a row
      # written by hand.
      def window_start(subscription)
        subscription.last_notified_at || subscription.confirmed_at
      end

      # Published after the last delivered window, up to and including its end.
      def new_contracts(subscription)
        Contract.open_data(@organization)
                .where(Contract.arel_table[:published_at].gt(window_start(subscription)))
                .where(published_at: ..cutoff)
      end

      def time_zone
        zone = @organization.try(:time_zone)
        (zone && ActiveSupport::TimeZone[zone]) || Time.zone
      end
    end
  end
end
