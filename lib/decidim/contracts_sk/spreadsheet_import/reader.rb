# frozen_string_literal: true

require "csv"

module Decidim
  module ContractsSk
    # Bulk import of existing contracts from a spreadsheet saved as CSV
    # (civora-org/civora-platform#129). The Reader is the hostile-input
    # boundary: bytes in, a header list plus raw cell rows (with their line
    # numbers) or a list of file-level problems out. It knows nothing about
    # contracts, Rails or the database; Preview owns the per-row rules.
    module SpreadsheetImport
      # Hard caps, documented in docs/spreadsheet-import.md. The byte cap is
      # checked BEFORE decoding or parsing, the row cap stops the parse as
      # soon as it is exceeded, and the field cap makes the CSV parser abort
      # a runaway quoted cell instead of buffering it.
      MAX_BYTES = 512 * 1024
      MAX_ROWS = 500
      MAX_FIELD_SIZE = 5_000

      # The recognised columns: the open-data CSV export's names (docs/
      # open-data.md), so export -> import round-trips. Export columns
      # outside this list (published_at, source, url) are ignored on purpose.
      KNOWN_COLUMNS = %w[
        reference title subject_matter amount currency signed_on effective_from
        crz_url party_roles party_icos party_names
      ].freeze
      REQUIRED_COLUMNS = %w[reference title].freeze

      # A file-level problem: a stable code (the locale key under
      # admin.contract_imports.errors) plus interpolation values.
      Problem = Struct.new(:code, :detail, keyword_init: true)

      # +rows+ is an array of [line, { column => cell }]; +text+ is the
      # decoded UTF-8 text (BOM removed), which the preview re-posts.
      Result = Struct.new(:problems, :rows, :ignored_columns, :text, keyword_init: true) do
        def ok?
          problems.empty?
        end
      end

      # Cop note: one cohesive hostile-input pipeline (size, encoding,
      # delimiter, headers, rows); splitting it would scatter the guards.
      class Reader
        UTF8_BOM = "\xEF\xBB\xBF".b.freeze

        def self.call(bytes, max_bytes: MAX_BYTES)
          new(bytes, max_bytes).call
        end

        def initialize(bytes, max_bytes)
          @bytes = bytes.to_s.b
          @max_bytes = max_bytes
        end

        def call
          return failure(:too_large, max: @max_bytes / 1024) if @bytes.bytesize > @max_bytes
          return failure(:empty) if @bytes.strip.empty?
          # NUL bytes never occur in a text CSV: they mark XLSX (a zip),
          # UTF-16 exports and other binary files (and PostgreSQL refuses
          # them in text columns anyway).
          return failure(:not_text) if @bytes.include?("\x00".b)

          text = decode
          return failure(:encoding) unless text

          parse(text)
        end

        private

        # UTF-8 (BOM or not) first; anything that is not valid UTF-8 is read
        # as Windows-1250, the Slovak Excel default. A byte Windows-1250
        # leaves undefined means we cannot read the file reliably.
        def decode
          data = @bytes.start_with?(UTF8_BOM) ? @bytes.byteslice(3..) : @bytes
          utf8 = data.dup.force_encoding(Encoding::UTF_8)
          return utf8 if utf8.valid_encoding?

          data.dup.force_encoding(Encoding::Windows_1250).encode(Encoding::UTF_8)
        rescue EncodingError
          nil
        end

        def parse(text)
          @line = 1
          csv = CSV.new(text, col_sep: delimiter(text), max_field_size: MAX_FIELD_SIZE)
          _, headers = next_nonblank(csv)
          return failure(:empty) if headers.nil?

          normalized = headers.map { |header| header.to_s.strip.downcase }
          problem = header_problem(normalized)
          return failure(problem.code, **problem.detail) if problem

          collect_rows(csv, normalized, text)
        rescue CSV::MalformedCSVError
          failure(:malformed, line: @line)
        end

        # Physical line numbers for the error report. The parser's own
        # counter skips blank lines and miscounts multi-line cells, so the
        # reader keeps its own: a row starts where the previous one ended,
        # and a quoted cell may span several lines. Returns [line, cells].
        def shift_row(csv)
          cells = csv.shift
          return nil unless cells

          start = @line
          @line += 1 + cells.sum { |cell| cell.to_s.count("\n") }
          [start, cells]
        end

        # Blank lines are skipped by the reader, not the parser, so that
        # they still advance the line counter.
        def next_nonblank(csv)
          while (row = shift_row(csv))
            return row unless blank_row?(row.last)
          end
          nil
        end

        def blank_row?(cells)
          cells.all? { |cell| cell.to_s.strip.empty? }
        end

        # The Excel profile of the export separates with ";" — pick the
        # delimiter that is more frequent on the header line.
        def delimiter(text)
          header_line = text.lines.first.to_s
          header_line.count(";") > header_line.count(",") ? ";" : ","
        end

        def header_problem(normalized)
          missing = REQUIRED_COLUMNS - normalized
          return Problem.new(code: :missing_headers, detail: { columns: missing.join(", ") }) if missing.any?

          duplicate = normalized.select { |name| KNOWN_COLUMNS.include?(name) }.tally.find { |_, n| n > 1 }
          Problem.new(code: :duplicate_header, detail: { column: duplicate.first }) if duplicate
        end

        def collect_rows(csv, headers, text)
          rows = []
          while (row = shift_row(csv))
            line, cells = row
            next if blank_row?(cells)
            return failure(:too_many_rows, max: MAX_ROWS) if rows.size >= MAX_ROWS

            rows << [line, row_cells(headers, cells)]
          end
          return failure(:empty) if rows.empty?

          Result.new(problems: [], rows: rows, text: text,
                     ignored_columns: headers.reject { |name| KNOWN_COLUMNS.include?(name) || name.empty? })
        end

        # Known columns only, stripped. Cells beyond the header width are not
        # silently dropped: the count rides along under "__extra" so the row
        # can be reported.
        def row_cells(headers, cells)
          known = headers.zip(cells).select { |name, _| KNOWN_COLUMNS.include?(name) }
          known.to_h { |name, cell| [name, cell.to_s.strip] }.merge("__extra" => [cells.size - headers.size, 0].max)
        end

        def failure(code, **detail)
          Result.new(problems: [Problem.new(code: code, detail: detail)], rows: [], ignored_columns: [], text: nil)
        end
      end
    end
  end
end
