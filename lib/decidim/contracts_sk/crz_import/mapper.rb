# frozen_string_literal: true

require "bigdecimal"
require "date"
require "digest"
require "active_support/core_ext/object/blank"
require "json"

module Decidim
  module ContractsSk
    module CrzImport
      # Pure mapping layer: ekosystem CRZ JSON payload → normalized
      # engine attributes (ADR-008, civora-org/civora-platform#86; the
      # field correspondence is the #83 spike's verified mapping). Tolerant
      # by contract: missing/blank/divergent fields map to nil — capture,
      # never crash. Structural invalidity (not a JSON object, missing CRZ
      # id) raises Mapper::Error so the Sync orchestrator can quarantine
      # the record.
      #
      # Mirror scope (ADR-008 decision 2): contract content fields + the
      # two parties. NOT mirrored: documents (link-only via crz_url),
      # currency and the VAT flag (absent upstream — manual/editorial
      # fields), amendment linkage hints (structurally unreliable).
      #
      # Checksum: SHA-256 hex over the CANONICAL JSON of the raw payload
      # (hash keys sorted recursively, arrays in order). Deterministic —
      # the same payload always yields the same digest regardless of key
      # order, so the upsert's checksum gate is stable across runs.
      # `changed_at` drives nothing in the upsert except being part of the
      # checksummed payload.
      module Mapper
        class Error < Decidim::ContractsSk::Error; end

        SOURCE = "crz"
        CRZ_URL_TEMPLATE = "https://crz.gov.sk/zmluva/%s/"

        # CRZ writes "0000-00-00" for null dates (spike gotcha #1) — a
        # sentinel, never year 0.
        DATE_SENTINELS = ["0000-00-00"].freeze

        # Contracts validate title/reference at 255 chars and parties
        # validate name/address at 255 — overlong source values are
        # clipped (capture, don't crash).
        MAX_STRING_LENGTH = 255

        class << self
          # Maps one raw payload Hash into the upsert record:
          #   { source_id:, attributes: {...}, parties: [...], checksum: }
          # Raises Mapper::Error on structural invalidity.
          def map(payload)
            raise Error, "CRZ record is not a JSON object" unless payload.is_a?(Hash)

            source_id = text(payload["id"]).presence
            raise Error, "CRZ record is missing its id" if source_id.blank?

            {
              source_id: source_id,
              attributes: contract_attributes(payload, source_id),
              parties: parties_for(payload),
              checksum: checksum(payload)
            }
          end

          # SHA-256 hex of the canonical JSON of the raw payload.
          # Structural garbage that survives the field mapping (e.g. mixed
          # key types from a broken source) fails here — folded into
          # Mapper::Error so the Sync orchestrator's quarantine path can
          # still identify the record by its id and stale-fallback-mark an
          # existing mirror row.
          def checksum(payload)
            Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))
          rescue StandardError => e
            raise Error, "checksum computation failed (#{e.class})"
          end

          private

          # The spike-verified correspondence, with the recorded fallbacks
          # (see the *_from helpers). Title and reference are clipped to
          # the 255-char model limit; currency is deliberately absent
          # (never imported — ADR-008).
          def contract_attributes(payload, source_id)
            {
              title: clip(title_from(payload)),
              reference: clip(reference_from(payload)),
              subject_matter: subject_matter_from(payload),
              amount: parse_amount(payload["contract_price_amount"]),
              signed_on: parse_date(payload["signed_on"]),
              effective_from: parse_date(payload["effective_from"]),
              crz_url: format(CRZ_URL_TEMPLATE, source_id)
            }
          end

          def title_from(payload)
            text(payload["subject"]).presence || text(payload["contract_identifier"]).presence
          end

          def reference_from(payload)
            text(payload["contract_identifier"]).presence || text(payload["reference"]).presence
          end

          def subject_matter_from(payload)
            text(payload["subject_description"]).presence || text(payload["subject"]).presence
          end

          def parties_for(payload)
            [mapped_party("object",
                          payload["contracting_authority_name"],
                          payload["contracting_authority_cin"],
                          payload["contracting_authority_formatted_address"]),
             mapped_party("contractor",
                          payload["supplier_name"],
                          payload["supplier_cin"],
                          payload["supplier_formatted_address"])].compact
          end

          # A party is mirrored only when it has a name; a blank name skips
          # the party (never a blank-named row). The CIN fields are
          # ekosystem's DISAMBIGUATED ones — trusted by name, never by
          # position (spike gotcha #2).
          def mapped_party(role, raw_name, raw_cin, raw_address)
            name = clip(text(raw_name).presence)
            return nil if name.blank?

            { role: role, name: name, ico: normalize_cin(raw_cin),
              address: clip(text(raw_address).presence) }
          end

          # "00 585 441" → "00585441"; anything that is not exactly 8
          # digits after whitespace removal ("bez ičo", partial numbers)
          # maps to nil — the Party model validates an 8-digit IČO, and a
          # malformed source value must not crash the write.
          def normalize_cin(raw)
            digits = text(raw).gsub(/\s+/, "")
            digits.match?(/\A\d{8}\z/) ? digits : nil
          end

          # Decimal strings ("1043.68"). Invalid, negative or above the
          # contracts column's decimal(12,2) ceiling → nil (the value would
          # fail the model's numericality or blow up on PostgreSQL hosts).
          def parse_amount(raw)
            value = text(raw)
            return nil if value.blank?

            amount = BigDecimal(value)
            return nil if amount.negative? || amount > max_amount

            amount
          rescue ArgumentError
            nil
          end

          # The model constant is resolved at CALL time — the mapper is a
          # lib/ class loaded before the app autoloader has run.
          def max_amount
            Decidim::ContractsSk::Contract::MAX_AMOUNT
          end

          # ISO dates; the 0000-00-00 sentinel, blanks and unparseable
          # values all map to nil.
          def parse_date(raw)
            value = text(raw)
            return nil if value.blank? || DATE_SENTINELS.include?(value)

            Date.parse(value)
          rescue ArgumentError, TypeError
            nil
          end

          def text(raw)
            raw.to_s.strip
          end

          def clip(value)
            value&.[](0, MAX_STRING_LENGTH)
          end

          # Canonical JSON input: hash keys sorted recursively (arrays keep
          # their order — element order is semantic), scalars as-is.
          def canonicalize(value)
            case value
            when Hash then value.sort.to_h.transform_values { |child| canonicalize(child) }
            when Array then value.map { |child| canonicalize(child) }
            else value
            end
          end
        end
      end
    end
  end
end
