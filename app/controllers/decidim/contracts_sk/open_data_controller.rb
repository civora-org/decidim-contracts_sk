# frozen_string_literal: true

require "csv"
require "json"

module Decidim
  module ContractsSk
    # Open-data export of the organization's published contracts
    # (civora-org/civora-platform#119): GET /export.csv and /export.json,
    # honouring the same filters as the catalogue (CatalogueQuery) over the
    # OWN-records scope (PublicCatalogue#open_data_scope — CRZ mirrors are
    # never exported). Read-only and authentication-free, like the catalogue
    # (a host that forces sign-in for the whole site forces it here too).
    #
    # Streaming: the response body is a plain Enumerator, NOT
    # ActionController::Live — no second thread (per-connection test
    # databases stay valid) and no buffering: the body is produced in
    # batches of EXPORT_BATCH_SIZE records, ordered by id ascending
    # (find_each), so memory stays flat however large the catalogue grows.
    # The enumerator runs AFTER the action returned, i.e. outside Decidim's
    # switch_locale / use_organization_time_zone around_actions, so
    # everything request- or locale-dependent (detail URLs, the file name)
    # is computed in the action and ContractRecord uses neither I18n nor
    # Time.zone. The explicit ETag (below) is what keeps Rack::ETag from
    # buffering the stream to digest it (Rack::ETag#skip_caching? is true
    # whenever an ETag header is already set).
    class OpenDataController < Decidim::ContractsSk::ApplicationController
      include Decidim::ContractsSk::PublicCatalogue

      EXPORT_BATCH_SIZE = 500
      # Bump when the export shape changes in a way FIELDS does not show.
      EXPORT_VERSION = 1
      FORMATS = %w[csv json].freeze
      EXCEL_PROFILE = "excel"
      BOM = "﻿"
      ID_PLACEHOLDER = "__contract_id__"

      def export
        format = request.path_parameters[:format].to_s
        raise ActionController::RoutingError, "Not Found" unless FORMATS.include?(format)

        excel = params[:profile].to_s == EXCEL_PROFILE
        query = build_catalogue_query(open_data_scope)
        relation = query.relation
        return unless stale?(etag: export_etag(query, format, excel), template: false)

        send_export(relation, format, excel)
      end

      private

      # Everything that decides the bytes: tenant, format, profile, the shape
      # (version + field list), the url column (base URL), the time zone (date
      # filter boundaries), the normalized filters (the export ignores sort)
      # and the data version (count + newest update).
      def export_etag(query, format, excel)
        relation = query.relation
        [current_organization.id, format, excel, EXPORT_VERSION, OpenData::ContractRecord::FIELDS,
         request.base_url, Time.zone.name, query.to_params.except("sort"),
         relation.count, relation.maximum(:updated_at)&.utc&.iso8601(6)]
      end

      # Sets the download headers and the streamed body. Everything the body
      # needs from the request (URL template, file date) is captured here.
      def send_export(relation, format, excel)
        records = record_builder
        response.headers["Content-Disposition"] = "attachment; filename=\"#{export_filename(format)}\""
        self.content_type = format == "csv" ? "text/csv; charset=utf-8" : "application/json; charset=utf-8"
        self.response_body = stream(relation, format, excel, records)
      end

      def export_filename(format)
        "contracts-#{Time.zone.today.iso8601}.#{format}"
      end

      # A lambda turning a contract into its ContractRecord with the absolute
      # detail URL; the URL template is resolved NOW, while the request
      # context is alive (locale: nil keeps Decidim's locale param out).
      def record_builder
        url_template = contract_url(id: ID_PLACEHOLDER, locale: nil)
        lambda do |contract|
          OpenData::ContractRecord.new(contract, url: url_template.sub(ID_PLACEHOLDER, contract.id.to_s))
        end
      end

      def stream(relation, format, excel, records)
        Enumerator.new do |yielder|
          # The executor's query cache stays on while a body streams; it
          # would retain every batch for the whole download.
          Contract.uncached do
            if format == "csv"
              stream_csv(yielder, relation, excel, records)
            else
              stream_json(yielder, relation, records)
            end
          end
        end
      end

      def stream_csv(yielder, relation, excel, records)
        separator = excel ? ";" : ","
        yielder << (BOM + CSV.generate_line(OpenData::ContractRecord::FIELDS, col_sep: separator))
        each_batch(relation) do |batch|
          yielder << batch.map { |contract| csv_line(records.call(contract), excel, separator) }.join
        end
      end

      def csv_line(record, excel, separator)
        CSV.generate_line(record.csv_row(decimal_comma: excel), col_sep: separator)
      end

      def stream_json(yielder, relation, records)
        yielder << "["
        first = true
        each_batch(relation) do |batch|
          chunk = batch.map { |contract| JSON.generate(records.call(contract).as_json_hash) }.join(",")
          yielder << (first ? chunk : ",#{chunk}")
          first = false
        end
        yielder << "]"
      end

      # Batches of records with their parties preloaded. A failure mid-stream
      # cannot change the already-sent 200: log what failed (class and the
      # last record id only; our own log line never carries the message, which
      # may hold SQL values) and re-raise so the server aborts the chunked
      # response instead of ending it cleanly, which lets clients detect the
      # truncation. The re-raised exception still reaches the server and any
      # error tracker with its message; keep those scrubbed.
      def each_batch(relation)
        last_id = nil
        relation.includes(:parties).find_in_batches(batch_size: EXPORT_BATCH_SIZE) do |batch|
          yield batch
          last_id = batch.last.id
        end
      rescue StandardError => e
        Rails.logger.error("[contracts_sk] open-data export aborted after contract id #{last_id.inspect}: #{e.class}")
        raise
      end
    end
  end
end
