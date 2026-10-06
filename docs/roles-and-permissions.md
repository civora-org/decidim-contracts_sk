# Roles and Permissions — Engine-to-Decidim Mapping

Design from **M02-01-B** ([civora-org/civora-platform#54]); implements the
role-mapping deferred by the lifecycle milestone's D6
([civora-org/civora-platform#53]).

> **Source of truth:** `lib/decidim/contracts_sk/role_resolver.rb` (who holds
> which engine role) and `app/permissions/decidim/contracts_sk/permissions.rb`
> (who may perform which action). The exhaustive spec
> (`spec/decidim/contracts_sk/permissions_spec.rb`) keeps both in sync with
> the transition table in `lib/decidim/contracts_sk/contract_lifecycle.rb`.

## Role taxonomy (2 engine-logical roles)

The engine knows exactly two roles — `Decidim::ContractsSk::ContractLifecycle::ROLES`
(`[:editor, :reviewer]`), both plain symbols:

| Role | Persona |
|---|---|
| `editor` | Owns the record's motion through non-judgmental steps: create, submit, publish, archive. Publication and archiving are **record-management acts** (fulfilling the duty to publish; closing a completed contract), not judgments about content. |
| `reviewer` | Pure gatekeeper: owns exactly the three judgment gates out of `in_review` (return, approve, reject). The role that drafts never judges; the role that judges never drafts or publishes. |

The **publisher-persona note**: `editor` is the publishing role by design
(lifecycle D2). Organizations that separate "who prepares" from "who
publishes" further can express that only at the host resolver level (below) —
the engine's two-role vocabulary stays unchanged for MVP.

## Vocabulary: scope / subject / action

The permissions class speaks Decidim's `PermissionAction` vocabulary and
answers for subjects `:contract`, `:party`, `:document`, `:amendment`,
`:link`, `:audit_event` and `:user_role`:

| Scope | Subject | Action | Allowed when |
|---|---|---|---|
| `admin` | `contract` | `create` | user's engine roles include `editor` (transition-table row 1 analog) |
| `admin` | `contract` | `update` | user's engine roles include `editor` **and** `ContractLifecycle.editable?(state)` (`draft`, `returned`) — the editorial twin of the lifecycle's editability rule (civora-org/civora-platform#58) |
| `admin` | `contract` | `confirm_redaction` | user's engine roles include `editor` **and** `ContractLifecycle.confirmable?(state)` — `CONFIRMABLE_STATES` = the editable states **plus** `approved`, so a reviewer-approved record can still be stamped right before publish; `editable?` itself is NOT widened (ADR-007, civora-org/civora-platform#91) |
| `admin` | `contract` | `download_crz_handoff` | user's engine roles include `editor`, **no lifecycle condition** — fetching the generated handoff aid is role-gated only, any state (M02-05-C, civora-org/civora-platform#74) |
| `admin` | `contract` | `generate_crz_handoff` | user's engine roles include `editor` **and** the record's state is lifecycle-editable — identical to the `update` rule (generating the aid is editorial work on an editable record, ADR-002) (civora-org/civora-platform#74) |
| `admin` | `contract` | `import_crz` | user's engine roles include `editor`, **no lifecycle condition** — importing one CRZ record is a record-management act on the catalogue, not an edit of an existing record (ADR-008, civora-org/civora-platform#86) |
| `admin` | `contract` | `confirm_crz_filing` | user's engine roles include `editor` **and** the record (`context[:contract]`, required — a bare state is denied) is editorial (`source != "crz"`), `published` and not yet confirmed as filed (`crz_filed_at` blank): only a published editorial record handed off to the CRZ can be linked to its official record, and once. The command re-checks all of it inside the row lock (civora-org/civora-platform#125) |
| `admin` | `contract` | `submit`, `return`, `approve`, `reject`, `publish`, `archive` | `ContractLifecycle.allowed_roles(from: state, event: action)` intersects the user's engine roles |
| `admin` | `contract` | `read` | user holds **any** engine role (admin index) |
| `admin` | `party` | `create`, `update`, `destroy` | user's engine roles include `editor` **and** the parent contract's state is lifecycle-editable (`ContractLifecycle.editable?`) — the same rule as `contract`/`update`, applied to party management (civora-org/civora-platform#76) |
| `admin` | `party` | `read` | user holds **any** engine role (party index) |
| `admin` | `document` | `create`, `update` (replace), `destroy` | user's engine roles include `editor` **and** the parent contract's state is lifecycle-editable (`ContractLifecycle.editable?`) — the same rule as `party` management (civora-org/civora-platform#73) |
| `admin` | `document` | `read` | user holds **any** engine role (documents section of the contract edit page) |
| `admin` | `link` | `create`, `update`, `destroy` | user's engine roles include `editor` **and** the parent contract's state is lifecycle-editable (`ContractLifecycle.editable?`) — the same rule as `party`/`document` management; the link routes expose only `create` and `destroy` (links have no editable content) but the shared rule covers the whole action set for symmetry (civora-org/civora-platform#87) |
| `admin` | `link` | `read` | user holds **any** engine role (declared for symmetry — the links manager lives on the contract edit page; no link index exists) |
| `admin` | `amendment` | `create` | user's engine roles include `editor` **and** the parent contract's state is `published` — version history exists only from publication onwards, so drafts are seeded onto published records only (M02-05-B, civora-org/civora-platform#65, ADR-006) |
| `admin` | `amendment` | `update`, `destroy` | user's engine roles include `editor` **and** the amendment is a draft — published amendments are immutable forever regardless of the contract's own state (ADR-006) |
| `admin` | `amendment` | `publish` | user's engine roles include `editor` **and** the parent contract's state is `published` **and** the amendment is a draft — one explicit POST per publish event, gated like the lifecycle transitions |
| `admin` | `amendment` | `read` | user holds **any** engine role (admin amendment index; drafts and published alike) |
| `admin` | `audit_event` | `read` | user holds **any** engine role — role-only gate, no record and no lifecycle condition: the audit-trail viewer is organization-level (the trail's tenancy is explicit on each row), and the trail has no write surface (civora-org/civora-platform#92) |
| `public` | `contract` | `read` | `ContractLifecycle.publicly_visible?(state)` — i.e. state in `PUBLIC_STATES` (`published`, `archived`) |
| `admin` | `user_role` | `read`, `create`, `destroy` | user is an **organization admin with accepted admin terms** (`user.admin? && user.admin_terms_accepted?`) — engine roles, stored or resolver-granted, never qualify, so a role holder can neither grant nor revoke roles for anyone, themselves included (civora-org/civora-platform#111, parent #95). The commands `GrantUserRole` / `RevokeUserRole` re-check the actor inside their row locks and write one `user_role.grant_<role>` / `user_role.revoke_<role>` audit row (target = the affected user, no email or name) |
| anything else | anything else | anything | **action left unset** → Decidim fails closed (see below) — including every `public`-scope `party`, `document`, `amendment`, `link` and `audit_event` action, so parties, documents, amendments, links and the audit trail are never publicly addressable as subjects (public document downloads and the version history render as part of the published `contract`/`read` page) |

The transition-event list is **derived** from
`ContractLifecycle::TRANSITIONS` (`Permissions::TRANSITION_EVENTS`), never
hand-enumerated — new table edges become checkable without edits here.

### Fail-closed semantics

- Actions the class does not answer for (other subjects, unknown events,
  unknown scopes, non-read public actions) are left **unset**;
  `PermissionAction#allowed?` then raises `PermissionNotSetError`, which
  Decidim's `NeedsPermission#allowed_to?` rescues to `false`.
- Known events from an unknown/missing state evaluate honestly: the allowed
  roles come back empty, so the action is **disallowed** (`allowed? == false`).
- The class never calls `allow!` after `disallow!` (Decidim raises
  `PermissionCannotBeDisallowedError`); downstream chain classes (core
  `Decidim::Permissions`, `Decidim::Admin::Permissions`) never touch subject
  `:contract`, so chain order is safe.

## Role resolver (config-time seam)

`Decidim::ContractsSk.role_resolver` (and `role_resolver=`) hold a
proc/lambda with the contract:

```ruby
resolver.call(user, context) # => Array of engine-role symbols
```

- **Config-time only.** The host assigns it in an initializer; never mutate
  it at request time.
- Results are always **intersected with `ContractLifecycle::ROLES`**
  (defensively, via `Array(...)`): foreign symbols are ignored, `nil` and
  bare symbols degrade safely to the empty set / a one-role set.
- **Default:** organization admins with accepted admin terms hold every
  engine role; everyone else holds the roles stored for them (see
  [Assigning roles](#assigning-roles-95)). The admin part of the default:

```ruby
->(user, _context) { user&.admin? && user.admin_terms_accepted? ? ContractLifecycle::ROLES : [] }
```

Host-override example (in `config/initializers/decidim_contracts_sk.rb`):

```ruby
Decidim::ContractsSk.role_resolver = lambda do |user, _context|
  return [] unless user&.admin? && user.admin_terms_accepted?

  # Illustration: plain admins draft and publish; a dedicated reviewer
  # role (however the host models it) adds the judgment gates.
  user.respond_to?(:contracts_reviewer?) && user.contracts_reviewer? ? %i[editor reviewer] : %i[editor]
end
```

## Notification recipients

Workflow notifications are sent through Decidim's event machinery when a
contract transitions (#94). The `submit` event notifies all users holding the
`:reviewer` role in the organization; the `return`, `approve`, `reject` and
`publish` events notify the contract's author. The acting user is never notified
about their own action.

Recipients come from a config-time seam (`Decidim::ContractsSk.notification_candidates`:
a callable `(organization) -> users`) which bounds the set of candidates, then
narrowed through the `role_resolver` to keep only those with `:reviewer`. The
default candidates are organization admins plus users holding a stored `reviewer`
`UserRole` in the organization (all confirmed, available), which covers everyone
the default resolver can grant `:reviewer` (#110).

**Key constraint:** when the `role_resolver` grants `:reviewer` to non-admins,
the `notification_candidates` seam **must** include them, otherwise eligible
reviewers will not be notified about submissions. The seam is config-time only,
like the resolver itself — see README § Configuration.

## State source (caller contract)

State is read duck-typed from the permission context:

```ruby
context[:contract]&.state || context[:state]
```

Callers (admin controllers, commands, the Contract model #55) pass a
contract-like object, a bare `:state`, or both. Transition checks and public
read both use it; with neither reachable, transition actions and public read
fail closed.

## Public rule

Public `read` on subject `:contract` ⇔
`ContractLifecycle.publicly_visible?(state)` ⇔ state in
`PUBLIC_STATES` (`published`, `archived`). No authentication and no engine
role are required; draft and in-review states can never leak through the
permission layer.

## Org-admin union (D6)

The default resolver implements the org-admin union anticipated by the
lifecycle doc's deferrals: org admins (with accepted admin terms) hold
**all** engine roles on **every** transition-table row, additively — the
table itself stays untouched. The union gives one admin both roles, which is
why the per-person [four-eyes rule](#four-eyes-rule-per-person-segregation-123)
below exists: roles alone never separated duties between two *people*.

Since #110 the default resolver also unions the user's stored `UserRole` rows
(#109) for the user's **own** organization, so a non-admin can hold `editor`
and/or `reviewer`. The resolver ignores its `context` argument (the admin menu
passes an organization, `Permissions` a Hash; spike #108, note N1). Admins
short-circuit with no query; for everyone else the stored roles cost one
indexed query per user object, memoized for that object's lifetime (one
request), so per-row `allowed_to?` calls do not multiply queries. A host that
assigns its own `role_resolver` is unaffected.

## Non-admin role holders and the engine admin (#108, #161)

A user who holds an engine role but is not a Decidim organization admin can
use the whole engine admin (spike: [docs/spikes/m03-06-a-role-admin-access.md](spikes/m03-06-a-role-admin-access.md)):
nothing in Decidim's admin base controller or layout requires an admin, and the
Decidim admin-terms page is only forced on users holding a Decidim role. What
they cannot open is Decidim's own `/admin` dashboard. Consequences, handled by
the engine:

- **Refusals.** Decidim redirects a refused admin action to `/admin`, a 404 for
  them. The engine's admin base controller overrides `user_has_no_permission_path`
  / `user_not_authorized_path`: an engine role holder lands on the engine admin
  overview, a user without a role on the public catalogue; the "not authorized"
  flash is unchanged, and a referer still wins (Decidim's behaviour).
- **Entry link.** Decidim's header, admin bar and account links to the admin are
  gated on `:read :admin_dashboard`, which they lack, so the engine registers a
  "Contracts administration" item in the `:user_menu` registry (the account-area
  navigation). It shows to engine role holders only, and is hidden when Decidim
  already offers its own admin link (org admins), so nobody sees two.
- **Known limitation.** The admin layout's logo and breadcrumb home icon still
  point at `/admin` (404 for them); that is Decidim's layout.

## Assigning roles (#95)

Roles are assigned per user in the engine admin, with no initializer edit
(civora-org/civora-platform#109-#112).

- **Storage.** One `Decidim::ContractsSk::UserRole` row per grant
  (`decidim_contracts_sk_user_roles`: user, organization, `role` in
  `editor`/`reviewer`), unique per `(user, organization, role)` and
  organization-scoped; it holds no personal data beyond the user reference.
  Hosts copy the migration like any other engine migration (README
  Installation).
- **Effective roles.** The default resolver returns the admin default (every
  role for organization admins with accepted terms) **unioned** with the
  user's stored rows; see [Org-admin union](#org-admin-union-d6). A grant or
  revoke applies from the user's next request, with no permission-table edit.
- **Who may assign.** Organization admins with accepted admin terms only
  (`:user_role`, `:read`/`:create`/`:destroy`). The rule does not go through
  the resolver: holding `editor` and/or `reviewer` never confers it, so a
  clerk cannot see or open the screen. The commands re-check this inside
  their locks.
- **The screen.** Admin sidebar **Roles** (sk: *Roly*), `/<mount>/admin/user_roles`:
  the role holders with a **Revoke** button per role (with a confirmation),
  and **Grant role**. Granting starts from a search by name, nickname or
  email: at least 3 characters, at most 20 hits, confirmed and available
  users of the organization only (not deleted, blocked or managed). Results
  show name and nickname; an email is matched but never shown, and the search
  is a POST so it never lands in a URL. Each result offers **Grant Editor** /
  **Grant Reviewer**; organization admins show "Holds both roles" and need no
  rows. A duplicate grant, an unknown user or a failed re-check gives one
  generic failure message. Self-revocation is allowed (admins keep both roles
  through the default anyway).
- **Audit.** Every grant and revoke writes an append-only row,
  `user_role.grant_editor`, `user_role.grant_reviewer`,
  `user_role.revoke_editor` or `user_role.revoke_reviewer`, with the acting
  admin as actor and the affected user as target. The trail
  (`/<mount>/admin/audit_events`) shows the user's **name**, never an email.
- **Host overrides bypass stored roles.** A host `role_resolver` replaces the
  default, so stored roles apply only if the host unions them itself:

```ruby
Decidim::ContractsSk.role_resolver = lambda do |user, context|
  stored = Decidim::ContractsSk::StoredRoles.for(user)
  (my_host_roles(user, context) | stored) & Decidim::ContractsSk::ContractLifecycle::ROLES
end
```

- **Role holders who are not admins** reach the engine admin through the
  [account-menu link](#non-admin-role-holders-and-the-engine-admin-108-161);
  they are not asked for Decidim's admin terms.
- **Non-goals.** No per-record ownership, no role hierarchy, no invitations:
  the user must already have a confirmed account.

## Admin overview: block visibility (#126)

The admin overview (`/admin`) is gated by the contracts index's own
permission (`:read :contract` — any engine role; a roleless user is redirected
with the permission alert). It adds **no role logic**: each role-specific
block asks the permission layer whether the user may perform the event the
block is about, with a bare-state context, so the page can never drift from
the permission table above.

| Block | Shown when (`allowed_to?`) | Editor only | Reviewer only | Both |
|---|---|---|---|---|
| Waiting for my review | `:approve :contract, state: :in_review` | hidden | shown | shown |
| Returned to me | `:submit :contract, state: :returned` | shown | hidden | shown |
| Approved, ready to publish | `:publish :contract, state: :approved` | shown | hidden | shown |
| CRZ deadline overdue / due within 14 days | any engine role (`:read :contract`) | shown | shown | shown |
| Counts per state | any engine role | shown | shown | shown |
| Recent activity (last 10 audit events) | `:read :audit_event` | shown | shown | shown |

The review queue is the set twin of the four-eyes predicate: it lists
`in_review` records for which `self_review_blocked?(record, user, :approve)`
is false — the user's own submissions are excluded (records with no submitter
stamp are included), unless `allow_self_review` is on. Everything is scoped to
the current organization. The contracts index gained the matching
`submitter=me|others` filter so every list's "Show all (N)" link lands on the
same set.

Cost note: the dashboard calls `allowed_to?(:update, …)` once per listed row
(to pick the title link), so a host `role_resolver` that hits the database
costs one query per row (at most 10 per list).

## Four-eyes rule (per-person segregation, #123)

([civora-org/civora-platform#123]) The person who last **submitted** a
contract for review may not **return, approve or reject** it. Role
segregation (`editor` drafts, `reviewer` judges) is not enough under the
org-admin union, where a single admin holds both roles and could draft,
submit and approve their own record.

- **Submitter stamp.** Every `submit` event (first submission and
  resubmission from `returned` alike) writes the acting user's id to
  `decidim_submitted_by_id` on the contract, inside the same row lock and
  UPDATE as the state change. A resubmission by someone else overwrites the
  stamp, so *who is blocked* always follows the last submitter. The column is
  a system field: no form and no CRZ upsert ever writes it. It has no foreign
  key and no index (same shape as `decidim_author_id`).
- **Which events.** Only the judgment events: `return`, `approve`, `reject`.
  The submitter keeps `submit`, `publish`, `archive` and every editorial
  action.
- **Where it is enforced (two layers, one predicate).**
  1. `Permissions` denies the three events to the recorded submitter when the
     record is passed in `context[:contract]`: the admin index renders no
     return/approve/reject controls for that person, and a direct POST gets
     the standard Decidim permission denial. A context carrying only `:state`
     has no submitter and is unaffected.
  2. `TransitionContract` re-checks inside the row lock against the reloaded
     row (defense in depth for races such as a resubmit landing after
     admission, and for other callers). It refuses with the `:self_review`
     payload, a dedicated flash, and writes no state, no decision reason and
     no audit row.

  Both call `Decidim::ContractsSk.self_review_blocked?(contract, user, event)`
  (`lib/decidim/contracts_sk/self_review.rb`), the single source of the event
  vocabulary and the comparison.
- **Legacy records.** A record whose stamp is nil (never submitted, or
  predating the rule) is not blocked. The migration
  `AddSubmittedByToDecidimContractsSkContracts` backfills the stamp from the
  audit trail: the actor of each record's most recent `contract.submit` audit
  row, reversibly (the column is simply dropped on rollback). Records with no
  submit audit row stay nil.
- **Opt-out seam, `allow_self_review`.** For one-person municipalities that
  cannot field a second reviewer, assign `true` in an initializer (default
  `false`, config-time only, like `role_resolver`). The submitter may then
  judge their own record, and every such act is audited under a distinct
  action, `contract.approve_self`, `contract.return_self` or
  `contract.reject_self` (labelled "(self-review)" in the audit viewer), so
  the trail keeps the exception visible. A non-submitter's judgment under the
  seam stays the plain `contract.<event>`.

```ruby
# config/initializers/contracts_sk.rb: only if you genuinely have one person.
Decidim::ContractsSk.allow_self_review = true
```

## Explicit deferrals

- **Role assignment per user** shipped with #95; see [Assigning roles](#assigning-roles-95).
- **Ownership enforcement** (only the authoring editor may submit) —
  authorization concern of the admin command/authorization milestone; the
  permission layer checks role symbols only.
- **Denial audit logging** — belongs to the audit-event model
  ([civora-org/civora-platform#57]).

## Privacy note

Resolvers and permission checks receive Decidim user objects. **Never log
the user argument or any payload derived from it** inside a custom resolver
or permission code: outcomes are plain booleans, and nothing user-identifying
should ever reach the logs from this layer.

[civora-org/civora-platform#53]: https://github.com/civora-org/civora-platform/issues/53
[civora-org/civora-platform#54]: https://github.com/civora-org/civora-platform/issues/54
[civora-org/civora-platform#57]: https://github.com/civora-org/civora-platform/issues/57
[civora-org/civora-platform#58]: https://github.com/civora-org/civora-platform/issues/58
[civora-org/civora-platform#60]: https://github.com/civora-org/civora-platform/issues/60
[civora-org/civora-platform#123]: https://github.com/civora-org/civora-platform/issues/123
