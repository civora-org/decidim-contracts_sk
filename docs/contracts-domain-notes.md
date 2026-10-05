# Contracts Domain Notes — Working Context

> Purpose: shared ground truth for agents and humans about **what this module
> actually is**, what is deliberately deferred, and which decisions are already
> made. Read this before planning any Contract-schema work.
>
> Established during the #55 refinement session (2026-09-03). Sources are
> cited; when this file and an ADR disagree, the ADR wins.

## What we are building (and not building)

- **V0.1 = workflow layer, not a CRZ replacement** (ADR-002, accepted,
  `civora-org/civora-platform` → `docs/00-product/civora-adrs.md`).
  - Legal effectiveness is tied to CRZ publication, never to Civora.
  - V0.1 covers: internal draft → review → publish workflow, contract
    metadata + party data, PDF attachments, public catalogue, amendments,
    audit trail, Slovak localisation.
  - **CRZ direct integration is explicitly OUT of scope for V0.1.** Handoff
    to CRZ is manual (checklist, metadata export).
- **V0.2+ direction (stakeholder requirement, not yet an epic):**
  - pull contract data from ekosystem.slovensko.digital / CRZ;
  - render contracts as a registered Decidim *component* (today the catalogue
    is a mounted engine at `/zmluvy`, not a component — both may coexist);
  - link contracts to projects/results — the engine-side half **landed**
    (civora-org/civora-platform#87): an engine-owned polymorphic join table
    (`decidim_contracts_sk_contract_links`; real FK on the contract, NO FK on
    the polymorphic target — the AuditEvent precedent — unique
    `(contract, target)` under
    `idx_contracts_sk_contract_links_on_contract_and_target`) plus the
    config-time `supported_link_target_types` / `link_target_resolver` seams;
    the platform-level entity registry itself stays a platform concern.
  - The `integration` subagent in `.opencode/` is pre-positioned for this;
    no issue tracks it yet.

## Schema consequences already decided (in #55)

The #55 migration is the *editorial skeleton* (minimal by issue design and by
epic #3's "minimal constraints" language), but carries **manual-CRZ-handoff
provenance columns** — these are V0.1-scope per ADR-002 ("catalogue for
contracts already published via CRZ", "metadata export"), not scope creep:

| Column | Why now |
|---|---|
| `source` string, null: false, default `"editorial"` | Distinguish editor-created vs CRZ-origin records; automated import arrives later and MUST NOT change this shape |
| `source_id` string, nullable | CRZ contract identifier for handoff/matching |
| `imported_at` datetime, nullable | Freshness metadata (AGENTS.md data/import policy) |
| `import_status` string, nullable | Import lifecycle placeholder; validated against `Contract::IMPORT_STATUSES` (`pending`/`succeeded`/`failed`/`stale`, #85), still filled by hand until the integration arc consumes it |

No behavior attached to these in #55 — they shipped as data insurance while
the table was empty. #85 hardened them additively (see below): `checksum`
is no longer deferred — it exists as a nullable column (the source-payload
digest, ADR-008), and `import_status` carries a validated vocabulary. The
import arc has since landed (#86, ADR-008 — see
[`docs/crz-import.md`](crz-import.md)) and consumes all five columns;
editorial records keep them hand-free (`source` stays `"editorial"`,
import lifecycle fields stay nil).

Deferred (additive migrations later, per downstream issues): real functional
fields — subject matter text, amounts/currency, signature/effectivity dates,
  amendments/versions (#57 landed the skeleton; the lifecycle, immutability
  and the public version history landed with #65 — see below); safe document
  content validation has since landed in #64 (see below).

## Provenance hardening landed in #85

The provenance columns above gained additive schema + model guarding —
consumed by the import arc since #86 (ADR-008,
[`docs/crz-import.md`](crz-import.md)):

- **`checksum`** — nullable string column on the contracts table: the
  source-payload digest (ADR-008). No default, no backfill, no behaviour
  yet.
- **Composite index on `(organization, source, source_id)`** — the
  idempotent upsert lookup the import arc will key on. Explicit name
  `idx_contracts_sk_contracts_on_organization_id_and_source_id` (59 bytes;
  the fully spelled convention name exceeds PostgreSQL's 63-byte identifier
  limit).
- **`import_status` vocabulary** — `Contract::IMPORT_STATUSES` =
  `pending`/`succeeded`/`failed`/`stale`, validated with `allow_nil: true`
  (editorial records carry no import lifecycle). The import arc stamps it;
  until then it is filled by hand.

Since civora-org/civora-platform#88 the provenance columns are consumed by
the public catalogue as well: `source` gates the "Externally confirmed"
badge, and `imported_at`/`import_status` drive the detail-page stale
indicator (threshold `Decidim::ContractsSk.stale_after`, ADR-008 decision
4). Read-only presentation — no new writers, no schema change.

## Schema consequences landed in #56 (M02-02-B)

`decidim_contracts_sk_parties` and `decidim_contracts_sk_documents` follow
the #55 skeleton, keeping its "minimal constraints" stance:

- **Parties** — `object` (the municipality side) / `contractor` roles, frozen
  vocabulary + positional enum mirroring Contract's state wiring; optional
  `ico` is a fixed 8-digit string validated at the model layer, optional
  `address` up to 255 characters.
- **Documents** — `contract` / `crz_export` / `annex` / `other` kinds
  (frozen vocabulary; column and enum both default to `"contract"`).
- **Tenancy is derived, not stored**: neither table carries an organization
  foreign key — tenant scoping flows through `contract.organization`.
- **Real FK constraints**: `contract_id` on both tables is a database-level
  FK to `decidim_contracts_sk_contracts`; `Contract` declares
  `dependent: :destroy` for both.
- **File metadata only**: `file_name` / `content_type` / `file_size` are
  nullable descriptive columns. They carried no behaviour until the upload
  arc landed (see #73 below).

## Storage wiring landed in #73 (M02-05-A0)

Document upload and storage are wired, **Option A — engine-side
ActiveStorage directly on `Document`**:

- **`has_one_attached :file`** on `Decidim::ContractsSk::Document`, no
  `Decidim::Attachment` (the engine stays self-contained; documents are
  contract-scoped engine records, not attachable component resources). The
  macro is declared unguarded, mirroring decidim-core: core declares
  `has_one_attached` on its own models unguarded and declares no
  activestorage gem dependency either — every Decidim application runs
  ActiveStorage, and this engine's runtime floor is decidim-core.
- **Metadata columns are the display source of truth.**
  `Document#attach_file!` attaches (or replaces) the file and syncs
  `file_name` / `content_type` / `file_size` from the blob, so the public
  catalogue renders size/type without touching the blob service.
- **No engine migration for the storage tables — on purpose.** The
  engine's own migration set stays untouched by this arc (the #56 documents
  table already carried the metadata columns). The ActiveStorage schema
  (`active_storage_blobs` / `active_storage_attachments` /
  `active_storage_variant_records`) is **owned by the host application** —
  a Decidim app has it by construction — so the engine must not create or
  migrate it. The blob-backed spec groups build those tables from the pinned
  activestorage gem's own migration for testing only. Storage-service
  configuration (Disk/S3/…) is likewise a host-app concern.
- **Removal cascades**: destroying a document destroys its attachment row
  with it (the `has_one_attached` wiring); the blob purge itself goes
  through the host's queuing backend (`purge_later`).
- **Deferred from this arc**: CRZ integration remains #74. Document
  content validation landed in #64 — see below.

## Upload safety landed in #64 (M02-05-A)

- **Content-type allowlist** — `Document::ALLOWED_CONTENT_TYPES`
  (`application/pdf`, `text/plain`, `image/png`, `image/jpeg`), enforced at
  the form boundary (`DocumentForm`), fail-closed: exact match against the
  client-declared type, no magic-byte sniffing (Decidim-core parity — core
  does not sniff either). The type is client-declared, so this is a safety
  floor, not a forensic guarantee.
- **Size cap** — `Document::MAX_FILE_SIZE` (10 MB), an engine constant,
  deliberately not host-configurable in v0.1; validated on the form before
  any blob is created.
- **Filename sanitization** — `Document.sanitize_filename` is the single
  choke point for every stored display name (attach, replace and the
  generated CRZ export all flow through `attach_file!`): strips directory
  components, control characters and anything outside `[A-Za-z0-9._-]`,
  collapses separator runs, caps at 255, and falls back to `document` (+
  preserved ASCII extension when one survives, e.g. `ččč.pdf` →
  `document.pdf`). The stored `file_name` is **display-only by contract** —
  it never feeds paths or headers; public downloads use the blob's own
  ActiveStorage-sanitized name, so the download dialog and the admin table
  may show cosmetically different renderings of the same original name.
- **Log safety** — no file payloads or blob IO are ever logged in the
  attach path.

## Schema consequences landed in #57 (M02-02-C)

`decidim_contracts_sk_amendments` and `decidim_contracts_sk_audit_events`
keep the "minimal constraints" stance:

- **Amendments** — a numbered revision of its contract: `version` is a
  positive integer and `(contract_id, version)` is unique (DB-level composite
  unique index, mirrored by a model uniqueness validation scoped to
  `contract_id`). **D1 — why a plain integer `version` and not a DB sequence
  or timestamp:** the number is editorial information (published revisions
  render as "version n" in the catalogue), it must be human-assignable and
  gapless per contract at the command layer, and the composite unique index
  doubles as the plain `contract_id` lookup index (the references line
  suppresses the redundant single-column index). Immutability and the
  version-sequence behaviour **landed with M02-05-B (#65)** — see below —
  M02-02-C shipped the validated, mutable skeleton only.
- **Audit events** — append-only by construction: `AuditEvent#readonly?`
  returns `persisted?`, so every write path through the model
  (save/update/update!/touch/update_columns/destroy) raises
  `ActiveRecord::ReadOnlyRecord` once persisted. Accepted gaps: `#delete`,
  `.delete_all`/`.update_all` and raw SQL bypass the model surface — DB
  triggers were rejected because they break migration reversibility and the
  SQLite `:db` spec harness. **D2 — explicit tenancy deviation:** unlike
  parties/documents, the audit table carries its own
  `decidim_organization_id` (plus `decidim_user_id` actor) instead of
  deriving tenancy through the target: the polymorphic target has no FK and
  may dangle after target deletion (the Decidim ActionLog precedent), so
  tenant scoping cannot be derived through it and the trail must stay
   attributable to organization and author regardless. The org/user refs
   also carry real FK constraints — a deliberate second deviation from
   Decidim's `decidim_action_logs`, which has none (RESTRICT on org/user
   deletion; consistent with this engine's parties/documents FK policy).
 - **Audit writes are live since M02-03-B (#59)** — each successful admin
   lifecycle transition appends one audit event atomically with its state
   change (single `with_lock` transaction in `Admin::TransitionContract`;
   failed transitions write nothing). The row shape is fixed by the #57
   migration (**D4**): `action` is `"contract.<event>"` (or
   `"contract.<event>_self"` under `allow_self_review`, #123), the polymorphic
   target is the contract, organization and actor are stored explicitly,
   timestamps only — no JSON payload, no from/to columns.

## The lock discipline is engine-wide since M02-07-B (#69)

What began as the lifecycle/amendment commands' TOCTOU guard is now the
doctrine for every admin command that writes contract state: take the
contract row's `with_lock` (which reloads under the lock), re-check the
lifecycle guard INSIDE the lock, and read anything the write depends on
(snapshots, artifact rendering) from the post-lock instance. As of #69
this covers `UpdateContract`, the party commands, the document commands
and `GenerateCrzHandoff` — a stale request can no longer write content,
parties or documents onto a record that left the editable states
mid-flight. The deterministic spec shape is the "request-start copy":
the child loaded through a pre-move contract copy (association +
`inverse_of`), then the row moved directly, then the command must
refuse and write nothing.

## Redaction confirmation gate landed in #91 (ADR-007)

Publication now carries a privacy precondition (ADR-007,
civora-org/civora-platform#91): the nullable `redaction_confirmed_at`
datetime on the contracts table records when an editor last confirmed —
on the contract's edit page, through one required-checkbox POST whose
affirmation value is consumed SERVER-SIDE (a POST without a truthy
checkbox value refuses with the localized alert; the HTML `required`
attribute is a UX aid, never the gate) — that personal data was redacted
from the record and its attached documents (checklist: personal
names/addresses of natural persons, bank/account details, amounts tying
the contract to identifiable persons, sensitive content inside attached
documents).

- **Gate placement** — `TransitionContract` refuses the publish edge
  inside the row lock while the stamp is blank (the in-lock re-check
  doctrine above; the refusal carries a `:redaction_gate` payload so the
  admin UI can flash a dedicated, actionable message), and
  `PublishAmendment` backstops on the same stamp for EDITORIAL parents
  only: a `crz` mirror's content is already-public upstream register data
  (ADR-008), the importing editor could never have affirmed a redaction
  checklist over it, so mirrors land published unstamped and their
  amendments stay publishable. The amendment snapshot freezes the
  contract's current — already confirmed — content, so there is
  deliberately no separate amendment checkbox (Gate-1 decision).
- **Confirmable window** — the confirmation may be stamped while the
  record is in `CONFIRMABLE_STATES` (`editable` states + `approved`):
  a reviewer sign-off can arrive unstamped, and the editor must still be
  able to confirm right before publishing. `editable?` itself is NOT
  widened — approval still locks the content fields.
- **System field** — written only by `Admin::ConfirmRedaction` (stamp +
  `contract.redaction_confirmed` audit row, one transaction), never
  form-writable, never cleared by the command. Additive migration, no
  backfill: pre-#91 records simply cannot publish until an editor
  confirms.
- **Idempotency** — a record that already carries the stamp refuses
  (the UI hides the control once stamped; re-stamping would move the
  confirmation date without a fresh affirmation behind it).

## Reviewer decision reasons landed in #90 (Gate-1 Option A)

The reviewer judgment edges (`in_review` → `return`/`reject`) now carry a
mandatory decision reason (civora-org/civora-platform#90), stored on the
contract row itself:

- **Option A — judgment text on the contract, not a payload table.** Two
  nullable columns: `review_reason` (string, capped at 1000 characters)
  and `reviewed_at` (datetime). Additive migration, no backfill, no index
  (mirrors the #91 stamp) — pre-#90 records carry no judgment text, which
  is exactly the truthful state. A returned/rejected record without a
  reason can only predate #90 (the command refuses reason-less
  judgments), so the admin edit banner stays hidden there.
- **D4 untouched** — the audit row shape stays the #57 vocabulary
  (`action` = `"contract.<event>"`, or `"contract.<event>_self"` under
  `allow_self_review`, #123; timestamps only, no JSON payload): the
  reason is record content, not audit metadata. The audit row for a
  judgment edge is written in the same locked transaction as the reason,
  so decision text, state, stamps and audit commit atomically or not at
  all.
- **Cleared on resubmit** — `submit` from `returned` nils both columns
  inside the same lock, persisted by the state write: a fresh `in_review`
  record never carries the previous round's judgment. From `draft` the
  columns are already nil (only a returned record ever carries a reason),
  making the clearing a no-op there. The banner on the edit page
  disappears with the clearing — the "Reviewer decision" banner renders
  exactly while the record sits in `ContractLifecycle::DECISION_STATES`
  (`returned`/`rejected`) with a reason present.
- **Judgment vocabulary stays reviewer-only** — any OTHER event
  (`submit`, `approve`, `publish`, `archive`) fails closed when a reason
  param arrives (the command broadcasts `:invalid` with a
  `REASON_REJECTED` payload; the UI flashes a dedicated localized alert).
  A blank/whitespace reason on a judgment edge refuses with
  `REASON_REQUIRED`. The reason-shape guard runs BEFORE the row lock
  (request-shaped input, no row state), while the write — reason +
  `reviewed_at` + state + audit — happens inside the existing
  `with_lock` transaction, per the lock discipline above.

## Amendment lifecycle landed in #65 (M02-05-B)

The amendments table grew its lifecycle (ADR-006, Option A — immutable
content-snapshot rows on the SAME contract; the record's live fields stay
the current version):

- **Lifecycle columns** — `state` (`draft` -> `published` only; NOT NULL
  with a `"draft"` default, which backfills pre-#65 rows correctly: nothing
  was ever published before #65, so no row can already be immutable),
  `published_at` (a system field, stamped by the publish command, never
  form-writable — the contract's own `published_at` doctrine, #75), and
  `content_snapshot`.
- **`content_snapshot` decision** — a single JSON column holding the frozen
  contract content-field hash taken at publish time (keys =
  `Amendment::SNAPSHOT_FIELDS`, the data-dictionary content set minus
  `published_at`). Values are stored as display-ready scalars — dates as
  ISO `:db` strings, the amount as a plain decimal string — so the frozen
  value JSON-serializes identically on every adapter and reads back exactly
  as written. No separate version table: the amendment row IS the
  historical version.
- **`:json`, not `:jsonb`** — on purpose. `:jsonb` is PostgreSQL-only,
  while this engine's `:db` spec harness (and some hosts) run SQLite;
  `:json` serializes identically everywhere, and nothing in v0.1 needs to
  index into the snapshot in SQL.
- **Immutability doctrine** — published amendments are immutable at the
  model layer (`Amendment#readonly?` returns true when the PERSISTED
  in-database state is `published` — deliberately not the dirty attribute,
  so the publish write itself can flip a draft row) and at the command
  layer, which is the primary guard: every write command re-checks the
  draft/published gates INSIDE `with_lock` (the TransitionContract TOCTOU
  doctrine — the permission layer's admission decision is request-start
  state). Locks nest in one fixed order (contract, then amendment; the
  amendment-only commands take no contract lock, so no cycle), and
  `PublishAmendment` serializes its snapshot read on the contract's row
  lock, freezing the content as it stands under the lock. Accepted gaps
  (the AuditEvent precedent): `#delete`, `.delete_all`/`.update_all` and
  raw SQL bypass the model surface — DB triggers were rejected because they
  break migration reversibility and the SQLite `:db` harness.
- **Nullable tenancy columns** — `decidim_organization_id` /
  `decidim_author_id` carry real FKs but are added NULLABLE: a NOT NULL
  `add_column` cannot serve pre-migration rows without fabricating FK
  values (copying the parent contract's author would invent provenance).
  The model requires both through `belongs_to ... optional: false`, so
  every engine write path still carries them.

## Four-eyes submitter stamp landed in #123

- **Column** — nullable `decidim_submitted_by_id` on the contracts table:
  no foreign key and no index (the `decidim_author_id` shape; it is read
  per record, never queried as a set). A system field: only
  `TransitionContract` writes it, never a form or the CRZ upsert.
- **Stamp semantics** — rewritten on EVERY `submit` (first submission and
  resubmission from `returned`), inside the row lock and the same UPDATE as
  the state, so it always names the last submitter. The person it names may
  not return, approve or reject the record (Permissions + in-lock command
  re-check; see `docs/roles-and-permissions.md`).
- **Backfill (D2-B)** — the migration stamps each record with the actor of
  its most recent `contract.submit` audit row; records with no such row stay
  nil, and nil is never blocked. Reversible: rollback drops the column.
- **The one D4 exception** — with `allow_self_review = true` a
  self-judgment is audited as `contract.approve_self`, `contract.return_self`
  or `contract.reject_self`; every other row keeps the plain
  `contract.<event>` vocabulary and shape.

## CRZ publication deadline landed in #124

- The § 47a OZ deadline is **computed, not stored**: `signed_on` +
  `Decidim::ContractsSk.crz_deadline` (default `3.months`). No column, no
  migration; the `Contract` scopes (`crz_deadline_tracked`, `crz_overdue`,
  `crz_due_soon`) compare `signed_on` against Ruby-computed thresholds because
  SQL date arithmetic is not portable (month-end clamping).
- "Filed in CRZ" was a **proxy** here (`crz_url` present); #125 replaced it
  with the verified `crz_filed_at` (below). Only editorial records
  (`source != "crz"`) in non-terminal states with `crz_filed_at` NULL are
  tracked.
- Details, caveats and non-goals in
  [contract-lifecycle.md](contract-lifecycle.md#crz-publication-deadline-124).

## CRZ filing confirmation landed in #125

- **Columns** (one additive, reversible migration, no backfill, all nullable
  system fields — never form-writable, like `redaction_confirmed_at`):
  `crz_filed_at` (datetime — the "filed" flag), `crz_published_on` (date, the
  publication date CRZ reports; nil for the sentinel/blank) and
  `crz_filing_reason` (string, 1000 — the editor's override reason, nil on a
  clean match).
- **Writer:** `Admin::ConfirmCrzFiling` only. Fetch outside any lock
  (`CrzImport::FilingLookup`), then `contract.with_lock` and an in-lock
  re-check on the reloaded row: editorial source, `published` state, not
  already filed, the preview's checksum token still equal to the fresh
  payload's, the `FilingComparison` re-run against the row as it is now, the
  reason rule, the id free. The unique `(organization, source_id)` index is
  the backstop (`RecordNotUnique` → "already linked"). Deterministic specs
  prove the stale-object paths without threads.
- **Lock order:** contract first, then the CRZ mirror holding the id — the
  only place two contract rows are locked, so no inverse order exists. A
  pristine mirror (no amendments/links/documents) is destroyed and audited as
  `contract.crz_mirror_absorbed`; the audit row targets the **editorial**
  record (the destroyed mirror would dangle and drop out of the per-contract
  trail filter; its own import rows keep their dangling targets as for every
  contract deletion).
- **Linked rule (sync):** `UpsertContract` treats a `source != "crz"` record
  holding the id with `crz_filed_at` present as `:linked` — zero writes, no
  mirror, not a collision (`Sync::Result#linked`/`linked_ids`). An unfiled
  editorial record holding the id stays a collision. The sync's failure paths
  stamp `import_status` only on `source="crz"` rows (`Sync#find_mirror` and
  `mark_failed!` are scoped to the mirror source), so a filed or colliding
  editorial record is never stamped.
- **Audit actions:** `contract.crz_filed`, `contract.crz_filed_override`,
  `contract.crz_mirror_absorbed`.
- **Permission:** `:confirm_crz_filing` — editor, editorial, published,
  unfiled ([roles-and-permissions.md](roles-and-permissions.md)).

## Catalogue filters and sorting landed in #116

`Decidim::ContractsSk::CatalogueQuery` (`app/queries/`) is the one query object behind the public catalogue's filters and sort; the supplier pages (#117), statistics (#118), exports (#119) and feeds (#120) are meant to reuse it, not to grow a second vocabulary.

**Reuse contract**

- `CatalogueQuery.new(scope:, params:, time_zone: Time.zone)`: `scope` is the caller's already-scoped relation (the controller passes the published, organization-scoped one); the query only narrows it, so published-only and tenant scoping survive every combination.
- `#filters` (normalized, frozen), `#relation` (filtered, **unordered**: for counts, aggregates, exports), `#results` (relation plus the sort), `#active?`, `#active_filter_keys`, `#to_params` (normalized strings, round-trips), `#with(**overrides)` (a new query over the same scope; `nil` removes a key; the supplier pages do NOT use `with(party: ico)`, whose IČO match is role-agnostic; see below). `#with` is strict: an unknown key, or a non-nil value that does not normalize, raises `ArgumentError` instead of silently widening the result to the whole catalogue. Any caller of `with(party:)` must therefore pass a valid 8-digit IČO (spaces allowed) to get the exact match; any other string would be a name substring search. `PARAM_KEYS` lists the accepted keys (controller slice, pagination `filter_keys`, specs).
- Pagination links carry the normalized params (`CatalogueQuery#to_params`, via the partial's `carried_params:` local), never the raw request. `#results` uses `reorder`, so a pre-ordered scope cannot break the deterministic sort. The search conditions are table-qualified. Everything lives in `catalogue_query/normalizer.rb` (params to filters) and `catalogue_query/conditions.rb` (filters to SQL).

**Normalization** (only String values; arrays and hashes are ignored; an invalid value is ignored, never an error)

- Amounts: spaces (incl. U+00A0/U+202F) removed; `\A\d+([.,]\d{1,2})?\z`, so "10 000,50", "10000.5" and "10000" pass while the ambiguous "10.000", negatives and anything above `Contract::MAX_AMOUNT` do not. Compared against the stored `amount`, whatever the currency (only EUR exists: `Contract::SUPPORTED_CURRENCIES`). Records without an amount drop out only while an amount filter is active.
- Dates: ISO `yyyy-mm-dd` and Slovak `d.m.yyyy` through strict regexes plus `Date.valid_date?`, years 1900 to 2100, never `Date.parse`. `signed_on` is an inclusive date range. Publication dates are calendar days in the supplied time zone (the public controller runs inside Decidim's organization time zone), applied as `[from 00:00, day after "to" 00:00)` on `published_at`.
- A reversed range (from after to) is **swapped silently** and the form shows the swapped values.
- `party`: control characters replaced by spaces, squished, capped at 255 (`q` shares the cap and the control-character cleaning; a NUL byte would otherwise make PostgreSQL raise on bind); exactly 8 digits (spaces removed) is an exact `ico` match (a string: leading zeros count), anything else a case-insensitive name substring. Both go through an `IN (SELECT contract_id FROM parties ...)` subquery: any role, no DISTINCT, no N+1.
- `source`: `editorial` (everything not `crz`, as in the admin index) or `crz`. `sort`: `published_desc` (default), `published_asc`, `amount_desc`, `amount_asc`; always tie-broken by `id` in the same direction; amount sorts put missing amounts last (`NULLS LAST`, emitted explicitly, since PostgreSQL's default for DESC is the opposite).

**Publication date caveat.** "Published in the catalogue" filters `published_at`, the moment the record entered the catalogue. For a CRZ mirror that is its import time, **not** the real CRZ publication date. Storing the real CRZ date is a follow-up; until then the label says what the field means.

**Search fix (public and admin).** The earlier condition lower-cased the column but not the pattern (case-sensitive on PostgreSQL: an upper-case term found nothing), and `sanitize_sql_like`'s backslash escaping did nothing on SQLite without an `ESCAPE` clause. `TextSearch` (`app/queries/`) now down-cases the term in Ruby and every condition carries `ESCAPE '\'`; the public `q`, the `party` name match and the admin index `q` share it. Known limit: SQLite's `LOWER()` folds ASCII only, so a stored diacritic capital ("Š") is not folded there; PostgreSQL folds per its collation (production).

## Open-data export landed in #119

`GET /export.csv|json` (`OpenDataController`) exports the organization's published **editorial** records through the same `CatalogueQuery` (`#relation`, unordered; the export orders by id). Full contract in [open-data.md](open-data.md); the design decisions worth knowing:

- **Shared read surface.** `PublicCatalogue` (a controller concern) owns `published_contracts`, `catalogue_query` / `build_catalogue_query(scope)` and `open_data_scope` (`published_contracts.where.not(source: "crz")`). The catalogue controller uses it; so will the feed (#120) and the supplier pages (#117). No controller reads `Contract` for the public directly.
- **Mirrors are excluded** (ADR-008 decision 6, #83: no CRZ reuse licence). `?source=crz` is an honest empty export.
- **One whitelist.** `OpenData::ContractRecord::FIELDS` is the only place that names exportable attributes; CSV and JSON both derive from it. It uses no I18n and no `Time.zone`, because the body streams after Decidim's locale and time-zone `around_action`s have returned: dates are ISO, `published_at` is UTC, detail URLs and the file name are computed in the action.
- **Streaming without `ActionController::Live`.** The body is an `Enumerator` (no second thread). An explicit `ETag` from `stale?` keeps `Rack::ETag` from buffering the stream to digest it (rack 2.2 `skip_caching?`); `Contract.uncached { }` keeps the request's query cache from retaining every batch.
- **`csv` is a declared dependency** (`csv >= 3.0` in the gemspec): it is a bundled, not default, gem from Ruby 3.4.

## Atom feed landed in #120

`GET /feed.atom` (`FeedsController`, `feeds/show.atom.builder`) reuses `PublicCatalogue#open_data_scope` and `CatalogueQuery` (`with(sort: "published_desc")`, `results.limit(50)`), so it can never list a mirror, a draft or another organization's record. Full contract in [open-data.md](open-data.md#atom-feed-of-new-contracts); decisions worth knowing:

- **Editorial only, like the export** (ADR-008 decision 6, #83).
- **The reader's sort is overridden**, not honoured: a feed is newest first, so the self link and the feed id carry no sort.
- **`FeedHelper` holds the vocabulary** (organization name resolved from its translatable hash without Decidim's `translated_attribute`, tag-URI ids, summary, the head link), so the builder template stays declarative and the head link is spec-pinned offline (the harness has no Decidim layout). `current_organization` is exposed to views through `PublicCatalogue` (Decidim already does so; harmless there).
- **Entry `updated` = `published_at`** by design; tag ids are minted from the id and host only, so edits and filter spelling never change them.
- **No explicit caching** (the export sets an ETag only to avoid buffering a stream; the feed is small, `Rack::ETag` suffices).
- Pre-existing and out of scope: on the host `/feed.rss` and other non-HTML unknown formats hit the catch-all `/:id` and 500, because Decidim has no xml/rss error template.

## Known gaps / drift (flagged, unowned)

- ~~The data dictionary does not exist anywhere yet~~ — **resolved 2026-09-03
  (#70):** it now lives in civora-platform at
  `docs/01-discovery/CONTRACTS-DATA-DICTIONARY.md`. #56/#58/#62/#63 should
  diff their field sets against it. CRZ correspondences there were
  field-by-field verified against the live sources by the #83 spike
  (2026-09-09) and are consumed verbatim by the #86 import mapper.
- The stakeholder requirement (CRZ pull / component / project links) is not
  captured in any civora-platform issue — candidate V0.2 epic.

## Handoff notes for future arcs

- **#58 admin CRUD:** form field set should be checked against the (future)
  data dictionary; enum selects must be built from
  `ContractLifecycle::STATES.map(&:to_s)`; concurrency: wrap transitions in
  `with_lock` at the command layer. Author↔organization consistency is also
  a command-layer duty: enforce `author.organization == contract.organization`
  before persisting (the model has no cross-tenant guard — author and
  organization are independent `belongs_to` associations).
- **Import arc — landed (#86, ADR-008):** the idempotent CRZ import ETL
  consumes the provenance columns above exactly as shaped — the only
  schema addition is the unique `(organization, source_id)` index
  (`idx_contracts_sk_contracts_on_org_and_source_id_unique`, the
  create-race backstop; NULL `source_id` exempt). Write semantics,
  triggers, failure modes and the concurrency layers live in
  [`docs/crz-import.md`](crz-import.md). Editorial collision protection
  keys on `(organization, source_id)` with `source != "crz"` — the
  upsert lookup deliberately ignores `source` so a manual record holding
  a CRZ id is found and protected.
- **Component registration:** a Decidim component registration is a separate
  integration surface from the mounted engine; do not conflate the catalogue
  milestone (#62/#63) with component work.

## Supplier pages landed in #117

`GET /suppliers/:ico` (`SuppliersController`, `suppliers/show.html.erb`) lists one counterparty's published contracts. Decisions worth knowing:

- **One IČO format.** `Decidim::ContractsSk::ICO_PATTERN` / `ICO_FORMAT` (`lib/decidim/contracts_sk.rb`, loadable before any model) define the 8 digits once for the model validation, the route constraint (unanchored, Rails refuses anchors there), the controller and the helper.
- **Contractor role only.** The scope is `published_contracts.where(id: Party.where(role: "contractor", ico:).select(:contract_id))`, handed to `CatalogueQuery.new(scope:, params: {})`. The object party is the contracting body, not a supplier, so it gets no page and no link on the detail page. (The catalogue's `party=<ico>` filter matches any role; that is why `with(party:)` is not used.)
- **404 when empty.** No published contract of this organization names the IČO as contractor: unknown, drafts only, another organization's, object role only. All indistinguishable. The route accepts exactly eight ASCII digits (`/suppliers/abc`, 7 and 9 digits are not routed; leading zeros survive because the segment stays a string) and has no format segment.
- **Mirrors are included**, unlike the open-data export: this is an HTML view whose rows carry the provenance badge. Consequence: **a contract published both editorially and as its CRZ mirror counts twice** in the count, the totals and the per-year tally. There is no dedupe in V1 (the two records are separate rows with no reliable link); the page says so in a note.
- **The name is the most recent spelling**, taken from the contractor party of the newest published record in this page's scope (subquery on the scope, so a draft's or another organization's spelling never leaks); ties break by contract id, then party id.
- **Figures** cover all matching records, not the visible page: count, `group(:currency).sum(:amount)` (records without an amount skipped), and a per-year tally by `signed_on` computed in Ruby from one `pluck`, with a "date unknown" bucket. About four queries plus the list.
- **No request filters in V1** (the query takes an empty param set); `page` is the only param read, as a string clamped to 1..100000 (an absurd offset would raise in the database). The clamp lives in `PublicCatalogue#public_page` and the catalogue index uses it too. A page past the last one shows a short "no contracts on this page" line with a link to page 1.
- **No index on `parties.ico`** (no migration). The contractor-IČO subquery scans the parties table; add an index when a catalogue is large enough to feel it.
- **Privacy: sole traders (SZČO).** A contractor may be a natural person trading under their own name. The page only re-presents what the public detail page already shows (name, IČO), but it aggregates it by person, so it carries `<meta name="robots" content="noindex">` (search engines are asked not to index it) and the organization should decide whether to link to it widely. Records for which redaction (ADR-007) removed a person's data show no such party in the first place.
- **No export/feed link.** The export's `party` filter matches any role and the export excludes mirrors, so a supplier-page link to it would not match the page's list; left out until that is reconciled.
