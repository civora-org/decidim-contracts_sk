# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Publishes a draft amendment of a published contract record
      # (M02-05-B, civora-org/civora-platform#65, ADR-006): the amendment's
      # snapshot is taken from the contract's CURRENT content fields and
      # frozen, making the amendment the record's newest public version
      # while the live fields stay the current one.
      #
      # Both gates are re-checked at execution time, fail-closed, INSIDE the
      # row locks — the TOCTOU doctrine of TransitionContract: the
      # permission layer's admission decision is request-start state, so a
      # stale one can neither publish a row twice nor publish onto a record
      # that has left the published state. The locks nest in one fixed
      # order — the parent contract first, then the amendment (the
      # amendment-only commands take no contract lock, so the order cannot
      # cycle) — and each lock reloads its row, so the guards read the
      # in-database state. contract.with_lock reloading the parent also
      # fixes the snapshot's read: the frozen content is serialized from
      # the row as it stands under the lock, never from the request-start
      # copy. The model's readonly? guard backs this up — a published
      # amendment is immutable at the model layer too.
      #
      # Everything commits atomically inside the one transaction the two
      # locks share: version, snapshot, state flip, published_at stamp and
      # the audit row — a failure at any step rolls the amendment back to
      # an untouched draft (the same doctrine as TransitionContract's
      # state-plus-audit atomicity). The version is defensive here:
      # CreateAmendment already sequences it, so it is only assigned when
      # missing (rows created outside the command layer) — and only INSIDE
      # the lock, since with_lock raises on a record carrying unpersisted
      # changes at entry (nothing may be assigned before it). The audit
      # payload shape follows the TransitionContract pattern (#59): action
      # "amendment.publish", polymorphic target = the amendment, explicit
      # organization/actor.
      #
      # The snapshot stores display-ready scalars on purpose: dates as ISO
      # strings and the amount as a plain decimal string — the frozen value
      # must JSON-serialize identically on every adapter and read back
      # exactly as written (keys are the model's SNAPSHOT_FIELDS).
      class PublishAmendment < Decidim::Command
        def initialize(amendment, user:)
          super()
          @amendment = amendment
          @user = user
        end

        def call
          contract.with_lock do
            amendment.with_lock do
              # Both fail-closed gates, read off the reloaded in-database
              # rows (see the class comment).
              return broadcast(:invalid) unless contract.published? && amendment.draft?

              publish!
            end
          end

          broadcast(:ok, amendment)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique,
               ActiveRecord::ReadOnlyRecord
          broadcast(:invalid)
        end

        private

        attr_reader :amendment, :user

        def contract
          amendment.contract
        end

        # The transaction's whole write: version (only when a draft carries
        # none — see the class comment), the frozen snapshot, the state flip,
        # the stamp, and the audit row. Runs inside the caller's locked
        # transaction, so its failure rolls the publication back with it.
        # Runs strictly after both reloads, so the guards above already saw
        # the in-database state and the version assignment below can never
        # trip with_lock's unpersisted-changes check.
        def publish!
          amendment.version ||= next_version
          amendment.update!(state: "published",
                            published_at: Time.current,
                            content_snapshot: content_snapshot)
          record_audit!
        end

        # Only reached when a draft row carries no version yet (see the
        # class comment); sequenced inside the caller's locked transaction
        # like CreateAmendment.
        def next_version
          contract.amendments.maximum(:version).to_i + 1
        end

        # The frozen data-dictionary field hash of the contract's live
        # content fields (keys = Amendment::SNAPSHOT_FIELDS), read off the
        # row as reloaded UNDER the lock — current content as of publish
        # time, not the request-start copy. Values are normalized to
        # display-ready scalars so the stored JSON is deterministic across
        # adapters (see the class comment).
        def content_snapshot
          {
            "subject_matter" => contract.subject_matter,
            "amount" => contract.amount&.to_s("F"),
            "currency" => contract.currency,
            "signed_on" => contract.signed_on&.to_fs(:db),
            "effective_from" => contract.effective_from&.to_fs(:db),
            "crz_url" => contract.crz_url
          }
        end

        # The audit row is written inside the caller's transaction, so its
        # failure rolls the publication back with it.
        def record_audit!
          AuditEvent.create!(action: "amendment.publish", target: amendment,
                             organization: amendment.organization, actor: user)
        end
      end
    end
  end
end
