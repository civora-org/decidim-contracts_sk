# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Base view helper for the Decidim ContractsSk module.
    #
    # Carries the public catalogue's CRZ-mirror provenance predicates
    # (civora-org/civora-platform#88): ADR-002 rule 1 makes the engine's
    # imported records "externally confirmed" data — never a legal
    # publication — and ADR-008 decisions 4/6 require a freshness signal
    # that never implies real-time accuracy.
    module ApplicationHelper
      # True when the record is a CRZ metadata mirror created by the import
      # ETL (ADR-008) rather than an editorial record. Drives every
      # provenance-labelled render in the catalogue; editorial records are
      # never labelled.
      def imported_contract?(contract)
        contract.source == "crz"
      end

      # True when a mirrored record must carry the stale notice (ADR-008
      # decision 4): the last import was stamped "failed" (the engine-side
      # stale-fallback signal — the record kept its last-good mirror data
      # but a re-import could not prove it current, docs/crz-import.md), or
      # the mirror's imported_at is blank (a crz-sourced row without a
      # timestamp cannot prove freshness — fail closed), or the timestamp
      # is older than the configurable Decidim::ContractsSk.stale_after
      # threshold (default 48 h — twice the recommended nightly sync
      # cadence). The comparison normalizes the setting through #to_i, so
      # hosts may configure Integer seconds or an ActiveSupport::Duration.
      #
      # Time.current (not Time.now) keeps the comparison in the Decidim
      # application time zone.
      def mirror_stale?(contract)
        return false unless imported_contract?(contract)
        return true if contract.import_status == "failed"
        return true if contract.imported_at.blank?

        contract.imported_at < Decidim::ContractsSk.stale_after.to_i.seconds.ago
      end
    end
  end
end
