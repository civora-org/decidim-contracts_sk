# Manual test scenarios and demo data

Fictional demo data for click-through / HTTP testing of the engine. All names,
companies and IČO values are placeholders — no real PII.

## 1. Seed a host app

From the host app root (engine mounted, e.g. at `/zmluvy`):

```bash
bin/rails "decidim_contracts_sk:seed_demo[<organization_id>]"
```

What you get (idempotent — safe to re-run):

| Reference        | State       | Notes |
|------------------|-------------|-------|
| DEMO-2026-001    | draft       | parties + 1 amendment; editable; **unstamped — the publish-gate demo record** |
| DEMO-2026-002    | in_review   | reviewer actions expected |
| DEMO-2026-003    | returned    | editable again |
| DEMO-2026-004    | approved    | redaction-stamped — publishable by editor (A8) |
| DEMO-2026-005    | rejected    | terminal |
| DEMO-2026-006    | published   | redaction-stamped; parties, 2 documents (PDF + TXT), draft amendment, CRZ URL |
| DEMO-2026-007    | archived    | redaction-stamped (was published); publicly visible, not editable |
| DEMO-2026-008    | published   | **CRZ import** (fictional): fresh mirror — provenance badge, no stale line; unstamped by design (ADR-008); 2 parties |
| DEMO-2026-009    | published   | **CRZ import** (fictional): stale mirror — `imported_at` 60 days back, stale line expected; unstamped by design (ADR-008) |
| DEMO-OTHER-001   | published   | **another organization** — must be invisible |

Users: `contracts-admin@example.org`, `contracts-editor@example.org` — both
organization admins with accepted admin terms (default role resolver ⇒ both
hold all engine roles). Passwords are unknown by design; reset either in the
host console to sign in:

```ruby
Decidim::User.find_by(email: "contracts-admin@example.org")
             .update!(password: "demo-password-123", password_confirmation: "demo-password-123")
```

## 2. Public catalogue scenarios

With the engine mounted at `/zmluvy` (adjust to your mount point). The
catalogue index is the mount root; detail is `/:id`.

| # | Request | Expected |
|---|---------|----------|
| P1 | `GET /zmluvy/` | index lists the published records (DEMO-2026-006 plus the two imported records DEMO-2026-008/009 — three cards out of the box — and anything you publish in section 3); localized empty state if no published rows |
| P2 | `GET /zmluvy/` as JSON-less browser without JS | same, server-rendered |
| P3 | detail for DEMO-2026-006 | content fields, parties, downloadable documents render |
| P4 | detail for DEMO-2026-007 | **404** — the catalogue scope pins `published` only; archived visibility is a deferred decision (`app/controllers/decidim/contracts_sk/contracts_controller.rb`) |
| P5 | detail for DEMO-2026-001..005 | **404** (non-published states) |
| P6 | detail for DEMO-OTHER-001's id | **404** (other organization) |
| P7 | `GET /zmluvy/999999` | **404**, indistinguishable from P5/P6 |
| P8 | document download link on P3 | file streams; metadata (name/type/size) comes from the columns |

```bash
BASE=http://localhost:3000/zmluvy
curl -s -o /dev/null -w "%{http_code}\n" "$BASE/"                       # P1 → 200
curl -s -o /dev/null -w "%{http_code}\n" "$BASE/999999"                 # P7 → 404
```

### 2a. Provenance and freshness walkthrough (civora-org/civora-platform#88)

CRZ-mirrored demo records (all fictional — no real CRZ ids, companies or
persons). Re-seeding never refreshes `imported_at`, so DEMO-2026-009 stays
stale forever by design. DEMO-2026-008 stays fresh only within the default
48 h of seeding; after that it correctly shows the stale line — destroy it
and re-run the seed task to re-demo the fresh path.

| # | Request | Expected |
|---|---------|----------|
| P9 | detail for DEMO-2026-008 (fresh mirror) | provenance block: "Externally confirmed" badge, "Mirrored from the CRZ register on \<seed date\>", attribution note (ekosystem.slovensko.digital, informational only, canonical record at crz.gov.sk); **no** stale line |
| P10 | detail for DEMO-2026-009 (stale mirror) | badge + attribution + the **stale line** ("This mirror may be out of date — verify the canonical record at crz.gov.sk.") — `imported_at` is 60 days old, beyond the default 48 h threshold |
| P11 | index cards of DEMO-2026-008/009 | "Externally confirmed" badge + mirror date on each card; **no** stale indicator on the index (detail-only) |
| P12 | detail for DEMO-2026-006 (editorial) | **no** provenance content anywhere — badge, mirror date, attribution and stale lines all absent |
| P13 | switch the host locale to `sk` | P9–P12 render the Slovak wording ("Externe potvrdené údaje", "Zrkadlené z registra CRZ dňa", …) |

## 3. Admin scenarios

Sign in as a seeded admin first. Base: `http://localhost:3000/zmluvy/admin`.

| # | Action | Expected |
|---|--------|----------|
| A1 | `GET /zmluvy/admin/contracts` unauthenticated | redirect to sign-in |
| A2 | index as admin | all org contracts, states shown (9 seeded + any created in A3) |
| A3 | create (POST `new`) with title+reference | lands in `draft` |
| A4 | edit DEMO-2026-001 (draft) | editable; state/author/organization not form-writable |
| A5 | edit DEMO-2026-006 (published) | update refused — not editable |
| A6 | `POST .../contracts/:id/submit` on DEMO-2026-001 | → `in_review`, audit event written |
| A7 | `POST .../return`, `/approve`, `/reject` on DEMO-2026-002 | each → next state; try the same on a draft — refused |
| A7b | four-eyes (#123): as `contracts-editor@example.org` (the submitter who ran A6 on DEMO-2026-001), open the index; then `POST .../approve` directly | no approve/return/reject controls on that row; the POST is denied with the permission flash; a **second** admin (`contracts-admin@example.org`) sees the controls and can approve (audit `contract.approve`) |
| A8 | `POST .../publish` on DEMO-2026-004 (seeded stamped) | → `published`, `published_at` stamped; now visible in P1 |
| A9 | `POST .../archive` on DEMO-2026-006 | → `archived`; still publicly visible |
| A10 | repeat any transition POST twice | second one refused (state moved on) |
| A11 | parties pages on DEMO-2026-001 | add/edit/remove object + contractor parties; two same-role parties allowed |
| A12 | parties pages on DEMO-2026-006 | refused — not editable |
| A13 | documents on edit page of DEMO-2026-001 | attach/replace/remove; metadata columns sync from blob |
| A14 | `GET .../contracts/:id/crz_handoff` (download) | editor-gated, allowed in any state; PDF labelled as a handoff aid |
| A15 | `POST .../crz_handoff` on DEMO-2026-001 | generates/replaces the `crz_export` document |
| A16 | CRZ deadline (#124): admin index, then `?deadline=due_soon` and `?deadline=overdue`, then edit DEMO-2026-003 / -001 | "CRZ deadline" column: DEMO-2026-003 amber "7 days" / "7 dní", DEMO-2026-002 and -004 red "Overdue" / "Po termíne", DEMO-2026-001 muted dash (no signing date); published/archived/rejected/mirror rows empty; chips "CRZ due within 14 days (1)" and "CRZ overdue (2)" ignore the active filter; each filter shows exactly its rows; DEMO-2026-003's edit page shows "CRZ filing deadline: … (7 days left)", DEMO-2026-001's "deadline unknown — add signing date"; record a CRZ URL on DEMO-2026-003 → badge and counts drop it |

> **A16 decays by design:** DEMO-2026-003's signing date is computed relative to the
> seeding day (deadline = seed day + 7), so its badge counts down as days pass and
> eventually turns overdue. Re-run `seed_demo` to re-demo (the seed re-signs it).
> Where a month-end clamp makes exactly 7 days unreachable, the badge shows the
> next reachable day count (8–10). Aid only, not legal advice.

> **Privacy-redaction gate walkthrough (ADR-007, on a fresh seed):** DEMO-2026-001
> is the one record demonstrating the gate. (1) `POST .../submit`, then
> `POST .../approve` (reviewer role, by a **second** admin — the submitter is refused by the four-eyes rule, A7b) — the record is now approved but
> unstamped. (2) `POST .../publish` → **refused** with the dedicated
> redaction-gate flash pointing at the edit page. (3) On the edit page the
> "Privacy redaction" card offers the checklist + required checkbox — the
> same confirmation is also offered collapsed in the record's row on the
> admin contracts index (open it right next to the Publish button);
> POSTing **without** the checkbox value (e.g. via curl) is refused
> server-side with the localized alert and writes nothing. (4) Confirm with
> the checkbox — the card flips to the confirmation stamp line (and the
> index row card disappears) — and `POST .../publish` now succeeds. The
> confirmation is also admittable
> directly on an approved record (that is exactly step 3–4 above); on a
> seeded record that already carries the stamp (DEMO-2026-004/006/007) the
> card shows the stamp line and a repeat POST refuses.

> **Amendments are seeded as drafts** by design: publication (and with it the
> frozen content snapshot) is the publish command's job, so the seed never
> fabricates published versions. To demo the public version history, open
> `/zmluvy/admin/contracts/:id/amendments` on DEMO-2026-006, publish the
> draft amendment, then re-check the detail page — the frozen snapshot
> appears under *Versions* while the live fields stay current. The
> amendment publish backstops on the parent's redaction stamp for
> editorial records (DEMO-2026-006 carries the seed stamp, so it works);
> CRZ mirrors are exempt (their content is already-public upstream data,
> ADR-008) and publish amendments unstamped.

## 4. RSpec-side demo data

`CONTRACTS_SK_DB=1 bundle exec rspec` gains the `ContractsSkDemoData` helper
(`spec/support/demo_data.rb`): `demo_contracts` (one contract per lifecycle
state, keyed by reference), `demo_contract`, `demo_parties!`,
`demo_documents!(attach:)`, `demo_amendments!` — deterministic and fictional,
usable in any `:db` group.
