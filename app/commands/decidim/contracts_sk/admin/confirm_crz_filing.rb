# frozen_string_literal: true

module Decidim
  module ContractsSk
    module Admin
      # Confirms that an editorial contract was filed in the CRZ and links the
      # official record (civora-org/civora-platform#125, the round trip after
      # the manual handoff of #74/ADR-002): the editor names the CRZ id, the
      # engine verifies the official record through the ekosystem feed
      # (read-only, CrzImport::FilingLookup) and, when it matches, stamps the
      # confirmation on the editorial record. The record stays editorial
      # (source never changes) — it becomes the canonical, linked record of
      # the CRZ id, which the sync then leaves alone (UpsertContract :linked).
      #
      # Order of work:
      # 1. Pre-lock, request-shaped refusals: the editor role, a configured
      #    organization IČO, the reason's length cap.
      # 2. The network fetch (FilingLookup) — ALWAYS outside any lock, so a
      #    slow or dead source never holds a row lock. A failed or empty
      #    fetch changes nothing and writes no audit row.
      # 3. The in-lock decision on the RELOADED row (with_lock reloads — the
      #    #69 TOCTOU doctrine, no pre-lock read or stale caller copy ever
      #    admits a write): editorial source, published state, not already
      #    filed, the preview's checksum token still equal to the fresh
      #    payload's checksum (else :stale — the official record changed
      #    since the editor looked), the comparison re-run against the
      #    row as it is NOW, the reason rule, and the id being free.
      #
      # Reason rule: any comparison row that is not a :match (mismatch OR
      # unverifiable) demands a stripped, non-blank reason of at most
      # MAX_REASON_LENGTH characters — the editor's override, stored in
      # crz_filing_reason and audited as "contract.crz_filed_override". A
      # clean match takes NO reason (a reason on a full match is refused, the
      # TransitionContract reason-shape doctrine) and audits as
      # "contract.crz_filed". Hard refusals (no override possible): no
      # configured IČO, record out of the organization's scope, CRZ status
      # cancelled/withdrawn (FilingLookup).
      #
      # Writes (one transaction under the contract's lock): crz_url
      # (the canonical CRZ template), crz_filed_at, source_id,
      # crz_published_on, crz_filing_reason and the audit row — all or
      # nothing. These are system fields, never form-writable.
      #
      # Mirror absorption (Gate-1 decision D5-B): the unique
      # (organization, source_id) index means a CRZ mirror that the sync
      # already imported under this id would block the claim. Lock order is
      # CONTRACT FIRST, THEN MIRROR (the only place two contract rows are
      # locked, so no inverse order exists to deadlock against). A PRISTINE
      # mirror (no amendments, links or documents — nothing an editor made
      # of it) is destroyed and the editorial record claims the id; a
      # "contract.crz_mirror_absorbed" audit row records it. Its audit
      # target is the EDITORIAL record: the mirror row no longer exists, and
      # a dangling target would render as "record no longer exists" and
      # drop out of the per-contract trail filter, whereas the claiming
      # record is the one the trail should explain (the destroyed mirror's
      # own import rows keep their dangling targets, as for every contract
      # deletion). A non-pristine mirror, or another editorial record
      # holding the id, refuses with :already_linked — resolved manually
      # (docs/crz-import.md). A concurrent claim that still slips through
      # trips the unique index (RecordNotUnique), rescued to the same
      # :already_linked.
      #
      # Broadcasts (bare symbols, for the controller's flash mapping):
      #   on(:ok)      { |outcome| } — :filed | :filed_override
      #   on(:invalid) { |reason| }  — :not_found, :failed, :not_configured,
      #     :out_of_scope, :withdrawn, :stale, :reason_required,
      #     :reason_rejected, :already_filed, :not_fileable, :already_linked
      #
      # Cop note: the class stays deliberately cohesive — the ordered guard
      # chain and the lock doctrine are one contract, and splitting it would
      # scatter the in-lock decision rather than simplify it.
      # rubocop:disable Metrics/ClassLength
      class ConfirmCrzFiling < Decidim::Command
        MAX_REASON_LENGTH = TransitionContract::MAX_REASON_LENGTH

        AUDIT_FILED = "contract.crz_filed"
        AUDIT_FILED_OVERRIDE = "contract.crz_filed_override"
        AUDIT_MIRROR_ABSORBED = "contract.crz_mirror_absorbed"

        # Internal control flow: an in-lock refusal unwinds the transaction
        # (nothing was written before any refusal, so the rollback is a
        # no-op) and carries the broadcast reason out.
        class Refusal < StandardError
          attr_reader :reason

          def initialize(reason)
            super(reason.to_s)
            @reason = reason
          end
        end

        # +checksum+ is the token the preview rendered (Mapper checksum of
        # the payload the editor compared); +client+ is the injection seam
        # for the verification fetch (specs stub it at its exact boundary).
        # rubocop:disable Metrics/ParameterLists
        def initialize(contract, crz_id:, checksum:, user:, reason: nil, client: nil)
          super()
          @contract = contract
          @crz_id = crz_id.to_s.strip
          @checksum = checksum.to_s
          @user = user
          @reason = reason
          @client = client
        end
        # rubocop:enable Metrics/ParameterLists

        def call
          broadcast(:ok, file_locked(verified_record))
        rescue Refusal => e
          broadcast(:invalid, e.reason)
        rescue ActiveRecord::RecordNotUnique
          broadcast(:invalid, :already_linked)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
          broadcast(:invalid, :not_fileable)
        end

        private

        attr_reader :contract, :crz_id, :checksum, :user, :reason

        # The pre-lock phase: request-shaped refusals that depend on no row
        # state (the editor role — defense in depth behind the permission
        # layer, fail-closed — and the reason's length cap), then the
        # network fetch, outside any lock. Returns the mapped CRZ record or
        # raises the Refusal that ends the command.
        def verified_record
          raise Refusal, :not_fileable unless editor?
          raise Refusal, :reason_rejected if normalized_reason.length > MAX_REASON_LENGTH

          lookup = CrzImport::FilingLookup.call(crz_id: crz_id, organization: contract.organization,
                                                client: @client)
          raise Refusal, lookup.refusal unless lookup.ok?

          lookup.record
        end

        def editor?
          Array(Decidim::ContractsSk.role_resolver.call(user, {})).include?(:editor)
        end

        def normalized_reason
          @normalized_reason ||= reason.to_s.strip
        end

        # The locked decision + writes; returns the ok outcome symbol, or
        # raises Refusal (rolling the transaction back, nothing written).
        def file_locked(record)
          contract.with_lock { decide_and_write(record) }
        end

        # The in-lock body, in guard order; returns the ok outcome.
        def decide_and_write(record)
          guard_row!
          guard_checksum!(record)
          comparison = CrzImport::FilingComparison.new(contract: contract, record: record)
          guard_reason!(comparison)
          mirror = claimable_mirror!(record)

          write_filing!(record, mirror)
          outcome = comparison.all_match? ? :filed : :filed_override
          record_audit!(outcome)
          outcome
        end

        # The row-state guards, read from the reloaded row.
        def guard_row!
          raise Refusal, :already_filed if contract.crz_filed_at.present?
          raise Refusal, :not_fileable unless fileable_row?
        end

        # An editorial, published record that carries no OTHER CRZ id.
        def fileable_row?
          contract.source == "editorial" && contract.state.to_s == "published" &&
            (contract.source_id.blank? || contract.source_id == crz_id)
        end

        # The official record must still be the one the editor compared.
        def guard_checksum!(record)
          raise Refusal, :stale unless record[:checksum] == checksum
        end

        # A non-match (mismatch or unverifiable) needs the override reason;
        # a clean match takes none.
        def guard_reason!(comparison)
          if comparison.needs_reason?
            raise Refusal, :reason_required if normalized_reason.blank?
          elsif normalized_reason.present?
            raise Refusal, :reason_rejected
          end
        end

        # The id must be free. Returns a destroyable pristine mirror (to be
        # absorbed), nil when nothing holds the id; raises :already_linked
        # for any other holder. The mirror is locked AFTER the contract
        # (lock order — see the class comment).
        def claimable_mirror!(record)
          holder = Contract.where(organization: contract.organization, source_id: record[:source_id])
                           .where.not(id: contract.id).lock.first
          return nil unless holder
          raise Refusal, :already_linked unless holder.source == CrzImport::Mapper::SOURCE && pristine?(holder)

          holder
        end

        # Nothing an editor made of the mirror: no amendments, links or
        # documents (parties are the import's own mirrored rows).
        def pristine?(mirror)
          !mirror.amendments.exists? && !mirror.links.exists? && !mirror.documents.exists?
        end

        def write_filing!(record, mirror)
          absorb!(mirror) if mirror

          contract.update!(
            crz_url: format(CrzImport::Mapper::CRZ_URL_TEMPLATE, record[:source_id]),
            crz_filed_at: Time.current,
            source_id: record[:source_id],
            crz_published_on: record[:published_on],
            crz_filing_reason: normalized_reason.presence
          )
        end

        # The mirror's row must be gone before the claim (the unique index);
        # its absorption is audited against the claiming record.
        def absorb!(mirror)
          mirror.destroy!
          write_audit!(AUDIT_MIRROR_ABSORBED)
        end

        def record_audit!(outcome)
          write_audit!(outcome == :filed ? AUDIT_FILED : AUDIT_FILED_OVERRIDE)
        end

        def write_audit!(action)
          AuditEvent.create!(action: action, target: contract,
                             organization: contract.organization, actor: user)
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
