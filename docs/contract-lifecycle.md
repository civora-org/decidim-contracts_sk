# Contract Lifecycle — State Machine and Transition Rules

Design from **M02-01-A** ([civora-org/civora-platform#53]); the transition table
below is the contract consumed by the permission-mapping milestone **M02-01-B**
([civora-org/civora-platform#54]).

> **Source of truth:** `lib/decidim/contracts_sk/contract_lifecycle.rb` constants.
> This document is the human-facing rendering. The exhaustive spec
> (`spec/decidim/contracts_sk/contract_lifecycle_spec.rb`) keeps the two in sync.

## States (7)

| State | Meaning |
|---|---|
| `draft` | Initial state. Editor is assembling the record. |
| `in_review` | Submitted; locked for editor edits; awaiting reviewer decision. |
| `returned` | Reviewer sent it back for changes; editor edits in place and re-submits. |
| `approved` | Reviewer signed off; not yet public. |
| `rejected` | Reviewer rejected definitively. **Terminal** (MVP). |
| `published` | Visible in the public catalogue. |
| `archived` | Removed from the active lifecycle; stays publicly visible as closed. **Terminal** (MVP). |

## Transition table

| # | From | Event | To | Allowed engine-role |
|---|------|-------|----|---------------------|
| 1 | — (creation) | `create` | `draft` | `editor` |
| 2 | `draft` | `submit` | `in_review` | `editor` |
| 3 | `in_review` | `return` | `returned` | `reviewer` |
| 4 | `in_review` | `approve` | `approved` | `reviewer` |
| 5 | `in_review` | `reject` | `rejected` | `reviewer` |
| 6 | `returned` | `submit` | `in_review` | `editor` |
| 7 | `approved` | `publish` | `published` | `editor` |
| 8 | `published` | `archive` | `archived` | `editor` |

> **Note on row 1:** the `create` edge is realized as `INITIAL_STATE = :draft` —
> it is not a machine event in `TRANSITIONS`. Authorization of creation is
> split: the *role gate* (editor may create) lives in the permission layer
> ([roles-and-permissions.md](roles-and-permissions.md)); *ownership*
> (only the authoring editor may act) is a model-level concern owned by the
> Contract model milestone ([civora-org/civora-platform#55]).
>
> **Note on row 7:** the publish edge carries the ADR-007 privacy-redaction
> precondition — it refuses while `redaction_confirmed_at` is blank; see
> [contracts-domain-notes.md](contracts-domain-notes.md#redaction-confirmation-gate-landed-in-91-adr-007).

### Role rationale

Two **engine-logical** roles only — `editor` and `reviewer`. These are symbols
inside this engine; mapping them onto actual Decidim users/permissions is
M02-01-B's job entirely.

- **`editor`** owns the record's motion through non-judgmental steps: create,
  submit, publish, archive. Publication and archiving are record-management
  acts (fulfilling the duty to publish; closing a completed contract).
- **`reviewer`** owns exactly the three judgment gates out of `in_review`:
  return, approve, reject. Segregation of duties: the role that drafts never
  judges; the role that judges never drafts or publishes.
- **Per person, not only per role** (civora-org/civora-platform#123): the
  default resolver gives org admins both roles, so the role split alone does
  not stop one admin from drafting, submitting and approving their own record.
  The person who last submitted a record therefore may not return, approve or
  reject it (the four-eyes rule; details, the `allow_self_review` opt-out and
  the audit trail in [roles-and-permissions.md](roles-and-permissions.md#four-eyes-rule-per-person-segregation-123)).

Role→user mapping and permission checks (M02-01-B): [roles-and-permissions.md](roles-and-permissions.md).

## Approved design decisions (M02-01-A, Gate 1)

| # | Decision | Outcome |
|---|---|---|
| D1 | `returned` representation | **Distinct state**, not an edge `in_review → draft` — auditable, editable in place |
| D2 | Who publishes | **`editor`** — reviewer stays a pure gatekeeper |
| D3 | Terminal states | `rejected` and `archived` are **terminal for MVP**; adding edges later is backward-compatible |
| D4 | Archived visibility | Archived contracts remain publicly visible (`PUBLIC_STATES = [:published, :archived]`) — only feeds the `publicly_visible?` predicate; the actual catalogue query (M02 catalogue milestone) may override |
| D5 | Un-approve edge | **None for MVP**; post-publication corrections go through amendments (M02-06, #65) |
| D6 | Role taxonomy | Two engine-logical roles now; Decidim mapping wholly deferred to M02-01-B |

## Explicit deferrals (for downstream milestones)

- **Ownership enforcement** (only the authoring editor may submit) — policy concern for the admin command/authorization milestone; the machine checks role symbols only.
- **Org-admin override** (Decidim convention: org admin bypasses) — M02-01-B may union `admin` into every row without touching this module; the table stays additive.
- **Side effects** — timestamps, audit trail, notifications: audit-event model (#57) and Decidim events, not the state machine.
- **i18n key convention** — states/events should surface as
  `decidim.contracts_sk.contract_states.*` / `decidim.contracts_sk.contract_events.*`
  (M02-06-A, #66).

## CRZ publication deadline (#124)

A contract that must be published in the CRZ and is not published within
three months of its conclusion is deemed never concluded (§ 47a of Act No.
211/2000 Coll., OZ). The engine shows the days left for every editorial
record that is not yet recorded as filed in CRZ, so an overdue or at-risk
contract cannot be missed.

- **Rule.** Deadline = `signed_on` + `Decidim::ContractsSk.crz_deadline`
  (default `3.months`, a config-time `ActiveSupport::Duration`, see the README).
  The deadline is **computed, never stored** — there is no column, so changing
  the signing date or the setting is always consistent. "Conclusion" is read as
  the date of the **last signature**, which is what `signed_on` records.
- **Tracked records.** Editorial records (`source != "crz"` — a CRZ mirror is
  filed by definition) in a non-terminal state, i.e.
  `ContractLifecycle::DEADLINE_TRACKED_STATES` = `STATES - TERMINAL_STATES`
  (`draft`, `in_review`, `returned`, `approved`, `published`). A signed draft
  is tracked: the clock runs from the signature, not from our workflow.
  `rejected` and `archived` are never tracked.
- **"Filed" is a proxy.** A record counts as recorded as filed when `crz_url`
  is present (NOT NULL and not `''`). Until real filing confirmation lands
  (civora-org/civora-platform#125) the UI says "not recorded as filed in CRZ",
  never "not published". Caveat: `crz_url` is only writable in the editable
  states (`draft`, `returned`), so a record that has moved past `returned`
  without a CRZ link cannot clear the flag until #125 ships.
- **Where it shows.** Admin index: a badge per tracked row (alert "po termíne"
  when overdue, warning for 0–14 days left, plain beyond; muted dash when
  `signed_on` is unknown), the `deadline=due_soon|overdue` filter and two
  counters next to the state chips (counted over the unfiltered tenant scope).
  Edit page: a deadline line under the header, read from the persisted record;
  a tracked record without `signed_on` shows "deadline unknown — add signing
  date".
- **Month-end semantics.** A period counted in months that lands on a missing
  day ends on the month's last day (§ 122(2) Civil Code), which is exactly Ruby's
  `Date + 3.months`: 2026-11-30 → 2027-02-28, 2027-11-30 → 2028-02-29. SQL date
  arithmetic is not portable (SQLite `date('2026-11-30','+3 months')` is
  2027-03-02), so the scopes only compare `signed_on` against dates computed in
  Ruby (`CrzDeadline.threshold`, the smallest signing date whose deadline is on
  or after a given day) — pinned against a brute-force classification in the
  specs.
- **Not modeled.** The § 122(3) shift of a deadline falling on a weekend or
  public holiday to the next working day. The displayed deadline is the
  conservative (earlier) one. The feature is an aid for editors, **not legal
  advice**.
- **Follow-ups.** Notifications on approaching deadlines: civora-org/civora-platform#94.
  Real filing confirmation replacing the `crz_url` proxy: #125.

## Public API

```ruby
Decidim::ContractsSk::ContractLifecycle::STATES            # frozen array of 7 states
Decidim::ContractsSk::ContractLifecycle::INITIAL_STATE     # :draft
Decidim::ContractsSk::ContractLifecycle::TERMINAL_STATES   # [:rejected, :archived]
Decidim::ContractsSk::ContractLifecycle::EDITABLE_STATES   # [:draft, :returned]
Decidim::ContractsSk::ContractLifecycle::CONFIRMABLE_STATES # [:draft, :returned, :approved] — ADR-007 confirmation window
Decidim::ContractsSk::ContractLifecycle::PUBLIC_STATES     # [:published, :archived]
Decidim::ContractsSk::ContractLifecycle::DEADLINE_TRACKED_STATES # [:draft, :in_review, :returned, :approved, :published] — CRZ deadline tracking (#124)
Decidim::ContractsSk::ContractLifecycle::ROLES             # [:editor, :reviewer]
Decidim::ContractsSk::ContractLifecycle::TRANSITIONS       # nested frozen hash

.state?(value)                              # bool; false for unknown
.initial_state                              # :draft
.terminal?(state)                           # bool
.editable?(state)                           # bool
.confirmable?(state)                        # bool — ADR-007 confirmation window
.publicly_visible?(state)                   # bool
.events_from(state)                         # frozen sorted array; [] for terminal/unknown
.transition_allowed?(from:, event:, role:)  # bool; false for unknown edges (fail closed)
.allowed_roles(from:, event:)               # frozen array; [] if edge doesn't exist
.next_state(from:, event:)                  # Symbol or nil
.transition!(from:, event:, role:)          # target Symbol; raises InvalidTransitionError
```

Query methods fail closed (`false`/`[]`/`nil` on unknown input); only
`transition!` raises. The Contract model (#55) wraps this: `state` column
validated against `STATES`, model-level transition persisting via
`transition!`.

[civora-org/civora-platform#53]: https://github.com/civora-org/civora-platform/issues/53
[civora-org/civora-platform#54]: https://github.com/civora-org/civora-platform/issues/54
[civora-org/civora-platform#55]: https://github.com/civora-org/civora-platform/issues/55
