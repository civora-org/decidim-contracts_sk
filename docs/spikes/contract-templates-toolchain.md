# Spike: contract-template toolchain (LibreOffice, sablon, redaction)

Step S1 of [civora-org/civora-platform#211](https://github.com/civora-org/civora-platform/issues/211), run 2026-10-20. Everything below was measured in a throwaway container (`debian:trixie-slim`, arm64, LibreOffice 25.2.3.2, Docker/OrbStack on a Mac). The scratch Ruby project used sablon 0.4.3, pdf-reader 2.16.0, nokogiri 1.19.4 and rubyzip 2.4.1 on Ruby 3.3.4. No engine code changed, and no real template or personal data is in this repository.

## Verdict

**GO** on the approved toolchain: LibreOffice in the host image, sablon for filling, redaction by a fixed block, pdf-reader for verification. Five findings change the plan; see [section 6](#6-what-changes-in-the-plan).

| # | Question | Verdict | Headline number |
|---|---|---|---|
| 1 | `.doc` to `.docx` keeps the layout | GO | 3 pages in and out; 2 of 3 pages pixel-identical, page 3 differs by 0.05% |
| 2 | sablon fills MERGEFIELDs; LibreOffice renders them to PDF | GO, with authoring rules | body, table loop, header, footer, repeated field, optional block all filled |
| 2b | MERGEFIELDs survive a LibreOffice round trip | NO-GO | `=name` fields become `FORMULA`; insert fields after the last LibreOffice save |
| 3 | Conversion cost | GO | 0.28 s warm, 0.63 s cold; +363 MB unpacked image |
| 4 | Redaction is verifiable | GO | 69 of 69 assertions pass; a leaked PDF swapped in fails the verifier |
| 5 | Gotenberg as a later sidecar | Viable | v8.38.1, MIT, about 440 MB compressed |

## 1. `.doc` to `.docx`

Input: the real clerk-authored NZ `.doc` (70 KB), read from outside the repository and never copied into it. Output `.docx` is 12 KB.

- Both routes give a 3-page A4 PDF: `.doc` straight to PDF, and `.doc` to `.docx` to PDF.
- At 60 dpi, pages 1 and 2 are pixel-identical between the routes. Page 3 differs by 159 pixels (0.05%).
- I looked at page 1 of both routes: headings, numbered clauses, the party block with tab stops and the footer page number all survive. The PDF embeds Liberation Sans for the template's Arial (metric-compatible), which is why `fonts-liberation` is required. Pages 2 and 3 were compared by pixels only.
- Both real files (NZ.doc and KZ.docx) contain **zero fields**. The pilot templates therefore need MERGEFIELDs inserted by hand at the dotted blanks, which is what the plan already assumed.
- The converted `.docx` keeps `dc:creator` and `cp:lastModifiedBy` from the source. Conversion does not anonymise; the sanitizer is needed (KZ.docx also carries a creator).

## 2. MERGEFIELDs

Fixtures (all invented: "Obec Vzorová", a fake buyer, fake IDs, and fake author/company metadata so the sanitizer has something to strip):

- `spec/fixtures/files/contract_templates/synthetic-template.docx`, built by `build_synthetic_template.py` next to it. It has MERGEFIELDs in the body, a table, the header and the footer; `cislo_zmluvy` repeated in the header and twice in the body; an optional block; a row loop; a PAGE field in the footer; Slovak diacritics.

sablon 0.4.3 fills all of it. Authoring rules that the spike found by failing first (these belong in the template-author guide):

1. Insertion fields are `MERGEFIELD =name \* MERGEFORMAT`. sablon anchors its pattern on the trailing `\* MERGEFORMAT`, which Word adds by itself.
2. Control fields (`x:if`, `x:endIf`, `x:each(i)`, `x:endEach`) must sit **alone in their own paragraph**. Text in the same paragraph is removed with the control field. My first fixture lost the whole optional block and the whole table this way.
3. A table-row loop needs three rows: a start row, the data row, an end row. Start and end in the same row produce no output at all.
4. Headers and footers are processed. A `PAGE` field passes through untouched, so the planned TemplateLinter must allowlist `PAGE` and `NUMPAGES` rather than reject every non-MERGEFIELD field.
5. A false or `nil` condition removes the block cleanly. Verified with a `priloha: nil` variant.

### Round trip: NO-GO

LibreOffice treats a field name that starts with `=` as a formula. After `.docx` to `.doc` to `.docx`, every `=name` field reads `MERGEFIELD FORMULA`, so the field name is gone. A plain `.docx` to `.docx` pass through LibreOffice does the same, and it also drops `\* MERGEFORMAT`, so sablon's pattern would not match anyway. Control fields (`polozky:each(p)`) survive the `.doc` round trip; insertion fields do not.

Rule: LibreOffice touches a template **at most once, before any field exists** (`.doc` to `.docx`). Fields are inserted afterwards in Word. After that the template is only read by sablon, never saved by LibreOffice. LibreOffice also converts *filled* output to PDF, which is safe because there are no fields left.

## 3. Cost and run flags

Image delta, `apt-get install` on `debian:trixie-slim` (78 packages, 104 MB unpacked, 30 MB as reported by Docker):

| Install | Packages | Unpacked | Reported image size | Build time |
|---|---|---|---|---|
| base | 78 | 104 MB | 30 MB | |
| `libreoffice-writer-nogui fonts-liberation` with `--no-install-recommends` | 218 | 467 MB (+363) | 173 MB (+142) | 26 s |
| the same without `--no-install-recommends` | 374 | 905 MB (+801) | 310 MB (+280) | 79 s |

Use `--no-install-recommends`: it halves the image and Writer still converts everything in this spike. Sizes are arm64; amd64 was not measured and should be within a few percent.

Timing (`soffice`, fresh container, native arm64; the first run includes creating a fresh profile):

| Case | Wall time |
|---|---|
| Cold, first `.doc` to `.docx` | 0.63 s |
| Warm, fresh profile each run (5 runs) | 0.28 s each |
| Warm, reused profile (5 runs) | 0.12 s, first one 0.28 s |
| `.docx` to PDF, 1 page and 3 pages | 0.30 to 0.35 s |
| `docker run` incl. container start + 3 PDF conversions | 1 s |
| 4 parallel conversions, distinct profiles | 0.63 s wall |

Memory: container peak 167 MB after three sequential conversions, 629 MB after the whole benchmark including four in parallel (cgroup `memory.peak`, includes page cache). Size the host for roughly 200 MB per concurrent conversion.

Flags the adapter should use:

```
env -i PATH=/usr/bin:/bin HOME=/tmp/lo-home LANG=C.UTF-8 \
  timeout 60 soffice --headless --norestore \
  -env:UserInstallation=file:///tmp/lo-<uuid> \
  --convert-to pdf --outdir <dir> <input.docx>
```

- A per-run profile directory works and costs only about 0.15 s over a reused one. It avoids the profile lock; two parallel runs on one shared profile happened to both succeed here, but that is not a guarantee, so keep one profile per run and delete it afterwards.
- `soffice` exits 0 even for garbage input (a text file named `.docx` produced a PDF of its text). The adapter must treat the exit status as insufficient: require the output file, the `%PDF` magic bytes and at least one page. The TemplateLinter already rejects non-docx input earlier.
- Timeout: `timeout -s KILL` and a `setsid` process-group kill both left zero orphan `soffice.bin` processes. Conversions finished in about 0.3 s, so the kill landed early and a genuine hang was **not reproduced**. Kill the whole process group on timeout and test with a stalled input in the adapter spec.
- Not measured: amd64, running as a non-root user with a read-only home. `-env:UserInstallation` under `/tmp` should cover it; the host Dockerfile task (H1) should assert it.

## 4. Redaction check

`docs/spikes/contract-templates-toolchain/fill.rb` renders three variants with sablon: full, publication (person fields replaced by `[osobné údaje – skryté]`) and publication without the optional attachment. The publication variants then go through the metadata strip (drops `dc:creator`, `cp:lastModifiedBy` and `<Company>`). LibreOffice converts all three to PDF. `verify.rb` reads the PDF text with pdf-reader and the `.docx` parts with rubyzip.

Result: **69 of 69 assertions pass**.

- The unredacted PDF contains every fake personal value (positive control), so the extraction proves something.
- Neither publication PDF contains any fake personal value or any fake author/company string; the fixed block appears 4 times (3 fields, one repeated).
- No part of either publication `.docx`, including `docProps`, contains them. The unsanitised `full.docx` still carries the fake author, so the strip is what removes it (negative control).
- The PDF Info dictionary carries `Creator: Writer`, the LibreOffice producer string, and the document `Title` from `docProps`. No author. The sanitizer should also clear or set the title.
- Mutation check: swapping the leaked PDF in as the publication PDF makes the verifier fail (10 failures).
- A multi-word value can wrap across lines or table cells. "Neexistujúce Mesto" was **not** found as a contiguous string in the unredacted PDF, because pdf-reader interleaves table cells. The verifier must therefore also search each word of 4 or more characters on its own, not just whole values. The script does both.

Limit of the approach: the verifier can only look for values it knows, namely the entered person fields. A clerk who types a name into a free-text field the template did not mark as `person` is not caught unless that exact value is also in the person fields. This stays the human confirmation's job, as the plan has it.

## 5. Gotenberg (later sidecar option)

Read from the registries; not pulled or run.

- Latest release **v8.38.1**, published 2026-10-15 ([GitHub](https://github.com/gotenberg/gotenberg)). The GitHub API reports the licence as **MIT**.
- Docker Hub `gotenberg/gotenberg`, compressed, amd64 / arm64: the LibreOffice-only tag `8.38.1-libreoffice` family about 440 / 433 MB; the full image (Chromium + LibreOffice) about 705 / 699 MB.
- Compared with in-image LibreOffice at +142 MB compressed, the sidecar costs about three times the download but gives process isolation, its own timeout and a stateless HTTP API, which is what the converter seam is for. Switching later is one adapter.

## 6. What changes in the plan

1. **Field insertion happens after conversion, in Word.** Never round-trip a template through LibreOffice once it has fields. Add this to the template-author guide and to the TemplateLinter: reject templates containing `MERGEFIELD FORMULA` (the signature of a LibreOffice round trip) with a clear message.
2. **Authoring rules for control fields** (own paragraph, own row, three-row table loop) go into the author guide and, where cheap, into the linter.
3. **TemplateLinter allowlist:** permit `PAGE` and `NUMPAGES` alongside MERGEFIELD, as in the fixture footer.
4. **DocxSanitizer** covers `dc:creator`, `cp:lastModifiedBy`, `<Company>` and should clear `dc:title`. It runs on every generated document, and a template-level pass is cheap insurance.
5. **RedactionVerifier searches per word as well as per value**, and treats the PDF Info dictionary as part of the surface.
6. **Generation can be synchronous.** Conversion is sub-second, so P5 does not need a background job; keep the 60 s timeout and a per-run profile. This keeps the "no background infrastructure" guardrail intact.
7. **Install with `--no-install-recommends`** in the host Dockerfile (H1): +142 MB compressed instead of +280 MB.

## Reproduce

Scripts are in `docs/spikes/contract-templates-toolchain/` (excluded from RuboCop). `Dockerfile` builds the throwaway image; `bench.sh` and `bench2.sh` run inside it with a work directory mounted at `/work`; `fill.rb` and `verify.rb` run from a scratch project with the `Gemfile` there. `bench.sh` expects a sample `.doc` mounted at `/in/sample.doc`; the real NZ file is deliberately not in the repository.
