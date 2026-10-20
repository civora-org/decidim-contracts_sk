# Contract template services

Pure Ruby service objects for the contract-template feature ([civora-org/civora-platform#211](https://github.com/civora-org/civora-platform/issues/211)). They take and return bytes: no models, no controllers. LibreOffice is reached only through the converter seam below. Code is in `lib/decidim/contracts_sk/templates/`. The toolchain choices come from [the S1 spike](spikes/contract-templates-toolchain.md).

| Service | Call | Returns |
|---|---|---|
| `TemplateLinter` | `call(docx_bytes)` | `Result` with `errors`, `warnings`, `merge_fields`, `control_fields`, `ok?` |
| `DocxSanitizer` | `call(docx_bytes)` | clean `.docx` bytes |
| `DocxFiller` | `call(template_bytes, values)` | filled `.docx` bytes (sablon 0.4.3) |
| `PublicationVariant` | `values_for(values, personal_keys)` | a copy of `values` with personal values replaced by `[osobné údaje – skryté]` |
| `Words` | `for_amount(amount)` | "slovom" text, via `AmountInWords` |
| `PdfConverter::LibreOfficeCli` / `Fake` | `call(docx_bytes)` | PDF bytes |
| `PdfMetadata` | `blank(pdf_bytes)` | PDF bytes with blank Title, Author, Subject, Keywords, Creator, Producer |
| `DocumentGenerator` | `call(template_bytes:, values:, personal_keys:)` | `{internal_docx:, internal_pdf:, publication_docx:, publication_pdf:}` |
| `RedactionVerifier` | `call(docx_bytes:, pdf_bytes: nil, personal_values:)` | `Result` with `leaks`, `errors`, `ok?` |

## Linter

Errors block a template: macros (`vbaProject`, macro-enabled content type), OLE embeddings, `altChunk`, any external relationship, a `DOCTYPE`, malformed XML, a field other than `MERGEFIELD`, `PAGE` or `NUMPAGES`, `MERGEFIELD FORMULA` (LibreOffice mangled it), a merge field that is not written `MERGEFIELD =name \* MERGEFORMAT` (sablon would leave it unfilled), and zip bombs (caps in `Package`: 25 MB input, 1000 entries, 32 MB per entry, 96 MB in total, counted while inflating).

Warnings: comments, tracked changes, hidden text, embedded media.

`merge_fields` lists insertion fields with the `=` removed (`cislo_zmluvy`, `p.nazov`), from the body, headers, footers and notes. Sablon control fields (`priloha:if`, `polozky:each(p)`) are listed apart in `control_fields`.

## Filler

Values are strings the caller has already formatted. Allowed: `String`, `nil`, `true`, `false`, a `Hash`, or an `Array` of `Hash` (a table-row loop). A `nil` or `false` value removes an optional block. Keys must be plain identifiers: sablon reads a key shaped `type:name` as typed content (`image:` reads a file), so such keys raise `ArgumentError`.

## Verifier

Fails closed: an empty value list, an unreadable package, a part it cannot inspect, an encrypted or text-less PDF are errors, never a pass. A `Leak` carries the location, the match kind (`:value` or `:word`) and the index into `personal_values`, never the value. Text is compared without whitespace, invisible format characters and diacritics, case-insensitively; a rodné číslo matches with and without the slash; each word of a multi-word value (4+ characters, not a common word such as "ulica" or "mesto") is also searched on its own.

## PDF converter seam

`Decidim::ContractsSk.pdf_converter` is any callable that takes .docx bytes and returns PDF bytes. The host may assign its own (a Gotenberg adapter, say); the default is `PdfConverter::LibreOfficeCli.new`, and `nil` restores it.

`LibreOfficeCli` writes the input to a private temp directory (also the LibreOffice profile and HOME), runs `soffice --headless --norestore -env:UserInstallation=... --convert-to pdf` with only `PATH` and `HOME` in the environment, in its own process group, and removes the directory in `ensure`. Options: `timeout:` (60 s; on expiry the whole group gets SIGKILL), `max_input_bytes:` (25 MB), `soffice:` (name or absolute path), `path:`. soffice exits 0 on garbage, so the output must start with `%PDF`, parse with pdf-reader and have at least one page (`PdfConverter.validate!`).

Errors, all under `PdfConverter::Error`: `ConversionTimeout`, `ConversionFailed` (bad or oversized input, non-zero exit, no or invalid output), `ConverterUnavailable` (soffice missing or not executable). Messages never carry document content.

`PdfConverter::Fake` returns a deterministic PDF whose text is the folded text of the docx paragraphs, with marker Info strings. The default suite uses it; examples tagged `:libreoffice` use the real binary and are skipped when `soffice` is not on PATH.

## Document generator

`DocumentGenerator.call(template_bytes:, values:, personal_keys:)` fills, sanitizes and converts the internal variant, builds the publication values with `PublicationVariant`, does the same for them, then runs `RedactionVerifier` on the publication docx and pdf. A leak, or anything the verifier cannot inspect, raises `RedactionFailed` (locations and kinds only, never values) and nothing is returned. `personal_keys` must not be empty. When no personal key holds a value there is nothing to verify and the verifier is skipped. Both PDFs go through `PdfMetadata.blank`.

`PdfMetadata` overwrites the Info strings in place with spaces of the same length: no PDF writer is needed (hexapdf is AGPL), every xref offset stays valid, and the old text is gone from the bytes. It re-reads the result with pdf-reader and raises on anything it cannot rewrite safely: encryption, an incremental update, XMP metadata, an Info object inside an object stream, an indirect string. LibreOffice's plain PDF export has none of these. Dates and other keys are left alone.

## Limits

- The verifier reads text. Text drawn as an image, or in a font without a Unicode map, is invisible to it.
- The sanitizer keeps a hidden run that holds a field marker (removing half a field corrupts it) and does not touch text hidden by a style in `styles.xml`; the verifier still sees both.
- The synthetic fixtures are rebuilt by `spec/fixtures/files/contract_templates/build_synthetic_template.py` and `build_pdf_fixtures.rb`.
