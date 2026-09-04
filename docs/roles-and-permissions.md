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
answers only for subject `:contract`:

| Scope | Subject | Action | Allowed when |
|---|---|---|---|
| `admin` | `contract` | `create` | user's engine roles include `editor` (transition-table row 1 analog) |
| `admin` | `contract` | `update` | user's engine roles include `editor` **and** `ContractLifecycle.editable?(state)` (`draft`, `returned`) — the editorial twin of the lifecycle's editability rule (civora-org/civora-platform#58) |
| `admin` | `contract` | `submit`, `return`, `approve`, `reject`, `publish`, `archive` | `ContractLifecycle.allowed_roles(from: state, event: action)` intersects the user's engine roles |
| `admin` | `contract` | `read` | user holds **any** engine role (admin index) |
| `public` | `contract` | `read` | `ContractLifecycle.publicly_visible?(state)` — i.e. state in `PUBLIC_STATES` (`published`, `archived`) |
| anything else | anything else | anything | **action left unset** → Decidim fails closed (see below) |

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
  engine role; everyone else holds none:

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
table itself stays untouched.

## Explicit deferrals

- **Role-assignment table refinement** — how host organizations designate
  editors and reviewers in Decidim terms is re-decided with the admin
  command milestones ([civora-org/civora-platform#58],
  [civora-org/civora-platform#60]).
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
