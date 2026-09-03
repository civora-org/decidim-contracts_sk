# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A numbered revision of a contract record: (contract, version) is unique
    # and version is a positive integer.
    #
    # Minimal for now (civora-org/civora-platform#57): records stay mutable
    # and there is no sequence or enum machinery — amendment immutability,
    # version sequencing and the public version history arrive with
    # M02-05-B (civora-org/civora-platform#65). Like Party, tenancy is
    # derived through the contract's organization.
    class Amendment < ApplicationRecord
      belongs_to :contract

      validates :version, presence: true,
                          numericality: { only_integer: true, greater_than: 0 },
                          uniqueness: { scope: :contract_id }
      validates :summary, presence: true, length: { maximum: 255 }
    end
  end
end
