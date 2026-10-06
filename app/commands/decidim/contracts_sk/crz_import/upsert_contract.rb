# frozen_string_literal: true

module Decidim
  module ContractsSk
    module CrzImport
      # The idempotent upsert of ONE mapped CRZ record (ADR-008 decision 3,
      # civora-org/civora-platform#86). Modeled on the engine's admin
      # commands: a Decidim::Command broadcasting :ok/:invalid, with the
      # engine-wide lock doctrine applied wherever it writes contract rows
      # (with_lock + in-lock re-check — docs/contracts-domain-notes.md).
      #
      # Write semantics:
      # - CREATE when no record holds the (organization, source_id) pair:
      #   the mirror lands `published` — the ONE recorded lifecycle
      #   exception — with its publication stamp, full provenance
      #   (source="crz", source_id, imported_at, import_status="succeeded",
      #   checksum), the mapped parties, and a "crz_import_create" audit
      #   event. Currency stays on the column default (never imported).
      #   `published_at` keeps meaning "entered the catalogue" (import
      #   time); the REAL CRZ publication date goes to crz_published_on
      #   (civora-org/civora-platform#159), which the catalogue prefers.
      #   crz_published_on is a date, never the "filed" flag — only
      #   crz_filed_at is — so a mirror carrying one is still a mirror.
      # - UPDATE when a source="crz" record exists, only if the stored
      #   checksum differs (checksum gate — no blind overwrites) AND the
      #   record is still `published` (an imported record that left the
      #   published state is never resurrected or overwritten; the guard
      #   is re-checked INSIDE the lock). Content fields, parties and
      #   provenance are re-mirrored; state/author/currency are never
      #   touched; crz_published_on is re-mirrored with the content (nil
      #   when CRZ reports none); a "crz_import_update" audit event rides
      #   the same transaction. A mirror imported before #159 is NOT
      #   refreshed by an unchanged payload (the checksum gate): the
      #   backfill task (CrzImport::BackfillPublishedOn) fills its date.
      # - LINKED when a record with the same source_id has a different
      #   source (an editorial record) that was CONFIRMED as filed
      #   (crz_filed_at present, Admin::ConfirmCrzFiling,
      #   civora-org/civora-platform#125): that record is already the
      #   canonical, linked record of the CRZ id — ZERO writes (updated_at
      #   untouched), outcome :linked. Not a mirror, not a collision.
      # - COLLISION when a record with the same source_id has a different
      #   source and is NOT confirmed as filed (an editorial record that
      #   merely carries the id): never touched, reason :collision —
      #   logged for manual resolution by the caller.
      # - UNCHANGED when the checksum matches: zero writes (updated_at
      #   untouched — the idempotency guarantee).
      #
      # Concurrency: the update path takes the contract row's with_lock and
      # re-checks source/checksum/state on the RELOADED row. The create
      # path re-checks the (organization, source_id) lookup INSIDE the
      # transaction and reroutes to the update/collision path when a
      # concurrent import won the race; the UNIQUE index on
      # (organization, source_id) is the database-level backstop — if two
      # transactions still both find nothing (READ COMMITTED), the losing
      # INSERT raises ActiveRecord::RecordNotUnique and is rerouted the
      # same way, so the race winner is never stamped failed by the
      # caller's error handling.
      #
      # Failures: a validation failure broadcasts :invalid with reason
      # :record_invalid and touches nothing (the surrounding transaction
      # rolls back). Marking the existing record's import_status="failed"
      # (the stale fallback) is the CALLER's duty — the Sync orchestrator
      # does it in a separate transaction, so a rolled-back write never
      # hides behind a failed stamp.
      #
      # Broadcast payloads (single-arg hashes; the EventRecorder captures
      # them whole):
      #   on(:ok)      { |result| } — result[:outcome] :created|:updated|:unchanged|:linked,
      #                               result[:contract]
      #   on(:invalid) { |result| } — result[:reason]
      #                               :collision|:lifecycle_guard|:record_invalid,
      #                               result[:contract] (nil on a failed create)
      #
      # Cop note: the class stays deliberately cohesive — the ADR-008 write
      # semantics (create/update/unchanged/collision/guard) and the lock
      # doctrine live in one readable place; splitting them off would
      # scatter the contract rather than simplify it.
      # rubocop:disable Metrics/ClassLength
      class UpsertContract < Decidim::Command
        SOURCE = Mapper::SOURCE

        # System provenance stamps: import time is the write time; the
        # import lifecycle vocabulary's success value.
        IMPORT_STATUS_SUCCESS = "succeeded"

        # Audit actions for the two mirrored write kinds (the D4 payload
        # shape: action, polymorphic target, explicit organization/actor).
        AUDIT_ACTIONS = { created: "crz_import_create", updated: "crz_import_update" }.freeze

        # `record` is the Mapper output ({ :source_id, :attributes,
        # :parties, :checksum, :published_on }); `actor` is the acting user (admin
        # trigger) or the configured operator persona (rake trigger) —
        # required, because both the Contract author and the AuditEvent
        # actor columns are NOT NULL by engine schema.
        def initialize(record, organization:, actor:)
          super()
          @record = record
          @organization = organization
          @actor = actor
        end

        def call
          broadcast_result(perform)
        end

        private

        attr_reader :record, :organization, :actor

        def perform
          existing = find_existing

          return foreign_holder_outcome(existing) if existing && existing.source != SOURCE
          return update_locked(existing) if existing

          create_transactional
        end

        # ---------- create path ----------

        def create_transactional
          result = nil
          Contract.transaction { result = create_or_reroute! }
          result
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
          invalid_outcome(:record_invalid, find_existing)
        rescue ActiveRecord::RecordNotUnique
          lost_create_race
        end

        # The unique (organization, source_id) index aborted this INSERT:
        # a concurrent import committed the same mirror between this
        # transaction's re-check and the write. Re-find AFTER the rollback
        # and reroute to the update/collision path — RecordNotUnique must
        # never escape to the caller's error handling, which would falsely
        # stamp the race winner failed.
        def lost_create_race
          fresh = find_existing
          return foreign_holder_outcome(fresh) if fresh && fresh.source != SOURCE
          return update_locked(fresh) if fresh

          # Unreachable in practice (the index fired, so a row committed);
          # fails closed as an unimportable record if ever hit.
          invalid_outcome(:record_invalid, nil)
        end

        # The create-edge lock doctrine: another import may have created
        # the record between the pre-read and this write; reroute instead
        # of double-creating (no unique index exists on source_id to make
        # the duplicate write fail).
        def create_or_reroute!
          fresh = find_existing
          return create! if fresh.nil?
          return update_locked(fresh) if fresh.source == SOURCE

          foreign_holder_outcome(fresh)
        end

        def create!
          contract = Contract.create!(create_attributes)
          replace_parties!(contract)
          write_audit!(AUDIT_ACTIONS.fetch(:created), contract)

          ok_outcome(:created, contract)
        end

        # Full creation attribute set: the mapper's content fields plus the
        # command-owned tenancy, authorship, lifecycle state and provenance.
        def create_attributes
          record[:attributes].merge(
            organization: organization,
            author: actor,
            state: "published",
            published_at: Time.current,
            crz_published_on: record[:published_on]
          ).merge(provenance_attributes)
        end

        # ---------- update path ----------

        def update_locked(contract)
          result = nil
          contract.with_lock { result = in_lock_update_outcome(contract) }
          result
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
          invalid_outcome(:record_invalid, contract)
        rescue ActiveRecord::RecordNotFound
          lost_row_race
        end

        # The row vanished between the pre-read and the lock's reload (a
        # filing confirmation absorbed this mirror, civora-org/
        # civora-platform#125): re-find AFTER the rollback and reroute like
        # lost_create_race, so the sync ends :linked instead of a spurious
        # failure.
        def lost_row_race
          fresh = find_existing
          return create_transactional unless fresh
          return foreign_holder_outcome(fresh) if fresh.source != SOURCE

          update_locked(fresh)
        end

        # The in-lock decision, read from the RELOADED row (with_lock
        # refetches under the row lock) — the TOCTOU doctrine: a pre-lock
        # read or a stale caller's copy never admits a write.
        def in_lock_update_outcome(contract)
          return foreign_holder_outcome(contract) if contract.source != SOURCE
          return ok_outcome(:unchanged, contract) if unchanged_checksum?(contract)
          return invalid_outcome(:lifecycle_guard, contract) if update_guarded?(contract)

          apply_update!(contract)
          ok_outcome(:updated, contract)
        end

        # A non-mirror record holds the source_id (civora-org/civora-platform
        # #125): confirmed as filed → :linked, zero writes; otherwise the
        # protected editorial :collision. Every decision point calls this
        # with the record as that point sees it — the in-lock call reads the
        # RELOADED row, so a filing confirmed between the pre-read and the
        # lock is honoured.
        def foreign_holder_outcome(contract)
          return ok_outcome(:linked, contract) if contract.crz_filed_at.present?

          invalid_outcome(:collision, contract)
        end

        # The provenance stamps every import write carries; on create it
        # joins the mirroring identity (source + source_id).
        def provenance_attributes
          {
            source: SOURCE,
            source_id: record[:source_id],
            imported_at: Time.current,
            import_status: IMPORT_STATUS_SUCCESS,
            checksum: record[:checksum]
          }
        end

        # The checksum gate: an identical payload must be a no-op —
        # no blind overwrites, updated_at untouched.
        def unchanged_checksum?(contract)
          contract.checksum == record[:checksum]
        end

        # The lifecycle guard: an imported record that left the published
        # state is never resurrected or overwritten.
        def update_guarded?(contract)
          contract.state != "published"
        end

        def apply_update!(contract)
          # Content fields + provenance only: lifecycle state, author and
          # currency are never written by the import (ADR-008).
          contract.update!(update_attributes)
          replace_parties!(contract)
          write_audit!(AUDIT_ACTIONS.fetch(:updated), contract)
        end

        def update_attributes
          record[:attributes].merge(
            crz_published_on: record[:published_on],
            imported_at: Time.current,
            import_status: IMPORT_STATUS_SUCCESS,
            checksum: record[:checksum]
          )
        end

        # ---------- shared pieces ----------

        # Single positional Hash payloads (the Wisper→EventRecorder path in
        # this engine's commands broadcasts positionally — Ruby 3 keeps
        # keywords separate, and the recorder folds one-arg broadcasts to
        # the arg itself).
        def ok_outcome(outcome, contract)
          { outcome: outcome, contract: contract }
        end

        def invalid_outcome(reason, contract)
          { reason: reason, contract: contract }
        end

        def broadcast_result(result)
          if result[:outcome]
            broadcast(:ok, { outcome: result[:outcome], contract: result[:contract] })
          else
            broadcast(:invalid, { reason: result[:reason], contract: result[:contract] })
          end
        end

        # The mirror replaces the mapped parties wholesale (create and
        # update alike), so the same payload always yields the same DB
        # state — the mirror is the source of truth for the two mapped
        # party roles. Runs inside the caller's transaction.
        def replace_parties!(contract)
          contract.parties.destroy_all
          record[:parties].each { |attrs| contract.parties.create!(attrs) }
        end

        def write_audit!(action, contract)
          AuditEvent.create!(action: action, target: contract,
                             organization: contract.organization, actor: actor)
        end

        # (organization, source_id) — deliberately NOT keyed on source, so
        # an editorial record holding the same source_id is found and
        # protected by the collision rule.
        def find_existing
          Contract.find_by(organization: organization, source_id: record[:source_id])
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
