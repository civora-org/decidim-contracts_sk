# frozen_string_literal: true

module Decidim
  module ContractsSk
    # A link from a contract record to a platform-level project/result
    # entity (M01-87, civora-org/civora-platform#87).
    #
    # Links are contract-scoped record content: tenancy derives through the
    # contract's organization (no organization column — the parties/
    # documents precedent) and the contract destroys them with itself
    # (Contract#links declares `dependent: :destroy`).
    #
    # The polymorphic target deliberately carries no database FK and may
    # dangle after the target's own deletion (the AuditEvent precedent):
    # `target` is optional at the model level, so a row whose target is
    # gone stays loadable — the admin surface flags it for cleanup, the
    # public catalogue hides it. What a target type means (label, URL) is
    # decided by the host through the config-time link_target_resolver seam
    # (lib/decidim/contracts_sk/link_targets.rb); the engine itself fixes
    # no target vocabulary.
    class ContractLink < ApplicationRecord
      belongs_to :contract

      # Optional on purpose: a persisted link whose target row has been
      # deleted must stay readable (dangling tolerance), and a fresh link
      # is validated for a target id at the form boundary instead.
      belongs_to :target, polymorphic: true, optional: true

      validates :target_type, presence: true
      validates :target_id, presence: true

      # Mirrors the migration's unique composite index
      # idx_contracts_sk_contract_links_on_contract_and_target: one link per
      # (contract, target) pair. The DB index is the backstop for concurrent
      # creates; this validation surfaces the conflict to the form layer.
      validates :target_id, uniqueness: { scope: %i[contract_id target_type] }
    end
  end
end
