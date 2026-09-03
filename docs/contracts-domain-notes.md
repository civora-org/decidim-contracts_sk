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
parties with IČO (#56), documents (#56), amendments/versions (#57).

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
