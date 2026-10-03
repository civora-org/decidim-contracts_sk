# frozen_string_literal: true

require "active_support/core_ext/object/blank"

module Decidim
  module ContractsSk
    module CrzImport
      # The read-only verification fetch behind the CRZ filing confirmation
      # (civora-org/civora-platform#125): resolves a CRZ id to the mapped
      # official record, or to the reason it cannot serve as one. Shared by
      # the admin preview (GET, writes nothing) and the
      # Admin::ConfirmCrzFiling command, so both see the same refusals in the
      # same order — and so the network call lives in one place, always
      # OUTSIDE any row lock.
      #
      # It is a read-only use of the same primary source as the import
      # (the ekosystem feed, ADR-008 decision 1): nothing is written, and no
      # payload is logged (the Client logs URLs and statuses only).
      #
      # Refusals, in the order evaluated (all fail closed, none overridable):
      #   :not_found      — the id is not numeric, or CRZ has no such record
      #                     (ekosystem may lag CRZ by about a day);
      #   :not_configured — the organization has no IČO configured;
      #   :failed         — the source is unreachable / returned garbage;
      #   :out_of_scope   — neither party carries the organization's IČO;
      #   :withdrawn      — CRZ status 4 (cancelled) or 5 (withdrawn).
      class FilingLookup
        Result = Struct.new(:record, :refusal, keyword_init: true) do
          def ok?
            refusal.nil?
          end
        end

        def self.call(crz_id:, organization:, client: nil)
          new(crz_id: crz_id, organization: organization, client: client).call
        end

        def initialize(crz_id:, organization:, client: nil)
          @crz_id = crz_id.to_s.strip
          @organization = organization
          @client = client
        end

        def call
          return refused(:not_found) unless crz_id.match?(/\A\d+\z/)

          ico = ContractsSk.crz_organization_ico(organization)
          return refused(:not_configured) unless ico

          record = fetch
          return record if record.is_a?(Result)
          return refused(:out_of_scope) unless CrzScope.in_scope?(record, ico)
          return refused(:withdrawn) if FilingComparison.withdrawn?(record)

          Result.new(record: record)
        end

        private

        attr_reader :crz_id, :organization

        def client
          @client ||= Client.new
        end

        # The mapped record, or a refused Result. The mapper's own id must
        # echo the requested one — a payload for a different record is never
        # accepted as the answer.
        def fetch
          record = Mapper.map(client.contract(crz_id))
          record[:source_id] == crz_id ? record : refused(:not_found)
        rescue Client::NotFoundError
          refused(:not_found)
        rescue Client::Error, Mapper::Error
          refused(:failed)
        end

        def refused(reason)
          Result.new(refusal: reason)
        end
      end
    end
  end
end
