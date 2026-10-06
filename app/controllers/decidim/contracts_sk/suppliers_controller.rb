# frozen_string_literal: true

module Decidim
  module ContractsSk
    # Supplier page (civora-org/civora-platform#117): every published contract
    # of one counterparty, identified by its IČO. Read-only and
    # authentication-free, like the catalogue.
    #
    # Scope: the current organization's published records (CRZ mirrors
    # included: this is an HTML view whose rows carry the provenance badge,
    # unlike the machine-readable surfaces) that name the IČO as CONTRACTOR.
    # The object party is the contracting body, never a supplier, so an
    # object-role IČO does not make a page. An IČO with nothing to show —
    # unknown, drafts only, another organization's, object-role only — is a
    # plain 404, indistinguishable from each other.
    #
    # No request filters in V1: the query is built from an empty param set,
    # so nothing but the IČO and the page number is read from the request.
    # The figures (count, totals per currency, per-year tally) cover every
    # matching record, not only the visible page. A record published both
    # editorially and as its CRZ mirror counts twice: there is no dedupe in
    # V1 (docs/contracts-domain-notes.md).
    class SuppliersController < Decidim::ContractsSk::ApplicationController
      include Decidim::ContractsSk::PublicCatalogue

      helper Decidim::ContractsSk::SuppliersHelper
      helper_method :supplier_ico, :supplier_name, :supplier_count, :supplier_totals, :supplier_years

      def show
        raise ActiveRecord::RecordNotFound unless Decidim::ContractsSk::ICO_FORMAT.match?(supplier_ico)
        raise ActiveRecord::RecordNotFound if supplier_count.zero?

        @contracts = supplier_query.results.includes(:parties).page(public_page)
                                   .per(Decidim::ContractsSk::CONTRACTS_PER_PAGE)
      end

      private

      def supplier_ico
        params[:ico].to_s
      end

      def supplier_query
        @supplier_query ||= CatalogueQuery.new(scope: supplier_scope, params: {}, time_zone: Time.zone)
      end

      def supplier_scope
        published_contracts.where(id: Party.where(role: "contractor", ico: supplier_ico).select(:contract_id))
      end

      def supplier_count
        @supplier_count ||= supplier_query.relation.count
      end

      # The most recent spelling of the name (newest publication date first, see Contract.publication_date_arel; id
      # then contract id, then party id: deterministic even when one contract
      # carries two spellings). Restricted to the contracts of THIS page's scope
      # through the subquery: a draft's or another organization's spelling
      # never leaks into the header.
      def supplier_name
        @supplier_name ||= supplier_name_candidates.pick(:name)
      end

      def supplier_name_candidates
        contracts = Contract.arel_table
        Party.where(role: "contractor", ico: supplier_ico, contract_id: supplier_query.relation.select(:id))
             .joins(:contract)
             .reorder(Contract.publication_date_arel.desc.nulls_last, contracts[:id].desc, Party.arel_table[:id].desc)
      end

      # { currency => total } over the records with an amount, one group
      # query; a nil currency groups under nil (rendered as a bare number).
      def supplier_totals
        @supplier_totals ||= supplier_query.relation.where.not(amount: nil)
                                           .group(:currency).sum(:amount)
                                           .sort_by { |currency, _| currency.to_s }
      end

      # [[year, count], ...] newest first, with a trailing [nil, count] for
      # records without a signing date. Computed in Ruby over one pluck.
      def supplier_years
        @supplier_years ||= begin
          tally = supplier_query.relation.pluck(:signed_on).map { |date| date&.year }.tally
          dated = tally.except(nil).sort_by { |year, _| -year }
          tally.key?(nil) ? dated + [[nil, tally[nil]]] : dated
        end
      end
    end
  end
end
