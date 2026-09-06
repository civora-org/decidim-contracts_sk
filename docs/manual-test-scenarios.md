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
| DEMO-2026-001    | draft       | parties + 1 amendment; editable |
| DEMO-2026-002    | in_review   | reviewer actions expected |
| DEMO-2026-003    | returned    | editable again |
| DEMO-2026-004    | approved    | publishable by editor |
| DEMO-2026-005    | rejected    | terminal |
| DEMO-2026-006    | published   | parties, 2 documents (PDF + TXT), draft amendment, CRZ URL |
| DEMO-2026-007    | archived    | publicly visible, not editable |
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
| P1 | `GET /zmluvy/` | index lists the published records (DEMO-2026-006, plus anything you published in section 3); localized empty state if no published rows |
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

## 3. Admin scenarios

Sign in as a seeded admin first. Base: `http://localhost:3000/zmluvy/admin`.

| # | Action | Expected |
|---|--------|----------|
| A1 | `GET /zmluvy/admin/contracts` unauthenticated | redirect to sign-in |
| A2 | index as admin | all org contracts, states shown (7 seeded + any created in A3) |
| A3 | create (POST `new`) with title+reference | lands in `draft` |
| A4 | edit DEMO-2026-001 (draft) | editable; state/author/organization not form-writable |
| A5 | edit DEMO-2026-006 (published) | update refused — not editable |
| A6 | `POST .../contracts/:id/submit` on DEMO-2026-001 | → `in_review`, audit event written |
| A7 | `POST .../return`, `/approve`, `/reject` on DEMO-2026-002 | each → next state; try the same on a draft — refused |
| A8 | `POST .../publish` on DEMO-2026-004 | → `published`, `published_at` stamped; now visible in P1 |
| A9 | `POST .../archive` on DEMO-2026-006 | → `archived`; still publicly visible |
| A10 | repeat any transition POST twice | second one refused (state moved on) |
| A11 | parties pages on DEMO-2026-001 | add/edit/remove object + contractor parties; two same-role parties allowed |
| A12 | parties pages on DEMO-2026-006 | refused — not editable |
| A13 | documents on edit page of DEMO-2026-001 | attach/replace/remove; metadata columns sync from blob |
| A14 | `GET .../contracts/:id/crz_handoff` (download) | editor-gated, allowed in any state; PDF labelled as a handoff aid |
| A15 | `POST .../crz_handoff` on DEMO-2026-001 | generates/replaces the `crz_export` document |

> **Amendments are seeded as drafts** by design: publication (and with it the
> frozen content snapshot) is the publish command's job, so the seed never
> fabricates published versions. To demo the public version history, open
> `/zmluvy/admin/contracts/:id/amendments` on DEMO-2026-006, publish the
> draft amendment, then re-check the detail page — the frozen snapshot
> appears under *Versions* while the live fields stay current.

## 4. RSpec-side demo data

`CONTRACTS_SK_DB=1 bundle exec rspec` gains the `ContractsSkDemoData` helper
(`spec/support/demo_data.rb`): `demo_contracts` (one contract per lifecycle
state, keyed by reference), `demo_contract`, `demo_parties!`,
`demo_documents!(attach:)`, `demo_amendments!` — deterministic and fictional,
usable in any `:db` group.
