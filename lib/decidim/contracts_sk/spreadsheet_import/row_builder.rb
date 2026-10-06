# frozen_string_literal: true

require "date"

module Decidim
  module ContractsSk
    module SpreadsheetImport
      # Builds and validates ONE spreadsheet row (civora-org/civora-platform
      # #129): the contract form and the party forms are the editor's own
      # (Admin::ContractForm, Admin::PartyForm), so a row passes exactly when
      # the same values would pass the admin form. On top of the forms it
      # applies the import-specific guards: strict dates, hostile cells
      # (control characters, formula starts) and the party list shape.
      # Reference collisions need the whole file and live in Preview.
      class RowBuilder
        # One CSV row: its starting line, the raw (stripped) cells, the
        # validated forms and the human-readable errors.
        Row = Struct.new(:line, :cells, :contract_form, :party_forms, :errors, keyword_init: true) do
          def ok?
            errors.empty?
          end
        end

        # Free-text columns checked for formula injection (a cell a
        # spreadsheet would evaluate); the trigger set is the export's
        # neutralizer, single-sourced from the serializer.
        TEXT_COLUMNS = %w[reference title subject_matter crz_url party_names].freeze

        # C0/C1 control characters (tab, LF and CR excepted) and the bidi
        # override/isolate characters: never legitimate in a contract record.
        HOSTILE_CHARS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F‪-‮⁦-⁩]/
        ISO_DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/
        SK_DATE = /\A(\d{1,2})\.\s?(\d{1,2})\.\s?(\d{4})\z/
        COMMA_AMOUNT = /\A-?\d+,\d+\z/
        YEARS = (1900..2100)

        def initialize(line, cells)
          @line = line
          @cells = cells
          @errors = []
        end

        def call
          form = contract_form
          @party_columns = PartyColumns.new(@cells)
          parties = party_forms
          hygiene_errors
          form_errors(form)
          party_errors(parties)
          Row.new(line: @line, cells: @cells, contract_form: form, party_forms: parties, errors: @errors)
        end

        private

        def contract_form
          attributes = {
            title: @cells["title"], reference: @cells["reference"], subject_matter: @cells["subject_matter"].presence,
            amount: amount_value, crz_url: @cells["crz_url"].presence,
            signed_on: date_value("signed_on"), effective_from: date_value("effective_from")
          }
          attributes[:currency] = @cells["currency"].upcase if @cells["currency"].present?
          Admin::ContractForm.new(attributes)
        end

        # Slovak spreadsheets write "1250,50": accepted as the one comma
        # decimal shape; everything else is left to the form's strict check.
        def amount_value
          raw = @cells["amount"]
          return nil if raw.blank?

          raw.match?(COMMA_AMOUNT) ? raw.tr(",", ".") : raw
        end

        # Strict: ISO (2026-03-31) or Slovak day-first (31.3.2026). The
        # form's :date cast would silently turn garbage into nil, so an
        # unparsable value is reported here instead of vanishing.
        def date_value(column)
          raw = @cells[column]
          return nil if raw.blank?

          date = parse_date(raw)
          @errors << error(:invalid_date, field: column) unless date
          date
        end

        def parse_date(raw)
          year, month, day = date_parts(raw)
          return nil unless year && YEARS.cover?(year) && Date.valid_date?(year, month, day)

          Date.new(year, month, day)
        end

        def date_parts(raw)
          if (m = raw.match(ISO_DATE))
            m.captures.map(&:to_i)
          elsif (m = raw.match(SK_DATE))
            m.captures.map(&:to_i).values_at(2, 1, 0)
          end
        end

        # The parallel party columns (PartyColumns): none, or a list that
        # lines up with the names; anything else invalidates the row.
        def party_forms
          return [] if @party_columns.blank?
          return @party_columns.forms if @party_columns.aligned?

          @errors << error(:party_count_mismatch)
          []
        end

        def hygiene_errors
          @errors << error(:extra_cells) if @cells["__extra"].positive?
          @errors << error(:too_many_parties, max: PartyColumns::MAX_PARTIES) if too_many_parties?
          control_char_errors
          TEXT_COLUMNS.each { |column| @errors << error(:formula, field: column) if formula?(column) }
        end

        def control_char_errors
          @cells.except("__extra").each do |column, value|
            @errors << error(:control_chars, field: column) if value.match?(HOSTILE_CHARS)
          end
        end

        # A cell a spreadsheet would run as a formula (=, +, -, @ ... after
        # optional whitespace) is refused, never stored: the export
        # neutralizes on the way out, the import refuses on the way in.
        def formula?(column)
          segments = column == "party_names" ? @party_columns.names : [@cells[column].to_s]
          segments.any? { |segment| segment.match?(OpenData::ContractRecord::FORMULA_START) }
        end

        def too_many_parties?
          @party_columns.name_count > PartyColumns::MAX_PARTIES
        end

        def form_errors(form)
          form.valid?
          form.errors.each { |e| @errors << error(:field_error, field: e.attribute, message: e.message) }
        end

        def party_errors(parties)
          parties.each_with_index do |party, index|
            party.valid?
            party.errors.each do |e|
              @errors << error(:party_error, number: index + 1, field: e.attribute, message: e.message)
            end
          end
        end

        def error(code, **detail)
          I18n.t("decidim.contracts_sk.admin.contract_imports.row_errors.#{code}", **detail)
        end
      end
    end
  end
end
