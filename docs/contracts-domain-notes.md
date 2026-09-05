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
| `import_status` string, nullable | Import lifecycle placeholder; unused until the integration arc |

No behavior attaches to these in #55 — they are data insurance while the
table is empty. `checksum` is deferred to the actual import milestone
(meaningful only with real sync).

Deferred (additive migrations later, per downstream issues): real functional
fields — subject matter text, amounts/currency, signature/effectivity dates,
amendments/versions (#57 landed the skeleton; immutability and the public
version history arrive with #65); safe document content validation (#64 —
the upload/storage wiring itself has landed, see #73 below).

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
- **Deferred from this arc**: document content validation (allowed kinds,
  size caps, content-type checks) remains
  **civora-org/civora-platform#64**; CRZ integration remains #74.

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
  version-sequence behaviour are deliberately **deferred to M02-05-B (#65)**
  — M02-02-C ships the validated, mutable skeleton only.
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

## Known gaps / drift (flagged, unowned)

- ~~The data dictionary does not exist anywhere yet~~ — **resolved 2026-09-03
  (#70):** it now lives in civora-platform at
  `docs/01-discovery/CONTRACTS-DATA-DICTIONARY.md`. #56/#58/#62/#63 should
  diff their field sets against it. CRZ correspondences there remain
  indicative until the #71 import arc verifies them against the live CRZ
  open-data schema.
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
- **Import arc (V0.2):** follow the AGENTS.md import policy — provenance,
  freshness, idempotency, malformed-source handling, no-PII fixtures; reuse
  the provenance columns above instead of migrating them in.
- **Component registration:** a Decidim component registration is a separate
  integration surface from the mounted engine; do not conflate the catalogue
  milestone (#62/#63) with component work.
