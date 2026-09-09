# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "json"
require "uri"

module Decidim
  module ContractsSk
    module CrzImport
      # Read-only ekosystem.slovensko.digital client over the Transport seam
      # (ADR-008, civora-org/civora-platform#86). Endpoints (spike-verified
      # 2026-09-09, docs/01-discovery/CRZ-OPENDATA-SPIKE.md in the platform
      # repo):
      #
      #   GET {base}/api/data/crz/contracts/sync?since=<ISO8601>&last_id=<int>
      #   GET {base}/api/data/crz/contracts/:id
      #
      # The sync cursor comes back verbatim in the `Link` response header
      # (rel="next" — the live API emits single quotes, so both quoting
      # styles parse): the cursor is the next URL AS SENT, always followed,
      # never reconstructed (the server rewrites `since`; rebuilding it
      # would silently re-read or skip windows).
      #
      # Failure policy: bounded retries (2 retries after the first attempt,
      # small backoff) on transient failures only — transport-level errors
      # (the Result with status 0), HTTP 429 and 5xx. Other 4xx fail
      # immediately. Retry exhaustion raises TransportError; a missing
      # single record raises NotFoundError. The client NEVER raises Net::*
      # errors out — the transport folds them into status-0 results.
      #
      # Privacy guardrail (#86): the client logs request URLs and response
      # statuses ONLY — never request/response bodies (the body is the
      # payload; the logs must stay free of party names and contract
      # content). URLs are safe: they carry only since/last_id/id.
      class Client
        DEFAULT_BASE_URL = "https://datahub.ekosystem.slovensko.digital"
        SYNC_PATH = "/api/data/crz/contracts/sync"
        CONTRACT_PATH = "/api/data/crz/contracts"

        MAX_RETRIES = 2

        # Backoff seconds slept before retry attempts 1 and 2 (small on
        # purpose: the ekosystem budget is 60 requests per window —
        # hammering on retries wastes it).
        DEFAULT_BACKOFF = [0.5, 1.0].freeze

        # Error vocabulary (domain errors — the Sync orchestrator rescues
        # exactly these; anything else propagating out is a bug).
        class Error < Decidim::ContractsSk::Error; end

        class TransportError < Error; end
        class NotFoundError < Error; end
        class ParseError < Error; end

        # `transport` is the injection seam (see Transport); `backoff` is
        # injectable so specs stay deterministic (no real sleeping).
        def initialize(transport: Transport.new, base_url: DEFAULT_BASE_URL,
                       logger: default_logger, backoff: DEFAULT_BACKOFF)
          @transport = transport
          @base_url = base_url.chomp("/")
          @logger = logger
          @backoff = backoff
        end

        # One page of the updated-since sync. `since` seeds the first call;
        # every later call MUST pass `cursor: <next_cursor>` (the verbatim
        # Link URL from the previous page) instead of a reconstructed since.
        # Returns { records: [...], next_cursor: String|nil }.
        def sync(since:, cursor: nil)
          url = cursor.presence || build_sync_url(since)
          response = get_with_retries(url)

          # Final non-transient statuses surface as domain errors before
          # any parsing (mirrors #contract's status handling).
          raise Error, "CRZ sync request failed (HTTP #{response.status})" unless response.status.between?(200, 299)

          { records: extract_records(response), next_cursor: extract_next_cursor(response) }
        end

        # One contract payload (a Hash) by its CRZ numeric id.
        def contract(id)
          response = get_with_retries(contract_url(id))

          raise NotFoundError, "CRZ contract #{id} not found (HTTP 404)" if response.status == 404
          raise Error, "CRZ contract #{id} fetch failed (HTTP #{response.status})" unless response.status.between?(200,
                                                                                                                   299)

          record_from(response, id)
        end

        private

        def contract_url(id)
          "#{@base_url}#{CONTRACT_PATH}/#{URI.encode_www_form_component(id.to_s)}"
        end

        def record_from(response, id)
          payload = parse_json(response)
          payload = payload["contract"] if payload.is_a?(Hash) && payload["contract"].is_a?(Hash)
          raise ParseError, "CRZ contract #{id}: expected a JSON object" unless payload.is_a?(Hash)

          payload
        end

        # The single request path with bounded retries. Returns the last
        # Result when it is final (success or non-transient failure);
        # raises TransportError when the retries are exhausted.
        def get_with_retries(url)
          (MAX_RETRIES + 1).times do |index|
            result = @transport.get(url)
            log_response(url, result, index)

            return result unless transient?(result)

            sleep(@backoff[index]) if @backoff[index]
          end

          raise TransportError, "CRZ import gave up on #{url} after #{MAX_RETRIES + 1} attempts"
        end

        def transient?(result)
          result.status.zero? || result.status == 429 || result.status >= 500
        end

        def build_sync_url(since)
          "#{@base_url}#{SYNC_PATH}?#{URI.encode_www_form({ since: since })}"
        end

        # Tolerant page-shape extraction: a bare JSON array (the observed
        # live shape) or an object carrying a "contracts" array. Non-hash
        # entries stay IN the list — the mapper's quarantine semantics
        # handle them per record, so one bad entry never aborts the batch.
        def extract_records(response)
          payload = parse_json(response)
          records =
            if payload.is_a?(Array)
              payload
            elsif payload.is_a?(Hash) && payload["contracts"].is_a?(Array)
              payload["contracts"]
            end
          raise ParseError, "CRZ sync page: expected an array of records" unless records.is_a?(Array)

          records
        end

        # The verbatim next URL from the Link header, or nil. Matches the
        # quoting styles observed in the wild — the live ekosystem API
        # emits rel='next' with SINGLE quotes (spike, 2026-09-09) — plus
        # double quotes and bare rel=next, case-insensitively.
        def extract_next_cursor(response)
          link = response.headers["link"].to_s
          match = link.scan(/<([^>]+)>\s*;\s*rel=["']?next["']?/i).flatten.first

          match.presence
        end

        def parse_json(response)
          JSON.parse(response.body)
        rescue JSON::ParserError, TypeError
          raise ParseError, "CRZ import: unparseable JSON (HTTP #{response.status})"
        end

        # The ONLY logging the import path does: URL, status, attempt
        # counter. Never the body, never payload fields.
        def log_response(url, result, index)
          return unless @logger

          attempt = "#{index + 1}/#{MAX_RETRIES + 1}"
          if result.status.zero?
            @logger.warn("[crz_import] GET #{url} failed (#{result.error.class}); attempt #{attempt}")
          else
            @logger.info("[crz_import] GET #{url} -> #{result.status}; attempt #{attempt}")
          end
        end

        def default_logger
          Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        end
      end
    end
  end
end
