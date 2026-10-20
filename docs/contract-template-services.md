# Contract template services

Pure Ruby service objects for the contract-template feature ([civora-org/civora-platform#211](https://github.com/civora-org/civora-platform/issues/211)). They take and return bytes: no models, no controllers, no LibreOffice. Code is in `lib/decidim/contracts_sk/templates/`. The toolchain choices come from [the S1 spike](spikes/contract-templates-toolchain.md).

| Service | Call | Returns |
|---|---|---|
| `TemplateLinter` | `call(docx_bytes)` | `Result` with `errors`, `warnings`, `merge_fields`, `control_fields`, `ok?` |
| `DocxSanitizer` | `call(docx_bytes)` | clean `.docx` bytes |
| `DocxFiller` | `call(template_bytes, values)` | filled `.docx` bytes (sablon 0.4.3) |
| `PublicationVariant` | `values_for(values, personal_keys)` | a copy of `values` with personal values replaced by `[osobné údaje – skryté]` |
| `Words` | `for_amount(amount)` | "slovom" text, via `AmountInWords` |
| `RedactionVerifier` | `call(docx_bytes:, pdf_bytes: nil, personal_values:)` | `Result` with `leaks`, `errors`, `ok?` |

## Linter

Errors block a template: macros (`vbaProject`, macro-enabled content type), OLE embeddings, `altChunk`, any external relationship, a `DOCTYPE`, malformed XML, a field other than `MERGEFIELD`, `PAGE` or `NUMPAGES`, `MERGEFIELD FORMULA` (LibreOffice mangled it), a merge field that is not written `MERGEFIELD =name \* MERGEFORMAT` (sablon would leave it unfilled), and zip bombs (caps in `Package`: 25 MB input, 1000 entries, 32 MB per entry, 96 MB in total, counted while inflating).

Warnings: comments, tracked changes, hidden text, embedded media.

`merge_fields` lists insertion fields with the `=` removed (`cislo_zmluvy`, `p.nazov`), from the body, headers, footers and notes. Sablon control fields (`priloha:if`, `polozky:each(p)`) are listed apart in `control_fields`.

## Filler

Values are strings the caller has already formatted. Allowed: `String`, `nil`, `true`, `false`, a `Hash`, or an `Array` of `Hash` (a table-row loop). A `nil` or `false` value removes an optional block. Keys must be plain identifiers: sablon reads a key shaped `type:name` as typed content (`image:` reads a file), so such keys raise `ArgumentError`.

## Verifier

Fails closed: an empty value list, an unreadable package, a part it cannot inspect, an encrypted or text-less PDF are errors, never a pass. A `Leak` carries the location, the match kind (`:value` or `:word`) and the index into `personal_values`, never the value. Text is compared without whitespace, invisible format characters and diacritics, case-insensitively; a rodné číslo matches with and without the slash; each word of a multi-word value (4+ characters, not a common word such as "ulica" or "mesto") is also searched on its own.

## Limits

- The verifier reads text. Text drawn as an image, or in a font without a Unicode map, is invisible to it.
- The sanitizer keeps a hidden run that holds a field marker (removing half a field corrupts it) and does not touch text hidden by a style in `styles.xml`; the verifier still sees both.
- The synthetic fixtures are rebuilt by `spec/fixtures/files/contract_templates/build_synthetic_template.py` and `build_pdf_fixtures.rb`.
