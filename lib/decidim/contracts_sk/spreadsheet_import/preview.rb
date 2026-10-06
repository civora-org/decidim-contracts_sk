# frozen_string_literal: true

module Decidim
  module ContractsSk
    module SpreadsheetImport
      # The dry run (civora-org/civora-platform#129): reads a CSV upload and
      # validates EVERY row with the same rules as the admin contract form
      # (RowBuilder), plus the file-wide reference checks (a repeat inside
      # the file, a reference the organization already holds). It writes
      # nothing. The import command takes a fresh Preview built from the
      # re-posted text and refuses unless #importable? — the preview screen
      # is never the gate.
      #
      # All-or-nothing: #importable? is true only when the file is readable
      # and EVERY row is valid, so a file is never half-imported. A re-import
      # of an already imported file is therefore refused whole (its
      # references are taken), which is the idempotency guarantee.
      class Preview
        Row = RowBuilder::Row

        attr_reader :problems, :rows, :ignored_columns, :text

        def initialize(bytes, organization:, max_bytes: MAX_BYTES)
          result = Reader.call(bytes, max_bytes: max_bytes)
          @problems = result.problems
          @ignored_columns = result.ignored_columns
          @text = result.text
          @organization = organization
          @rows = result.rows.map { |line, cells| RowBuilder.new(line, cells).call }
          flag_references
        end

        def importable?
          problems.empty? && rows.any? && rows.all?(&:ok?)
        end

        def invalid_rows
          rows.reject(&:ok?)
        end

        private

        attr_reader :organization

        # Duplicate references: within the file (every repeat names the
        # first line) and against records the organization already holds.
        def flag_references
          taken = existing_references
          first_seen = {}
          rows.each do |row|
            reference = row.cells["reference"]
            next if reference.blank?

            row.errors << error(:reference_taken) if taken.include?(reference)
            flag_repeat(row, reference, first_seen)
          end
        end

        def flag_repeat(row, reference, first_seen)
          if first_seen.key?(reference)
            row.errors << error(:duplicate_in_file, line: first_seen[reference])
          else
            first_seen[reference] = row.line
          end
        end

        def existing_references
          references = rows.map { |row| row.cells["reference"] }.compact_blank.uniq
          return Set.new if references.empty? || organization.nil?

          Contract.where(decidim_organization_id: organization.id, reference: references).pluck(:reference).to_set
        end

        def error(code, **detail)
          I18n.t("decidim.contracts_sk.admin.contract_imports.row_errors.#{code}", **detail)
        end
      end
    end
  end
end
