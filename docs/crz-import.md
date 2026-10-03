# CRZ Import — Operations Guide

> The engine's CRZ import ETL (ADR-008, accepted; implementation arc
> civora-org/civora-platform#86): an idempotent mirror of already-public
> Slovak central-register (CRZ) contract metadata into the engine's
> catalogue. This page is the operator's entry point: triggers, scheduling,
> failure modes and the manual steps the import deliberately leaves to
> humans.

## What the import is (and is not)

- **A metadata mirror, not a legal publication.** Imported records are
  labelled externally-confirmed data (ADR-002 rule 1); the CRZ record at
  `https://crz.gov.sk/zmluva/<ID>/` remains the canonical source. Every
  imported record carries that link in `crz_url`.
- **Source:** `ekosystem.slovensko.digital` (community API; the spike-
  verified primary — `docs/01-discovery/CRZ-OPENDATA-SPIKE.md` in the
  platform repo). The official crz.gov.sk nightly delta ZIPs remain the
  designated fallback/backfill backbone; the engine does not implement
  them yet (a future arc; see "Non-goals" below).
- **Mirror scope (ADR-008 decision 2):** contract content fields (title,
  reference, subject matter, amount, signature/effectivity dates, CRZ
  link) plus the two parties (objednávateľ → `object`,
  dodávateľ → `contractor`). **Not mirrored:** documents (link-only via
  `crz_url`), currency and the VAT flag (absent upstream — manual fields),
  amendment linkage hints (structurally unreliable per the spike).
- **Organization scope (civora-org/civora-platform#145):** the ekosystem
  feed carries every contract published anywhere in Slovakia. Only
  records whose parties carry the organization's IČO (as objednávateľ or
  dodávateľ, matched on ekosystem's normalized `*_cin` fields) are
  mirrored; everything else is counted as `out_of_scope` and never
  written. The host supplies the IČO through
  `Decidim::ContractsSk.crz_organization_ico_resolver` (README §
  Configuration). **Fail closed:** without a configured IČO the rake task
  refuses to run (exit 1) and the admin action answers "not configured" —
  nothing is ever imported unscoped.

## Write semantics (ADR-008 decision 3)

| Situation | What happens |
|---|---|
| No record holds the CRZ id | A new record is created in **`published`** state — the ONE recorded lifecycle exception — with full provenance and a `crz_import_create` audit event. |
| A `source="crz"` record exists, payload checksum unchanged | **No-op** (zero writes, `updated_at` untouched). This is what makes re-running the sync safe. |
| A `source="crz"` record exists, checksum changed, record still `published` | Content fields, parties and provenance are re-mirrored + a `crz_import_update` audit event. Lifecycle state, author and currency are never touched. |
| A `source="crz"` record exists but left `published` (e.g. archived) | **Skipped** — never resurrected or overwritten. |
| A record with the same source id has `source != "crz"` (editorial record) | **Never touched** — the collision is counted and logged for manual resolution (see below). |

Provenance on every write: `source="crz"`, `source_id` (the CRZ numeric
id), `imported_at` (write time), `import_status="succeeded"`,
`checksum` (SHA-256 of the canonical source payload — identical payloads
always produce identical digests, which is what gates updates).

All contract-row writes go through the engine's lock doctrine
(`with_lock` + in-lock re-check; `docs/contracts-domain-notes.md`) and the
same command layer the editorial flow uses — the import path adds no
bypasses (ADR-008 decision 7).

### Concurrency and the create race

The upsert is safe to run concurrently (e.g. the nightly rake task while
an editor triggers a single import). The layers, in order:

1. **In-transaction re-check** — before creating, the command re-runs the
   `(organization, source_id)` lookup inside its transaction and reroutes
   to the update/collision path if a row appeared.
2. **Unique index** — `idx_contracts_sk_contracts_on_org_and_source_id_unique`
   on `(organization, source_id)` is the database-level backstop: if two
   transactions still both find nothing (READ COMMITTED), the losing
   `INSERT` raises `ActiveRecord::RecordNotUnique`. The command rescues it,
   re-finds after the rollback and reroutes to the update/collision path —
   the race winner is never touched twice and never stamped failed.
3. **Update path** — always serialized by the contract row's `with_lock`,
   with the checksum/published guards re-checked inside the lock.

NULL `source_id` is exempt from the index (NULLs are distinct in both
PostgreSQL and SQLite), so editorial records are unaffected.

## Triggers

### 1. Rake task (host-scheduled, recommended nightly)

```bash
# SINCE via env var:
SINCE=2026-09-08T00:00:00Z bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>]"

# or both as task arguments:
bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,2026-09-08T00:00:00Z]"
```

- `SINCE` is an ISO8601 timestamp — the updated-since cursor seed. For a
  first run, use the go-live timestamp; afterwards, schedule each run with
  the previous run's start (or persist the last cursor — the sync itself
  always follows the server's `Link` cursor within a run and never
  reconstructs `since`).
- The task exits **non-zero** when the sync stopped early (source
  unreachable), so a scheduler can alert. Partial pages already applied
  stay applied; re-running is always safe (idempotent upsert).
- Summary counters (created/updated/unchanged/collisions/quarantined/
  failed/skipped/out_of_scope + ids) print at the end; collisions and
  quarantined ids need human follow-up (below). `out_of_scope` is a count
  only (other organizations' contracts), never a follow-up item.

#### Pruning mirrors from before the scoping

Stacks that synced before the organization scope existed hold other
organizations' contracts. The prune task lists them (dry run) and deletes
them only when confirmed; it considers `source="crz"` mirrors only, so
editorial records are never candidates:

```bash
bin/rails "decidim_contracts_sk:crz_import:prune_out_of_scope[<organization_id>]"            # dry run: count
CONFIRM=1 bin/rails "decidim_contracts_sk:crz_import:prune_out_of_scope[<organization_id>]"  # delete
```

Deleting a mirror removes its parties, documents, amendments and links;
the audit trail survives, as for any contract deletion. Take a backup
first.

**Caveat — IČOs mirrored before v1.4.0.** ekosystem serves `*_cin` as an
integer, and earlier versions dropped any IČO that had lost its leading
zeros — which is most municipalities' (`00323560` arrived as `323560`).
Mirrors imported before the fix therefore carry no IČO for such a party,
so the prune task counts even the organization's *own* old mirrors as
out of scope, and the checksum gate never refreshes their parties (the
payload did not change). On a stack with real pre-v1.4.0 mirrors, run the
dry run, check the count, and after pruning re-sync from the go-live
`SINCE` to restore the organization's own contracts with correct IČOs.

### 2. Admin action (single record, interactive)

`POST /admin/contracts/import_crz` with `source_id` (the CRZ numeric id) —
the form on the admin contracts index. Editor-gated (the `:import_crz`
permission, role-only). Every outcome is a localized flash: created /
updated / unchanged / collision / lifecycle guard / invalid data /
not found / source unavailable. Use it to pull one contract by hand, e.g.
when a municipal clerk references a specific CRZ record.

### Actor / authorship

Both the contract's author column and the audit actor column are NOT NULL,
so every import carries a real user: the acting editor for the admin
action; for the rake task, the organization's first admin who accepted the
admin terms, or an explicit `ACTOR_EMAIL=<login email>` env var. The
engine never fabricates synthetic users.

## Scheduling and rate budgets

- **Recommended cadence:** nightly (ADR-008 decision 5). Ekosystem harvests
  continuously; a nightly window keeps the catalogue fresh without
  pressuring the community service.
- **Ekosystem budget:** 60 requests per rate-limit window
  (`x-ratelimit-limit: 60` on every response). The client's cursor
  pagination spends one request per ~100 records; the bounded retry
  policy (2 retries, small backoff) is deliberately conservative so
  retries never burn the window.
- **Official CRZ fallback budget (for any future fallback arc):**
  1 request per 2 seconds during the day (06:00–20:00 Slovak time), < 3
  requests/second at night — documented on crz.gov.sk. Not applicable to
  the ekosystem path.
- The engine ships **no background infrastructure** — the host platform
  owns scheduling (cron, Solidus-style recurring jobs, whatever it
  already runs).

## Failure modes

| Failure | Behaviour | Operator action |
|---|---|---|
| Source unreachable mid-run (retries exhausted) | The run stops gracefully; pages already applied stand; the task reports the error and exits non-zero. **Prior catalogue data is never degraded.** | Re-run later — the sync is idempotent. |
| One record in a batch is malformed (missing id, unparseable, mapper failure) | The record is **quarantined** (skipped + counted); the batch continues. If a mirror row already exists for that id it is stamped `import_status="failed"` — its data stays intact (stale fallback). | Check the logged source ids; usually source-side drift — wait for the next sync, or import that id via the admin action. |
| A changed payload fails validation on update | No write; the existing mirror is stamped `import_status="failed"`, data intact. | Inspect the record; the next clean payload clears the stamp on the next successful update. |
| No IČO configured for the organization | The rake task prints the refusal and exits non-zero without calling the source; the admin action flashes "not configured". Nothing is written. | Configure `crz_organization_ico_resolver` in the host (README § Configuration). |
| Record belongs to another organization | Counted `out_of_scope`, not written; an existing mirror of it is left untouched (remove it with the prune task). The admin action flashes "does not involve this organization". | None — expected for every other organization's contract in the national feed. |
| Unknown source id (admin action) | Localized "not found" flash; nothing written. | Verify the numeric CRZ id on crz.gov.sk. |
| Timeouts | The transport uses explicit timeouts (5s connection / 60s read — the live 2026-09-09 run observed ~50s server-side response times under throttling); timeouts are retried like other transient failures. | None — the run reports itself. |
| Old mirror, dead `crz_url` | The public CRZ portal serves records only while they are within its publication window; ekosystem keeps its historical harvest indefinitely. A mirror of an old record (e.g. a 2015 contract) can therefore point at a `crz.gov.sk/zmluva/<id>/` URL that now 404s, while the ekosystem payload still says `status_id: 2` (published). Verified live 2026-09-09 (id 2142424). | Expected behaviour, not a bug — keep the canonical URL per ADR-008 attribution; the freshness indicator already signals mirror age. |

**Stale fallback principle:** a failed sync never overwrites, truncates or
deletes anything. Existing records keep their last-good mirror data; only
`import_status` may flip to `failed` as a signal.

## Freshness UX (civora-org/civora-platform#88)

The public catalogue surfaces the provenance and freshness metadata the
import writes — mirrors are labelled, never implied to be real-time
(ADR-002 rule 1, ADR-008 decisions 4/6):

- **Index card:** the "Externally confirmed" badge plus the mirror date
  (`imported_at`, rendered as a localized date). No stale indicator — cards
  stay lean.
- **Detail page:** a provenance block with the badge, the mirror date and
  the preserved attribution note (data via ekosystem.slovensko.digital;
  informational only; the canonical record lives at crz.gov.sk). When the
  mirror is stale, the block additionally warns readers to verify the
  canonical record.
- **Stale rule (ADR-008 decision 4):** a mirror is stale when its
  `imported_at` is older than `Decidim::ContractsSk.stale_after` (default
  172 800 seconds = 48 h, twice the recommended nightly cadence), when its
  last import was stamped `import_status="failed"` (the stale-fallback
  signal above — the data is intact but the last re-import could not prove
  it current), or when it carries no import timestamp at all (freshness
  cannot be proven). Hosts tune the threshold in an initializer; Integer
  seconds and `ActiveSupport::Duration` both work:

  ```ruby
  Decidim::ContractsSk.stale_after = 12.hours
  ```

## Manual resolution steps

- **Editorial collisions** (a manually created record holds a CRZ id):
  the import never touches them. Resolve by deciding which record is the
  source of truth: either (a) delete/merge the manual record and let the
  import mirror the CRZ data, or (b) clear the manual record's
  `source_id` if it was set by mistake. The sync's collision ids list is
  the worklist.
- **Quarantined ids**: check ekosystem's record for schema drift; a
  single record can usually be imported via the admin action once the
  source is sane.
- **Currency and VAT flag**: not importable (absent upstream). If a
  contract needs them, edit the record manually — but note an imported
  record's content fields are re-mirrored on the next checksum change, so
  manual content edits on imported records do not survive source updates.
  Editorial protection exists only for records the import has never
  claimed (`source != "crz"`).

## Privacy and logging

- Logs carry **ids, statuses, URLs and counters only** — never payloads
  or party names (enforced by design and pinned by specs).
- No request bodies are ever logged; the transport layer does not log at
  all.
- Fixtures and demo data are synthetic ("Obec Ukážková", fake IČO
  patterns) — no real persons or companies.

## Attribution / license notes (ADR-008 decision 6)

- CRZ content is published under Act No. 211/2000 §5a as amended; **no
  reuse license is declared** by the register. Mirroring *metadata* is the
  settled V0 scope; any republication beyond metadata mirroring (e.g.
  document mirroring) must settle the license question first.
- ekosystem.slovensko.digital's dataset terms require preserving
  attribution clauses; the CRZ dataset there is under the general minimal
  terms, not a named CC license. Keep the source attribution when
  presenting imported data, and present it as externally confirmed — never
  as a legal publication. The catalogue's provenance block surfaces this
  attribution verbatim in both shipped locales (civora-org/civora-platform
  #88).

## Non-goals (V0)

- No official-CRZ nightly-ZIP fallback/backfill implementation yet
  (designated by ADR-008; a future arc).
- No document (binary) mirroring — link-only via `crz_url`.
- No amendment linkage — EK's `kind_id`/`reference` hints are officially
  unreliable; treat any future linking as a separate, heuristic arc.
- No engine-shipped background jobs — the host schedules the rake task.
