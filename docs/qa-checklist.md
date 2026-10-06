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
- [ ] Header and filter bar (#116): the title "Zmluvy" and the Zoznam | Štatistiky switch share one line (wrapping at 375px); no lead paragraph; one full-width search field; five native `<details>` chips (Suma, Dátum zverejnenia, Dátum podpisu, Strana / IČO, Zdroj), one open at a time, each reachable and operable by keyboard with a visible focus ring; a chip with a value shows it in its label; every field has a label (en + sk); each from/to pair sits in a fieldset with a legend; the party field announces its hint ("Name or 8-digit IČO"); one "Použiť" submit applies everything.
- [ ] At 375px nothing overflows horizontally (chip panels open in the flow, rows are single-column with the date in the meta line); the first result is visible without scrolling past blocks of text.
- [ ] Toolbar: the count and the EUR total match the filtered list; records without an amount and in another currency are noted, never summed in; "Zoradiť" marks the current sort and keeps the filters; "Stiahnuť" links carry the filters but not the sort; "Sledovať" opens the alerts page with the search named in one line. Print shows the list without chips, menus and switch.
- [ ] Each filter and sort narrows/orders the list as expected; an invalid value (e.g. `amount_min=abc`, `published_from=2026-02-30`) is ignored with a normal 200 page; a reversed range is swapped and the form shows the swapped values.
- [ ] Applied filters are chips that each drop only their own param; "Clear filters" returns to the bare catalogue (search cleared too); page 2 keeps every active filter; a miss shows the "no match" message, not the empty-catalogue one.
- [ ] Records without an amount stay listed until an amount filter is used; amount sorts list them last.
- [ ] Open data (#119, #120): the "Download data" block offers CSV, CSV for Excel, JSON and Atom feed, each carrying the active filters but never the sort; with `source=crz` the block shows the crz.gov.sk note and no links. `/feed.atom` opens in a feed reader (or `xmllint --noout`) as a valid feed: 50 entries at most, newest first, no CRZ mirror, no draft; the page head has the Atom alternate link (view source); `/feed` is a plain 404 Switch the page to English: the Atom button, the head alternate link and the feed's `rel=self` all carry the same `locale=en` (feed texts in English, ids unchanged). (`/feed.rss` and other non-HTML unknown formats currently 500 on the host, a known pre-existing gap).

## Public detail

- [ ] Exactly one `h1` (the contract title); `h2` per section (parties, documents, version history); `h3` per published version.
- [ ] Empty states render localized: parties, documents, version history (en + sk).
- [ ] Sparse published record (nil amount / subject matter) — **KNOWN GAP**: bare label with empty value renders; follow-up issue.
- [ ] 404 matrix indistinguishable: draft / in_review / returned / approved / rejected / archived / other-organization / nonexistent id all take the same not-found path.
- [ ] CRZ link absent (not a blank `href`) when the record has no `crz_url`.
- [ ] Document links download with attachment disposition (no in-browser surprise rendering).

## Statistics page (#118)

- [ ] `/statistics` opens from the "Štatistiky" / "Statistics" tab of the view switch above the catalogue heading (en and sk; the active tab carries the blue line, and in Chrome, Edge or Safari 18.2+ the line slides between the tabs — nothing animates with reduced motion); one `h1`, the freshness line ("Data as of" / "Údaje k"), the KPI strip, the 12-month table (current month marked "so far" / "zatiaľ"), the per-year table, the two top-supplier tables and, when CRZ mirrors exist, the own-versus-CRZ table.
- [ ] Every table has a caption (read aloud by a screen reader) and row headers; the bars are decoration only: with CSS off or a screen reader the numbers carry the whole page.
- [ ] Amounts are shown per currency, never mixed; records without an amount are counted and reported as "N without an amount".
- [ ] The head has no `noindex` (the page is meant to be found); supplier names link to the supplier pages and the counts agree with them.
- [ ] 1440px and 375px: no horizontal scroll; at 375px the summary shows two columns and the bars sit under the numbers.
- [ ] Publishing or editing a contract shows up on the next load; an organization without published contracts gets the empty state with a catalogue link.

## Supplier pages (#117)

- [ ] On a contract detail page, a contractor with an 8-digit IČO is a link to `/suppliers/<IČO>`; a contractor without an IČO, a malformed stored IČO and the object party are plain text (no link, no error).
- [ ] The supplier page shows one `h1` (name), the IČO, the contract count, the total value per currency, the per-year tally ("Date unknown" last) and the contracts newest first; view source shows `<meta name="robots" content="noindex">`.
- [ ] CRZ mirrors of the supplier appear with the "Externally confirmed" badge; the note about double counting is visible.
- [ ] More than 25 contracts paginate; the figures still cover all of them. `?page=abc`, `?page[]=2` and `?page=%00` render page 1.
- [ ] 404: an IČO with only drafts, another organization's contracts, only the object role, or no contract at all. `/suppliers/1234567`, `/suppliers/123456789` and `/suppliers/abcdefgh` are not found either.
- [ ] 375px wide: no horizontal scroll; the facts stack in one column; en and sk both render.
- [ ] Privacy: the page shows only names and IČOs the register already publishes; for a sole trader (SZČO) confirm the organization accepts the page before linking to it widely.

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

## Contract templates (#127)

- [ ] Contracts index header: a **Templates** button for an editor, none for a reviewer; `/admin/templates` as a reviewer is refused with the permission flash.
- [ ] Templates list: empty state with the "New template" button; with templates, one row each with name, title pattern, currency, object party and IČO, and **New contract** / **Edit** / **Remove** all rendered as visible buttons (not plain text) at 1440px and 375px, no horizontal page scroll.
- [ ] Template form: every field has a visible label, the name is marked required, the IČO hint is shown, the textarea is bordered like the contract form's; a duplicate name, a 7-digit IČO, or an IČO without a party name each re-render with an announced error summary and keep the typed values.
- [ ] New contract with at least one template: a **Start from** row (blank plus each template), the current choice highlighted; picking a template reloads the form prefilled (title, subject matter, currency) and names the object party that will be added; the reference stays empty.
- [ ] Saving the draft: it is a plain draft (not published, not submitted) with the object party copied; the audit trail shows "Contract draft created from a template"; the template list is unchanged. Editing or removing the template afterwards does not change the contract.
- [ ] Another organization's templates never appear in the list, the chooser or by id (`?template_id=` of a foreign template is a 404).

## Known gaps and follow-ups

- CRZ handoff section disappears on a failed contract update re-render — civora-org/civora-platform#77.

<!-- Resolved by the pilot-demo-ux arc (civora-org/civora-platform#78, #79, #80, #81):
     announced/focused 422 error summaries + required markers; amount/IČO hints and
     the currency select; guarded blank live fields on the public detail page;
     locale-aware money/date rendering and the UTC-labelled PDF stamp. -->
