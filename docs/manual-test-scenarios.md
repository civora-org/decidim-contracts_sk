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
| DEMO-2026-010 … 033 | published | **statistics demo** (#118): 24 fictional published records spread over the last 12 months relative to the seeding day (re-seed to slide them), 7 repeat contractors (`00000003`, `00000005`, `00000011` … `00000015`), 2 without an amount (-019, -029), 3 CRZ mirrors (-014, -022, -027); -010 is the play-equipment contract the participation demo links to and is never overwritten when it already exists (its parties are matched by role); editorial ones are redaction-stamped and CRZ-filed (so the admin deadline chips are untouched) |
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
| P1 | `GET /zmluvy/` | index lists the published records (DEMO-2026-006, the two imported records DEMO-2026-008/009 and the 24 statistics-demo records — 27 out of the box, so two pages of 25 — and anything you publish in section 3); localized empty state if no published rows |
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

### 2b. Filters and sorting walkthrough (civora-org/civora-platform#116)

Run against the demo seed (published: DEMO-2026-006, the CRZ mirrors DEMO-2026-008/009, plus anything you published in section 3).

| # | Request | Expected |
|---|---------|----------|
| P14 | `GET /zmluvy/?source=crz` | only the two mirrored records; "More filters" is open; summary chip "Source: Mirrored from CRZ" |
| P15 | `GET /zmluvy/?source=editorial` | only editorial records |
| P16 | `GET /zmluvy/?amount_min=1000` and `?amount_min=10.000` | the first lists records with a stored amount of at least 1000 (records without amount disappear); the second value is ambiguous, so it is ignored and everything is listed |
| P17 | `GET /zmluvy/?published_from=2026-09-10&published_to=2026-09-01` | reversed range swapped; the form fields show 2026-09-01 and 2026-09-10 |
| P18 | `GET /zmluvy/?signed_from=1.9.2026` (Slovak date) | accepted; the date field shows 2026-09-01 |
| P19 | `GET /zmluvy/?party=<8-digit IČO of a seeded party>` and `?party=<part of a party name in CAPITALS>` | exact IČO match; case-insensitive name match |
| P20 | `GET /zmluvy/?sort=amount_desc` and `?sort=amount_asc` | by amount, records without amount last in both; `?sort=bogus` behaves like the default (newest first) |
| P21 | `GET /zmluvy/?q=ZMLUVA&source=crz&sort=amount_asc`, then follow "Next" if there is a second page | all params survive in the page link |
| P22 | "Clear filters" link | back to `/zmluvy/`, search cleared, all records listed |
| P23 | filter combination matching nothing | "No contracts match your search or filters." (not the empty-catalogue text) |
| P24 | admin index search with an upper-case term (`?q=BRIDGE`) and a literal `%` | admin and public searches agree: case-insensitive, `%` and `_` literal |

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

### 2c. Supplier pages walkthrough (civora-org/civora-platform#117)

Seed IČOs: `00000003` (Odpadové služby Demo a.s., DEMO-2026-006, published), `00000005` (Svetlá Demo, s.r.o., DEMO-2026-008, a CRZ mirror), `00000002` (DEMO-2026-001, draft only), `00000001` (object party only).

| # | Request | Expected |
|---|---------|----------|
| P25 | detail for DEMO-2026-006, click "Odpadové služby Demo a.s." | `GET /zmluvy/suppliers/00000003`: name, IČO, 4 contracts (DEMO-2026-006, -016, -022, -026), total value, per-year tally, the contract rows; head has `noindex` |
| P26 | `GET /zmluvy/suppliers/00000005` | the two mirrored records (DEMO-2026-008, -014) are listed with their "Externally confirmed" badge |
| P27 | `GET /zmluvy/suppliers/00000002` and `/zmluvy/suppliers/00000001` and `/zmluvy/suppliers/99999999` | **404** (draft only, object role only, unknown) on the freshly seeded data, before section 3 publishes DEMO-2026-001 |
| P28 | `GET /zmluvy/suppliers/1234567`, `/123456789`, `/abcdefgh` | not routed (404 / routing error) |
| P29 | `GET /zmluvy/suppliers/00000003?page=abc&q=x` | page 1; the filter param is ignored |
| P30 | detail for DEMO-2026-006, the object party "Mesto Demo" | plain text, no link |

### 2d. Statistics page walkthrough (civora-org/civora-platform#118)

On the freshly seeded data (the page is built from the 27 published records; run the seed on the day you demo, the 24 statistics records are dated relative to it).

| # | Request | Expected |
|---|---------|----------|
| P31 | `GET /zmluvy/statistics`, or the "Štatistiky" tab above the catalogue heading | 200; KPI strip (this month, this year, all time with the EUR total and "2 without an amount", own-records share 81,5 % / 81.5%); twelve month rows, the current one flagged "so far", every month non-zero; by-year table with a "Signing date unknown" row (DEMO-2026-009 has no signing date); the page is indexable (no `noindex` in the head) |
| P32 | top suppliers | by value: `00000011` Stavebná Ukážka first; by count: `00000013` Digitálne Riešenia first (6); names link to `/zmluvy/suppliers/<IČO>` and the counts agree with the supplier pages (a CRZ mirror counts, so `00000003` shows 4) |
| P33 | "Own records and records from CRZ" block | 22 own (81,5 %) and 5 CRZ (18,5 %); the block disappears on an organization with no mirrors |
| P34 | publish a record (A8), reload | the page shows it at once (the cache key follows the data); an empty organization shows the empty state (200, message, catalogue link) |
| P35 | `GET /zmluvy/statistics?q=x&page=999999999999` | 200 (the page reads no parameters) |

## 3. Admin scenarios

Sign in as a seeded admin first. Base: `http://localhost:3000/zmluvy/admin`.

| # | Action | Expected |
|---|--------|----------|
| A1 | `GET /zmluvy/admin/contracts` unauthenticated | redirect to sign-in |
| A2 | index as admin | all org contracts, states shown (33 seeded + any created in A3) |
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
| A16 | CRZ deadline (#124): admin index, then `?deadline=due_soon` and `?deadline=overdue`, then edit DEMO-2026-003 / -001 | "CRZ deadline" column: DEMO-2026-003 amber "7 days" / "7 dní", DEMO-2026-002 and -004 red "Overdue" / "Po termíne", DEMO-2026-001 muted dash (no signing date); archived/rejected/mirror rows empty, and DEMO-2026-006 (published) shows no badge only because it has a CRZ URL (filed) — published editorial records ARE tracked; chips "CRZ due within 14 days (1)" and "CRZ overdue (2)" ignore the active filter; each filter shows exactly its rows; DEMO-2026-003's edit page shows "CRZ filing deadline: … (7 days left)", DEMO-2026-001's "deadline unknown — add signing date"; record a CRZ URL on DEMO-2026-003 → badge and counts drop it |
| A17 | Admin overview (#126), the role matrix: open `/zmluvy/admin` as the editor-only, reviewer-only and both-roles users (with a resolver giving them those roles), then follow each "Show all (N)" link | editor-only: returned / approved / deadlines / counts / recent activity, **no** "Waiting for my review"; reviewer-only: "Waiting for my review" (your own submissions absent, a record with no submitter present), deadlines, counts, recent activity, **no** returned/approved; both: every block; each rendered block has an empty state when nothing matches; each link opens the contracts index with the same N rows; a roleless user is redirected with the permission alert; the sidebar entry opens the overview and stays highlighted on the contracts index |

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

> **CRZ filing confirmation (#125).** On a published editorial record (e.g.
> DEMO-2026-006 is already confirmed; publish another editorial record first)
> the index row offers **Record CRZ filing**. Enter a CRZ id of a contract of
> the demo organization: the page shows the CRZ record beside yours with
> match / mismatch / cannot-be-verified rows. With all rows matching, confirm;
> with a difference the reason field appears (required, 1000 characters max)
> and the audit trail records `CRZ filing confirmed despite differences`. An
> unknown id answers "not found — the data source may lag the CRZ by about a
> day"; an id of another organization, or a cancelled/withdrawn record, is
> refused outright. After confirming, the record leaves the deadline counters,
> the public detail page says "Published in CRZ on <date>" with the official
> link, and a later `import_crz` of the same id answers "already linked"
> without writing. Needs network access to the ekosystem feed.

## 3b. Notifications walkthrough (civora-org/civora-platform#94)

End-to-end verification of workflow notifications. Both demo users are
organization admins, so each holds the `editor` and `reviewer` roles; as
result, the actor always receives the recipient role but is excluded by the
"actor never notified of own action" rule. Run steps 1–5 live on a booted
host with a job processor (Sidekiq, GoodJob, etc.) running the `events` queue;
the second user watches for notifications in the Decidim bell icon
(`/notifications` or the dropdown).

| # | User | Action | Expected | Notes |
|---|---|---|---|---|
| N1 | `contracts-editor@example.org` | Create contract `MANUAL-2026-NOTIF`; edit title/reference; **Submit** it | submit notification queued | contract transitions to `in_review` |
| N2 | — | Bell icon → dropdown (or `/notifications`) | notification "… was submitted for review", linking to the edit page; timestamp | no email without SMTP; the notified users are those with `:reviewer` role |
| N3 | `contracts-admin@example.org` | Open the notification; check the contract title/reference in the email (if SMTP) or the in-app card | title/reference rendered, reference as `decidim_html_escape(resource.reference)` (safe from XSS) | privacy rule: no amounts, parties, documents |
| N4 | `contracts-admin@example.org` | **Return** the contract with reason "Doplňte prílohu." | return notification queued for the **author** (`contracts-editor`) | actor (`contracts-admin`) never sees own action |
| N5 | `contracts-editor@example.org` | Check `/notifications` | "… was returned for changes"; read the reason "Doplňte prílohu." in the notification and email | reason included in return/reject only |
| N6 | `contracts-admin@example.org` | **Resubmit** the same user; confirm **Approve** it | approve notification queued for author (`contracts-editor`) | non-reason events: `approve`, `reject`, `publish` have no reason field |
| N7 | `contracts-editor@example.org` | Check notifications | approve card; resubmit, **Publish** (confirm redaction first) | publish notification queued for author (would be editor if someone else published) |
| N8 | — | Both users check their inboxes | each has their own notifications only (author-targeted events; editor never gets their own submit) | "archive" is never notified; both seeded users hold all roles, so either could publish; author is always receiver for approve/reject/publish |
| N9 | Switch host locale to `sk` and repeat one step | Slovak event text and reason rendering | localized keys live in `config/locales/sk.yml` | the i18n_scope lives under `decidim.contracts_sk.events.*` |
| N10 | Check Rails logs | `[decidim-contracts_sk] transition notification failed:` should **not** appear | fail-soft logging (no class name only; no message/ids/emails) | see pilot-operations.md § Notification queue operations |

> **Seeded-user note:** demo users are both org admins with all roles. To test
> with editor-only and reviewer-only users, configure a host `role_resolver`
> that assigns roles narrowly; then make sure `notification_candidates` includes
> them (see README § Configuration and docs/roles-and-permissions.md).

## 4. RSpec-side demo data

`CONTRACTS_SK_DB=1 bundle exec rspec` gains the `ContractsSkDemoData` helper
(`spec/support/demo_data.rb`): `demo_contracts` (one contract per lifecycle
state, keyed by reference), `demo_contract`, `demo_parties!`,
`demo_documents!(attach:)`, `demo_amendments!` — deterministic and fictional,
usable in any `:db` group.
