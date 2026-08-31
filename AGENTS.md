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
| `contracts` | `zai/glm-5.3` | Primary collaborator/router for this engine |
| `architect` | `zai/glm-5.3` | Read-only scope and decomposition |
| `reviewer` | `zai/glm-5.3` | Read-only code review |
| `rails` | `zai/glm-5.3-flash` | Rails/Decidim implementation |
| `tester` | `zai/glm-5.3-flash` | Test design and verification mapping |
| `integration` | `zai/glm-5.3-flash` | Optional future external-source/import integration |
| `retro` | `zai/glm-5.3-flash` | Retrospective analysis |

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

## Default Workflow

1. Read `README.md`, `decidim-contracts_sk.gemspec`, `config/routes.rb`, and affected files.
2. Run a baseline `bundle exec rspec` (and `bundle exec rubocop`) **before** planning any task — surface environment problems when they are cheap.
3. Restate the task as goal, scope/non-scope, affected areas, risks, AC, and DoD.
4. Ask for approval before edits or migrations.
5. Implement the smallest viable approved change.
6. Run relevant tests and safe verification steps.
7. Summarize changes, risks, follow-ups, and DoD status.
8. After a meaningful task, prepare a retro draft without writing retro files automatically.

### Process Lessons

Distilled from retro drafts; treat as working agreements, not archive:

- **Baseline first.** Always verify the test suite runs green before starting work; fix environment/dependency drift before planning.
- **Name design conflicts.** When an issue's code example conflicts with route-level scope or engineering guardrails, present it as an explicit named decision (e.g., Option A/B) at an approval gate — never silently fix, never silently obey.
- **One consolidated follow-up issue.** Collect reviewer findings into a single prioritized issue in `civora-org/civora-platform` instead of scattering them across chat.
- **Document conventions before they are needed.** Keep the *Project Conventions* section current as soon as a new convention is decided, not after it causes friction.

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
| `/retro <number>` | Prepares retro draft without changing files |

## Model Verification

After connecting Z.AI, verify the actual model IDs via `/models` and adjust `opencode.jsonc` if the provider uses different exact identifiers.
