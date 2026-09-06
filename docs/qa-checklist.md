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

## Admin contracts (new / edit / index / transitions)

- [ ] **New**: one `h1`; every input has a `label` with a unique `id`; back-to-index link present.
- [ ] **Edit**: one `h1`; `h2` sections (documents, CRZ handoff); lifecycle state, author, organization and `published_at` are not form-writable.
- [ ] **Index**: one `h1`; table headers localized; localized empty state when the organization has no contracts.
- [ ] **Index (sk pass)**: state labels and transition button labels render localized (no raw enum values).
- [ ] Per-state transition buttons only (no event whose edge does not start at the record's state, none for roles that own no edge).
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

## Parties

- [ ] Add / edit / remove work; multiple parties with the same role are legal.
- [ ] Localized empty state when the contract has no parties.
- [ ] Remove control carries a confirm dialog; pages refused on non-editable records.

## Amendments

- [ ] Index lists drafts and published versions, newest version first; localized empty state when none.
- [ ] Published rows render bare — no edit / publish / remove controls (immutable, ADR-006); all controls sit on draft rows only.
- [ ] Publish and remove carry confirm dialogs; create offered on published contracts only.
- [ ] After a successful publish, the frozen snapshot appears in the public detail page's version history.

## Cross-cutting

- [ ] Exactly one `h1` per page; heading hierarchy never skips a level.
- [ ] Every input labeled, ids unique per page (en + sk).
- [ ] Confirm dialogs on ALL destroys, amendment publish and contract transitions; keyboard-operable.
- [ ] Writes are POST/redirect/flash (no re-render on success); 422 re-renders keep values and show errors near the form top.
- [ ] Money and dates render per convention — **DECISION RECORD**: ISO dates, fixed-point EUR amounts, no locale-dependent grouping (deterministic across hosts).
- [ ] Loading states: N/A (no async UI in the engine).
- [ ] Mixed en/sk content: page `lang` is host-owned; spot-check that engine strings match the active locale even when record content is in the other language.
- [ ] Keyboard-only full workflow pass: create → edit → parties → documents → submit → return → approve → publish → amendment → archive.
- [ ] Screen-reader spot-check: table headers announced, error list reachable after failed submit, focus returns to the trigger after a confirm dialog closes.

## Known gaps and follow-ups

- Validation errors are visible but not announced to assistive tech; no required-field markers on forms — civora-org/civora-platform#78.
- Hints for constrained inputs (dot-decimal amount, 8-digit IČO) and currency as a select — civora-org/civora-platform#79.
- Sparse published records (nil amount / subject matter) render bare labels on the public detail page — civora-org/civora-platform#80.
- CRZ handoff section disappears on a failed contract update re-render — civora-org/civora-platform#77.
- Formatting conventions (ISO dates, ungrouped fixed-point money, PDF timestamp without zone) are deliberate V0.1 determinism pending a product decision — civora-org/civora-platform#81.
