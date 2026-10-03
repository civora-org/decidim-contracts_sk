# frozen_string_literal: true

require "active_support/core_ext/object/blank"

module Decidim
  module ContractsSk
    module CrzImport
      # Batch orchestrator of the CRZ import (ADR-008 decision 5,
      # civora-org/civora-platform#86): paginates the Client's updated-since
      # sync following the Link cursor, feeds every record through the
      # Mapper and the UpsertContract command, and folds per-record and
      # per-page failures into a Result summary. Never raises out of the
      # batch loop — a failed run reports itself and leaves the prior data
      # intact (the stale fallback: existing catalogue data is never
      # degraded by a bad sync).
      #
      # Failure taxonomy (the Result counters):
      # - quarantined — a record that cannot even be mapped (structural
      #   garbage, missing id, mapper total failure, or a create that no
      #   record exists to attach a failure to): skipped, the batch
      #   continues, no payload ever logged (ids only).
      # - failed — a per-record write failure or an unreachable source for
      #   a KNOWN record: the existing mirror row (if any) is stamped
      #   import_status="failed" in its own transaction, its data untouched
      #   (stale fallback).
      # - collisions — editorial records holding the same source_id: never
      #   touched; resolved manually (docs/crz-import.md).
      # - skipped — imported records that left the published state: the
      #   lifecycle guard refuses the update, data untouched.
      # - out_of_scope — a record whose parties do not carry the
      #   organization's IČO (civora-org/civora-platform#145): another
      #   organization's contract from the national feed. Not written, not
      #   logged per id; counted only.
      # - error — the message of the Client error that stopped pagination
      #   (prior pages stand; later pages were never attempted), or the
      #   refusal to run when the organization has no IČO configured. Nil
      #   on a clean run.
      #
      # Scope (civora-org/civora-platform#145): the sync fails closed — an
      # organization without a configured IČO
      # (Decidim::ContractsSk.crz_organization_ico) imports nothing.
      #
      # Privacy guardrail (#86): only ids, statuses and counts are logged —
      # NEVER payloads or party names.
      #
      # Cop note: the class stays deliberately cohesive — it owns the whole
      # ADR-008 failure taxonomy (quarantine, stale-fallback marking,
      # collision counting, lifecycle skips) in one place, and splitting
      # the accounting off would scatter that contract rather than
      # simplify it.
      # rubocop:disable Metrics/ClassLength
      class Sync
        # Summary of one run/import: counts + the ids behind them + the
        # stopping error (nil on a clean run).
        Result = Struct.new(:created, :updated, :unchanged, :collisions, :quarantined,
                            :failed, :skipped, :out_of_scope, :created_ids, :collision_ids,
                            :quarantined_ids, :failed_ids, :error, keyword_init: true)

        class << self
          # Full batch sync of one organization. `since` is an ISO8601
          # timestamp; `actor` is the operator persona behind the audit
          # rows and authorship (see UpsertContract).
          def run(organization:, since:, actor:, client: nil)
            new(organization: organization, actor: actor,
                client: client || Client.new).run(since)
          end

          # Single-record import by CRZ id (the admin action's path).
          # Returns an outcome symbol for the controller's flash mapping:
          # :created/:updated/:unchanged/:collision/:lifecycle_guard/
          # :record_invalid/:quarantined/:not_found/:failed/:out_of_scope/
          # :not_configured.
          def import_one(source_id:, organization:, actor:, client: nil)
            new(organization: organization, actor: actor,
                client: client || Client.new).import_one(source_id)
          end
        end

        # The refusal message when the organization has no IČO configured.
        NOT_CONFIGURED_MESSAGE = "no IČO configured for this organization " \
                                 "(Decidim::ContractsSk.crz_organization_ico_resolver) — nothing imported"

        def initialize(organization:, actor:, client:)
          @organization = organization
          @actor = actor
          @client = client
          @ico = ContractsSk.crz_organization_ico(organization)
          @result = Result.new(created: 0, updated: 0, unchanged: 0, collisions: 0,
                               quarantined: 0, failed: 0, skipped: 0, out_of_scope: 0,
                               created_ids: [], collision_ids: [], quarantined_ids: [],
                               failed_ids: [], error: nil)
        end

        def run(since)
          return not_configured! unless @ico

          page = @client.sync(since: since)
          process_page(page)
          run_cursor_pages(page)
          result
        rescue Client::Error => e
          # Stale fallback: the pages applied so far stand, later pages were
          # never attempted, nothing raises out of the batch.
          @result.error = e.message
          log(:warn, "sync stopped early: #{e.class}")
          result
        end

        # Later pages are fetched with the verbatim Link cursor only —
        # never a reconstructed since.
        def run_cursor_pages(first_page)
          page = first_page
          while (cursor = page[:next_cursor])
            page = @client.sync(since: nil, cursor: cursor)
            process_page(page)
          end
        end

        def import_one(source_id)
          return :not_configured unless @ico

          payload = @client.contract(source_id)
          upsert_record!(payload)[:status]
        rescue Client::NotFoundError
          :not_found
        rescue Client::Error => e
          @result.error = e.message
          mark_failed!(source_id)
          log(:warn, "single import of #{source_id} failed: #{e.class}")
          :failed
        end

        private

        attr_reader :result

        def process_page(page)
          page.fetch(:records).each { |payload| upsert_record!(payload) }
        end

        # Maps and upserts one raw payload, folding every outcome into the
        # summary. Per-record failures never abort the batch.
        def upsert_record!(payload)
          record = Mapper.map(payload)
          return out_of_scope! unless in_scope?(record)

          events = UpsertContract.call(record, organization: @organization, actor: @actor)

          events.key?(:ok) ? apply_ok(events[:ok], record) : apply_invalid(events[:invalid], record)
        rescue Mapper::Error => e
          quarantine!(payload, e.message)
        rescue StandardError => e
          record_error!(payload, e)
        end

        # In scope when the organization's IČO is on either mirrored party.
        # The party IČOs are the mapper's normalized ekosystem *_cin values.
        def in_scope?(record)
          record[:parties].any? { |party| party[:ico] == @ico }
        end

        def out_of_scope!
          result.out_of_scope += 1
          { status: :out_of_scope }
        end

        def not_configured!
          result.error = NOT_CONFIGURED_MESSAGE
          log(:warn, "sync refused: #{NOT_CONFIGURED_MESSAGE}")
          result
        end

        def apply_ok(event, record)
          outcome = event[:outcome]
          contract = event[:contract]

          count_outcome!(outcome, contract)
          log(:info, "record #{record[:source_id]}: #{outcome} (contract ##{contract.id})")

          { status: outcome, contract: contract }
        end

        def count_outcome!(outcome, contract)
          case outcome
          when :created
            result.created += 1
            result.created_ids << contract.id
          when :updated then result.updated += 1
          when :unchanged then result.unchanged += 1
          end
        end

        def apply_invalid(failure, record)
          reason = failure[:reason]
          contract = failure[:contract]

          case reason
          when :collision then apply_collision!(record, contract)
          when :lifecycle_guard then apply_skip!(record)
          when :record_invalid then apply_record_invalid!(record, contract)
          end

          { status: reason, contract: contract }
        end

        def apply_collision!(record, contract)
          result.collisions += 1
          result.collision_ids << contract.id
          log(:warn, "editorial collision on source_id=#{record[:source_id]} " \
                     "(contract ##{contract.id}) — manual resolution required")
        end

        def apply_skip!(record)
          result.skipped += 1
          log(:info, "record #{record[:source_id]}: skipped (no longer published)")
        end

        def apply_record_invalid!(record, contract)
          if contract
            result.failed += 1
            result.failed_ids << contract.id
            mark_failed!(record[:source_id], contract)
          else
            # Nothing exists to stamp — the record is unimportable, so it
            # lands in the quarantine bucket.
            result.quarantined += 1
            result.quarantined_ids << record[:source_id]
          end
          log(:warn, "record #{record[:source_id]}: invalid data, no write")
        end

        # Quarantine: skip the record, count it, log the id only. When a
        # mirror row already exists for the same source_id, it is stamped
        # failed (stale fallback) and counted as failed instead — prior
        # data intact either way.
        def quarantine!(payload, message)
          source_id = payload_source_id(payload)
          existing = find_mirror(source_id)

          return quarantine_existing!(source_id, existing) if existing

          result.quarantined += 1
          result.quarantined_ids << source_id
          log(:warn, "record #{source_id}: quarantined (#{message})")
          { status: :quarantined }
        end

        def quarantine_existing!(source_id, existing)
          mark_failed!(source_id, existing)
          result.failed += 1
          result.failed_ids << existing.id
          log(:warn, "record #{source_id}: unmappable payload, existing mirror stamped failed")
          { status: :failed }
        end

        # Unexpected per-record failure: count it, stale-fallback-mark the
        # mirror row when the source_id is known, keep the batch going.
        def record_error!(payload, error)
          source_id = payload_source_id(payload)
          stamped = mark_failed!(source_id)
          result.failed_ids << stamped.id if stamped
          result.failed += 1
          log(:warn, "record failed unexpectedly#{source_id ? " (source_id=#{source_id})" : ""}: #{error.class}")
          { status: :failed }
        end

        def payload_source_id(payload)
          payload.is_a?(Hash) ? payload["id"].to_s.presence : nil
        end

        # The stale fallback stamp: a separate transaction from the
        # (rolled-back) failed write — only import_status flips, all prior
        # data stays intact. The row is RE-FOUND fresh on purpose: the
        # command's post-rollback instance may still carry the rolled-back
        # dirty attributes, and writing through it would re-fail. Returns
        # the stamped row, or nil when nothing exists to stamp.
        def mark_failed!(source_id, contract = nil)
          fresh = contract ? Contract.find(contract.id) : find_mirror(source_id)
          return unless fresh

          fresh.update!(import_status: "failed")
          fresh
        rescue StandardError => e
          log(:warn, "could not stamp import_status=failed on source_id=#{source_id}: #{e.class}")
          nil
        end

        def find_mirror(source_id)
          source_id && Contract.find_by(organization: @organization, source_id: source_id)
        end

        def log(level, message)
          logger = Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          logger&.public_send(level, "[crz_import] #{message}")
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
