# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Sends the morning CRZ deadline digest of ONE organization
    # (civora-org/civora-platform#202). Run by the host's scheduler through
    # `decidim_contracts_sk:crz_deadline_digest`.
    #
    # What: the organization's contracts in Contract.crz_attention (not
    # confirmed as filed in the CRZ, so not yet effective, with the deadline
    # overdue or within CrzDeadline::DUE_SOON_DAYS), the very set of the admin
    # home. To whom: the organization's confirmed, available admins plus the
    # users holding a stored :editor role there; never another
    # organization's users. Nothing due, nothing sent: no empty mail, no
    # per-person state to keep (the digest is a daily reminder, not a log).
    #
    # Fail-soft: one failing recipient is logged by class only (never an
    # address) and counted; the others still get their mail.
    class DeliverCrzDeadlineDigest
      # At most this many contracts are listed (most overdue first); the
      # total is carried in the mail's "and more" line.
      LIST_LIMIT = 20

      Summary = Data.define(:contracts, :recipients, :delivered, :failed)

      def self.call(...)
        new(...).call
      end

      def initialize(organization:, today: nil, logger: Rails.logger)
        @organization = organization
        @today = today || organization_today
        @logger = logger
      end

      def call
        due = Contract.where(organization: @organization).crz_attention(@today)
        total = due.count
        return Summary.new(contracts: 0, recipients: 0, delivered: 0, failed: 0) if total.zero?

        send_all(due.order(signed_on: :asc, id: :asc).limit(LIST_LIMIT).to_a, total)
      end

      # Confirmed, available admins and :editor role holders of THIS
      # organization.
      def recipients
        users = Decidim::User.where(organization: @organization).available.confirmed
        editor_ids = UserRole.where(decidim_organization_id: @organization.id, role: "editor")
                             .select(:decidim_user_id)
        users.where(admin: true).or(users.where(id: editor_ids))
      end

      private

      def send_all(contracts, total)
        users = recipients.to_a
        delivered = users.count { |user| deliver(user, contracts, total) }
        Summary.new(contracts: total, recipients: users.size, delivered: delivered, failed: users.size - delivered)
      end

      def deliver(user, contracts, total)
        CrzDeadlineDigestMailer.digest(user, @organization, contracts, total, today: @today).deliver_now
        true
      rescue StandardError => e
        @logger.error("[contracts_sk] crz deadline digest to user #{user.id} failed: #{e.class}")
        false
      end

      def organization_today
        zone = @organization.try(:time_zone)
        zone = (zone && ActiveSupport::TimeZone[zone]) || Time.zone
        zone.today
      end
    end
  end
end
