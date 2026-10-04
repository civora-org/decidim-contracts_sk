# Manual QA checklist

Accessibility/UX pass for the engine's rendered pages. **Scope: engine-owned
markup only** — layout, CSS and JS (including the confirm dialogs) are
host-provided by Decidim; html `lang` and the admin chrome are the host app's
too. Run against a seeded host app ([manual-test-scenarios.md](manual-test-scenarios.md)),
ideally in both `en` and `sk` where noted.

## Public index

- [ ] Exactly one `h1`; table has header cells for title / reference / published on.
- [ ] Only published records of the current organization are listed.
- [ ] Localized empty state renders when nothing is published (en + sk).
- [ ] Links are keyboard-reachable in DOM order.

## Public detail

- [ ] Exactly one `h1` (the contract title); `h2` per section (parties, documents, version history); `h3` per published version.
- [ ] Empty states render localized: parties, documents, version history (en + sk).
- [ ] Sparse published record (nil amount / subject matter) — **KNOWN GAP**: bare label with empty value renders; follow-up issue.
- [ ] 404 matrix indistinguishable: draft / in_review / returned / approved / rejected / archived / other-organization / nonexistent id all take the same not-found path.
- [ ] CRZ link absent (not a blank `href`) when the record has no `crz_url`.
- [ ] Document links download with attachment disposition (no in-browser surprise rendering).

## Admin overview (#126)

- [ ] `/admin` is the sidebar entry's target; the entry stays highlighted on every engine admin page; "Overview" links on the contracts index and the audit trail lead back.
- [ ] Role matrix: editor-only sees returned / approved / deadlines / counts / recent activity but no review queue; reviewer-only sees the review queue (own submissions excluded, no-stamp records included), deadlines, counts, recent activity but no returned/approved; both roles see every block; a roleless user gets the permission alert, an anonymous visitor the sign-in redirect.
- [ ] Each rendered block: localized title and hint (en + sk, proper diacritics), at most 10 rows, a "Show all (N)" link whose index shows exactly N rows (`?state=in_review&submitter=others`, `?state=returned&submitter=me`, `?state=approved`, `?deadline=overdue|due_soon`), and its own empty state.
- [ ] Approved rows without a redaction confirmation carry the "Redaction not confirmed" warning label; deadline rows carry the deadline badge.
- [ ] State counts list every lifecycle state in lifecycle order (zeros included), each linking to its state filter; "All" links to the bare index.
- [ ] Recent activity shows the last 10 audit events of this organization only, same labels as the audit trail; another organization's records never appear.
- [ ] One `h1`; `h2` per block; no horizontal scroll at 375px.

## Admin contracts (new / edit / index / transitions)

- [ ] **New**: one `h1`; every input has a `label` with a unique `id`; back-to-index link present.
- [ ] **Edit**: one `h1`; `h2` sections (privacy redaction, documents, links, CRZ handoff); lifecycle state, author, organization and `published_at` are not form-writable.
- [ ] **Index**: one `h1`; table headers localized; localized empty state when the organization has no contracts.
- [ ] **Index (CRZ deadline, #124)**: a "CRZ deadline" column with `label` badges (overdue = alert, 0–14 days = warning, beyond = plain, unknown = muted dash with a title, filed/mirror/terminal = empty cell); the `deadline` filter and the two counter chips agree with the badges; Slovak plurals read "1 deň" / "3 dni" / "7 dní"; the edit page shows the deadline line (or the "deadline unknown — add signing date" prompt) and nothing for a record confirmed as filed.
- [ ] **Index (sk pass)**: state labels and transition button labels render localized (no raw enum values).
- [ ] Per-state transition buttons only (no event whose edge does not start at the record's state, none for roles that own no edge).
- [ ] Four-eyes rule (civora-org/civora-platform#123): the user who submitted a record sees no return/approve/reject controls on its row (another admin does), a direct POST by them is denied, and with `allow_self_review = true` they may judge it and the audit viewer labels the row "(self-review)" / "(vlastné posúdenie)".
- [ ] Each transition button POSTs to its event route, asks for confirmation, and lands back on the index with a success flash (PRG).
- [ ] Confirm dialogs are keyboard-operable (Tab / Enter / Esc via the host's confirm.js).
- [ ] **Error paths**: a 422 re-render keeps the entered values; the error list / alert is visible near the form top. Announcement to assistive tech = **KNOWN GAP** (follow-up issue); no required-field markers either = **KNOWN GAP**.

## Documents & CRZ handoff (contract edit page)

- [ ] Documents section shows the localized empty state when the contract has none.
- [ ] Oversized upload (> 10 MB) and disallowed content type surface a visible error; nothing is stored.
- [ ] Remove-document controls carry confirm dialogs.
- [ ] CRZ disclaimer text visible on the edit page (and in the generated PDF: labelled an aid, never a legal publication).
- [ ] Generate/regenerate offered only on an editable-state record (editor); download offered on any lifecycle state (editor).
- [ ] Download on a stale page (artifact since deleted) redirects with the localized download-missing flash instead of erroring.

## Privacy redaction (contract edit page + admin index row, ADR-007)

- [ ] The "Privacy redaction" card renders on the edit page of a confirmable record (editable states + approved) — checklist + required checkbox while unstamped; confirmation stamp line once stamped (checkbox form gone).
- [ ] The admin contracts index shows the same confirmation as a COLLAPSED row card for a confirmable, unstamped record (only the trigger label until opened) — for the acting editor only: nothing once stamped, nothing for a reviewer, nothing outside the confirmable window (e.g. in_review, published).
- [ ] The checkbox carries an accessible label (`<label for="redaction_confirmed_<record id>">` pointing at the input's id — derived per record, so several confirmable rows on one index page never collide), in both en and sk.
- [ ] A POST without the checkbox value (hand-crafted / stale page) is refused server-side with the localized alert — no stamp, no audit row (the HTML `required` attribute is a UX aid, never the gate).
- [ ] A repeat POST on an already-stamped record is refused with the localized alert; the original confirmation date never moves.
- [ ] Publishing an unstamped record is refused with the DEDICATED redaction-gate flash (actionable, pointing at the edit page) — not the generic transition alert.
- [ ] CRZ-imported records show no redaction card expectation: mirrors carry no stamp by design (their content is already-public upstream data, ADR-008).

## Parties

- [ ] Add / edit / remove work; multiple parties with the same role are legal.
- [ ] Localized empty state when the contract has no parties.
- [ ] Remove control carries a confirm dialog; pages refused on non-editable records.

## Amendments

- [ ] Index lists drafts and published versions, newest version first; localized empty state when none.
- [ ] Published rows render bare — no edit / publish / remove controls (immutable, ADR-006); all controls sit on draft rows only.
- [ ] Publish and remove carry confirm dialogs; create offered on published contracts only.
- [ ] After a successful publish, the frozen snapshot appears in the public detail page's version history.

## Audit trail (admin, read-only)

- [ ] The contract edit page links to the audit trail pre-filtered to that record; the link renders for every engine role.
- [ ] The viewer lists the organization's events newest-first; a contract-filtered view shows the naming banner and the back-to-all link.
- [ ] Rows show the localized action (lifecycle verbs, redaction confirmation, amendment publish, CRZ import), the target record, the acting user and the localized date.
- [ ] A target whose record was deleted renders the localized "record no longer exists" label — no error, no internals (en + sk).
- [ ] The decision-reason column fills only for records sitting in a decision state (returned/rejected) carrying a reason; everything else stays blank.
- [ ] Localized empty state when the organization has no events (en + sk); pagination carries the contract filter across pages.

## Cross-cutting

- [ ] Exactly one `h1` per page; heading hierarchy never skips a level.
- [ ] Every input labeled, ids unique per page (en + sk).
- [ ] Confirm dialogs on ALL destroys, amendment publish and contract transitions; keyboard-operable.
- [ ] Writes are POST/redirect/flash (no re-render on success); 422 re-renders keep values and show errors near the form top.
- [ ] Money and dates render per convention — **DECISION RECORD** (civora-org/civora-platform#81): locale-aware rendering — under :sk amounts group thousands with a regular space and use comma decimals ("1 250,50 EUR") and dates render "01. 09. 2026"; under :en the historical ISO dates and fixed-point amounts ("1250.5 EUR") are kept. The date format strings and the sk separators ship with the engine (no host locale data), and the PDF footer stamp is UTC-converted and explicitly labelled "UTC".
- [ ] Loading states: N/A (no async UI in the engine).
- [ ] Mixed en/sk content: page `lang` is host-owned; spot-check that engine strings match the active locale even when record content is in the other language.
- [ ] Keyboard-only full workflow pass: create → edit → parties → documents → redaction confirmation → submit → return → approve → publish → amendment → archive (return and approve are done by a second admin, four-eyes rule #123, or with `allow_self_review = true`).
- [ ] Screen-reader spot-check: table headers announced, error list reachable after failed submit, focus returns to the trigger after a confirm dialog closes.

## CRZ filing confirmation (#125)

- [ ] Index row: **Record CRZ filing** shows only for an editor on a published, unfiled editorial record; hidden for reviewers, mirrors, drafts and filed records.
- [ ] Filing page: id form (numeric only; a non-numeric id never reaches the network), side-by-side comparison with per-row labels (match = success, mismatch = alert, cannot be verified = warning), lag hint visible (en + sk, proper diacritics in sk).
- [ ] Full match: confirm button only, no reason field; mismatch/unverifiable: reason textarea required, `maxlength` 1000; a stale preview, a missing reason and an already-linked id each flash a distinct message and change nothing.
- [ ] Not found, source unavailable, other organization, withdrawn/cancelled and no-IČO each refuse with a localized flash and write no audit row.
- [ ] After confirming: record leaves the deadline counters and filter; audit trail shows `CRZ filing confirmed` (or `... despite differences`, and `CRZ mirror absorbed ...` when a pristine mirror was replaced); public detail shows "Published in CRZ on <date>" (or "Publication in CRZ confirmed" without a date) with the official link.
- [ ] `import_crz` / sync of a filed record's id: "already linked", no new mirror, `updated_at` unchanged; the rake summary counts it under `linked`.

## Known gaps and follow-ups

- CRZ handoff section disappears on a failed contract update re-render — civora-org/civora-platform#77.

<!-- Resolved by the pilot-demo-ux arc (civora-org/civora-platform#78, #79, #80, #81):
     announced/focused 422 error summaries + required markers; amount/IČO hints and
     the currency select; guarded blank live fields on the public detail page;
     locale-aware money/date rendering and the UTC-labelled PDF stamp. -->
