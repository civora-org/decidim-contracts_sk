# frozen_string_literal: true

require "net/http"

module Decidim
  module ContractsSk
    module CrzImport
      # Swappable HTTP transport seam for the CRZ import ETL (ADR-008,
      # civora-org/civora-platform#86). A small object responding to
      # `get(url, headers: {})` that returns a Result — nothing more.
      #
      # The seam exists so the offline spec suite never touches the network:
      # specs inject a stub transport into the Client (constructor
      # injection — preferred over webmock, keeping the suite offline and
      # the dependency list lean). The default implementation is Net::HTTP
      # with explicit open/read timeouts and NO logging at all — payloads
      # never reach a logger through this layer (the privacy guardrail of
      # the #86 brief; the Client is the only layer allowed to log, and it
      # logs statuses and URLs only, never bodies).
      class Transport
        # Explicit timeouts (seconds) — a sync run must never hang a worker
        # or a request on a silent upstream (civora-org/civora-platform#86).
        # OPEN: connection-establishment only — fast everywhere. READ: the
        # live 2026-09-09 run observed ~50s server-side TTFB on the ekosystem
        # source under throttling, so the read budget is generous and the
        # bounded retries (Client layer) carry the failure discipline.
        OPEN_TIMEOUT_SECONDS = 5
        READ_TIMEOUT_SECONDS = 60

        # Immutable response summary: HTTP status (0 when the request never
        # completed — DNS, timeout, connection refused), the raw body, the
        # response headers with downcased keys (Link header lookups are
        # case-insensitive by contract), and the transport error when
        # status is 0. Deliberately opaque about success — the Client owns
        # the retry/status policy.
        Result = Struct.new(:status, :body, :headers, :error, keyword_init: true)

        def get(url, headers: {})
          uri = URI(url)
          response = http_for(uri).get(uri.request_uri, headers)
          Result.new(status: response.code.to_i,
                     body: response.body.to_s,
                     headers: response.each_header.to_h.transform_keys(&:downcase),
                     error: nil)
        rescue StandardError => e
          Result.new(status: 0, body: "", headers: {}, error: e)
        end

        private

        def http_for(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.is_a?(URI::HTTPS)
          http.open_timeout = OPEN_TIMEOUT_SECONDS
          http.read_timeout = READ_TIMEOUT_SECONDS
          http
        end
      end
    end
  end
end
