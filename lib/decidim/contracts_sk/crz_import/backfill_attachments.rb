# frozen_string_literal: true

module Decidim
  module ContractsSk
    module CrzImport
      # One-off backfill of the CRZ attachment links for mirrors imported
      # before the import wrote them (civora-org/civora-platform#189).
      #
      # Why a re-sync cannot do it: the upsert's checksum gate leaves an
      # unchanged payload alone, so a mirror whose CRZ record never changed
      # never gets its attachment rows from the sync. This module fetches
      # each candidate's payload by id (Client#contract), maps it with the
      # Mapper (the same allowlist the import uses) and writes the
      # crz_attachments rows. LINK ONLY: no file is downloaded.
      #
      # Candidates: the organization's source="crz" mirrors that have no
      # attachment rows yet. A mirror whose CRZ record has no attachments
      # stays a candidate (nothing marks "checked"), so a re-run refetches
      # it; the run is a one-off, and failed rows are retried the same way.
      #
      # Write semantics (deliberately NOT a re-mirror): only the
      # crz_attachments rows are written, in one transaction under the row's
      # with_lock with an in-lock re-check that the row is still a mirror
      # with no attachment rows. updated_at, checksum, imported_at,
      # import_status, parties and the audit trail are left alone (a
      # checksum written from this fetch would hide a later genuine change
      # from the next sync).
      #
      # Throttling: like BackfillPublishedOn, a PAUSE (default 1.1 s) between
      # fetches keeps the run under ekosystem's 60 requests a minute; skipped
      # on a dry run, which fetches nothing, and injectable for specs.
      #
      # Failure policy: not found / unreachable / invalid payload count as
      # failed; no attachment with an allowlisted file (or a row that
      # changed under the lock) counts as skipped. Nothing aborts the run.
      # Logging is ids and counts only, never titles.
      module BackfillAttachments
        DEFAULT_PAUSE = BackfillPublishedOn::DEFAULT_PAUSE
        LISTING_LIMIT = BackfillPublishedOn::LISTING_LIMIT

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

        def self.format_ids(ids, limit: LISTING_LIMIT)
          BackfillPublishedOn.format_ids(ids, limit: limit)
        end

        def self.call(organization:, client: Client.new, confirm: false, pause: DEFAULT_PAUSE)
          contracts = candidates(organization).order(:id).to_a
          result = Result.new(candidate_ids: contracts.map(&:source_id), updated_ids: [], skipped_ids: [],
                              failed_ids: [], confirmed: confirm)
          backfill_all(result, client, contracts, pause) if confirm

          result
        end

        def self.backfill_all(result, client, contracts, pause)
          contracts.each_with_index do |contract, index|
            sleep(pause) if index.positive? && pause.to_f.positive?
            backfill_one(result, client, contract)
          end
        end

        def self.candidates(organization)
          Contract.where(organization: organization, source: Mapper::SOURCE)
                  .where.not(id: CrzAttachment.select(:contract_id))
        end

        def self.backfill_one(result, client, contract)
          rows = Mapper.map(client.contract(contract.source_id))[:attachments]
          written = rows.any? && write_rows(contract, rows)
          (written ? result.updated_ids : result.skipped_ids) << contract.source_id
        rescue Client::Error, Mapper::Error
          result.failed_ids << contract.source_id
        end

        # The locked, re-checked write; false when the row is no longer a
        # candidate (another source, rows landed meanwhile, or gone).
        def self.write_rows(contract, rows)
          written = false
          contract.with_lock do
            if contract.source == Mapper::SOURCE && !contract.crz_attachments.exists?
              rows.each { |attrs| contract.crz_attachments.create!(attrs) }
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
