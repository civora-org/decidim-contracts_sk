# Open data: CSV and JSON export and Atom feed of published contracts

Landed in civora-org/civora-platform#119. Machine-readable downloads of the organization's published contracts, honouring the same filters as the catalogue. With the engine mounted at `/zmluvy`:

| Endpoint | Format |
|---|---|
| `GET /zmluvy/export.csv` | UTF-8 CSV with a byte-order mark (opens correctly in Excel) |
| `GET /zmluvy/export.json` | one JSON array of objects |

Read-only, no authentication (a host that forces sign-in for the whole site forces it here too). Anything else (`/export`, `/export.xml`, ...) is the catalogue's ordinary 404.

## What is exported

**The organization's own records only.** Exactly the contracts that are lifecycle-published, belong to the current organization and have `source: "editorial"`. Never exported: drafts, records in review, archived or rejected records, other organizations' records, and **records mirrored from CRZ**.

Why mirrors are excluded: ADR-008 decision 6 makes the CRZ mirror a link-only pointer to the canonical record, and the #83 spike found that CRZ declares no reuse licence (publication is statutory: zákon 211/2000 §5a, nariadenie vlády 498/2011) while the ekosystem.slovensko.digital terms require attribution to be preserved. Until the reuse basis is settled with a lawyer, mirrors are linked back to crz.gov.sk, not re-published as data. `?source=crz` therefore yields an honest empty export (header only for CSV, `[]` for JSON), and the catalogue hides its download links and points to crz.gov.sk when that filter is active.

## Parameters

The same filter keys as the catalogue (`q`, `amount_min`, `amount_max`, `published_from`, `published_to`, `signed_from`, `signed_to`, `party`, `source`), normalized the same way (an invalid value is ignored, a reversed range is swapped; see [contracts-domain-notes.md](contracts-domain-notes.md#catalogue-filters-and-sorting-landed-in-116)). `published_from`/`published_to` filter the **publication date**, as in the catalogue: the CRZ publication date where the record carries one (e.g. one confirmed as filed), else the date it entered the catalogue (#159); the export's `published_at` column stays "entered the catalogue". `sort` and `page` are not read: the export is always **ordered by id ascending** and is never paginated. The catalogue's download links carry the active filters.

- `profile=excel` (CSV only): `;` as the separator and a decimal comma in `amount` (`1250,50`). Any other value, or none, gives the default profile: `,` separator and a decimal point (`1250.50`).

## Fields

The whitelist is `Decidim::ContractsSk::OpenData::ContractRecord::FIELDS`; this table is pinned to it, and no other attribute is ever serialized. The CSV header is exactly the column list below; the JSON keys are the same, except that the three `party_*` columns become one `parties` array. **Column and key names are stable**: new fields may be appended, existing ones are not renamed or reordered without a major release.

| CSV column | JSON key | Content |
|---|---|---|
| `reference` | `reference` | the organization's reference number |
| `title` | `title` | contract title |
| `subject_matter` | `subject_matter` | subject of the contract |
| `amount` | `amount` | contract value; CSV: text with two decimals, never scientific; JSON: a number |
| `currency` | `currency` | ISO code (EUR) |
| `signed_on` | `signed_on` | signing date, `YYYY-MM-DD` |
| `effective_from` | `effective_from` | effective date, `YYYY-MM-DD` |
| `published_at` | `published_at` | moment of publication in the catalogue, ISO 8601 in UTC (`2026-09-01T12:00:00Z`) |
| `source` | `source` | `editorial` (always, see above) |
| `crz_url` | `crz_url` | link to the CRZ record when one was recorded |
| `party_roles`, `party_icos`, `party_names` | `parties` | parties, see below |
| `url` | `url` | absolute URL of the public detail page |

Missing values are an empty CSV cell and `null` in JSON. Dates never depend on the viewer's locale or time zone.

**Parties.** Only parties **with a well-formed IČO (8 digits)** are exported; a party without an IČO (typically a natural person) is dropped entirely, name included. Parties are ordered by role (`contractor` before `object`), then by id. CSV: three parallel columns whose values are joined with ` | ` and line up position by position. JSON: `"parties": [{"role": "contractor", "ico": "87654321", "name": "..."}]`. Party addresses are never exported. Note that the `party` filter still matches parties without an IČO: their names are not exported, but the filter can select contracts that involve them (they are already listed on the public detail page).

**Never exported:** review reasons and review timestamps, the redaction-confirmation stamp, author and submitter, CRZ filing data, import provenance (`source_id`, checksum, import status), documents, amendments.

## CSV details

- UTF-8, a leading byte-order mark, `\n` row endings, RFC 4180-style quoting (embedded quotes, separators and newlines are quoted), LF row endings.
- **Spreadsheet formula injection.** A text cell (`reference`, `title`, `subject_matter`, `crz_url`, `party_names`) that starts with `=`, `+`, `-`, `@`, a tab or a carriage return gets a leading `'` so that Excel and LibreOffice treat it as text. If you parse the file with code and compare titles, strip that single leading apostrophe. JSON is never altered.
- File name: `contracts-YYYY-MM-DD.csv` (the date in the organization's time zone), sent as an attachment. JSON uses `.json`.

## Streaming, caching and limits

- The body streams in batches of 500 records (`OpenDataController::EXPORT_BATCH_SIZE`), so memory stays flat however large the catalogue grows. Records are read in id order; a record published while a download is running may or may not appear.
- If the database fails mid-download the response has already started: the connection is aborted (no clean end), so a client sees a truncated file or invalid JSON. The export logs the exception class and the last record id only; the re-raised exception itself still reaches the server and any error tracker with its message.
- The response carries an `ETag` derived from the organization, format, profile, the normalized filters, the record count and the newest `updated_at`; `If-None-Match` is answered with `304`. There is no `Last-Modified`.
- Decidim's `rack_attack` throttling (production) applies to these URLs like to any other; consumers should cache and respect `304`.

## Atom feed of new contracts

Landed in civora-org/civora-platform#120. `GET /zmluvy/feed.atom` is an Atom (RFC 4287) feed of the newest published contracts, for readers, journalists and watchdog tools. It is announced on the catalogue page by a `<link rel="alternate" type="application/atom+xml">` in the page head, and by an "Atom feed" button in the download block.

- **Same scope as the export.** The organization's own lifecycle-published records only; CRZ mirrors are never listed (see above), so `?source=crz` gives a valid, empty feed (the catalogue then omits the head link and the button). The filters are the catalogue's (`q`, `amount_*`, `published_*`, `signed_*`, `party`, `source`); the filters are echoed in the feed's subtitle, its `self` link and its id.
- **Always newest first, 50 entries at most.** `sort` and `page` are ignored: the publication date descending (the CRZ date where the record carries one, e.g. a record confirmed as filed, else `published_at`; the catalogue's sort, #159), then id descending. The entries' `published`/`updated` stamps stay `published_at`. A feed is "what is new"; use the export for the whole set. `/feed` is the catalogue's ordinary 404 (a non-HTML unknown format such as `/feed.rss` is a known pre-existing host gap: Decidim has no xml error template, so it answers 500).
- **Feed.** `title` "Zmluvy — <organization name>" (the organization's name in the reader's locale, falling back to its default locale, then any translation, then its host), `subtitle`, `author` (the organization name), `updated` (the newest entry's `published_at`; for an empty feed the organization's creation date, so the value is stable), `link rel=self` (filters plus the request locale, identical to the catalogue's Atom button and head link, so subscribing from the English page gives the English feed; the ids ignore the locale), `link rel=alternate` (the catalogue), `id`. `xml:lang` is the request locale.
- **Entry.** `title` (the contract title), `link rel=alternate` (the detail page), `summary` (plain text: reference, amount, signing date, whichever are known), `published` and `updated` (both the record's `published_at`: the feed announces publication, not later edits), `id`.
- **Stable ids.** Tag URIs (RFC 4151), minted once and never changed: entry `tag:<host>,2026:contracts_sk/contract/<id>`, feed `tag:<host>,2026:contracts_sk/feed` plus `?<normalized filters, sorted by key>` when filtered. `<host>` is the organization's host (the request host when it has none). Readers therefore see an unchanged id however the filters were ordered or their numbers and dates spelled (the search term `q` is case-sensitive: `Cesta` and `cesta` are different feeds), and a record never turns into a new entry because it was edited.
- **Well-formed by construction.** All text goes through the XML builder's escaping; markup characters are escaped and characters XML 1.0 forbids (control characters, NUL) are replaced, so a hostile title cannot break the feed.
- **Caching.** No explicit headers; the host's `Rack::ETag` digests the small body, so `If-None-Match` is answered with `304`. Decidim's `rack_attack` throttling (production) applies; readers should poll at a modest rate.

## Licence

The municipality decides under which licence it publishes this data; the engine states none. A sensible default is **Creative Commons Attribution 4.0 (CC BY 4.0)** with an attribution such as: "Contract data of <organization name>, published at <catalogue URL>, licensed under CC BY 4.0." Put the chosen licence on the page your organization links from Decidim's Open Data page (below) and in any dataset listing.

## Host follow-up: Decidim's Open Data page

Decidim's own Open Data page does not list contracts. The host can add a sentence and a link, for example:

- sk: "Zverejnené zmluvy organizácie sú dostupné ako otvorené dáta vo formátoch CSV a JSON: <odkaz na /zmluvy>. Licencia: <licencia organizácie>."
- en: "The organization's published contracts are available as open data in CSV and JSON: <link to /zmluvy>. Licence: <the organization's licence>."

The catalogue page itself carries the "Download data" block, so the link can point there.
