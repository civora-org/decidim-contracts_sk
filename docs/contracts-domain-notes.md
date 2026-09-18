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
  - link contracts to projects/results (platform-level concern; join table
    design TBD).
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
   migration (**D4**): `action` is `"contract.<event>"`, the polymorphic
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
