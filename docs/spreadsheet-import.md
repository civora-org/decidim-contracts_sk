# Spreadsheet import: onboarding an existing contract list as drafts

Landed in civora-org/civora-platform#129. An editor uploads a CSV with the municipality's existing contract list, sees a per-row preview (a dry run that writes nothing) and confirms. Admin pages: `/admin/contracts/import` (upload), `POST /admin/contracts/import/preview` (dry run), `POST /admin/contracts/import` (import). The entry button is on the admin contracts index.

## Product rules

- **Drafts only.** Every row becomes a `draft` owned by the importing user, source `editorial`, with no submitter stamp, no redaction confirmation and no publication stamp. The import never publishes: each record still goes through submit, second-person review (four-eyes, #123), redaction confirmation and publication.
- **All-or-nothing.** If any row has an error nothing is saved, and the confirm button does not appear. The import also re-parses the posted text and refuses unless every row is valid, so a tampered or stale preview cannot import anything. The whole batch runs in one transaction.
- **Idempotent re-import.** References the organization already holds are errors, so uploading the same file twice is refused whole and adds nothing. Fix the file (drop the rows already imported) and upload again.
- **Audit.** One `contract.imported_from_file` audit row per created record (shown as "Imported from a spreadsheet" in the audit trail), by the importing user.
- **Permission.** `:import_file`, editors only (reviewers are denied), like the CRZ import.
- **No extra personal data.** Only the fields of the normal contract and party forms are stored (party address is not importable). The uploaded file itself is never stored: the preview re-posts its text in a hidden field, and nothing is kept after the request.

## Format

CSV only (UTF-8 with or without a byte-order mark, or Windows-1250; comma or semicolon separated). Excel `.xlsx` is **not** read: save the sheet as CSV. The header row uses the names of the open-data export (docs/open-data.md), so an export can be re-imported:

| Column | Required | Notes |
|---|---|---|
| `reference`, `title` | yes | max 255 characters |
| `subject_matter` | no | |
| `amount` | no | `1250.50` or `1250,50`; non-negative, up to 9 999 999 999.99. No thousands separators, no `1e5`. |
| `currency` | no | `EUR` (default) |
| `signed_on`, `effective_from` | no | `2026-03-31` or `31.3.2026`; an unparsable date is an error, never silently dropped |
| `crz_url` | no | http(s) link |
| `party_roles`, `party_icos`, `party_names` | no | parallel lists separated by `\|`. `party_roles` is `object` or `contractor` (contractor when the column is omitted); `party_icos` is 8 digits or empty; `party_names` required per party. Lists must be omitted or have one value per name. Max 10 parties. |

Other columns (the export's `published_at`, `source`, `url`, or anything else) are ignored and named in the preview. Column names are case-insensitive; order does not matter. There is no column-mapping screen: rename the headers in the spreadsheet.

## Limits

- **512 KB per file** (`SpreadsheetImport::MAX_BYTES`), checked before parsing; at most **500 data rows** (`MAX_ROWS`); a single cell at most 5 000 characters. The re-posted text on confirm is capped at 1 MB.
- Blank rows are skipped; line numbers in the report are physical file lines (the header is line 1).

## Hostile input

- **Formula injection.** A text cell (`reference`, `title`, `subject_matter`, `crz_url`, party names) starting with `=`, `+`, `-`, `@` (after optional whitespace, also fullwidth variants, or a tab/CR/LF) is refused as a row error, not stored. The export prefixes such cells with `'`; a re-imported cell therefore comes back with that apostrophe as plain text.
- **Encoding.** Bytes that are not valid UTF-8 are read as Windows-1250; bytes undefined there, NUL bytes (xlsx, UTF-16 and other binaries) are refused with a readable message.
- **Control and bidi characters** (other than tab, LF, CR) are row errors. All values are HTML-escaped when rendered.
- **Malformed CSV** (unclosed quote, oversized cell) reports the line; extra cells beyond the header width are a row error.
- **Duplicates** inside the file name the first line; references already in the organization (any state) are errors; tenancy is the current organization.

## Tests

`spec/decidim/contracts_sk/spreadsheet_import/` (reader, preview, round trip with the export), `spec/decidim/contracts_sk/admin/import_contracts_spec.rb` (command), `spec/requests/admin/contract_imports_spec.rb` (flow, permissions, hostile files). Fixtures: `spec/fixtures/files/spreadsheet_import/` (fictional `DEMO-*` data).
