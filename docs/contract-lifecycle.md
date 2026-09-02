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
> it is not a machine event in `TRANSITIONS`. Authorization of creation is a
> model-level concern owned by the Contract model milestone
> ([civora-org/civora-platform#55]).

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

## Public API

```ruby
Decidim::ContractsSk::ContractLifecycle::STATES            # frozen array of 7 states
Decidim::ContractsSk::ContractLifecycle::INITIAL_STATE     # :draft
Decidim::ContractsSk::ContractLifecycle::TERMINAL_STATES   # [:rejected, :archived]
Decidim::ContractsSk::ContractLifecycle::EDITABLE_STATES   # [:draft, :returned]
Decidim::ContractsSk::ContractLifecycle::PUBLIC_STATES     # [:published, :archived]
Decidim::ContractsSk::ContractLifecycle::ROLES             # [:editor, :reviewer]
Decidim::ContractsSk::ContractLifecycle::TRANSITIONS       # nested frozen hash

.state?(value)                              # bool; false for unknown
.initial_state                              # :draft
.terminal?(state)                           # bool
.editable?(state)                           # bool
.publicly_visible?(state)                   # bool
.events_from(state)                         # frozen sorted array; [] for terminal/unknown
.transition_allowed?(from:, event:, role:)  # bool; false for unknown edges (fail closed)
.allowed_roles(from:, event:)               # frozen array; [] if edge doesn't exist
.next_state(from:, event:)                  # Symbol or nil
.transition!(from:, event:, role:)          # target Symbol; raises InvalidTransitionError
```

Query methods fail closed (`false`/`[]`/`nil` on unknown input); only
`transition!` raises. The future Contract model (#55) wraps this: `state`
column validated against `STATES`, model-level transition persisting via
`transition!`.

[civora-org/civora-platform#53]: https://github.com/civora-org/civora-platform/issues/53
[civora-org/civora-platform#54]: https://github.com/civora-org/civora-platform/issues/54
[civora-org/civora-platform#55]: https://github.com/civora-org/civora-platform/issues/55
