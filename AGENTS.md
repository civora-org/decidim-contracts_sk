# decidim-contracts_sk Agents

## Primary Configuration

The primary AI configuration for this repository should live in `opencode.jsonc` and `.opencode/`.

- **Config:** `opencode.jsonc`
- **Agents:** `.opencode/agents/`
- **Commands:** `.opencode/commands/`

This repository is a focused Decidim engine, not the full Civora platform. Agents must optimize for a reusable, maintainable module with clear boundaries, deterministic behavior, and low solo-maintainer overhead. The orchestration model is inspired by Civora, but the context is adapted to this engine's actual scope.

## Repository Purpose

`decidim-contracts_sk` is a standalone Decidim engine for Slovak public contracts workflow and catalogue. The gemspec describes it as a module for drafting, reviewing, and publishing public contract records together with a public catalogue for Slovak municipalities and public-sector organisations.

Current route-level scope in the repository:

- Public routes: `contracts#index`, `contracts#show`.
- Admin routes: `admin/contracts` CRUD namespace.

## Project Conventions

### GitHub Issue Tracking

Issues for this engine are tracked in the platform repository, **not** in this repo:

- **Issue repository:** `civora-org/civora-platform`
- `/issue <number>` and issue references resolve there, e.g. `civora-org/civora-platform#36` (M01-01-D).
- This repository itself typically has no issues; do not create issues here.

### Branch, Commit, and PR Conventions

- Branch names follow the milestone task: `m01-01-d-create-base-application-controller` (pattern: `{milestone-task}-{kebab-description}`); non-milestone work uses `{type}/{kebab-description}`, e.g. `docs/issue-linking-conventions`, `fix/admin-auth-hardening`.
- PR titles mirror the issue title, e.g. `M01-01-D: Create base application controller`; PRs target `main`.
- Commits follow Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`) with the milestone tag, e.g. `feat(controllers): ... (M01-01-D)`.
- **Every PR must link to its driving issue** in `civora-org/civora-platform` (full cross-repo reference, e.g. `civora-org/civora-platform#45`).
- **Close issues when development finishes.** GitHub closing keywords (`Closes #n`) do **not** work across repositories — close the issue explicitly (`gh issue close --repo civora-org/civora-platform`) after the PR is merged. For multi-item issues, close only when every item is done (or split items first).
- `CHANGELOG.md` is managed by release-please from commit messages — **do not edit it manually**.
- As a gem, `Gemfile.lock` stays uncommitted.

## OpenCode Orchestration Model

This repo should keep the same high-level workflow pattern as Civora:

- work starts from a GitHub Issue or a clearly written feature request;
- the router agent reads local context and decides which subagents to use;
- planning happens before implementation;
- approval is required before edits, migrations, git write actions, external calls, or deploy-like actions.

Recommended agents for this repository:

| Agent | Model | Role |
|-------|-------|------|
| `contracts` | `zai-coding-plan/glm-5.3` | Primary collaborator/router for this engine |
| `architect` | `zai-coding-plan/glm-5.3` | Read-only scope and decomposition |
| `reviewer` | `zai-coding-plan/glm-5.3` | Read-only code review |
| `rails` | `zai-coding-plan/glm-5.3-flash` | Rails/Decidim implementation |
| `tester` | `zai-coding-plan/glm-5.3-flash` | Test design and verification mapping |
| `integration` | `zai-coding-plan/glm-5.3-flash` | Optional future external-source/import integration |
| `retro` | `zai-coding-plan/glm-5.3-flash` | Optional second-opinion retrospective analysis (router owns retros; see *Retro Policy*) |

## Engineering Guardrails

- Do not fork or patch Decidim core unless explicitly approved.
- Prefer Rails engines, Decidim extension points, standard Rails patterns, and isolated engine-friendly design.
- Keep admin and public behaviour clearly separated.
- Keep the engine usable independently from the wider Civora product context.
- Do not introduce premature microservices, background infra, or product-wide assumptions.
- Explain migrations before applying them.
- Deterministic tests are required for meaningful changes.

## Data and Privacy

Even though this module works with public contract records, agents must still be conservative with data handling.

- Do not assume source data is clean.
- Avoid storing unnecessary personal or sensitive data.
- Do not use real personal data in fixtures, demos, or examples.
- Keep logs safe and avoid dumping sensitive payloads.
- If external imports are added later, capture provenance and freshness metadata such as source URL, import time, checksum, and import status.

## Approval Gates

The main router agent must stop and request human approval before:

- editing code or docs;
- running DB migrations;
- creating or modifying branches;
- committing or pushing;
- creating or modifying GitHub Issues, PRs, comments, or labels;
- making external API calls;
- deploy-like actions.

**Standing exception (Retro Policy):** after a meaningful task the router self-reviews the arc (no delegation required) and may edit the *Process Lessons* section of `AGENTS.md` directly — including executing its growth/migration policy — without prior human approval. Committing those edits still passes the normal git gate (bundle them into the next approved commit or a dedicated `docs(agents):` commit at the next gate).

## Default Workflow

1. Read `README.md`, `decidim-contracts_sk.gemspec`, `config/routes.rb`, and affected files.
2. Run a baseline `bundle exec rspec` (and `bundle exec rubocop`) **before** planning any task — surface environment problems when they are cheap.
3. Restate the task as goal, scope/non-scope, affected areas, risks, AC, and DoD.
4. Ask for approval before edits or migrations.
5. Implement the smallest viable approved change.
6. Run relevant tests and safe verification steps.
7. Summarize changes, risks, follow-ups, and DoD status.
8. After a meaningful task, run the retro: the router self-reviews the arc, distills durable lessons into *Process Lessons* below, and — when the section hits its growth trigger — executes the migration policy.

### Process Lessons

Distilled from router retros; treat as working agreements, not archive.

**Growth/migration policy:** this section is the *active* set and must stay scannable. When it exceeds ~15 lessons, or when lessons cluster into distinct themes (e.g., tooling vs. issue hygiene), migrate the overflow into `docs/retro-lessons.md` (dated, per-arc) and keep here only the active agreements plus a link. Migrations are covered by the Retro Policy exception.

Current lessons:

- **Baseline first.** Always verify the test suite runs green before starting work; fix environment/dependency drift before planning.
- **Pinned gem source is ground truth.** Verify every Decidim/rubocop API claim against the installed gem sources (`bundle info <gem> --path`, then grep) before planning — treat issue code examples as suggestions, not facts (proven ×3 in the #45 arc).
- **The tree is ground truth for issue state.** Milestone issues drift from the repo — #39 arrived ~80% implemented by an earlier task. Before planning, diff the issue's task list against the current tree and split it into *already shipped* / *shipped but unverified* / *genuinely missing*; plan only the remainder and restate the split in the issue's closing comment (proven in the #39 arc).
- **Load dev tools, don't just install them.** Validate dev-dependency pins by actually activating the tool (e.g. rubocop plugins) in a real run — "installed but not loaded" can hide version incompatibilities until they detonate.
- **Name design conflicts.** When an issue's code example conflicts with route-level scope or engineering guardrails, present it as an explicit named decision (e.g., Option A/B) at an approval gate — never silently fix, never silently obey.
- **Document conventions before they are needed.** Keep the *Project Conventions* section current as soon as a new convention is decided, not after it causes friction. Policies are usually mirrored across files (`AGENTS.md`, `opencode.jsonc`, agent/command markdown) — update every mirror in the same change, or the drift surfaces later (re-proven in the #47 arc: the platform README shipped an aspirational monorepo layout that never existed).
- **The host app is ground truth too.** Before planning host-integration issues, diff the issue's assumptions against the actual host app the user points to — versions, boot state, DB. #46 assumed a fresh 0.28.x bootstrap while the real host was an existing 0.31.7 app, turning half the issue into a decision. When engine pins conflict with the host, move the engine to the host's major *early*: the cost of the jump grows with the engine's surface (proven in the #46 arc).
- **DISABLE_SPRING=1 for host-app rails commands.** Spring daemonizes tool sessions in the host app and swallows command completion — prefix every host-app command with it.
- **Set explicit security floors for `=`-pinned meta-gem families.** Decidim's meta-gems pin each other with `=`, so a loose floor (`~> 0.31.0`) lets *fresh* resolutions settle on an old, unpatched line (0.31.0, CVE-2026-45573) while local committed locks sit on the patched one. Raise the floor to the patched line (`~> 0.31.5`) — and run the auditor in CI against fresh resolutions, which is exactly what caught this.
- **Decidim's initializers override plain Rails config.** `config.force_ssl = false` in `production.rb` was silently re-overridden by decidim-core's `ssl_and_hsts` initializer; the effective knob was `DECIDIM_FORCE_SSL`. For any host-app env config, check the pinned gem's initializer order first — the Rails-level setting may be dead code (proven in the #48 arc).
- **Local checkout names drift from repo names.** `civora-org/civora-host` lives at `~/Code/decidim-app` — before cloning any civora repo, ask for (or list `~/Code` fully and inspect remotes of likely candidates) the existing local checkout; don't clone fresh just because the directory name doesn't match (proven in the #51 arc).
- **Verify container-image script paths against the actual pinned tag.** Entry scripts drift between image versions — GlitchTip v5 renamed `run-worker.sh` to `run-celery.sh` and its stock entrypoint skips `migrate`. Before wiring a `command:`/entrypoint, `docker run --rm --entrypoint ls <image> bin/` (or equivalent) and check what init steps the image actually performs (proven in the #51 arc).
- **Cross-component wiring fails silently at boot.** Prometheus ran "healthy" with no `alerting:` section — alerts simply never left. For any chain (app → collector → Prometheus → Alertmanager → webhook), pin every hop in structural tests and verify the last hop receives, not just that first ones emit (proven in the #51 arc).
- **Scripts sharing a compose stack must select compose files in one place.** deploy/smoke scripts running bare `docker compose` silently strip overlay config (env vars, logging caps) from recreated services; drive file selection via `COMPOSE_FILE` in `.env` and have scripts defer to it (proven in the #51 arc).
- **Respect require-time constant order in entry files.** `lib/decidim/contracts_sk.rb` defines `Error` at the top because `contract_lifecycle.rb` subclasses it at require time — when adding a `require_relative`, check it doesn't reference constants defined *below* the require line; the suite catches it only as a full-suite NameError (proven in the #53 arc).
- **Deep-freeze means every level.** A frozen outer hash leaves nested hashes/arrays mutable; freeze role arrays → edge hashes → per-state maps → table, and spec-guard each level (`be_frozen` down the nesting), or the "immutable constants" guarantee is illusory (proven in the #53 arc).
- **Implementation is delegated, not hand-written by the router.** After Gate-1 design approval, hand implementation + verification to the `rails` subagent (user preference, #53 arc); the router stops at design/gates.
- **Bootstrap self-hosted UIs via their container CLI.** `manage.py migrate/createsuperuser/shell` inside the container replaces hand-clicking and enables DSN generation in-task; expect model-name drift from upstream docs and inspect the installed source, not memory (proven in the #51 arc).
- **The platform repo's docs are product ground truth.** Before planning any schema/domain task, read `civora-org/civora-platform` `docs/00-product/` (ADRs, V0-scope) and `docs/01-discovery/` — the product boundary (e.g. "workflow layer, not CRZ replacement", manual handoff fields) lives there, not in the engine repo or the issue text (proven in the #55 arc: ADR-002 reframed schema decisions late in the arc).
- **Offline review cannot replace a live boot.** Both the tester and reviewer passes missed boot-only failures (worker script path, missing `alerting:` section); the first `docker compose up` found them in minutes. For infra-bearing changes, the arc is not done until the real stack boots and the acceptance behavior is demonstrated live (proven in the #51 arc).

*Archived lessons (tracker & issue hygiene; engine mount-design; tooling & verification hygiene clusters) live in [`docs/retro-lessons.md`](docs/retro-lessons.md).*

## Testing Expectations

Every meaningful change should map acceptance criteria to deterministic tests. The testing agent should at minimum consider:

- model validations and domain logic;
- public and admin request behaviour;
- authorization checks for admin flows;
- empty state and malformed input handling;
- regression coverage for fixed bugs.

If import or sync functionality is introduced later, also cover timeout, retries, stale fallback, repeated import, malformed source data, and absence of real PII in fixtures.

## Review Heuristics

Reviewers should check:

- Decidim compatibility;
- engine isolation;
- admin/public separation;
- migration safety;
- privacy and logging safety;
- test completeness;
- documentation drift;
- unnecessary complexity.

Use findings grouped as:

- BLOCKER
- HIGH
- MEDIUM
- LOW

## Recommended Commands

| Command | Description |
|---------|-------------|
| `/issue <number>` | Read-only analysis and auto-router plan for an existing Issue |
| `/feature <description>` | Read-only plan for a new feature |
| `/review <number>` | Read-only current-diff review tied to Issue or current diff |
| `/verify` | Runs only safe, applicable local tests/lints |
| `/retro <number>` | Router self-review of an arc; distills lessons into `AGENTS.md` *Process Lessons* (pre-approved) |

## Model Verification

After connecting Z.AI, verify the actual model IDs via `/models` and adjust `opencode.jsonc` if the provider uses different exact identifiers.
