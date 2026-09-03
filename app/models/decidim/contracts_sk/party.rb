# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A party on a contract record — the object of the contract (typically
    # the contracting municipality) and the contractor delivering it.
    #
    # Parties are contract-scoped: tenancy is derived through the contract's
    # organization, so there is no organization foreign key here
    # (civora-org/civora-platform#56).
    class Party < ApplicationRecord
      # Stored-string role vocabulary for the inclusion validator — frozen
      # so a captured validator reference cannot mutate the vocabulary.
      ROLES = %w[object contractor].freeze

      # Symbol => stored String mapping for the Rails enum, mirroring
      # Contract's STATE_VALUES style.
      ROLE_VALUES = ROLES.to_h { |role| [role, role] }.freeze

      belongs_to :contract

      validates :role, presence: true,
                       inclusion: { in: ROLES }
      validates :name, presence: true, length: { maximum: 255 }
      validates :ico, length: { is: 8 },
                      format: { with: /\A\d{8}\z/ },
                      allow_blank: true
      validates :address, length: { maximum: 255 }, allow_nil: true

      # Positional arguments: the Rails 7.2 enum API (the keyword form is
      # deprecated and removed in Rails 8). No default on either the column
      # or this enum: a party must state its role explicitly.
      enum :role, ROLE_VALUES
    end
  end
end
