# frozen_string_literal: true

module Decidim
  module ContractsSk
    module CrzImport
      # One-off backfill of the real CRZ publication date for mirrors
      # imported before the import wrote it (civora-org/civora-platform#159).
      #
      # Why a re-sync cannot do it: the upsert's checksum gate leaves an
      # unchanged payload alone (zero writes), so a mirror whose CRZ record
      # never changed never gets crz_published_on from the sync. This module
      # fetches each candidate's payload by id (Client#contract), maps it
      # with the Mapper (the same parse the import uses) and writes ONE
      # column.
      #
      # Candidates: the organization's source="crz" mirrors whose
      # crz_published_on is NULL. Editorial records (any other source) and
      # other organizations' mirrors are never candidates; mirrors that
      # already carry a date are never refreshed.
      #
      # Write semantics (deliberately NOT a re-mirror): only
      # crz_published_on is written, through update_column — no validations,
      # no callbacks, and updated_at, checksum, imported_at, import_status,
      # the parties and the audit trail are all left alone. A backfill is not
      # an import: stamping imported_at/checksum would claim the mirror was
      # refreshed from a payload this code never compared, and a checksum
      # written from this fetch would hide a genuine later payload change
      # from the next sync. The column is a pure derived date, so no audit
      # event rides along either (the date is public CRZ data, and the
      # run's counts and ids are the operator's record).
      #
      # Throttling: ekosystem rate-limits to 60 requests per minute, and the
      # client's own retries (3 attempts, short backoff) cannot outlast a
      # spent window: an unthrottled run over hundreds of mirrors failed a
      # third of them with 429s. The run therefore pauses PAUSE seconds
      # between fetches (default 1.1 s, deterministically under 60 per
      # minute); the rate-limit headers are deliberately not parsed. The
      # pause is injectable (specs pass 0 and never sleep for real) and is
      # skipped on a dry run, which fetches nothing. Failed rows stay
      # candidates, so simply re-running picks them up.
      #
      # Lock doctrine: the write takes the row's with_lock (which reloads)
      # and re-checks, on the reloaded row, that it is still a mirror with
      # no date — a concurrent sync or filing confirmation that moved the
      # row in between wins, and the backfill skips it.
      #
      # Failure policy: per-record problems — the record gone upstream
      # (NotFoundError), the source unreachable (TransportError, any other
      # client error) or unparseable, a structurally invalid payload
      # (Mapper::Error) — are counted as failed; no usable date (nil:
      # sentinel, blank, garbage) or a row that changed under the lock is
      # counted as skipped. Nothing aborts the run. Logging is ids and
      # counts only, never payloads.
      #
      # The Rails models are resolved at call time, like the rest of the
      # CrzImport layer (no Rails constants touched at load time).
      module BackfillPublishedOn
        # Seconds between two fetches: 60 / 1.1 is about 54 requests a minute.
        DEFAULT_PAUSE = 1.1

        # How many ids a printed listing shows before "... and N more".
        LISTING_LIMIT = 50

        # candidate_ids are the CRZ source ids of the mirrors without a date
        # at the start of the run; updated_ids / skipped_ids / failed_ids
        # are CRZ source ids too. In a dry run (confirmed false) nothing is
        # fetched or written, so only the candidates are filled.
        Result = Struct.new(:candidate_ids, :updated_ids, :skipped_ids, :failed_ids, :confirmed, keyword_init: true) do
          def candidates
            candidate_ids.size
          end

          def updated
            updated_ids.size
          end

          def skipped
            skipped_ids.size
          end

          def failed
            failed_ids.size
          end
        end

        # "a, b, c, ... and N more": the ids capped at +limit+ for printing.
        def self.format_ids(ids, limit: LISTING_LIMIT)
          shown = ids.first(limit).join(", ")
          ids.size > limit ? "#{shown}, \u2026 and #{ids.size - limit} more" : shown
        end

        def self.call(organization:, client: Client.new, confirm: false, pause: DEFAULT_PAUSE)
          contracts = candidates(organization).order(:id).to_a
          result = Result.new(candidate_ids: contracts.map(&:source_id), updated_ids: [], skipped_ids: [],
                              failed_ids: [], confirmed: confirm)
          backfill_all(result, client, contracts, pause) if confirm

          result
        end

        # One fetch per candidate, PAUSE seconds apart (none before the first).
        def self.backfill_all(result, client, contracts, pause)
          contracts.each_with_index do |contract, index|
            sleep(pause) if index.positive? && pause.to_f.positive?
            backfill_one(result, client, contract)
          end
        end

        def self.candidates(organization)
          Contract.where(organization: organization, source: Mapper::SOURCE, crz_published_on: nil)
        end

        def self.backfill_one(result, client, contract)
          published_on = fetch_date(client, contract.source_id)
          written = published_on && write_date(contract, published_on)
          (written ? result.updated_ids : result.skipped_ids) << contract.source_id
        rescue Client::Error, Mapper::Error
          # Not found, unreachable (retries exhausted), unparseable or a
          # structurally invalid payload: counted, never fatal.
          result.failed_ids << contract.source_id
        end

        # The mapped date of the record's CRZ payload (nil when CRZ reports
        # none). Raises the client's / mapper's domain errors.
        def self.fetch_date(client, source_id)
          Mapper.map(client.contract(source_id))[:published_on]
        end

        # The locked, re-checked write on a candidate loaded at the start of
        # the run (so possibly stale: the fetch happens between the load and
        # the lock). with_lock reloads the row and the re-check reads that
        # reloaded state. Returns false when the row is no longer a
        # candidate (a date or another source landed meanwhile, or the row
        # is gone).
        def self.write_date(contract, published_on)
          written = false
          contract.with_lock do
            if contract.source == Mapper::SOURCE && contract.crz_published_on.nil?
              contract.update_column(:crz_published_on, published_on)
              written = true
            end
          end
          written
        rescue ActiveRecord::RecordNotFound
          false
        end
      end
    end
  end
end
