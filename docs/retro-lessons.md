# Retro lessons archive

Durable lessons migrated from the *Process Lessons* section of `AGENTS.md` (per its growth/migration policy). Dated, per-arc. These remain true — they just graduated out of the active set.

## PR & closing hygiene (proven #59/#36–#58 arcs; migrated 2026-09-05 from the M02-06-A arc retro)

- **Stacked PRs: rebase onto `origin/main` before creating the PR.** When the base PR merges mid-arc, `gh pr create --base <feature-branch>` fails ("No commits between"); check the base PR's merge state first, `git rebase origin/main`, and target `main` directly (proven in the #59 arc).
- **Cross-repo closing keywords DO work when the PR author has push access to both repos (same org).** `Closes civora-org/civora-platform#n` in a merged PR body auto-closed the platform issue within seconds (proven in the #36/#58 arc). Keep the belt-and-braces explicit `gh issue close` — but check state first; do not assume the convention note above still holds for other org setups.

## Tracker & issue hygiene (proven 2026-08-31 – 2026-09-01 arcs; migrated 2026-09-01 from the #47 arc retro)

- **One consolidated follow-up issue.** Collect reviewer findings into a single prioritized issue in `civora-org/civora-platform` instead of scattering them across chat.
- **Re-scope multi-item issues in place.** For consolidated follow-up issues, re-scope remaining items with explicit stage labels, and map carried-forward items to their named future homes in the closing comment before closing.
- **Audit for closed twins before closing.** Trackers can carry multiple generations of the same work — the platform had closed #24–#27 as twins of open #18–#22. Before closing a "ready-for-review" issue, search closed issues for twins: a closed twin is both evidence (artifacts exist) and precedent (closure pattern to cite) (proven in the 2026-09-01 tracker-refinement arc).
- **Close the status mirrors with the milestone.** Hand-maintained status artifacts (`civora-status-board.md`) drift from the tracker just like config mirrors do — when closing milestone-level work, refresh every mirrored status artifact in the same change, not at the next "convenient" moment (the board still claimed M01-01 was "ready to start" after 8 of 11 sub-issues had shipped).

## Engine mount-design (proven M01-01/#46; migrated 2026-09-01 from the #49 arc retro)

- **Never ship routes without their minimal controller.** Routes aimed at nonexistent controllers pass structural specs but cannot satisfy "responds 200" acceptance criteria — #46 had to backfill M01-01's missing public scaffold controller before the mount could be verified end-to-end.
- **Design mounted routes relative to the mount point.** An engine mounted at a noun path must not repeat the noun inside (`/contracts/contracts` was a design smell): use `root to:` plus `get "/:id"`; note that an unconstrained `/:id` accepts any string as id until a model lookup lands (M01-02 adds the 404).

## Tooling & verification hygiene (proven 2026-09-01 CI arcs; migrated 2026-09-02 from the #48 arc retro)

- **The CI bundle is not the local bundle.** Three independent skews in the #49 arc: a config-required gem (rubocop-rake) that only local global gems masked, a brakeman version gap that made "zero warnings" stale, and CI's `vendor/bundle` directory (absent locally) whose vendored gem configs broke rubocop. Treat first CI runs as discovery — budget iterations, and re-verify tool claims against the same lock CI uses.
- **Change one variable, then re-measure.** Editing an ignore/exclusion file and reading the *previous* run's output as the new baseline produced two wrong dispositions in the #49 arc. After touching any config that filters output, re-run the tool before drawing conclusions — and beware `cmd | tail; $?`, which reports `tail`'s exit status, not the tool's.
- **Dotdirs are invisible to glob tools.** "The engine has no `.github/` at all" was a glob-hidden-dotdir artifact that propagated into issue text; the engine had working CI all along. Verify infrastructure state with `ls -a`, never with glob patterns alone.

## Docker, pins & release hygiene (proven #47/#48 arcs; migrated 2026-09-03 from the #51 arc retro)

- **Release tags are the pin contract for git-pinned engines.** A `tag:` pin in the host Gemfile can only carry changes that are actually released: v0.5.0 could not resolve against Decidim 0.31.7 because the 0.31 retarget sat unreleased on engine `main`. Before planning around a tag pin, verify the tag contains the needed change; if it doesn't, cut the release rather than pinning a branch (release-please shipped v0.6.0 mid-task in the #47 arc and the deterministic pin was restored).
- **`gh auth setup-git` unlocks bundler `github:` sources.** Bundler's `github:` shorthand clones over HTTPS and fails non-interactively ("could not read Username") without a credential helper — on gh-authed machines, run `gh auth setup-git` before `bundle install` (documented in the civora-host README; proven in the #47 arc).
- **Pass Docker build secrets as BuildKit secret mounts, never build args.** Private git gem sources break in-image `bundle install` ("could not read Username"); inject a token into a same-layer temp `GIT_CONFIG_GLOBAL` (deleted before the layer commits) and verify absence with `docker history --no-trunc` + `docker save | grep` — 0 matches for every secret value (proven in the #48 arc).

## Org capabilities & tooling hygiene (proven #49/#50 arcs; migrated 2026-09-03 from the #51 arc retro)

- **Load dev tools, don't just install them.** Validate dev-dependency pins by actually activating the tool (e.g. rubocop plugins) in a real run — "installed but not loaded" can hide version incompatibilities until they detonate.
- **Check org plan capabilities before promising GitHub gating.** The civora org is on the free plan: branch protection *and* rulesets 403 on private repos, and no existing repo has ever had protection. Don't write protection/required-check promises into plans or issue checklists without a capability check; the practical gate is CI (#49) plus discipline, and unlocking real protection is a pay-or-accept decision for the human.
- **Document conventions before they are needed.** Keep the *Project Conventions* section current as soon as a new convention is decided, not after it causes friction. Policies are usually mirrored across files (`AGENTS.md`, `opencode.jsonc`, agent/command markdown) — update every mirror in the same change, or the drift surfaces later (re-proven in the #47 arc: the platform README shipped an aspirational monorepo layout that never existed).

> De-duplication 2026-09-04 (#75 arc retro): "Load dev tools" and "Document conventions" had stale copies left in the AGENTS.md *active* set after this cluster's migration — the copies were removed; this archive is their only home.

## Decidim host-app smoke (proven #48 arc; migrated 2026-09-03 from the #51 arc retro)

- **Decidim serves nothing without an organization.** Every page of a mounted engine redirects to the system root when `current_organization` is nil, so fresh-DB smoke tests need an idempotent minimal-org seed; `Decidim.seed!` is faker-based and unsuitable for production images.

## Host-app & ops cluster (proven #46/#48/#51 arcs; migrated 2026-09-03 from the #61 arc retro)

- **The host app is ground truth too.** Before planning host-integration issues, diff the issue's assumptions against the actual host app the user points to — versions, boot state, DB. #46 assumed a fresh 0.28.x bootstrap while the real host was an existing 0.31.7 app, turning half the issue into a decision. When engine pins conflict with the host, move the engine to the host's major *early*: the cost of the jump grows with the engine's surface.
- **DISABLE_SPRING=1 for host-app rails commands.** Spring daemonizes tool sessions in the host app and swallows command completion — prefix every host-app command with it.
- **Decidim's initializers override plain Rails config.** `config.force_ssl = false` in `production.rb` was silently re-overridden by decidim-core's `ssl_and_hsts` initializer; the effective knob was `DECIDIM_FORCE_SSL`. For any host-app env config, check the pinned gem's initializer order first — the Rails-level setting may be dead code.
- **Local checkout names drift from repo names.** `civora-org/civora-host` lives at `~/Code/decidim-app` — before cloning any civora repo, ask for (or list `~/Code` fully and inspect remotes of likely candidates) the existing local checkout; don't clone fresh just because the directory name doesn't match.
- **Verify container-image script paths against the actual pinned tag.** Entry scripts drift between image versions — GlitchTip v5 renamed `run-worker.sh` to `run-celery.sh` and its stock entrypoint skips `migrate`. Before wiring a `command:`/entrypoint, `docker run --rm --entrypoint ls <image> bin/` (or equivalent) and check what init steps the image actually performs.
- **Cross-component wiring fails silently at boot.** Prometheus ran "healthy" with no `alerting:` section — alerts simply never left. For any chain (app → collector → Prometheus → Alertmanager → webhook), pin every hop in structural tests and verify the last hop receives, not just that first ones emit.
- **Scripts sharing a compose stack must select compose files in one place.** deploy/smoke scripts running bare `docker compose` silently strip overlay config (env vars, logging caps) from recreated services; drive file selection via `COMPOSE_FILE` in `.env` and have scripts defer to it.
- **Bootstrap self-hosted UIs via their container CLI.** `manage.py migrate/createsuperuser/shell` inside the container replaces hand-clicking and enables DSN generation in-task; expect model-name drift from upstream docs and inspect the installed source, not memory.

## Engine implementation mechanics (proven #53 arc; migrated 2026-09-04 from the #58/#59 arc retro)

- **Respect require-time constant order in entry files.** `lib/decidim/contracts_sk.rb` defines `Error` at the top because `contract_lifecycle.rb` subclasses it at require time — when adding a `require_relative`, check it doesn't reference constants defined *below* the require line; the suite catches it only as a full-suite NameError.
- **Deep-freeze means every level.** A frozen outer hash leaves nested hashes/arrays mutable; freeze role arrays → edge hashes → per-state maps → table, and spec-guard each level (`be_frozen` down the nesting), or the "immutable constants" guarantee is illusory.
