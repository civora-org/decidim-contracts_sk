# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A per-organization sequence behind internal contract numbers
    # (civora-org/civora-platform#211). One row per (organization, scope_key);
    # a yearly sequence uses a key such as "zmluvy:2026" (see .scope_key_for),
    # so a new year simply starts a new counter at 1.
    #
    # Gap-free numbering is NOT promised: a number handed out and then not
    # used (a rolled-back caller transaction aside, which rolls the counter
    # back with it) is not reclaimed.
    class ReferenceCounter < ApplicationRecord
      SCOPE_KEY_FORMAT = /\A[a-z0-9][a-z0-9_.:-]*\z/

      belongs_to :organization,
                 foreign_key: "decidim_organization_id",
                 class_name: "Decidim::Organization"

      validates :organization, presence: true
      validates :scope_key, presence: true
      validates :scope_key, length: { maximum: 100 },
                            format: { with: SCOPE_KEY_FORMAT },
                            uniqueness: { scope: :decidim_organization_id },
                            allow_blank: true
      validates :last_value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

      # "zmluvy" + 2026 => "zmluvy:2026".
      def self.scope_key_for(base, year)
        "#{base}:#{Integer(year)}"
      end

      # Hands out the next number of a sequence, creating the counter on first
      # use. The create races safely: the unique index makes the loser re-read
      # the winner's row instead of creating a second one.
      def self.next!(organization, scope_key)
        counter = find_or_create_counter!(organization, scope_key)
        counter.next!
      end

      def self.find_or_create_counter!(organization, scope_key)
        find_by(organization: organization, scope_key: scope_key) ||
          # A savepoint: on PostgreSQL a unique violation aborts the enclosing
          # transaction unless it is rolled back to a savepoint first.
          transaction(requires_new: true) { create!(organization: organization, scope_key: scope_key) }
      rescue ActiveRecord::RecordNotUnique
        where(organization: organization, scope_key: scope_key).take!
      end
      private_class_method :find_or_create_counter!

      # Increments under a row lock and returns the new value. `with_lock`
      # reloads the row once the lock is held, so a stale in-memory instance
      # (loaded before another request incremented) still yields a fresh,
      # never-repeated number.
      def next!
        with_lock do
          update!(last_value: last_value + 1)
          last_value
        end
      end
    end
  end
end
