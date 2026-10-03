# frozen_string_literal: true

module Decidim
  module ContractsSk
    module CrzImport
      # One-off cleanup for mirrors imported before the sync was scoped to
      # the organization's own contracts (civora-org/civora-platform#145):
      # finds the organization's source="crz" records whose parties do not
      # carry its IČO and, only when confirmed, destroys them. Editorial
      # records (any other source) are never candidates.
      #
      # Destroying a contract takes its parties, documents, amendments and
      # links with it (Contract's dependent: :destroy); the audit trail
      # survives with dangling targets, as for every contract deletion.
      #
      # The Rails model is resolved at call time, like the rest of the
      # CrzImport layer (no Rails constants touched at load time).
      module Prune
        Result = Struct.new(:matched, :confirmed, keyword_init: true)

        def self.call(organization:, ico:, confirm: false)
          scope = candidates(organization, ico)
          matched = scope.count
          scope.find_each(&:destroy!) if confirm

          Result.new(matched: matched, confirmed: confirm)
        end

        def self.candidates(organization, ico)
          own = Party.where(ico: ico).select(:contract_id)
          Contract.where(organization: organization, source: Mapper::SOURCE).where.not(id: own)
        end
      end
    end
  end
end
