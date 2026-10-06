# frozen_string_literal: true

module Decidim
  module ContractsSk
    # An e-mail alert subscription (civora-org/civora-platform#121): one
    # address watching one catalogue search. Anonymous (no account) and
    # double opt-in: a row is created unconfirmed, nothing is ever sent to it
    # except the confirmation e-mail, and it is purged when the link is not
    # used within CONFIRMATION_TTL.
    #
    # Data minimisation: see the migration. Unsubscribing destroys the row.
    #
    # Two kinds of token, on purpose:
    # * the CONFIRMATION token is random (256 bit) and only its SHA-256
    #   digest is stored; the raw value exists in the confirmation e-mail
    #   alone;
    # * the UNSUBSCRIBE token is a signed id (find_signed, purpose-bound),
    #   so every later e-mail can carry one although no raw token is kept.
    #   It does not expire (a resident must always be able to leave) and is
    #   invalidated only by deleting the row or rotating the host's
    #   secret_key_base.
    class Subscription < ApplicationRecord
      # An unconfirmed subscription is purged this long after its creation.
      CONFIRMATION_TTL = 48.hours
      # Active subscriptions (pending or confirmed) per address and
      # organization: bounds storage and mail from one address.
      MAX_PER_EMAIL = 5
      EMAIL_MAX_LENGTH = 254
      UNSUBSCRIBE_PURPOSE = :contracts_sk_unsubscribe
      # A pragmatic address shape (RFC 5322's atom characters, a dotted
      # domain of letter/digit/hyphen labels): no spaces, quotes, brackets,
      # control characters or second @, so a value that is not an address
      # (an array's inspect string, a header-injection attempt) never passes.
      EMAIL_FORMAT = %r{\A[\p{L}\p{N}.!#$%&'*+/=?^_`{|}~-]+@[\p{L}\p{N}-]+(\.[\p{L}\p{N}-]+)+\z}

      belongs_to :organization, foreign_key: "decidim_organization_id",
                                class_name: "Decidim::Organization", optional: false

      normalizes :email, with: ->(email) { email.to_s.strip.downcase }

      validates :email, presence: true, length: { maximum: EMAIL_MAX_LENGTH }
      validates :email, format: { with: EMAIL_FORMAT }, if: -> { email.to_s.length <= EMAIL_MAX_LENGTH }
      validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }
      validates :token_digest, presence: true, uniqueness: true
      validate :filters_are_alertable

      scope :confirmed, -> { where.not(confirmed_at: nil) }
      scope :pending, -> { where(confirmed_at: nil) }
      # Unconfirmed and older than the TTL at `now`.
      scope :expired, ->(now = Time.current) { pending.where(created_at: ..(now - CONFIRMATION_TTL)) }

      # A fresh random confirmation token (the only raw token there is).
      def self.generate_token
        SecureRandom.urlsafe_base64(32)
      end

      def self.digest(token)
        OpenSSL::Digest::SHA256.hexdigest(token.to_s)
      end

      # The subscription a raw confirmation token belongs to, or nil. The
      # lookup is by digest, so a tampered token matches nothing.
      def self.find_by_token(token)
        return if token.blank?

        find_by(token_digest: digest(token))
      end

      # The subscription an unsubscribe token (signed id) belongs to, or nil
      # for a tampered, foreign-purpose or already-deleted one.
      def self.find_by_unsubscribe_token(token)
        return if token.blank?

        find_signed(token, purpose: UNSUBSCRIBE_PURPOSE)
      end

      # Deletes the expired unconfirmed rows; returns how many went.
      def self.purge_expired(now = Time.current)
        expired(now).delete_all
      end

      def unsubscribe_token
        signed_id(purpose: UNSUBSCRIBE_PURPOSE)
      end

      def confirmed?
        confirmed_at.present?
      end

      def expired?(now = Time.current)
        !confirmed? && created_at <= now - CONFIRMATION_TTL
      end

      # Confirms under the row lock (the double-opt-in step another request
      # can race): :confirmed, :already_confirmed, or :expired (the row is
      # deleted). The delivery window starts at the confirmation, so nothing
      # published before it is ever mailed.
      def confirm!(now = Time.current)
        with_lock do
          next :already_confirmed if confirmed?

          if expired?(now)
            destroy!
            next :expired
          end

          update!(confirmed_at: now, last_notified_at: now)
          :confirmed
        end
      end

      private

      # Alerts cover the organization's own records only (the feed's scope),
      # so a search restricted to CRZ mirrors could never match.
      def filters_are_alertable
        errors.add(:filter_params, :invalid) unless filter_params.is_a?(Hash)
        errors.add(:filter_params, :unsupported_source) if filter_params.is_a?(Hash) && filter_params["source"] == "crz"
      end
    end
  end
end
