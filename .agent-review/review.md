# Agent Review

## Task
civora-org/civora-platform#125: CRZ round-trip — confirm the filing and link the official record

## Session
- Session ID: 3475ce5c-5efe-491e-b0c8-096df82cca8e
- Branch: feat/crz-filing-confirmation
- Started: 2026-10-03T16:51:14.148Z
- Finished: 2026-10-03T17:29:00.695Z

## Summary
CRZ filing columns migration: civora-platform#125: store the verified CRZ filing confirmation (filed_at, published_on, override reason) as nullable system columns. Admin::ConfirmCrzFiling command, FilingLookup, FilingComparison, Mapper/CrzScope extensions: Verify a hand-filed editorial contract against the official CRZ record and stamp the filing under the row lock, with mirror absorption. Sync linked rule, G4 fix, deadline hard switch: A filing-confirmed editorial record is the canonical linked record of its CRZ id; sync must not duplicate or flag it. Failure stamps must never touch editorial rows. Deadline tracking keys on crz_filed_at. Admin filing UI, permission, routes, public detail, locales, audit labels, docs: Editor-facing round trip: preview comparison page, confirm POST, index entry link, public CRZ publication line.

## Logical Changes

### 1. Admin::ConfirmCrzFiling command, FilingLookup, FilingComparison, Mapper/CrzScope extensions
- What changed: added in `app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb`, `lib/decidim/contracts_sk/crz_import/filing_lookup.rb`, `lib/decidim/contracts_sk/crz_import/filing_comparison.rb`, `lib/decidim/contracts_sk/crz_import/mapper.rb`, `lib/decidim/contracts_sk/crz_scope.rb`
- Why: Verify a hand-filed editorial contract against the official CRZ record and stamp the filing under the row lock, with mirror absorption.
- Expected behavior: Fetch outside lock; in-lock re-check of source/state/filed/checksum/comparison/reason/id; one transaction with audit row; refusals broadcast as symbols.
- Risk: medium
- Alternatives considered: Audit absorbed-mirror row targeting the destroyed mirror (rejected: dangling target)
### 2. Sync linked rule, G4 fix, deadline hard switch
- What changed: modified in `app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb`, `lib/decidim/contracts_sk/crz_import/sync.rb`, `lib/decidim/contracts_sk/crz_deadline.rb`, `app/models/decidim/contracts_sk/contract.rb`, `lib/tasks/decidim_contracts_sk_crz_import.rake`
- Why: A filing-confirmed editorial record is the canonical linked record of its CRZ id; sync must not duplicate or flag it. Failure stamps must never touch editorial rows. Deadline tracking keys on crz_filed_at.
- Expected behavior: :linked outcome with zero writes at all decision points; linked counters; find_mirror/mark_failed scoped to source crz; tracked? uses crz_filed_at.
- Risk: medium
### 3. CRZ filing columns migration
- What changed: added in `db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb`, `spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb`
- Why: civora-platform#125: store the verified CRZ filing confirmation (filed_at, published_on, override reason) as nullable system columns.
- Expected behavior: Additive reversible migration, no backfill, no defaults/indexes.
- Risk: low
### 4. Admin filing UI, permission, routes, public detail, locales, audit labels, docs
- What changed: added in `app/controllers/decidim/contracts_sk/admin/contracts_controller.rb`, `app/permissions/decidim/contracts_sk/permissions.rb`, `config/routes.rb`, `app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb`, `app/views/decidim/contracts_sk/contracts/show.html.erb`, `config/locales/en.yml`, `config/locales/sk.yml`, `docs/crz-import.md`
- Why: Editor-facing round trip: preview comparison page, confirm POST, index entry link, public CRZ publication line.
- Expected behavior: GET preview writes nothing; POST runs the command; en/sk parity; editor-only permission on published unfiled editorial records.
- Risk: low

## Test Evidence

### Run 1
- Command: `bundle exec rubocop`
- Result: **passed** (exit code: 0)
- Duration: 1613 ms
- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
- Notes: stderr captured (342 lines, redacted and truncated)

## Risks
- Large diff: 2757 insertions across 52 files.

## Limitations
- Snapshots cover only files that were changed at checkpoint time.
- Symbol extraction is regex-based, not AST-based.
- Only observed facts are recorded — private model reasoning is not captured.

## Changed Files
- `app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb` — modified (ruby, +242/−0)
- `app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb` — modified (ruby, +40/−6)
- `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb` — modified (ruby, +13/−2)
- `app/controllers/decidim/contracts_sk/admin/contracts_controller.rb` — modified (ruby, +93/−2)
- `app/models/decidim/contracts_sk/contract.rb` — modified (ruby, +6/−5)
- `app/permissions/decidim/contracts_sk/permissions.rb` — modified (ruby, +27/−1)
- `app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb` — modified (unknown, +99/−0)
- `app/views/decidim/contracts_sk/admin/contracts/index.html.erb` — modified (unknown, +11/−2)
- `app/views/decidim/contracts_sk/contracts/show.html.erb` — modified (unknown, +19/−1)
- `config/locales/en.yml` — modified (yaml, +55/−2)
- `config/locales/sk.yml` — modified (yaml, +55/−2)
- `config/routes.rb` — modified (ruby, +14/−0)
- `db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb` — modified (ruby, +37/−0)
- `docs/contract-lifecycle.md` — modified (markdown, +13/−8)
- `docs/contracts-domain-notes.md` — modified (markdown, +39/−3)
- `docs/crz-import.md` — modified (markdown, +70/−7)
- `docs/manual-test-scenarios.md` — modified (markdown, +14/−0)
- `docs/pilot-operations.md` — modified (markdown, +1/−1)
- `docs/qa-checklist.md` — modified (markdown, +10/−1)
- `docs/roles-and-permissions.md` — modified (markdown, +1/−0)
- `lib/decidim/contracts_sk.rb` — modified (ruby, +2/−0)
- `lib/decidim/contracts_sk/crz_deadline.rb` — modified (ruby, +8/−7)
- `lib/decidim/contracts_sk/crz_import/filing_comparison.rb` — modified (ruby, +124/−0)
- `lib/decidim/contracts_sk/crz_import/filing_lookup.rb` — modified (ruby, +84/−0)
- `lib/decidim/contracts_sk/crz_import/mapper.rb` — modified (ruby, +42/−2)
- `lib/decidim/contracts_sk/crz_import/sync.rb` — modified (ruby, +54/−24)
- `lib/decidim/contracts_sk/crz_scope.rb` — modified (ruby, +19/−0)
- `lib/tasks/decidim_contracts_sk_crz_import.rake` — modified (unknown, +5/−1)
- `lib/tasks/decidim_contracts_sk_seed_demo.rake` — modified (unknown, +6/−1)
- `README.md` — modified (markdown, +2/−2)
- `spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb` — modified (ruby, +121/−0)
- `spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb` — modified (ruby, +5/−4)
- `spec/decidim/contracts_sk_crz_scope_spec.rb` — modified (ruby, +19/−0)
- `spec/decidim/contracts_sk_locales_spec.rb` — modified (ruby, +79/−0)
- `spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb` — modified (ruby, +4/−3)
- `spec/decidim/contracts_sk/admin/confirm_crz_filing_spec.rb` — modified (ruby, +335/−0)
- `spec/decidim/contracts_sk/admin/contracts_controller_spec.rb` — modified (ruby, +6/−3)
- `spec/decidim/contracts_sk/contract_crz_deadline_spec.rb` — modified (ruby, +7/−7)
- `spec/decidim/contracts_sk/crz_deadline_spec.rb` — modified (ruby, +5/−6)
- `spec/decidim/contracts_sk/crz_import/filing_comparison_spec.rb` — modified (ruby, +158/−0)
- `spec/decidim/contracts_sk/crz_import/filing_lookup_spec.rb` — modified (ruby, +88/−0)
- `spec/decidim/contracts_sk/crz_import/mapper_spec.rb` — modified (ruby, +42/−0)
- `spec/decidim/contracts_sk/crz_import/sync_spec.rb` — modified (ruby, +92/−0)
- `spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb` — modified (ruby, +83/−2)
- `spec/decidim/contracts_sk/engine_routing_spec.rb` — modified (ruby, +48/−8)
- `spec/decidim/contracts_sk/permissions_spec.rb` — modified (ruby, +63/−0)
- `spec/requests/admin/audit_events_spec.rb` — modified (ruby, +15/−0)
- `spec/requests/admin/contracts_crz_deadline_spec.rb` — modified (ruby, +8/−7)
- `spec/requests/admin/contracts_spec.rb` — modified (ruby, +10/−0)
- `spec/requests/admin/crz_filing_spec.rb` — modified (ruby, +303/−0)
- `spec/requests/admin/crz_import_spec.rb` — modified (ruby, +20/−0)
- `spec/requests/contracts_spec.rb` — modified (ruby, +41/−0)

## Commits
- `c34981147e` feat(crz-filing): confirm the CRZ filing and link the official record (civora-org/civora-platform#125) (Denys Kozlov, 2026-10-03T19:28:40+02:00)

## Diff
```diff
diff --git a/.agent-review/change-package.json b/.agent-review/change-package.json
index 56ab3ef..70e11ef 100644
--- a/.agent-review/change-package.json
+++ b/.agent-review/change-package.json
@@ -1,304 +1,749 @@
 {
   "schemaVersion": "agent-review/v1",
   "session": {
-    "id": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
-    "startedAt": "2026-10-02T22:26:31.118Z",
-    "endedAt": "2026-10-02T22:27:52.305Z",
-    "status": "ended"
+    "id": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+    "startedAt": "2026-10-03T16:51:14.148Z",
+    "endedAt": null,
+    "status": "active"
   },
-  "task": "Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code",
-  "branch": "chore/claude-code-config",
+  "task": "civora-org/civora-platform#125: CRZ round-trip — confirm the filing and link the official record",
+  "branch": "feat/crz-filing-confirmation",
   "commits": [
     {
-      "hash": "5a3f5102c111c56ea154eb5878727e15e45169e1",
-      "subject": "chore: mirror OpenCode agent setup for Claude Code",
+      "hash": "c34981147e9420354b899f42e0c40565ceaf7017",
+      "subject": "feat(crz-filing): confirm the CRZ filing and link the official record (civora-org/civora-platform#125)",
       "author": "Denys Kozlov",
-      "date": "2026-10-03T00:27:48+02:00"
+      "date": "2026-10-03T19:28:40+02:00"
     }
   ],
   "changedFiles": [
     {
-      "path": ".agent-review/change-package.json",
+      "path": "app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb",
       "kind": "modified",
-      "language": "json",
-      "insertions": 207,
-      "deletions": 341
+      "language": "ruby",
+      "insertions": 242,
+      "deletions": 0,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "Admin",
+        "ConfirmCrzFiling",
+        "Refusal",
+        "initialize",
+        "call",
+        "verified_record",
+        "editor?",
+        "normalized_reason"
+      ]
     },
     {
-      "path": ".agent-review/github/inline-comments.preview.json",
+      "path": "app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb",
       "kind": "modified",
-      "language": "json",
-      "insertions": 18,
-      "deletions": 5
+      "language": "ruby",
+      "insertions": 40,
+      "deletions": 6,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "CrzImport",
+        "UpsertContract",
+        "initialize",
+        "call",
+        "perform",
+        "create_transactional",
+        "lost_create_race",
+        "create_or_reroute!"
+      ]
     },
     {
-      "path": ".agent-review/github/pr-body.md",
+      "path": "app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 16,
-      "deletions": 9
+      "language": "ruby",
+      "insertions": 13,
+      "deletions": 2,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "Admin",
+        "AuditEventsController",
+        "index",
+        "filtered_events",
+        "audit_events_scope",
+        "filtered_contract",
+        "contracts_scope",
+        "audit_action_label"
+      ]
     },
     {
-      "path": ".agent-review/github/pr-preview.json",
+      "path": "app/controllers/decidim/contracts_sk/admin/contracts_controller.rb",
       "kind": "modified",
-      "language": "json",
-      "insertions": 23,
-      "deletions": 10
+      "language": "ruby",
+      "insertions": 93,
+      "deletions": 2,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "Admin",
+        "ContractsController",
+        "index",
+        "new",
+        "create",
+        "edit",
+        "update",
+        "download_crz_handoff"
+      ]
     },
     {
-      "path": ".agent-review/github/publish-plan.md",
+      "path": "app/models/decidim/contracts_sk/contract.rb",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 5,
-      "deletions": 4
+      "language": "ruby",
+      "insertions": 6,
+      "deletions": 5,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "Contract",
+        "crz_deadline",
+        "crz_days_left",
+        "crz_deadline_tracked?",
+        "crz_deadline_status"
+      ]
     },
     {
-      "path": ".agent-review/review.md",
+      "path": "app/permissions/decidim/contracts_sk/permissions.rb",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 4156,
-      "deletions": 997
+      "language": "ruby",
+      "insertions": 27,
+      "deletions": 1,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "Permissions",
+        "permissions",
+        "admin_action",
+        "audit_event_action",
+        "contract_action",
+        "self_review_blocked?",
+        "child_record_action",
+        "amendment_action"
+      ]
     },
     {
-      "path": ".claude/agents/architect.md",
+      "path": "app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 39,
+      "language": "unknown",
+      "insertions": 99,
       "deletions": 0
     },
     {
-      "path": ".claude/agents/integration.md",
+      "path": "app/views/decidim/contracts_sk/admin/contracts/index.html.erb",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 34,
-      "deletions": 0
+      "language": "unknown",
+      "insertions": 11,
+      "deletions": 2
     },
     {
-      "path": ".claude/agents/rails.md",
+      "path": "app/views/decidim/contracts_sk/contracts/show.html.erb",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 27,
-      "deletions": 0
+      "language": "unknown",
+      "insertions": 19,
+      "deletions": 1
     },
     {
-      "path": ".claude/agents/retro.md",
+      "path": "config/locales/en.yml",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 24,
-      "deletions": 0
+      "language": "yaml",
+      "insertions": 55,
+      "deletions": 2
     },
     {
-      "path": ".claude/agents/reviewer.md",
+      "path": "config/locales/sk.yml",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 35,
-      "deletions": 0
+      "language": "yaml",
+      "insertions": 55,
+      "deletions": 2
     },
     {
-      "path": ".claude/agents/tester.md",
+      "path": "config/routes.rb",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 36,
+      "language": "ruby",
+      "insertions": 14,
       "deletions": 0
     },
     {
-      "path": ".claude/settings.json",
+      "path": "db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb",
       "kind": "modified",
-      "language": "json",
-      "insertions": 56,
-      "deletions": 0
+      "language": "ruby",
+      "insertions": 37,
+      "deletions": 0,
+      "symbols": [
+        "AddCrzFilingToDecidimContractsSkContracts",
+        "change"
+      ]
     },
     {
-      "path": ".claude/skills/agent-review",
+      "path": "docs/contract-lifecycle.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 1,
-      "deletions": 0
+      "language": "markdown",
+      "insertions": 13,
+      "deletions": 8
     },
     {
-      "path": ".claude/skills/agent-review-github-status/SKILL.md",
+      "path": "docs/contracts-domain-notes.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 21,
-      "deletions": 0
+      "insertions": 39,
+      "deletions": 3
     },
     {
-      "path": ".claude/skills/agent-review-prepare-pr/SKILL.md",
+      "path": "docs/crz-import.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 25,
-      "deletions": 0
+      "insertions": 70,
+      "deletions": 7
     },
     {
-      "path": ".claude/skills/agent-review-publish-pr/SKILL.md",
+      "path": "docs/manual-test-scenarios.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 26,
+      "insertions": 14,
       "deletions": 0
     },
     {
-      "path": ".claude/skills/agent-review-update-review/SKILL.md",
+      "path": "docs/pilot-operations.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 23,
-      "deletions": 0
+      "insertions": 1,
+      "deletions": 1
     },
     {
-      "path": ".claude/skills/feature/SKILL.md",
+      "path": "docs/qa-checklist.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 22,
-      "deletions": 0
+      "insertions": 10,
+      "deletions": 1
     },
     {
-      "path": ".claude/skills/issue/SKILL.md",
+      "path": "docs/roles-and-permissions.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 23,
+      "insertions": 1,
       "deletions": 0
     },
     {
-      "path": ".claude/skills/retro/SKILL.md",
+      "path": "lib/decidim/contracts_sk.rb",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 21,
-      "deletions": 0
+      "language": "ruby",
+      "insertions": 2,
+      "deletions": 0,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "Error"
+      ]
     },
     {
-      "path": ".claude/skills/review/SKILL.md",
+      "path": "lib/decidim/contracts_sk/crz_deadline.rb",
       "kind": "modified",
-      "language": "markdown",
+      "language": "ruby",
+      "insertions": 8,
+      "deletions": 7,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "crz_deadline=",
+        "CrzDeadline",
+        "ThresholdError",
+        "deadline_for",
+        "days_left",
+        "threshold",
+        "status",
+        "tracked?"
+      ]
+    },
+    {
+      "path": "lib/decidim/contracts_sk/crz_import/filing_comparison.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 124,
+      "deletions": 0,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "CrzImport",
+        "FilingComparison",
+        "self",
+        "initialize",
+        "rows",
+        "all_match?",
+        "needs_reason?",
+        "reference_row"
+      ]
+    },
+    {
+      "path": "lib/decidim/contracts_sk/crz_import/filing_lookup.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 84,
+      "deletions": 0,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "CrzImport",
+        "FilingLookup",
+        "ok?",
+        "self",
+        "initialize",
+        "call",
+        "client",
+        "fetch"
+      ]
+    },
+    {
+      "path": "lib/decidim/contracts_sk/crz_import/mapper.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 42,
+      "deletions": 2,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "CrzImport",
+        "Mapper",
+        "Error",
+        "map",
+        "checksum",
+        "contract_attributes",
+        "title_from",
+        "reference_from"
+      ]
+    },
+    {
+      "path": "lib/decidim/contracts_sk/crz_import/sync.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 54,
+      "deletions": 24,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "CrzImport",
+        "Sync",
+        "run",
+        "import_one",
+        "initialize",
+        "run_cursor_pages",
+        "process_page",
+        "upsert_record!"
+      ]
+    },
+    {
+      "path": "lib/decidim/contracts_sk/crz_scope.rb",
+      "kind": "modified",
+      "language": "ruby",
       "insertions": 19,
-      "deletions": 0
+      "deletions": 0,
+      "symbols": [
+        "Decidim",
+        "ContractsSk",
+        "self",
+        "CrzScope",
+        "in_scope?"
+      ]
     },
     {
-      "path": ".claude/skills/verify/SKILL.md",
+      "path": "lib/tasks/decidim_contracts_sk_crz_import.rake",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 20,
-      "deletions": 0
+      "language": "unknown",
+      "insertions": 5,
+      "deletions": 1
     },
     {
-      "path": ".mcp.json",
+      "path": "lib/tasks/decidim_contracts_sk_seed_demo.rake",
       "kind": "modified",
-      "language": "json",
-      "insertions": 16,
-      "deletions": 0
+      "language": "unknown",
+      "insertions": 6,
+      "deletions": 1
     },
     {
-      "path": "AGENTS.md",
+      "path": "README.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 1,
-      "deletions": 0
+      "insertions": 2,
+      "deletions": 2
     },
     {
-      "path": "CLAUDE.md",
+      "path": "spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 25,
+      "language": "ruby",
+      "insertions": 121,
+      "deletions": 0,
+      "symbols": [
+        "migration_files",
+        "migration_path",
+        "migration_class_name",
+        "base_migration_path",
+        "table_name",
+        "stripped_lines",
+        "column_line",
+        "column_by_name"
+      ]
+    },
+    {
+      "path": "spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 5,
+      "deletions": 4,
+      "symbols": [
+        "migration_files",
+        "migration_path",
+        "migration_class_name",
+        "migration_path_for",
+        "table_name",
+        "stripped_lines",
+        "prerequisite_migrations!",
+        "column_by_name",
+        "sql_value",
+        "insert_contract"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk_crz_scope_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 19,
       "deletions": 0
-    }
-  ],
-  "logicalChanges": [
+    },
     {
-      "id": "31f58dca-257b-42df-b67e-cf78fb49b15a",
-      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
-      "recordedAt": "2026-10-02T22:26:44.812Z",
-      "entity": "Claude Code subagents",
-      "files": [
-        ".claude/agents/architect.md",
-        ".claude/agents/reviewer.md",
-        ".claude/agents/rails.md",
-        ".claude/agents/tester.md",
-        ".claude/agents/integration.md",
-        ".claude/agents/retro.md"
-      ],
-      "changeKind": "added",
-      "reason": "Port .opencode/agents to Claude Code subagents so both harnesses share the same roles",
-      "expectedBehavior": "architect/reviewer run on opus with read-only tools; rails/tester/integration/retro on sonnet; bodies identical to the OpenCode agents",
-      "risk": "low",
-      "alternatives": [
-        "Keep GLM-only OpenCode agents"
-      ],
-      "limitations": [
-        "The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md"
+      "path": "spec/decidim/contracts_sk_locales_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 79,
+      "deletions": 0,
+      "symbols": [
+        "LocaleContract",
+        "locale_file",
+        "translations",
+        "module_tree",
+        "leaf_paths",
+        "leaf_values",
+        "fresh_backend",
+        "PublicCatalogueLabels",
+        "CrzDeadlineLabels"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 4,
+      "deletions": 3,
+      "symbols": [
+        "Decidim",
+        "ContractsSk"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/admin/confirm_crz_filing_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 335,
+      "deletions": 0,
+      "symbols": [
+        "create_editorial",
+        "call_command",
+        "expect_untouched"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/admin/contracts_controller_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 6,
+      "deletions": 3,
+      "symbols": [
+        "Decidim",
+        "ContractsSk"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/contract_crz_deadline_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 7,
+      "deletions": 7,
+      "symbols": [
+        "create_contract!",
+        "references"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/crz_deadline_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 5,
+      "deletions": 6,
+      "symbols": [
+        "date",
+        "tracked?"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/crz_import/filing_comparison_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 158,
+      "deletions": 0,
+      "symbols": [
+        "crz_payload",
+        "record",
+        "contract",
+        "statuses",
+        "compare"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/crz_import/filing_lookup_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 88,
+      "deletions": 0,
+      "symbols": [
+        "lookup"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/crz_import/mapper_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 42,
+      "deletions": 0,
+      "symbols": [
+        "crz_payload"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/crz_import/sync_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 92,
+      "deletions": 0,
+      "symbols": [
+        "page",
+        "run_sync"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 83,
+      "deletions": 2,
+      "symbols": [
+        "call_command",
+        "expect_linked_without_writes"
+      ]
+    },
+    {
+      "path": "spec/decidim/contracts_sk/engine_routing_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 48,
+      "deletions": 8,
+      "symbols": [
+        "EngineRoutingContract",
+        "route_triples",
+        "public_routes",
+        "admin_routes",
+        "party_routes",
+        "document_routes",
+        "amendment_routes",
+        "link_routes",
+        "audit_event_routes",
+        "controllers_of"
       ]
     },
     {
-      "id": "52236dd7-6925-41b6-9df3-c8d3c80bd018",
-      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
-      "recordedAt": "2026-10-02T22:26:44.912Z",
-      "entity": "Claude Code slash-command skills",
+      "path": "spec/decidim/contracts_sk/permissions_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 63,
+      "deletions": 0,
+      "symbols": [
+        "admin?",
+        "admin_terms_accepted?",
+        "action_for",
+        "unset?",
+        "resolver_of",
+        "swap_resolver",
+        "user_with_roles",
+        "filing_user_with_roles",
+        "filing_action",
+        "redaction_user_with_roles"
+      ]
+    },
+    {
+      "path": "spec/requests/admin/audit_events_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 15,
+      "deletions": 0,
+      "symbols": [
+        "sign_in",
+        "create_contract!",
+        "create_event!"
+      ]
+    },
+    {
+      "path": "spec/requests/admin/contracts_crz_deadline_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 8,
+      "deletions": 7,
+      "symbols": [
+        "create_contract!",
+        "references_in",
+        "with_slovak",
+        "seed_deadline_set!"
+      ]
+    },
+    {
+      "path": "spec/requests/admin/contracts_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 10,
+      "deletions": 0,
+      "symbols": [
+        "RecordingIndexScope",
+        "initialize",
+        "where",
+        "not",
+        "order",
+        "group",
+        "count",
+        "crz_overdue",
+        "crz_due_soon",
+        "CountingView"
+      ]
+    },
+    {
+      "path": "spec/requests/admin/crz_filing_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 303,
+      "deletions": 0,
+      "symbols": [
+        "sign_in_as"
+      ]
+    },
+    {
+      "path": "spec/requests/admin/crz_import_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 20,
+      "deletions": 0,
+      "symbols": [
+        "sign_in",
+        "stub_transport",
+        "response_with"
+      ]
+    },
+    {
+      "path": "spec/requests/contracts_spec.rb",
+      "kind": "modified",
+      "language": "ruby",
+      "insertions": 41,
+      "deletions": 0,
+      "symbols": [
+        "PublishedContractFixture",
+        "PaginableStub",
+        "initialize",
+        "page",
+        "per",
+        "each",
+        "any?",
+        "current_page",
+        "prev_page",
+        "next_page"
+      ]
+    }
+  ],
+  "logicalChanges": [
+    {
+      "id": "1a77f7ce-a784-4832-9c60-3e9c8df9cb4c",
+      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+      "recordedAt": "2026-10-03T17:06:39.454Z",
+      "entity": "CRZ filing columns migration",
       "files": [
-        ".claude/skills/issue/SKILL.md",
-        ".claude/skills/feature/SKILL.md",
-        ".claude/skills/review/SKILL.md",
-        ".claude/skills/verify/SKILL.md",
-        ".claude/skills/retro/SKILL.md",
-        ".claude/skills/agent-review-github-status/SKILL.md",
-        ".claude/skills/agent-review-prepare-pr/SKILL.md",
-        ".claude/skills/agent-review-publish-pr/SKILL.md",
-        ".claude/skills/agent-review-update-review/SKILL.md"
+        "db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb",
+        "spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb"
       ],
       "changeKind": "added",
-      "reason": "Port the 9 .opencode/commands to Claude Code skills invoked as /<name>",
-      "expectedBehavior": "/issue reads civora-org/civora-platform issues via gh; publish-pr, update-review and retro are user-invoked only (disable-model-invocation)",
+      "reason": "civora-platform#125: store the verified CRZ filing confirmation (filed_at, published_on, override reason) as nullable system columns.",
+      "expectedBehavior": "Additive reversible migration, no backfill, no defaults/indexes.",
       "risk": "low",
       "alternatives": [],
       "limitations": []
     },
     {
-      "id": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
-      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
-      "recordedAt": "2026-10-02T22:26:45.009Z",
-      "entity": "agent-review skill, MCP servers and journaling hook",
+      "id": "77e75c1a-89f9-4f75-8b46-230e9df03f7f",
+      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+      "recordedAt": "2026-10-03T17:06:42.120Z",
+      "entity": "Admin::ConfirmCrzFiling command, FilingLookup, FilingComparison, Mapper/CrzScope extensions",
       "files": [
-        ".claude/skills/agent-review",
-        ".mcp.json",
-        ".claude/settings.json"
+        "app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb",
+        "lib/decidim/contracts_sk/crz_import/filing_lookup.rb",
+        "lib/decidim/contracts_sk/crz_import/filing_comparison.rb",
+        "lib/decidim/contracts_sk/crz_import/mapper.rb",
+        "lib/decidim/contracts_sk/crz_scope.rb"
       ],
       "changeKind": "added",
-      "reason": "Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers",
-      "expectedBehavior": "Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active",
+      "reason": "Verify a hand-filed editorial contract against the official CRZ record and stamp the filing under the row lock, with mirror absorption.",
+      "expectedBehavior": "Fetch outside lock; in-lock re-check of source/state/filed/checksum/comparison/reason/id; one transaction with audit row; refusals broadcast as symbols.",
       "risk": "medium",
-      "alternatives": [],
-      "limitations": [
-        "Absolute machine paths in .mcp.json (same as opencode.jsonc)",
-        "Hook assumes agent-review is a sibling checkout",
-        "Skill is a symlink into ../agent-review"
+      "alternatives": [
+        "Audit absorbed-mirror row targeting the destroyed mirror (rejected: dangling target)"
       ],
-      "evidence": "agent-review npm test: 70/70 pass incl. MCP listTools + hook mapping; stdio smoke call agent_review_status returned status inactive"
+      "limitations": []
     },
     {
-      "id": "6c1abf82-4513-47c1-a072-4edf4f90e454",
-      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
-      "recordedAt": "2026-10-02T22:26:45.110Z",
-      "entity": "Claude Code permissions",
+      "id": "4b9e4cab-db76-4056-931b-84626813c29e",
+      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+      "recordedAt": "2026-10-03T17:06:44.428Z",
+      "entity": "Sync linked rule, G4 fix, deadline hard switch",
       "files": [
-        ".claude/settings.json"
+        "app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb",
+        "lib/decidim/contracts_sk/crz_import/sync.rb",
+        "lib/decidim/contracts_sk/crz_deadline.rb",
+        "app/models/decidim/contracts_sk/contract.rb",
+        "lib/tasks/decidim_contracts_sk_crz_import.rake"
       ],
-      "changeKind": "added",
-      "reason": "Mirror opencode.jsonc permissions",
-      "expectedBehavior": "git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied",
-      "risk": "low",
+      "changeKind": "modified",
+      "reason": "A filing-confirmed editorial record is the canonical linked record of its CRZ id; sync must not duplicate or flag it. Failure stamps must never touch editorial rows. Deadline tracking keys on crz_filed_at.",
+      "expectedBehavior": ":linked outcome with zero writes at all decision points; linked counters; find_mirror/mark_failed scoped to source crz; tracked? uses crz_filed_at.",
+      "risk": "medium",
       "alternatives": [],
-      "limitations": [
-        "edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates"
-      ]
+      "limitations": []
     },
     {
-      "id": "e272f979-badc-4ead-b674-6708421f71f1",
-      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
-      "recordedAt": "2026-10-02T22:26:45.213Z",
-      "entity": "CLAUDE.md and AGENTS.md pointer",
+      "id": "6009392a-aba6-4c87-a7d8-a9ba633d95e4",
+      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+      "recordedAt": "2026-10-03T17:06:46.615Z",
+      "entity": "Admin filing UI, permission, routes, public detail, locales, audit labels, docs",
       "files": [
-        "CLAUDE.md",
-        "AGENTS.md"
+        "app/controllers/decidim/contracts_sk/admin/contracts_controller.rb",
+        "app/permissions/decidim/contracts_sk/permissions.rb",
+        "config/routes.rb",
+        "app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb",
+        "app/views/decidim/contracts_sk/contracts/show.html.erb",
+        "config/locales/en.yml",
+        "config/locales/sk.yml",
+        "docs/crz-import.md"
       ],
       "changeKind": "added",
-      "reason": "Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router",
-      "expectedBehavior": "CLAUDE.md imports @AGENTS.md; AGENTS.md lists the Claude Code mirror to keep in sync",
+      "reason": "Editor-facing round trip: preview comparison page, confirm POST, index entry link, public CRZ publication line.",
+      "expectedBehavior": "GET preview writes nothing; POST runs the command; en/sk parity; editor-only permission on published unfiled editorial records.",
       "risk": "low",
       "alternatives": [],
       "limitations": []
@@ -306,63 +751,32 @@
   ],
   "tests": [
     {
-      "command": "bundle exec rspec",
-      "startedAt": "2026-10-02T22:26:52.256Z",
-      "finishedAt": "2026-10-02T22:26:55.393Z",
-      "durationMs": 3133,
+      "command": "bundle exec rubocop",
+      "startedAt": "2026-10-03T17:06:47.256Z",
+      "finishedAt": "2026-10-03T17:06:48.870Z",
+      "durationMs": 1613,
       "exitCode": 0,
       "status": "passed",
-      "stdoutSummary": "Run options: exclude {:db=>true}\n\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_redaction_confirmation_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds only the redaction_confirmed_at column, as a plain nullable datetime\n    attaches no default and no backfill (a fabricated stamp would defeat the gate)\n    adds no index (the stamp is read per-record, never queried as a set)\n\ndb/migrate/*_add_review_decision_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the review_reason and reviewed_at columns\n    adds review_reason as a plain nullable string capped at 1000 characters\n    adds reviewed_at as a plain nullable datetime\n    attaches no default and no backfill (a fabricated judgment would defeat the gate)\n    adds no index (the decision is read per-record, never queried as a set)\n\ndb/migrate/*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  index\n    uniquely indexes (organization, source_id) under the explicit unique name\n    keeps the index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_create_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes version a NOT NULL integer\n    makes summary a NOT NULL string\n  indexes\n    uniquely indexes (contract_id, version) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_audit_events.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant reference NOT NULL with a real FK to the organizations table\n    makes the actor reference NOT NULL with a real FK to the users table\n    makes the target a NOT NULL polymorphic reference\n    makes action a NOT NULL string\n  indexes\n    indexes every reference and created_at under explicit names\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contract_links.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes the target a NOT NULL polymorphic reference with no index of its own\n  indexes\n    uniquely indexes (contract_id, target_type, target_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant and author references NOT NULL\n    makes title and reference NOT NULL strings\n    pins state as NOT NULL defaulting to draft\n    pins source as NOT NULL defaulting to editorial\n    keeps the provenance columns nullable\n  indexes\n    indexes the organization reference under an explicit name\n    indexes the author reference\n    uniquely indexes (organization, reference) under an explicit name\n    indexes (organization, state) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_documents.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL with a real FK to the contracts table\n    makes title NOT NULL\n    pins kind as NOT NULL defaulting to contract\n    keeps the file metadata columns nullable\n  indexes\n    indexes the contract reference under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_parties.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes role and name NOT NULL strings\n    keeps ico as a nullable string with the 8-character limit\n    keeps address nullable\n  indexes\n    compositely indexes (contract_id, role) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\nDecidim::ContractsSk::Admin::AmendmentForm\n  accepts a complete amendment form\n  rejects a blank summary\n  rejects a missing summary\n  caps the summary at 255 characters\n\nDecidim::ContractsSk::Admin::AuditEventsController\n  inherits from the engine's admin base controller\n  implements exactly the index action (read-only viewer)\n  does not sit on the engine's public base controller chain\n  pins the audit action vocabulary actually written by the commands\n  derives the six lifecycle-action keys from the transition table, never hand-enumerated\n\nDecidim::ContractsSk::Admin::ContractForm\n  accepts dotted decimal strings\n  accepts proper numerics without the string guard (spec/API compatibility)\n  accepts the decimal(12,2) ceiling itself\n  accepts a nil amount (the value may be unknown while drafting)\n  rejects non-numeric strings instead of letting the cast zero them\n  rejects comma decimals (the Slovak '12,50' habit, caught deliberately)\n  rejects scientific notation (the format guard stays strict)\n  rejects negative amounts\n  rejects amounts beyond the decimal(12,2) column's ceiling\n  rejects over-ceiling strings too (raw input, same cap)\n\nDecidim::ContractsSk::Admin::ContractsController\n  inherits from the engine's admin base controller\n  implements exactly the CRUD + transition + CRZ-handoff + import + redaction actions (no show, no destroy)\n  does not sit on the engine's public base controller chain\n\nDecidim::ContractsSk::Admin::DocumentForm\n  accepts a complete form\n  defaults the kind to the model's column default\n  accepts every kind of the form's editor vocabulary\n  narrows the mod",
-      "stderrSummary": "",
+      "stdoutSummary": "Inspecting 174 files\n..............................................................................................................................................................................\n\n174 files inspected, no offenses detected\n",
+      "stderrSummary": "The following cops were added to RuboCop, but are not configured. Please set Enabled to either `true` or `false` in your `.rubocop.yml` file.\n\nPlease also note that you can opt-in to new cops by default by adding this to your config:\n  AllCops:\n    NewCops: enable\nGemspec/AddRuntimeDependency: # new in 1.65\n  Enabled: true\nGemspec/AttributeAssignment: # new in 1.77\n  Enabled: true\nGemspec/DeprecatedAttributeAssignment: # new in 1.30\n  Enabled: true\nGemspec/DevelopmentDependencies: # new in 1.44\n  Enabled: true\nGemspec/RequireMFA: # new in 1.23\n  Enabled: true\nLayout/EmptyLinesAfterModuleInclusion: # new in 1.79\n  Enabled: true\nLayout/LineContinuationLeadingSpace: # new in 1.31\n  Enabled: true\nLayout/LineContinuationSpacing: # new in 1.31\n  Enabled: true\nLayout/LineEndStringConcatenationIndentation: # new in 1.18\n  Enabled: true\nLayout/SpaceBeforeBrackets: # new in 1.7\n  Enabled: true\nLint/AmbiguousAssignment: # new in 1.7\n  Enabled: true\nLint/AmbiguousOperatorPrecedence: # new in 1.21\n  Enabled: true\nLint/AmbiguousRange: # new in 1.19\n  Enabled: true\nLint/ArgumentMismatch: # new in 1.90\n  Enabled: true\nLint/ArrayLiteralInRegexp: # new in 1.71\n  Enabled: true\nLint/ConstantOverwrittenInRescue: # new in 1.31\n  Enabled: true\nLint/ConstantReassignment: # new in 1.70\n  Enabled: true\nLint/DataDefineOverride: # new in 1.85\n  Enabled: true\nLint/DeprecatedConstants: # new in 1.8\n  Enabled: true\nLint/DeprecatedReference: # new in 1.89\n  Enabled: true\nLint/DuplicateBranch: # new in 1.3\n  Enabled: true\nLint/DuplicateMagicComment: # new in 1.37\n  Enabled: true\nLint/DuplicateMatchPattern: # new in 1.50\n  Enabled: true\nLint/DuplicateRegexpCharacterClassElement: # new in 1.1\n  Enabled: true\nLint/DuplicateSetElement: # new in 1.67\n  Enabled: true\nLint/EmptyBlock: # new in 1.1\n  Enabled: true\nLint/EmptyClass: # new in 1.3\n  Enabled: true\nLint/EmptyInPattern: # new in 1.16\n  Enabled: true\nLint/HashNewWithKeywordArgumentsAsDefault: # new in 1.69\n  Enabled: true\nLint/IncompatibleIoSelectWithFiberScheduler: # new in 1.21\n  Enabled: true\nLint/ItWithoutArgumentsInBlock: # new in 1.59\n  Enabled: true\nLint/LambdaWithoutLiteralBlock: # new in 1.8\n  Enabled: true\nLint/LiteralAssignmentInCondition: # new in 1.58\n  Enabled: true\nLint/MisplacedMagicComment: # new in 1.91\n  Enabled: true\nLint/MixedCaseRange: # new in 1.53\n  Enabled: true\nLint/NameTypo: # new in 1.89\n  Enabled: true\nLint/NoReturnInBeginEndBlocks: # new in 1.2\n  Enabled: true\nLint/NonAtomicFileOperation: # new in 1.31\n  Enabled: true\nLint/NumberedParameterAssignment: # new in 1.9\n  Enabled: true\nLint/NumericOperationWithConstantResult: # new in 1.69\n  Enabled: true\nLint/OrAssignmentToConstant: # new in 1.9\n  Enabled: true\nLint/RedundantDirGlobSort: # new in 1.8\n  Enabled: true\nLint/RedundantRegexpQuantifiers: # new in 1.53\n  Enabled: true\nLint/RedundantTypeConversion: # new in 1.72\n  Enabled: true\nLint/RefinementImportMethods: # new in 1.27\n  Enabled: true\nLint/RequireRangeParentheses: # new in 1.32\n  Enabled: true\nLint/RequireRelativeSelfPath: # new in 1.22\n  Enabled: true\nLint/SharedMutableDefault: # new in 1.70\n  Enabled: true\nLint/SuperArgumentMismatch: # new in 1.90\n  Enabled: true\nLint/SuppressedExceptionInNumberConversion: # new in 1.72\n  Enabled: true\nLint/SymbolConversion: # new in 1.9\n  Enabled: true\nLint/ToEnumArguments: # new in 1.1\n  Enabled: true\nLint/TripleQuotes: # new in 1.9\n  Enabled: true\nLint/UnescapedBracketInRegexp: # new in 1.68\n  Enabled: true\nLint/UnexpectedBlockArity: # new in 1.5\n  Enabled: true\nLint/UnmodifiedReduceAccumulator: # new in 1.1\n  Enabled: true\nLint/UnreachablePatternBranch: # new in 1.85\n  Enabled: true\nLint/UselessConstantScoping: # new in 1.72\n  Enabled: true\nLint/UselessDefaultValueArgument: # new in 1.76\n  Enabled: true\nLint/UselessDefined: # new in 1.69\n  Enabled: true\nLint/UselessNumericOperation: # new in 1.66\n  Enabled: true\nLint/UselessOr: # new in 1.76\n  Enabled: true\nLint/UselessRescue: # new in 1.43\n  Enabled: true\nLint/UselessRuby2Keywords: # new in 1.23\n  Enabled: true\nMetrics/CollectionLiteralLength: # new in 1.47\n  Enabled: true\nNaming/BlockForwarding: # new in 1.24\n  Enabled: true\nNaming/PredicateMethod: # new in 1.76\n  Enabled: true\nSecurity/CompoundHash: # new in 1.28\n  Enabled: true\nSecurity/IoMethods: # new in 1.22\n  Enabled: true\nStyle/AmbiguousEndlessMethodDefinition: # new in 1.68\n  Enabled: true\nStyle/ArgumentsForwarding: # new in 1.1\n  Enabled: true\nStyle/ArrayIntersect: # new in 1.40\n  Enabled: true\nStyle/ArrayIntersectWithSingleElement: # new in 1.81\n  Enabled: true\nStyle/BitwisePredicate: # new in 1.68\n  Enabled: true\nStyle/CollectionCompact: # new in 1.2\n  Enabled: true\nStyle/CollectionQuerying: # new in 1.77\n  Enabled: true\nStyle/CombinableDefined: # new in 1.68\n  Enabled: true\nStyle/ComparableBetween: # new in 1.74\n  Enabled: true\nStyle/ComparableClamp: # new in 1.44\n  Enabled: true\nStyle/ConcatArrayLiterals: # new in 1.41\n  Enabled: true\nStyle/DataInheritance: # new in 1.49\n  Enabled: true\nStyle/DigChain: # new in 1.69\n  Enabled: true\nStyle/DirEmpty: # new in 1.48\n  Enabled: true\nStyle/DirectiveScope: # new in 1.90\n  Enabled: true\nStyle/DocumentDynamicEvalDefinition: # new in 1.1\n  Enabled: true\nStyle/EmptyClassDefinition: # new in 1.84\n  Enabled: true\nStyle/EmptyHeredoc: # new in 1.32\n  Enabled: true\nStyle/EmptyStringInsideInterpolation: # new in 1.76\n  Enabled: true\nStyle/EndlessMethod: # new in 1.8\n  Enabled: true\nStyle/EnvHome: # new in 1.29\n  Enabled: true\nStyle/ExactRegexpMatch: # new in 1.51\n  Enabled: true\nStyle/FetchEnvVar: # new in 1.28\n  Enabled: true\nStyle/FileEmpty: # new in 1.48\n  Enabled: true\nStyle/FileNull: # new in 1.69\n  Enabled: true\nStyle/FileOpen: # new in 1.85\n  Enabled: true\nStyle/FileRead: # new in 1.24\n  Enabled: true\nStyle/FileTouch: # new in 1.69\n  Enabled: true\nStyle/FileWrite: # new in 1.24\n  Enabled: true\nStyle/HashConversion: # new in 1.10\n  Enabled: true\nStyle/HashExcept: # new in 1.7\n  Enabled: true\nStyle/HashFetchChain: # new in 1.75\n  Enabled: true\nStyle/HashSlice: # new in 1.71\n  Enabled: true\nStyle/IfWithBooleanLiteralBranches: # new in 1.9\n  Enabled: true\nStyle/InPatternThen: # new in 1.16\n  Enabled: true\nStyle/ItAssignment: # new in 1.70\n  Enabled: true\nStyle/ItBlockParameter: # new in 1.75\n  Enabled: true\nStyle/KeywordArgumentsMerging: # new in 1.68\n  Enabled: true\nStyle/MagicCommentFormat: # new in 1.35\n  Enabled: true\nStyle/MapCompactWithConditionalBlock: # new in 1.30\n  Enabled: true\nStyle/MapIntoArray: # new in 1.63\n  Enabled: true\nStyle/MapJoin: # new in 1.85\n  Enabled: true\nStyle/MapToHash: # new in 1.24\n  Enabled: true\nStyle/MapToSet: # new in 1.42\n  Enabled: true\nStyle/MinMaxComparison: # new in 1.42\n  Enabled: true\nStyle/ModuleMemberExistenceCheck: # new in 1.82\n  Enabled: true\nStyle/MultilineInPatternThen: # new in 1.16\n  Enabled: true\nStyle/NegatedIfElseCondition: # new in 1.2\n  Enabled: true\nStyle/NegativeArrayIndex: # new in 1.84\n  Enabled: true\nStyle/NestedFileDirname: # new in 1.26\n  Enabled: true\nStyle/NilLambda: # new in 1.3\n  Enabled: true\nStyle/NumberedParameters: # new in 1.22\n  Enabled: true\nStyle/NumberedParametersLimit: # new in 1.22\n  Enabled: true\nStyle/ObjectThen: # new in 1.28\n  Enabled: true\nStyle/OneClassPerFile: # new in 1.85\n  Enabled: true\nStyle/OpenStructUse: # new in 1.23\n  Enabled: true\nStyle/OperatorMethodCall: # new in 1.37\n  Enabled: true\nStyle/PartitionInsteadOfDoubleSelect: # new in 1.85\n  Enabled: true\nStyle/PredicateWithKind: # new in 1.85\n  Enabled: true\nStyle/QuotedSymbols: # new in 1.16\n  Enabled: true\nStyle/ReduceToHash: # new in 1.85\n  Enabled: true\nStyle/RedundantArgument: # new in 1.4\n  Enabled: true\nStyle/RedundantArrayConstructor: # new in 1.52\n  Enabled: true\nStyle/RedundantArrayFlatten: # new in 1.76\n  Enabled: true\nStyle/RedundantConstantBase: # new in 1.40\n  Enabled: true\nStyle/RedundantCurrentDirectoryInPath: # new in 1.53\n  Enabled: true\nStyle/RedundantDoubleSplatHashBraces: # new in 1.41\n  Enabled: true\nStyle/RedundantEach: # new in 1.38\n  Enabled: true\nStyle/RedundantFilterChain: # new in 1.52\n  Enabled: true\nStyle/RedundantFormat: # new in 1.72\n  Enabled: true\nStyle/RedundantHeredocDelimiterQuotes: # new in 1.45\n  Enabled: true\nStyle/RedundantInitialize: # new in 1.27\n  Enabled: true\nStyle/RedundantInterpolationUnfreeze: # new in 1.66\n  Enabled: true\nStyle/RedundantLineContinuation: # new in 1.49\n  Enabled: true\nStyle/RedundantMinMaxBy: # new in 1.85\n  Enabled: true\nStyle/RedundantRegexpArgument: # new in 1.53\n  Enabled: true\nStyle/RedundantRegexpConstructor: # new in 1.52\n  Enabled: true\nStyle/RedundantSelfAssignmentBranch: # new in 1.19\n  Enabled: true\nStyle/RedundantStringEscape: # new in 1.37\n  Enabled: true\nStyle/ReturnNilInPredicateMethodDefinition: # new in 1.53\n  Enabled: true\nStyle/ReverseFind: # new in 1.84\n  Enabled: true\nStyle/SafeNavigationChainLength: # new in 1.68\n  Enabled: true\nStyle/SelectByKind: # new in 1.85\n  Enabled: true\nStyle/SelectByRange: # new in 1.85\n  Enabled: true\nStyle/SelectByRegexp: # new in 1.22\n  Enabled: true\nStyle/SendWithLiteralMethodName: # new in 1.64\n  Enabled: true\nStyle/SingleLineDoEndBlock: # new in 1.57\n  Enabled: true\nStyle/StringChars: # new in 1.12\n  Enabled: true\nStyle/SuperArguments: # new in 1.64\n  Enabled: true\nStyle/SuperWithArgsParentheses: # new in 1.58\n  Enabled: true\nStyle/SwapValues: # new in 1.1\n  Enabled: true\nStyle/TallyMethod: # new in 1.85\n  Enabled: true\nStyle/TimeNow: # new in 1.90\n  Enabled: true\nStyle/YAMLFileRead: # new in 1.53\n  Enabled: true\nRSpec/DiscardedMatcher: # new in 3.10\n  Enabled: true\nRSpec/IncludeExamples: # new in 3.6\n  Enabled: true\nRSpec/LeakyLocalVariable: # new in 3.8\n  Enabled: true\nRSpec/MatchWithSimpleRegex: # new in 3.10\n  Enabled: true\nRSpec/Output: # new in 3.9\n  Enabled: true\nFor more information: https://docs.rubocop.org/rubocop/versioning.html\n",
       "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
       "commandTruncated": false
     }
   ],
   "risks": [
-    "Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.",
-    "Large diff: 4919 insertions across 26 files."
+    "Large diff: 2757 insertions across 52 files."
   ],
   "limitations": [
     "Snapshots cover only files that were changed at checkpoint time.",
     "Symbol extraction is regex-based, not AST-based.",
-    "Only observed facts are recorded — private model reasoning is not captured.",
-    "The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md",
-    "Absolute machine paths in .mcp.json (same as opencode.jsonc)",
-    "Hook assumes agent-review is a sibling checkout",
-    "Skill is a symlink into ../agent-review",
-    "edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates"
+    "Only observed facts are recorded — private model reasoning is not captured."
   ],
   "agentMetadata": {
     "toolCalls": 0,
     "commands": 0,
     "checkpoints": 1,
     "tests": 1,
-    "events": 3816
+    "events": 3951
   },
-  "generatedAt": "2026-10-02T22:28:12.683Z",
-  "github": {
-    "repository": null,
-    "baseBranch": "main",
-    "headBranch": "chore/claude-code-config",
-    "pullRequestNumber": null,
-    "pullRequestUrl": null,
-    "headCommit": "5a3f5102c111c56ea154eb5878727e15e45169e1",
-    "status": "preview_ready",
-    "inlineComments": [
-      {
-        "logicalChangeId": "6c1abf82-4513-47c1-a072-4edf4f90e454",
-        "path": ".claude/settings.json",
-        "line": 1,
-        "side": "RIGHT",
-        "status": "preview"
-      },
-      {
-        "logicalChangeId": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
-        "path": ".claude/skills/agent-review",
-        "line": 1,
-        "side": "RIGHT",
-        "status": "preview"
-      }
-    ]
-  }
+  "generatedAt": "2026-10-03T17:29:00.669Z"
 }
diff --git a/README.md b/README.md
index 15bc2dd..42bcb82 100644
--- a/README.md
+++ b/README.md
@@ -51,7 +51,7 @@ bin/rails decidim_contracts_sk:install:migrations
 bin/rails db:migrate
 ```
 
-The engine ships its tables as migrations (contracts, parties, documents, amendments, audit events, contract links; later additive migrations extend the contracts table, e.g. the submitter stamp behind the four-eyes rule); `install:migrations` copies them into the host. It re-stamps their timestamps, which is fine for a new host. A host that already ran the engine migrations under their original timestamps should keep copying new ones verbatim instead — the reference host documents that procedure in its README ("Upgrading the engine"). The host owns the ActiveStorage schema (see *Known limitations*).
+The engine ships its tables as migrations (contracts, parties, documents, amendments, audit events, contract links; later additive migrations extend the contracts table, e.g. the submitter stamp behind the four-eyes rule and the CRZ filing confirmation columns `crz_filed_at`/`crz_published_on`/`crz_filing_reason`); `install:migrations` copies them into the host. It re-stamps their timestamps, which is fine for a new host. A host that already ran the engine migrations under their original timestamps should keep copying new ones verbatim instead — the reference host documents that procedure in its README ("Upgrading the engine"). The host owns the ActiveStorage schema (see *Known limitations*).
 
 Mount the engine in your app's `config/routes.rb` (mount point is your choice; the reference host uses `/contracts`):
 
@@ -69,7 +69,7 @@ With the engine mounted at `/zmluvy`:
 
 - **Public catalogue** — `GET /zmluvy` (list, with a `q` free-text filter and pagination) and `GET /zmluvy/:id` (detail). Published records of the current organization only — no authentication required; anything else (draft, in-review, rejected, archived, another organization's, nonexistent) is an indistinguishable 404. The list paginates at 25 records per page. The detail page also renders the public version history: the live fields are the current version, above the published amendments' frozen content snapshots (newest first, published-only — drafts are never publicly visible) (civora-org/civora-platform#65). When the record carries project/result links, a "Links" section renders them (labelled and URL'd live through the [link target resolver](#configuration)); dangling or unresolvable targets are hidden, and the section disappears entirely when nothing renderable remains (civora-org/civora-platform#87).
 - **Provenance and freshness for CRZ mirrors** — records mirrored from the CRZ register (`source: "crz"`) are labelled externally confirmed, never presented as a legal publication (ADR-002 rule 1, ADR-008 decisions 4/6): the catalogue list shows the "Externally confirmed" badge with the mirror date on each imported record's card, and the detail page adds a provenance block with the badge, the mirror date and the preserved attribution note (data via ekosystem.slovensko.digital; informational only; the canonical record lives at crz.gov.sk). When a mirror is stale, the detail page additionally warns readers to verify the canonical record: a mirror counts as stale when its `imported_at` is older than `Decidim::ContractsSk.stale_after` (default 48 h — twice the recommended nightly sync cadence), when its last import was stamped `failed`, or when it carries no import timestamp at all (freshness cannot be proven). The stale indicator is detail-only; cards stay lean (civora-org/civora-platform#88).
-- **Admin** — `/zmluvy/admin/contracts` (list, create and edit contract records and drive lifecycle transitions — one POST action per event; sign-in plus an engine role required, each transition gated to the role that owns its edge in the [lifecycle table](docs/contract-lifecycle.md): `editor` for submit/publish/archive, `reviewer` for return/approve/reject, and the person who last submitted a record can never return, approve or reject it themselves (four-eyes rule, civora-org/civora-platform#123, [docs/roles-and-permissions.md](docs/roles-and-permissions.md)); `update` only while the record's lifecycle state is editable; publish additionally requires the record's privacy-redaction confirmation, below). The reviewer `return`/`reject` decisions carry a mandatory decision reason (up to 1000 characters) through an inline form on the index row — the reason and its timestamp render as a "Reviewer decision" banner on the record's edit page until resubmission clears them, and any other transition refuses a passed reason (civora-org/civora-platform#90). The index paginates at 25 records per page and filters by lifecycle state, provenance source (`crz` import vs. `editorial`) and a case-insensitive title/reference search — GET params preserved across page links, unknown values falling back to the defaults (civora-org/civora-platform#86b). The index header also renders per-state counter chips — one grouped query over the unfiltered tenant scope, so the counts are honest navigation that ignore the active filter, each chip linking to its `state=` filter while preserving the others — and a distinct no-matches empty state with a clear-filters link when active filters return zero rows (civora-org/civora-platform#93). It also tracks the CRZ publication deadline (§ 47a OZ, civora-org/civora-platform#124): every editorial record not yet recorded as filed in CRZ (`crz_url` empty, a proxy until real filing confirmation lands) gets a deadline badge in the index (overdue / days left, `signed_on` + 3 months, computed never stored), a `deadline` filter (due within 14 days / overdue) and two counters next to the state chips, and the edit page shows the deadline line (or "deadline unknown — add signing date") — an aid, not legal advice; see [docs/contract-lifecycle.md](docs/contract-lifecycle.md#crz-publication-deadline-124). Each contract also has a nested party manager at `/zmluvy/admin/contracts/:contract_id/parties` — add/edit/remove the object/contractor parties, `editor`-gated and available only while the record's lifecycle state is editable. The contract edit page also hosts the document manager — attach/replace/remove files, `editor`-gated on an editable-state contract (civora-org/civora-platform#73) — and the CRZ handoff export: generate/regenerate the PDF aid (`editor`-gated on an editable-state contract) and download it (`editor`-gated on any lifecycle state); the PDF is labelled a handoff aid for the clerical CRZ record, never a legal publication (civora-org/civora-platform#74). Each contract also has a nested amendment manager at `/zmluvy/admin/contracts/:contract_id/amendments` — draft version-history entries published by one explicit POST per event: create is `editor`-gated on a published contract; update/destroy/publish are `editor`-gated on a draft amendment (publish additionally requires the contract still published); published amendments are immutable (civora-org/civora-platform#65). The contract edit page also hosts the project/result link manager — add/remove links to platform-level entities (`editor`-gated on an editable-state contract; create/destroy only — links have no editable content), with an explicit flag next to links whose target no longer resolves so editors can clean them up (civora-org/civora-platform#87). The contract edit page also hosts the privacy-redaction confirmation gate (ADR-007, civora-org/civora-platform#91): before the record may be published, an editor must confirm the localized redaction checklist — personal names/addresses of natural persons, bank/account details, amounts tying the contract to identifiable persons, sensitive content inside attached documents — through one required-checkbox POST whose affirmation value is consumed server-side (`POST /zmluvy/admin/contracts/:contract_id/confirm_redaction`, `editor`-gated on a confirmable contract — the editable states plus `approved`, so a reviewer-approved record can still be stamped right before publish; the publish transition refuses while the stamp is missing, and amendment publication backstops on the same stamp for editorial records — CRZ mirrors are exempt, their content being already-public upstream data per ADR-008). Once confirmed, the edit page shows the confirmation stamp line instead of the checkbox form. The contract edit page also links to the read-only audit trail — `/zmluvy/admin/audit_events` (civora-org/civora-platform#92), a paginated, newest-first listing of the organization's append-only audit events (lifecycle transitions, the privacy-redaction confirmation, amendment publications and CRZ-import actions), optionally filtered to one contract through `?contract_id=<id>`; every engine role may consult it, each row shows the localized action, the target record (dangling targets render a "record no longer exists" label — the trail outlives what it observed), the acting user and the date and time, plus the reviewer decision reason for records sitting in a decision state.
+- **Admin** — `/zmluvy/admin/contracts` (list, create and edit contract records and drive lifecycle transitions — one POST action per event; sign-in plus an engine role required, each transition gated to the role that owns its edge in the [lifecycle table](docs/contract-lifecycle.md): `editor` for submit/publish/archive, `reviewer` for return/approve/reject, and the person who last submitted a record can never return, approve or reject it themselves (four-eyes rule, civora-org/civora-platform#123, [docs/roles-and-permissions.md](docs/roles-and-permissions.md)); `update` only while the record's lifecycle state is editable; publish additionally requires the record's privacy-redaction confirmation, below). The reviewer `return`/`reject` decisions carry a mandatory decision reason (up to 1000 characters) through an inline form on the index row — the reason and its timestamp render as a "Reviewer decision" banner on the record's edit page until resubmission clears them, and any other transition refuses a passed reason (civora-org/civora-platform#90). The index paginates at 25 records per page and filters by lifecycle state, provenance source (`crz` import vs. `editorial`) and a case-insensitive title/reference search — GET params preserved across page links, unknown values falling back to the defaults (civora-org/civora-platform#86b). The index header also renders per-state counter chips — one grouped query over the unfiltered tenant scope, so the counts are honest navigation that ignore the active filter, each chip linking to its `state=` filter while preserving the others — and a distinct no-matches empty state with a clear-filters link when active filters return zero rows (civora-org/civora-platform#93). It also tracks the CRZ publication deadline (§ 47a OZ, civora-org/civora-platform#124): every editorial record not yet confirmed as filed in CRZ (`crz_filed_at` empty — the verified filing confirmation of civora-org/civora-platform#125, replacing the interim `crz_url` proxy; nothing is backfilled) gets a deadline badge in the index (overdue / days left, `signed_on` + 3 months, computed never stored), a `deadline` filter (due within 14 days / overdue) and two counters next to the state chips, and the edit page shows the deadline line (or "deadline unknown — add signing date") — an aid, not legal advice; see [docs/contract-lifecycle.md](docs/contract-lifecycle.md#crz-publication-deadline-124). The CRZ round trip (civora-org/civora-platform#125): a published, unfiled editorial record offers **Record CRZ filing** on its index row (`GET`/`POST /zmluvy/admin/contracts/:id/crz_filing`, `editor`-gated) — the editor names the CRZ id, the engine fetches the official record read-only from the ekosystem feed (which may lag the CRZ by about a day), compares reference, supplier IČO and amount side by side, and confirms the filing on a match (any difference needs a stored, audited reason; hard refusals for another organization's record, a cancelled/withdrawn record or an unconfigured IČO). The record stays editorial and becomes the linked record of the CRZ id: the sync then neither mirrors nor flags it (`linked`), a pristine mirror already holding the id is absorbed, and the public detail page says "Published in CRZ on <date>" with the official link; see [docs/crz-import.md](docs/crz-import.md). Each contract also has a nested party manager at `/zmluvy/admin/contracts/:contract_id/parties` — add/edit/remove the object/contractor parties, `editor`-gated and available only while the record's lifecycle state is editable. The contract edit page also hosts the document manager — attach/replace/remove files, `editor`-gated on an editable-state contract (civora-org/civora-platform#73) — and the CRZ handoff export: generate/regenerate the PDF aid (`editor`-gated on an editable-state contract) and download it (`editor`-gated on any lifecycle state); the PDF is labelled a handoff aid for the clerical CRZ record, never a legal publication (civora-org/civora-platform#74). Each contract also has a nested amendment manager at `/zmluvy/admin/contracts/:contract_id/amendments` — draft version-history entries published by one explicit POST per event: create is `editor`-gated on a published contract; update/destroy/publish are `editor`-gated on a draft amendment (publish additionally requires the contract still published); published amendments are immutable (civora-org/civora-platform#65). The contract edit page also hosts the project/result link manager — add/remove links to platform-level entities (`editor`-gated on an editable-state contract; create/destroy only — links have no editable content), with an explicit flag next to links whose target no longer resolves so editors can clean them up (civora-org/civora-platform#87). The contract edit page also hosts the privacy-redaction confirmation gate (ADR-007, civora-org/civora-platform#91): before the record may be published, an editor must confirm the localized redaction checklist — personal names/addresses of natural persons, bank/account details, amounts tying the contract to identifiable persons, sensitive content inside attached documents — through one required-checkbox POST whose affirmation value is consumed server-side (`POST /zmluvy/admin/contracts/:contract_id/confirm_redaction`, `editor`-gated on a confirmable contract — the editable states plus `approved`, so a reviewer-approved record can still be stamped right before publish; the publish transition refuses while the stamp is missing, and amendment publication backstops on the same stamp for editorial records — CRZ mirrors are exempt, their content being already-public upstream data per ADR-008). Once confirmed, the edit page shows the confirmation stamp line instead of the checkbox form. The contract edit page also links to the read-only audit trail — `/zmluvy/admin/audit_events` (civora-org/civora-platform#92), a paginated, newest-first listing of the organization's append-only audit events (lifecycle transitions, the privacy-redaction confirmation, amendment publications, CRZ filing confirmations and CRZ-import actions), optionally filtered to one contract through `?contract_id=<id>`; every engine role may consult it, each row shows the localized action, the target record (dangling targets render a "record no longer exists" label — the trail outlives what it observed), the acting user and the date and time, plus the reviewer decision reason for records sitting in a decision state.
 - **Roles and permissions** — the engine-logical `editor`/`reviewer` roles map onto Decidim permissions via a config-time resolver; see [docs/roles-and-permissions.md](docs/roles-and-permissions.md).
 - **Navigation** — a "Contracts / Zmluvy" entry in Decidim's main menu (and its mobile menu twin) pointing at the public catalogue, and a "Contracts" entry in the Decidim admin sidebar pointing at the admin contracts index — the sidebar entry renders only for users holding an engine role. Both sit at position 2.4, next to the other content modules; hosts can re-order, override or remove them per Decidim menu conventions (`Decidim.menu :menu do |menu| menu.move :contracts_sk, ... end`, `menu.remove_item :contracts_sk`) (civora-org/civora-platform#86c).
 - **CRZ import** — an editor-gated `POST /zmluvy/admin/contracts/import_crz` (form on the admin contracts index) pulls one CRZ record by its numeric id, and the host-scheduled `bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,<SINCE ISO8601>]"` task mirrors updated records in batch (SINCE also via the `SINCE` env var). Mirrors land `published` with full provenance and an audit event; re-running is always safe. Operations, scheduling, failure modes and the manual collision resolution in [docs/crz-import.md](docs/crz-import.md).
diff --git a/app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb b/app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb
new file mode 100644
index 0000000..0dc713d
--- /dev/null
+++ b/app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb
@@ -0,0 +1,242 @@
+# frozen_string_literal: true
+
+module Decidim
+  module ContractsSk
+    module Admin
+      # Confirms that an editorial contract was filed in the CRZ and links the
+      # official record (civora-org/civora-platform#125, the round trip after
+      # the manual handoff of #74/ADR-002): the editor names the CRZ id, the
+      # engine verifies the official record through the ekosystem feed
+      # (read-only, CrzImport::FilingLookup) and, when it matches, stamps the
+      # confirmation on the editorial record. The record stays editorial
+      # (source never changes) — it becomes the canonical, linked record of
+      # the CRZ id, which the sync then leaves alone (UpsertContract :linked).
+      #
+      # Order of work:
+      # 1. Pre-lock, request-shaped refusals: the editor role, a configured
+      #    organization IČO, the reason's length cap.
+      # 2. The network fetch (FilingLookup) — ALWAYS outside any lock, so a
+      #    slow or dead source never holds a row lock. A failed or empty
+      #    fetch changes nothing and writes no audit row.
+      # 3. The in-lock decision on the RELOADED row (with_lock reloads — the
+      #    #69 TOCTOU doctrine, no pre-lock read or stale caller copy ever
+      #    admits a write): editorial source, published state, not already
+      #    filed, the preview's checksum token still equal to the fresh
+      #    payload's checksum (else :stale — the official record changed
+      #    since the editor looked), the comparison re-run against the
+      #    row as it is NOW, the reason rule, and the id being free.
+      #
+      # Reason rule: any comparison row that is not a :match (mismatch OR
+      # unverifiable) demands a stripped, non-blank reason of at most
+      # MAX_REASON_LENGTH characters — the editor's override, stored in
+      # crz_filing_reason and audited as "contract.crz_filed_override". A
+      # clean match takes NO reason (a reason on a full match is refused, the
+      # TransitionContract reason-shape doctrine) and audits as
+      # "contract.crz_filed". Hard refusals (no override possible): no
+      # configured IČO, record out of the organization's scope, CRZ status
+      # cancelled/withdrawn (FilingLookup).
+      #
+      # Writes (one transaction under the contract's lock): crz_url
+      # (the canonical CRZ template), crz_filed_at, source_id,
+      # crz_published_on, crz_filing_reason and the audit row — all or
+      # nothing. These are system fields, never form-writable.
+      #
+      # Mirror absorption (Gate-1 decision D5-B): the unique
+      # (organization, source_id) index means a CRZ mirror that the sync
+      # already imported under this id would block the claim. Lock order is
+      # CONTRACT FIRST, THEN MIRROR (the only place two contract rows are
+      # locked, so no inverse order exists to deadlock against). A PRISTINE
+      # mirror (no amendments, links or documents — nothing an editor made
+      # of it) is destroyed and the editorial record claims the id; a
+      # "contract.crz_mirror_absorbed" audit row records it. Its audit
+      # target is the EDITORIAL record: the mirror row no longer exists, and
+      # a dangling target would render as "record no longer exists" and
+      # drop out of the per-contract trail filter, whereas the claiming
+      # record is the one the trail should explain (the destroyed mirror's
+      # own import rows keep their dangling targets, as for every contract
+      # deletion). A non-pristine mirror, or another editorial record
+      # holding the id, refuses with :already_linked — resolved manually
+      # (docs/crz-import.md). A concurrent claim that still slips through
+      # trips the unique index (RecordNotUnique), rescued to the same
+      # :already_linked.
+      #
+      # Broadcasts (bare symbols, for the controller's flash mapping):
+      #   on(:ok)      { |outcome| } — :filed | :filed_override
+      #   on(:invalid) { |reason| }  — :not_found, :failed, :not_configured,
+      #     :out_of_scope, :withdrawn, :stale, :reason_required,
+      #     :reason_rejected, :already_filed, :not_fileable, :already_linked
+      #
+      # Cop note: the class stays deliberately cohesive — the ordered guard
+      # chain and the lock doctrine are one contract, and splitting it would
+      # scatter the in-lock decision rather than simplify it.
+      # rubocop:disable Metrics/ClassLength
+      class ConfirmCrzFiling < Decidim::Command
+        MAX_REASON_LENGTH = TransitionContract::MAX_REASON_LENGTH
+
+        AUDIT_FILED = "contract.crz_filed"
+        AUDIT_FILED_OVERRIDE = "contract.crz_filed_override"
+        AUDIT_MIRROR_ABSORBED = "contract.crz_mirror_absorbed"
+
+        # Internal control flow: an in-lock refusal unwinds the transaction
+        # (nothing was written before any refusal, so the rollback is a
+        # no-op) and carries the broadcast reason out.
+        class Refusal < StandardError
+          attr_reader :reason
+
+          def initialize(reason)
+            super(reason.to_s)
+            @reason = reason
+          end
+        end
+
+        # +checksum+ is the token the preview rendered (Mapper checksum of
+        # the payload the editor compared); +client+ is the injection seam
+        # for the verification fetch (specs stub it at its exact boundary).
+        # rubocop:disable Metrics/ParameterLists
+        def initialize(contract, crz_id:, checksum:, user:, reason: nil, client: nil)
+          super()
+          @contract = contract
+          @crz_id = crz_id.to_s.strip
+          @checksum = checksum.to_s
+          @user = user
+          @reason = reason
+          @client = client
+        end
+        # rubocop:enable Metrics/ParameterLists
+
+        def call
+          broadcast(:ok, file_locked(verified_record))
+        rescue Refusal => e
+          broadcast(:invalid, e.reason)
+        rescue ActiveRecord::RecordNotUnique
+          broadcast(:invalid, :already_linked)
+        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
+          broadcast(:invalid, :not_fileable)
+        end
+
+        private
+
+        attr_reader :contract, :crz_id, :checksum, :user, :reason
+
+        # The pre-lock phase: request-shaped refusals that depend on no row
+        # state (the editor role — defense in depth behind the permission
+        # layer, fail-closed — and the reason's length cap), then the
+        # network fetch, outside any lock. Returns the mapped CRZ record or
+        # raises the Refusal that ends the command.
+        def verified_record
+          raise Refusal, :not_fileable unless editor?
+          raise Refusal, :reason_rejected if normalized_reason.length > MAX_REASON_LENGTH
+
+          lookup = CrzImport::FilingLookup.call(crz_id: crz_id, organization: contract.organization,
+                                                client: @client)
+          raise Refusal, lookup.refusal unless lookup.ok?
+
+          lookup.record
+        end
+
+        def editor?
+          Array(Decidim::ContractsSk.role_resolver.call(user, {})).include?(:editor)
+        end
+
+        def normalized_reason
+          @normalized_reason ||= reason.to_s.strip
+        end
+
+        # The locked decision + writes; returns the ok outcome symbol, or
+        # raises Refusal (rolling the transaction back, nothing written).
+        def file_locked(record)
+          contract.with_lock { decide_and_write(record) }
+        end
+
+        # The in-lock body, in guard order; returns the ok outcome.
+        def decide_and_write(record)
+          guard_row!
+          guard_checksum!(record)
+          comparison = CrzImport::FilingComparison.new(contract: contract, record: record)
+          guard_reason!(comparison)
+          mirror = claimable_mirror!(record)
+
+          write_filing!(record, mirror)
+          outcome = comparison.all_match? ? :filed : :filed_override
+          record_audit!(outcome)
+          outcome
+        end
+
+        # The row-state guards, read from the reloaded row.
+        def guard_row!
+          raise Refusal, :already_filed if contract.crz_filed_at.present?
+          raise Refusal, :not_fileable unless fileable_row?
+        end
+
+        # An editorial, published record that carries no OTHER CRZ id.
+        def fileable_row?
+          contract.source == "editorial" && contract.state.to_s == "published" &&
+            (contract.source_id.blank? || contract.source_id == crz_id)
+        end
+
+        # The official record must still be the one the editor compared.
+        def guard_checksum!(record)
+          raise Refusal, :stale unless record[:checksum] == checksum
+        end
+
+        # A non-match (mismatch or unverifiable) needs the override reason;
+        # a clean match takes none.
+        def guard_reason!(comparison)
+          if comparison.needs_reason?
+            raise Refusal, :reason_required if normalized_reason.blank?
+          elsif normalized_reason.present?
+            raise Refusal, :reason_rejected
+          end
+        end
+
+        # The id must be free. Returns a destroyable pristine mirror (to be
+        # absorbed), nil when nothing holds the id; raises :already_linked
+        # for any other holder. The mirror is locked AFTER the contract
+        # (lock order — see the class comment).
+        def claimable_mirror!(record)
+          holder = Contract.where(organization: contract.organization, source_id: record[:source_id])
+                           .where.not(id: contract.id).lock.first
+          return nil unless holder
+          raise Refusal, :already_linked unless holder.source == CrzImport::Mapper::SOURCE && pristine?(holder)
+
+          holder
+        end
+
+        # Nothing an editor made of the mirror: no amendments, links or
+        # documents (parties are the import's own mirrored rows).
+        def pristine?(mirror)
+          !mirror.amendments.exists? && !mirror.links.exists? && !mirror.documents.exists?
+        end
+
+        def write_filing!(record, mirror)
+          absorb!(mirror) if mirror
+
+          contract.update!(
+            crz_url: format(CrzImport::Mapper::CRZ_URL_TEMPLATE, record[:source_id]),
+            crz_filed_at: Time.current,
+            source_id: record[:source_id],
+            crz_published_on: record[:published_on],
+            crz_filing_reason: normalized_reason.presence
+          )
+        end
+
+        # The mirror's row must be gone before the claim (the unique index);
+        # its absorption is audited against the claiming record.
+        def absorb!(mirror)
+          mirror.destroy!
+          write_audit!(AUDIT_MIRROR_ABSORBED)
+        end
+
+        def record_audit!(outcome)
+          write_audit!(outcome == :filed ? AUDIT_FILED : AUDIT_FILED_OVERRIDE)
+        end
+
+        def write_audit!(action)
+          AuditEvent.create!(action: action, target: contract,
+                             organization: contract.organization, actor: user)
+        end
+      end
+      # rubocop:enable Metrics/ClassLength
+    end
+  end
+end
diff --git a/app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb b/app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb
index 47ef381..5f35ac6 100644
--- a/app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb
+++ b/app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb
@@ -24,8 +24,15 @@ module Decidim
       #   provenance are re-mirrored; state/author/currency are never
       #   touched; a "crz_import_update" audit event rides the same
       #   transaction.
+      # - LINKED when a record with the same source_id has a different
+      #   source (an editorial record) that was CONFIRMED as filed
+      #   (crz_filed_at present, Admin::ConfirmCrzFiling,
+      #   civora-org/civora-platform#125): that record is already the
+      #   canonical, linked record of the CRZ id — ZERO writes (updated_at
+      #   untouched), outcome :linked. Not a mirror, not a collision.
       # - COLLISION when a record with the same source_id has a different
-      #   source (an editorial record): never touched, reason :collision —
+      #   source and is NOT confirmed as filed (an editorial record that
+      #   merely carries the id): never touched, reason :collision —
       #   logged for manual resolution by the caller.
       # - UNCHANGED when the checksum matches: zero writes (updated_at
       #   untouched — the idempotency guarantee).
@@ -50,7 +57,7 @@ module Decidim
       #
       # Broadcast payloads (single-arg hashes; the EventRecorder captures
       # them whole):
-      #   on(:ok)      { |result| } — result[:outcome] :created|:updated|:unchanged,
+      #   on(:ok)      { |result| } — result[:outcome] :created|:updated|:unchanged|:linked,
       #                               result[:contract]
       #   on(:invalid) { |result| } — result[:reason]
       #                               :collision|:lifecycle_guard|:record_invalid,
@@ -95,7 +102,7 @@ module Decidim
         def perform
           existing = find_existing
 
-          return invalid_outcome(:collision, existing) if existing && existing.source != SOURCE
+          return foreign_holder_outcome(existing) if existing && existing.source != SOURCE
           return update_locked(existing) if existing
 
           create_transactional
@@ -121,7 +128,7 @@ module Decidim
         # stamp the race winner failed.
         def lost_create_race
           fresh = find_existing
-          return invalid_outcome(:collision, fresh) if fresh && fresh.source != SOURCE
+          return foreign_holder_outcome(fresh) if fresh && fresh.source != SOURCE
           return update_locked(fresh) if fresh
 
           # Unreachable in practice (the index fired, so a row committed);
@@ -138,7 +145,7 @@ module Decidim
           return create! if fresh.nil?
           return update_locked(fresh) if fresh.source == SOURCE
 
-          invalid_outcome(:collision, fresh)
+          foreign_holder_outcome(fresh)
         end
 
         def create!
@@ -168,13 +175,28 @@ module Decidim
           result
         rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
           invalid_outcome(:record_invalid, contract)
+        rescue ActiveRecord::RecordNotFound
+          lost_row_race
+        end
+
+        # The row vanished between the pre-read and the lock's reload (a
+        # filing confirmation absorbed this mirror, civora-org/
+        # civora-platform#125): re-find AFTER the rollback and reroute like
+        # lost_create_race, so the sync ends :linked instead of a spurious
+        # failure.
+        def lost_row_race
+          fresh = find_existing
+          return create_transactional unless fresh
+          return foreign_holder_outcome(fresh) if fresh.source != SOURCE
+
+          update_locked(fresh)
         end
 
         # The in-lock decision, read from the RELOADED row (with_lock
         # refetches under the row lock) — the TOCTOU doctrine: a pre-lock
         # read or a stale caller's copy never admits a write.
         def in_lock_update_outcome(contract)
-          return invalid_outcome(:collision, contract) if contract.source != SOURCE
+          return foreign_holder_outcome(contract) if contract.source != SOURCE
           return ok_outcome(:unchanged, contract) if unchanged_checksum?(contract)
           return invalid_outcome(:lifecycle_guard, contract) if update_guarded?(contract)
 
@@ -182,6 +204,18 @@ module Decidim
           ok_outcome(:updated, contract)
         end
 
+        # A non-mirror record holds the source_id (civora-org/civora-platform
+        # #125): confirmed as filed → :linked, zero writes; otherwise the
+        # protected editorial :collision. Every decision point calls this
+        # with the record as that point sees it — the in-lock call reads the
+        # RELOADED row, so a filing confirmed between the pre-read and the
+        # lock is honoured.
+        def foreign_holder_outcome(contract)
+          return ok_outcome(:linked, contract) if contract.crz_filed_at.present?
+
+          invalid_outcome(:collision, contract)
+        end
+
         # The provenance stamps every import write carries; on create it
         # joins the mirroring identity (source + source_id).
         def provenance_attributes
diff --git a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
index 0fd78a8..f3b91b0 100644
--- a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
+++ b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
@@ -60,6 +60,9 @@ module Decidim
           "contract.archive" => "decidim.contracts_sk.admin.contracts.transition.archive",
           "contract.redaction_confirmed" => "decidim.contracts_sk.admin.audit_events.actions.redaction_confirmed",
           "amendment.publish" => "decidim.contracts_sk.admin.audit_events.actions.amendment_publish",
+          "contract.crz_filed" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed",
+          "contract.crz_filed_override" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed_override",
+          "contract.crz_mirror_absorbed" => "decidim.contracts_sk.admin.audit_events.actions.crz_mirror_absorbed",
           "crz_import_create" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_create",
           "crz_import_update" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_update"
         }.freeze
@@ -179,12 +182,20 @@ module Decidim
           return nil unless event.target_type == CONTRACT_TARGET_TYPE
 
           contract = event.target
+          # The override reason of a CRZ filing confirmation (civora-org/
+          # civora-platform#125) is shown on its own audit row.
+          return contract&.crz_filing_reason.presence if event.action == "contract.crz_filed_override"
+
+          decision_reason(contract)
+        rescue StandardError
+          nil
+        end
+
+        def decision_reason(contract)
           return nil unless contract.present? && contract.review_reason.present?
           return nil unless ContractLifecycle::DECISION_STATES.include?(contract.state&.to_sym)
 
           contract.review_reason
-        rescue StandardError
-          nil
         end
       end
     end
diff --git a/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb b/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb
index 0076589..2bdec90 100644
--- a/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb
+++ b/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb
@@ -10,7 +10,10 @@ module Decidim
       # civora-org/civora-platform#86), the ADR-007 privacy-redaction
       # confirmation POST (civora-org/civora-platform#91) and the
       # reviewer-decision-reason pass-through on the transition actions
-      # (civora-org/civora-platform#90).
+      # (civora-org/civora-platform#90), and the CRZ filing confirmation
+      # pair (civora-org/civora-platform#125: a read-only side-by-side
+      # preview and the verifying POST, both editor-gated on a published,
+      # unfiled editorial record).
       #
       # index/new/create open with enforce_permission_to before anything
       # else; edit/update and the transition actions load the record first,
@@ -209,6 +212,40 @@ module Decidim
           end
         end
 
+        # CRZ filing confirmation (civora-org/civora-platform#125), GET: the
+        # CRZ-id form and — with ?crz_id= — the read-only side-by-side
+        # comparison of this record against the official one fetched
+        # through the ekosystem feed. WRITES NOTHING: the confirm form it
+        # renders carries the preview's checksum token, which the POST's
+        # command re-verifies inside the row lock. The id is validated
+        # (`\A\d+\z`) before any network call (the import_crz precedent).
+        # A refusal re-renders the id form with a localized alert.
+        def crz_filing
+          @contract = contracts_scope.find(params[:id])
+
+          enforce_permission_to :confirm_crz_filing, :contract, contract: @contract
+
+          @crz_id = params[:crz_id].to_s.strip
+          load_filing_preview if @crz_id.present?
+        end
+
+        # CRZ filing confirmation, POST: the verifying command. Every
+        # outcome is a PRG redirect with a localized flash — success to the
+        # index (a filed record is published and no longer editable); a
+        # refusal the editor can act on (stale preview, reason problems)
+        # back to the preview of the same id, the others to the id form or
+        # the index (see FILING_PREVIEW_REASONS / #filing_failed).
+        def confirm_crz_filing
+          @contract = contracts_scope.find(params[:id])
+
+          enforce_permission_to :confirm_crz_filing, :contract, contract: @contract
+
+          crz_id = params[:crz_id].to_s.strip
+          return filing_failed(:not_found, crz_id) unless crz_id.match?(CRZ_ID_FORMAT)
+
+          run_filing_confirmation(crz_id)
+        end
+
         # One explicit action per lifecycle transition event. The route set
         # is derived from ContractLifecycle::TRANSITIONS in config/routes.rb;
         # these named shells exist so the derived routes map onto readable
@@ -239,7 +276,15 @@ module Decidim
 
         # The import outcome vocabulary mirrors CrzImport outcomes 1:1;
         # the successful trio flashes :notice, everything else :alert.
-        IMPORT_NOTICE_OUTCOMES = %i[created updated unchanged].freeze
+        IMPORT_NOTICE_OUTCOMES = %i[created updated unchanged linked].freeze
+
+        # Filing-confirmation refusals that redirect back to the PREVIEW of
+        # the same id (the editor can correct the reason, or must re-read a
+        # changed official record); every other refusal returns to the bare
+        # id form, and :already_filed / :not_fileable to the index.
+        CRZ_ID_FORMAT = /\A\d+\z/
+        FILING_PREVIEW_REASONS = %i[stale reason_required reason_rejected].freeze
+        FILING_INDEX_REASONS = %i[already_filed not_fileable].freeze
 
         private
 
@@ -256,6 +301,52 @@ module Decidim
           redirect_to admin_contracts_path
         end
 
+        # The preview fetch (read-only, FilingLookup): sets the comparison
+        # and checksum token for the view, or re-renders the id form with a
+        # localized refusal. A non-numeric id never reaches the network.
+        def load_filing_preview
+          return filing_invalid_id unless @crz_id.match?(CRZ_ID_FORMAT)
+
+          lookup = CrzImport::FilingLookup.call(crz_id: @crz_id, organization: current_organization)
+          return flash.now[:alert] = filing_message(lookup.refusal, @crz_id) unless lookup.ok?
+
+          @crz_record = lookup.record
+          @comparison = CrzImport::FilingComparison.new(contract: @contract, record: @crz_record)
+        end
+
+        def filing_invalid_id
+          flash.now[:alert] = t("decidim.contracts_sk.admin.contracts.crz_filing.invalid_id")
+        end
+
+        def run_filing_confirmation(crz_id)
+          ConfirmCrzFiling.call(@contract, crz_id: crz_id, checksum: params[:checksum],
+                                           reason: params[:reason], user: current_user) do
+            on(:ok) { |outcome| filing_succeeded(outcome, crz_id) }
+            on(:invalid) { |reason| filing_failed(reason, crz_id) }
+          end
+        end
+
+        def filing_message(reason, crz_id)
+          t("decidim.contracts_sk.admin.contracts.crz_filing.refusals.#{reason}", crz_id: crz_id)
+        end
+
+        def filing_succeeded(outcome, crz_id)
+          flash[:notice] = t("decidim.contracts_sk.admin.contracts.crz_filing.#{outcome}", crz_id: crz_id)
+          redirect_to admin_contracts_path
+        end
+
+        def filing_failed(reason, crz_id)
+          flash[:alert] = filing_message(reason, crz_id)
+
+          if FILING_INDEX_REASONS.include?(reason)
+            redirect_to admin_contracts_path
+          elsif FILING_PREVIEW_REASONS.include?(reason)
+            redirect_to crz_filing_admin_contract_path(@contract, crz_id: crz_id)
+          else
+            redirect_to crz_filing_admin_contract_path(@contract)
+          end
+        end
+
         # PRG on success: notice + back to the admin index.
         def create_succeeded
           flash[:notice] = t("decidim.contracts_sk.admin.contracts.create.success")
diff --git a/app/models/decidim/contracts_sk/contract.rb b/app/models/decidim/contracts_sk/contract.rb
index adee019..0d6df4d 100644
--- a/app/models/decidim/contracts_sk/contract.rb
+++ b/app/models/decidim/contracts_sk/contract.rb
@@ -162,15 +162,16 @@ module Decidim
       # the instance helpers and the scopes agree by construction.
       #
       # Tracked = an editorial record (source != the CRZ mirror's), in a
-      # DEADLINE_TRACKED_STATES state, with crz_url NULL or '' — "not
-      # recorded as filed in CRZ", the interim filed proxy until real filing
-      # confirmation lands (civora-org/civora-platform#125). Records with an
+      # DEADLINE_TRACKED_STATES state, with crz_filed_at NULL — "not
+      # confirmed as filed in CRZ" (the verified filing confirmation of
+      # civora-org/civora-platform#125 replaced the #124 crz_url proxy;
+      # a typed crz_url alone no longer counts). Records with an
       # unknown signed_on ARE tracked here (the edit page and the row badge
       # flag them) but belong to neither the overdue nor the due-soon scope.
       scope :crz_deadline_tracked, lambda {
         where.not(source: CrzImport::Mapper::SOURCE)
              .where(state: ContractLifecycle::DEADLINE_TRACKED_STATES.map(&:to_s))
-             .where(crz_url: [nil, ""])
+             .where(crz_filed_at: nil)
       }
 
       # Tracked records whose deadline lies before +today+:
@@ -202,7 +203,7 @@ module Decidim
       # Whether this record is subject to deadline tracking (the instance
       # twin of the crz_deadline_tracked scope).
       def crz_deadline_tracked?
-        CrzDeadline.tracked?(source: source, state: state, crz_url: crz_url)
+        CrzDeadline.tracked?(source: source, state: state, crz_filed_at: crz_filed_at)
       end
 
       # :untracked (filed, mirror or terminal), :unknown (tracked, no
diff --git a/app/permissions/decidim/contracts_sk/permissions.rb b/app/permissions/decidim/contracts_sk/permissions.rb
index 237cc37..0e7bb5c 100644
--- a/app/permissions/decidim/contracts_sk/permissions.rb
+++ b/app/permissions/decidim/contracts_sk/permissions.rb
@@ -33,6 +33,14 @@ module Decidim
     #   role-gated only, so an editor can retrieve it on any lifecycle
     #   state (unlike :update, which stays editable-state-gated for the
     #   generating twin action).
+    # - :confirm_crz_filing (civora-org/civora-platform#125) is allowed when
+    #   the user's engine roles include :editor AND the record
+    #   (context[:contract] — required, a bare :state context is denied
+    #   fail-closed) is editorial (source != the CRZ mirror's), published and
+    #   not yet confirmed as filed (crz_filed_at blank): only a published
+    #   editorial record that has been handed off to the CRZ can be linked to
+    #   its official record, and once. Reviewers are denied. The command
+    #   re-checks all of it inside the row lock.
     # - Transition events (:submit, :return, :approve, :reject, :publish,
     #   :archive) are allowed when ContractLifecycle.allowed_roles for the
     #   record's state intersect the user's engine roles. The event list is
@@ -112,6 +120,10 @@ module Decidim
     # at class-body load; this file is only ever loaded through the gem's
     # lib require chain (which defines ContractLifecycle first), never
     # standalone.
+    # Cop note: the class stays deliberately cohesive — one rule table per
+    # subject, every gate readable in one file; splitting it would scatter
+    # the permission contract rather than simplify it.
+    # rubocop:disable Metrics/ClassLength
     class Permissions < Decidim::DefaultPermissions
       TRANSITION_EVENTS = ContractLifecycle::TRANSITIONS.values
                                                         .flat_map(&:keys)
@@ -163,7 +175,7 @@ module Decidim
         # consult different lifecycle windows (see #action_state_window):
         # the stamp may still land on an approved record right before
         # publish, while editability itself is never widened.
-        when :update, :confirm_redaction
+        when :update, :confirm_redaction, :confirm_crz_filing
           toggle_allow(contract_write_allowed?)
         when :read
           toggle_allow(roles_for_user.any?)
@@ -222,6 +234,8 @@ module Decidim
       # The shared gate behind :update and :confirm_redaction: the editor
       # role plus the action's lifecycle window (see #action_state_window).
       def contract_write_allowed?
+        return editor? && crz_filing_allowed? if action == :confirm_crz_filing
+
         editor? && action_state_window.include?(state)
       end
 
@@ -239,6 +253,17 @@ module Decidim
         end
       end
 
+      # The CRZ filing confirmation window (civora-org/civora-platform#125):
+      # an editorial, published, not-yet-filed record. Needs the record
+      # itself — the filed flag and the source are not derivable from a bare
+      # state, so a context without :contract denies.
+      def crz_filing_allowed?
+        record = context[:contract]
+        return false unless record
+
+        record.source.to_s != CrzImport::Mapper::SOURCE && state == :published && record.crz_filed_at.blank?
+      end
+
       def amendment_edit_allowed?
         editor? && amendment_draft?
       end
@@ -287,5 +312,6 @@ module Decidim
         Array(Decidim::ContractsSk.role_resolver.call(user, context)) & ContractLifecycle::ROLES
       end
     end
+    # rubocop:enable Metrics/ClassLength
   end
 end
diff --git a/app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb b/app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb
new file mode 100644
index 0000000..53216ad
--- /dev/null
+++ b/app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb
@@ -0,0 +1,99 @@
+<%# CRZ filing confirmation page (civora-org/civora-platform#125): the
+    editor names the CRZ id of the record they filed by hand; with ?crz_id=
+    the controller has fetched the official record (read-only) and the page
+    shows it side by side with this one. Nothing is written by this page.
+    Ivars: @contract, @crz_id, and — when the fetch succeeded —
+    @crz_record (the mapped record) and @comparison (FilingComparison).
+    The confirm form carries the preview's checksum token and the CRZ id as
+    hidden fields; the command re-verifies the token, the comparison and the
+    reason rule inside the row lock, so nothing here is the gate. Plain
+    form_with tag helpers (the import_crz form precedent). %>
+<% scope = "decidim.contracts_sk.admin.contracts.crz_filing" %>
+<div class="item_show__header">
+  <h1 class="item_show__header-title">
+    <%= t("#{scope}.title") %>
+  </h1>
+</div>
+
+<p><strong><%= @contract.title %></strong> (<%= @contract.reference %>)</p>
+<p><%= t("#{scope}.description") %></p>
+
+<div class="card">
+  <div class="card-section">
+    <%= form_with url: crz_filing_admin_contract_path(@contract), method: :get, local: true do %>
+      <div class="row column">
+        <%= label_tag :crz_id, t("#{scope}.crz_id_label") %>
+        <%= text_field_tag :crz_id, @crz_id, placeholder: "12345678", inputmode: "numeric" %>
+      </div>
+      <%= submit_tag t("#{scope}.lookup"), name: nil, class: "button button__sm button__secondary" %>
+      <p><em><%= t("#{scope}.lag_hint") %></em></p>
+    <% end %>
+  </div>
+</div>
+
+<% if @comparison %>
+  <div class="card">
+    <div class="card-divider">
+      <h2 class="card-title"><%= t("#{scope}.comparison.title") %></h2>
+    </div>
+    <div class="card-section">
+      <div class="table-scroll">
+        <table class="table-list">
+          <thead>
+            <tr>
+              <th><%= t("#{scope}.comparison.field") %></th>
+              <th><%= t("#{scope}.comparison.editorial") %></th>
+              <th><%= t("#{scope}.comparison.crz") %></th>
+              <th><%= t("#{scope}.comparison.result") %></th>
+            </tr>
+          </thead>
+          <tbody>
+            <% @comparison.rows.each do |row| %>
+              <% label_class = { match: "success", mismatch: "alert", unverifiable: "warning" }.fetch(row.status) %>
+              <tr>
+                <td><%= t("#{scope}.comparison.fields.#{row.field}") %></td>
+                <td><%= Array(row.editorial).join(", ").presence || "—" %></td>
+                <td><%= Array(row.crz).join(", ").presence || "—" %></td>
+                <td><span class="label <%= label_class %>"><%= t("#{scope}.comparison.statuses.#{row.status}") %></span></td>
+              </tr>
+            <% end %>
+          </tbody>
+        </table>
+      </div>
+
+      <p>
+        <%= t("#{scope}.comparison.published_on") %>:
+        <%= @crz_record[:published_on] ? format_date(@crz_record[:published_on]) : t("#{scope}.comparison.published_on_unknown") %>
+        —
+        <%= link_to t("#{scope}.comparison.official_record"),
+                    format(Decidim::ContractsSk::CrzImport::Mapper::CRZ_URL_TEMPLATE, @crz_record[:source_id]) %>
+      </p>
+    </div>
+  </div>
+
+  <div class="card">
+    <div class="card-section">
+      <%= form_with url: confirm_crz_filing_admin_contract_path(@contract), method: :post, local: true do %>
+        <%= hidden_field_tag :crz_id, @crz_record[:source_id] %>
+        <%= hidden_field_tag :checksum, @crz_record[:checksum] %>
+
+        <% if @comparison.needs_reason? %>
+          <p><strong><%= t("#{scope}.override.warning") %></strong></p>
+          <div class="row column">
+            <%= label_tag :reason, t("#{scope}.override.label") %>
+            <%= text_area_tag :reason, nil,
+                              placeholder: t("#{scope}.override.placeholder"),
+                              maxlength: Decidim::ContractsSk::Admin::ConfirmCrzFiling::MAX_REASON_LENGTH,
+                              required: true %>
+          </div>
+        <% end %>
+
+        <%= submit_tag t("#{scope}.confirm"),
+                       class: "button button__sm button__secondary",
+                       data: { confirm: t("#{scope}.confirm_prompt") } %>
+      <% end %>
+    </div>
+  </div>
+<% end %>
+
+<p><%= link_to t("#{scope}.back"), admin_contracts_path %></p>
diff --git a/app/views/decidim/contracts_sk/admin/contracts/index.html.erb b/app/views/decidim/contracts_sk/admin/contracts/index.html.erb
index 84bd7a4..9711c93 100644
--- a/app/views/decidim/contracts_sk/admin/contracts/index.html.erb
+++ b/app/views/decidim/contracts_sk/admin/contracts/index.html.erb
@@ -21,8 +21,8 @@
   </div>
 
   <%# CRZ publication deadline counters (§ 47a OZ, civora-org/
-      civora-platform#124): editorial records NOT RECORDED AS FILED in CRZ
-      (crz_url empty) that are overdue or due within 14 days. Like the state
+      civora-platform#124): editorial records NOT CONFIRMED AS FILED in CRZ
+      (crz_filed_at empty, #125) that are overdue or due within 14 days. Like the state
       chips they count the UNFILTERED tenant scope and link to the deadline=
       filter while preserving the other normalized filters. Aid only, not
       legal advice (see the hint). %>
@@ -141,6 +141,15 @@
                 <% if allowed_to?(:confirm_redaction, :contract, contract: contract) && contract.redaction_confirmed_at.blank? %>
                   <%= render "redaction_confirmation", contract: contract, collapsed: true %>
                 <% end %>
+                <%# CRZ filing confirmation entry (civora-org/civora-platform#125):
+                    shown only when the acting editor may confirm (editor, a
+                    published, unfiled editorial record — the :confirm_crz_filing
+                    permission). The flow itself lives on its own page. %>
+                <% if allowed_to?(:confirm_crz_filing, :contract, contract: contract) %>
+                  <%= link_to t("decidim.contracts_sk.admin.contracts.crz_filing.link"),
+                              crz_filing_admin_contract_path(contract),
+                              class: "button button__sm button__secondary" %>
+                <% end %>
                 <%# Reviewer decision on the row (civora-org/civora-platform#90):
                     a record sitting in a decision state with a captured
                     reason shows it collapsed right here — for a rejected
diff --git a/app/views/decidim/contracts_sk/contracts/show.html.erb b/app/views/decidim/contracts_sk/contracts/show.html.erb
index bdfe809..c60469f 100644
--- a/app/views/decidim/contracts_sk/contracts/show.html.erb
+++ b/app/views/decidim/contracts_sk/contracts/show.html.erb
@@ -75,7 +75,25 @@
           <%# The originally guarded field: a link to a blank URL would
               render href="". The full URL stays visible (it is the
               citation) and breaks anywhere, so it cannot overflow. %>
-          <% if @contract.crz_url.present? %>
+          <%# A record CONFIRMED as filed (crz_filed_at, civora-org/civora-platform
+              #125) says so, with the CRZ publication date when CRZ carried one,
+              and links the official record; the guarded plain-URL row below
+              stays for every other record. %>
+          <% if @contract.crz_filed_at.present? %>
+            <div>
+              <dt><%= t("decidim.contracts_sk.contract.crz_filed") %></dt>
+              <dd>
+                <% if @contract.crz_published_on.present? %>
+                  <%= t("decidim.contracts_sk.contract.crz_filed_on", date: format_date(@contract.crz_published_on)) %>
+                <% else %>
+                  <%= t("decidim.contracts_sk.contract.crz_filed_confirmed") %>
+                <% end %>
+                <% if @contract.crz_url.present? %>
+                  <br><%= link_to @contract.crz_url, @contract.crz_url %>
+                <% end %>
+              </dd>
+            </div>
+          <% elsif @contract.crz_url.present? %>
             <div>
               <dt><%= t("decidim.contracts_sk.contract.crz_url") %></dt>
               <dd><%= link_to @contract.crz_url, @contract.crz_url %></dd>
diff --git a/config/locales/en.yml b/config/locales/en.yml
index 3ec5a42..da85bca 100644
--- a/config/locales/en.yml
+++ b/config/locales/en.yml
@@ -12,6 +12,9 @@ en:
         effective_from: "Effective from"
         crz_url: "CRZ URL"
         published_on: "Published on"
+        crz_filed: "Published in CRZ"
+        crz_filed_on: "Published in CRZ on %{date}"
+        crz_filed_confirmed: "Publication in CRZ confirmed"
         summary: "Summary"
         party:
           object: "Object party"
@@ -91,7 +94,7 @@ en:
                 all: "All sources"
                 crz: "CRZ import"
                 editorial: "Editorial"
-              deadline: "CRZ deadline (not recorded as filed)"
+              deadline: "CRZ deadline (not confirmed as filed)"
               deadlines:
                 any: "Any deadline"
                 due_soon: "Due within %{days} days"
@@ -103,7 +106,7 @@ en:
               body: "Adjust or clear the filters and try again."
               clear: "Clear filters and show all contracts"
           deadline:
-            hint: "Shown while the contract is not recorded as filed in CRZ (CRZ URL empty). An aid based on the signing date, not legal advice."
+            hint: "Shown while the contract is not confirmed as filed in CRZ (use the Record CRZ filing action once it is). An aid based on the signing date, not legal advice."
             badge:
               overdue: "Overdue"
               today: "Due today"
@@ -176,6 +179,52 @@ en:
             signed_on: "Signed on"
             effective_from: "Effective from"
             crz_url: "CRZ URL"
+          crz_filing:
+            link: "Record CRZ filing"
+            title: "Record filing in CRZ"
+            description: "Confirm that this contract was filed in the Slovak central register of contracts (CRZ). Enter the CRZ id; the engine fetches the official record read-only and compares it with this one. The record stays an editorial record — it becomes the linked record of that CRZ id."
+            crz_id_label: "CRZ contract id"
+            lookup: "Compare with CRZ"
+            lag_hint: "The data comes from the ekosystem.slovensko.digital feed, which may lag the CRZ by about a day. A record filed today may not be found yet — try again later."
+            back: "Back to the contract list"
+            invalid_id: "Enter the numeric CRZ contract id."
+            comparison:
+              title: "This record compared with the CRZ record"
+              field: "Field"
+              editorial: "This record"
+              crz: "CRZ record"
+              result: "Result"
+              published_on: "Published in CRZ on"
+              published_on_unknown: "date not available"
+              official_record: "Open the record in CRZ"
+              fields:
+                reference: "Reference number"
+                supplier_ico: "Supplier IČO"
+                amount: "Amount"
+              statuses:
+                match: "Match"
+                mismatch: "Mismatch"
+                unverifiable: "Cannot be verified"
+            override:
+              warning: "Not every field matches the CRZ record. You can still confirm the filing, but you must state the reason; it is stored and audited."
+              label: "Reason for confirming despite the differences"
+              placeholder: "e.g. the reference number was corrected in CRZ after filing"
+            confirm: "Confirm filing in CRZ"
+            confirm_prompt: "Confirm that this contract was filed in CRZ as the record shown? This cannot be undone."
+            filed: "Filing of contract %{crz_id} in CRZ confirmed and linked."
+            filed_override: "Filing of contract %{crz_id} in CRZ confirmed and linked despite differences (the reason was recorded)."
+            refusals:
+              not_found: "No CRZ contract with id %{crz_id} was found. The data source may lag the CRZ by about a day — try again later."
+              failed: "The CRZ data source is unavailable. Nothing was changed — try again later."
+              not_configured: "The CRZ link is not configured for this organization (no IČO set). Nothing was changed."
+              out_of_scope: "CRZ contract %{crz_id} does not involve this organization (its IČO is on neither party); it cannot be confirmed."
+              withdrawn: "CRZ contract %{crz_id} is cancelled or withdrawn in CRZ; it cannot be confirmed as a filing."
+              stale: "The CRZ record changed since you compared it. Review the comparison again and confirm."
+              reason_required: "The record differs from the CRZ record or cannot be verified — enter the reason for confirming anyway."
+              reason_rejected: "The reason was refused: it must be at most 1000 characters, and is only accepted when the record differs from CRZ."
+              already_filed: "This contract is already confirmed as filed in CRZ."
+              not_fileable: "This contract cannot be confirmed as filed (it must be a published editorial record)."
+              already_linked: "CRZ id %{crz_id} is already linked to another record. Resolve it manually (docs/crz-import.md)."
           import_crz:
             title: "Import from CRZ"
             description: "Import one contract record from the Slovak central register (CRZ) by its numeric id. The mirror lands published with its source metadata; editorial records holding the same id are never touched."
@@ -187,6 +236,7 @@ en:
             created: "Contract %{source_id} imported and published."
             updated: "Contract %{source_id} updated from the CRZ payload."
             unchanged: "Contract %{source_id} is already up to date."
+            linked: "Contract %{source_id} is already linked to a record confirmed as filed in CRZ — nothing was changed."
             collision: "A manually created record already holds CRZ id %{source_id} — the import did not touch it. Resolve the collision manually."
             lifecycle_guard: "Contract %{source_id} is no longer published; the import did not update it."
             record_invalid: "Contract %{source_id} could not be imported (invalid data). No existing record was changed."
@@ -212,6 +262,9 @@ en:
             amendment_publish: "Amendment published"
             crz_import_create: "Imported from CRZ"
             crz_import_update: "Updated from CRZ"
+            crz_filed: "CRZ filing confirmed"
+            crz_filed_override: "CRZ filing confirmed despite differences"
+            crz_mirror_absorbed: "CRZ mirror absorbed by the filed record"
           amendment_target: "Amendment v%{version}"
           deleted_target: "Record no longer exists"
           filter_banner: "Showing audit events for: %{title}"
diff --git a/config/locales/sk.yml b/config/locales/sk.yml
index 2cc395f..3d3cc61 100644
--- a/config/locales/sk.yml
+++ b/config/locales/sk.yml
@@ -12,6 +12,9 @@ sk:
         effective_from: "Dátum účinnosti"
         crz_url: "Odkaz na CRZ"
         published_on: "Dátum zverejnenia"
+        crz_filed: "Zverejnené v CRZ"
+        crz_filed_on: "Zverejnené v CRZ dňa %{date}"
+        crz_filed_confirmed: "Zverejnenie v CRZ potvrdené"
         summary: "Súhrn"
         party:
           object: "Objednávateľ"
@@ -91,7 +94,7 @@ sk:
                 all: "Všetky zdroje"
                 crz: "Import z CRZ"
                 editorial: "Redakčná"
-              deadline: "Lehota CRZ (nezaznamenané ako zverejnené)"
+              deadline: "Lehota CRZ (nepotvrdené ako zverejnené)"
               deadlines:
                 any: "Ľubovoľná lehota"
                 due_soon: "Do %{days} dní"
@@ -103,7 +106,7 @@ sk:
               body: "Upravte alebo zrušte filtre a skúste to znova."
               clear: "Zrušiť filtre a zobraziť všetky zmluvy"
           deadline:
-            hint: "Zobrazuje sa, kým zmluva nie je zaznamenaná ako zverejnená v CRZ (prázdny odkaz na CRZ). Pomôcka podľa dátumu podpisu, nie právne poradenstvo."
+            hint: "Zobrazuje sa, kým zmluva nie je potvrdená ako zverejnená v CRZ (použite akciu Zaznamenať zverejnenie v CRZ, keď už je). Pomôcka podľa dátumu podpisu, nie právne poradenstvo."
             badge:
               overdue: "Po termíne"
               today: "Dnes"
@@ -176,6 +179,52 @@ sk:
             signed_on: "Dátum podpisu"
             effective_from: "Dátum účinnosti"
             crz_url: "Odkaz na CRZ"
+          crz_filing:
+            link: "Zaznamenať zverejnenie v CRZ"
+            title: "Zaznamenať zverejnenie v CRZ"
+            description: "Potvrďte, že táto zmluva bola zverejnená v Centrálnom registri zmlúv (CRZ). Zadajte ID z CRZ; systém si úradný záznam len na čítanie stiahne a porovná ho s týmto záznamom. Záznam zostane redakčným záznamom — stane sa prepojeným záznamom daného ID z CRZ."
+            crz_id_label: "ID zmluvy v CRZ"
+            lookup: "Porovnať s CRZ"
+            lag_hint: "Údaje pochádzajú zo zdroja údajov ekosystem.slovensko.digital, ktorý môže za CRZ zaostávať približne o deň. Zmluva zverejnená dnes tam ešte nemusí byť — skúste to neskôr."
+            back: "Späť na zoznam zmlúv"
+            invalid_id: "Zadajte číselné ID zmluvy z CRZ."
+            comparison:
+              title: "Porovnanie tohto záznamu so záznamom v CRZ"
+              field: "Pole"
+              editorial: "Tento záznam"
+              crz: "Záznam v CRZ"
+              result: "Výsledok"
+              published_on: "Zverejnené v CRZ dňa"
+              published_on_unknown: "dátum nie je k dispozícii"
+              official_record: "Otvoriť záznam v CRZ"
+              fields:
+                reference: "Číslo zmluvy"
+                supplier_ico: "IČO dodávateľa"
+                amount: "Suma"
+              statuses:
+                match: "Zhoda"
+                mismatch: "Nezhoda"
+                unverifiable: "Nedá sa overiť"
+            override:
+              warning: "Nie všetky polia sa zhodujú so záznamom v CRZ. Zverejnenie môžete aj tak potvrdiť, ale musíte uviesť dôvod; ukladá sa a zapisuje do auditu."
+              label: "Dôvod potvrdenia napriek rozdielom"
+              placeholder: "napr. číslo zmluvy bolo v CRZ po zverejnení opravené"
+            confirm: "Potvrdiť zverejnenie v CRZ"
+            confirm_prompt: "Potvrdzujete, že táto zmluva bola v CRZ zverejnená ako zobrazený záznam? Túto akciu nie je možné vrátiť."
+            filed: "Zverejnenie zmluvy s ID %{crz_id} v CRZ bolo potvrdené a prepojené."
+            filed_override: "Zverejnenie zmluvy s ID %{crz_id} v CRZ bolo potvrdené a prepojené napriek rozdielom (dôvod bol zaznamenaný)."
+            refusals:
+              not_found: "Zmluva s ID %{crz_id} nebola v CRZ nájdená. Zdroj údajov môže za CRZ zaostávať približne o deň — skúste to neskôr."
+              failed: "Zdroj údajov z CRZ nie je dostupný. Nič sa nezmenilo — skúste to neskôr."
+              not_configured: "Prepojenie s CRZ nie je pre túto organizáciu nastavené (chýba IČO). Nič sa nezmenilo."
+              out_of_scope: "Zmluva %{crz_id} z CRZ sa netýka tejto organizácie (jej IČO nie je ani pri jednej zmluvnej strane); nemožno ju potvrdiť."
+              withdrawn: "Zmluva %{crz_id} je v CRZ zrušená alebo stiahnutá; nemožno ju potvrdiť ako zverejnenie."
+              stale: "Záznam v CRZ sa od porovnania zmenil. Skontrolujte porovnanie znova a potvrďte."
+              reason_required: "Záznam sa líši od záznamu v CRZ alebo sa nedá overiť — uveďte dôvod, prečo ho aj tak potvrdzujete."
+              reason_rejected: "Dôvod bol odmietnutý: môže mať najviac 1000 znakov a prijíma sa len vtedy, keď sa záznam od CRZ líši."
+              already_filed: "Táto zmluva je už potvrdená ako zverejnená v CRZ."
+              not_fileable: "Túto zmluvu nemožno potvrdiť ako zverejnenú (musí ísť o zverejnený redakčný záznam)."
+              already_linked: "ID z CRZ %{crz_id} je už prepojené s iným záznamom. Vyriešte to ručne (docs/crz-import.md)."
           import_crz:
             title: "Import z CRZ"
             description: "Import jednej zmluvy zo Slovenského centrálneho registra zmlúv (CRZ) podľa jej číselného ID. Zrkadlový záznam sa zverejní s metadátami zdroja; ručne vytvorené záznamy s rovnakým ID zostanú nedotknuté."
@@ -187,6 +236,7 @@ sk:
             created: "Zmluva %{source_id} bola importovaná a zverejnená."
             updated: "Zmluva %{source_id} bola aktualizovaná podľa údajov z CRZ."
             unchanged: "Zmluva %{source_id} je už aktuálna."
+            linked: "Zmluva %{source_id} je už prepojená so záznamom potvrdeným ako zverejnený v CRZ — nič sa nezmenilo."
             collision: "Ručne vytvorený záznam už obsahuje ID z CRZ %{source_id} — import ho ponechal nedotknutý. Kolíziu je potrebné vyriešiť ručne."
             lifecycle_guard: "Zmluva %{source_id} už nie je zverejnená; import ju neaktualizoval."
             record_invalid: "Zmluvu %{source_id} sa nepodarilo importovať (neplatné údaje). Existujúci záznam nebol zmenený."
@@ -212,6 +262,9 @@ sk:
             amendment_publish: "Dodatok zverejnený"
             crz_import_create: "Importované z CRZ"
             crz_import_update: "Aktualizované z CRZ"
+            crz_filed: "Zverejnenie v CRZ potvrdené"
+            crz_filed_override: "Zverejnenie v CRZ potvrdené napriek rozdielom"
+            crz_mirror_absorbed: "Zrkadlový záznam z CRZ nahradený potvrdeným záznamom"
           amendment_target: "Dodatok č. %{version}"
           deleted_target: "Záznam už neexistuje"
           filter_banner: "Zobrazujú sa udalosti auditnej stopy pre: %{title}"
diff --git a/config/routes.rb b/config/routes.rb
index 66990dd..cd191ba 100644
--- a/config/routes.rb
+++ b/config/routes.rb
@@ -1,5 +1,8 @@
 # frozen_string_literal: true
 
+# The route table is one declarative list (each block documents its own
+# reason to exist), so the block-length budget does not apply.
+# rubocop:disable Metrics/BlockLength
 Decidim::ContractsSk::Engine.routes.draw do
   # Admin routes (declared before the public /:id catch-all so that the
   # admin namespace is matched first). Contract records have no :show — they
@@ -44,6 +47,16 @@ Decidim::ContractsSk::Engine.routes.draw do
       # the derivation above (same reasoning as the CRZ-handoff pair).
       member { post :confirm_redaction }
 
+      # CRZ filing confirmation (civora-org/civora-platform#125): a GET
+      # form + read-only side-by-side preview (?crz_id=, writes nothing) and
+      # a POST that verifies and stamps the filing. Declared explicitly —
+      # NOT a lifecycle event, so outside the derivation above (the
+      # crz_handoff pair's precedent): same path, two verbs, two actions.
+      member do
+        get :crz_filing, action: :crz_filing, as: :crz_filing
+        post :crz_filing, action: :confirm_crz_filing, as: :confirm_crz_filing
+      end
+
       # Per-contract party management (civora-org/civora-platform#76):
       # dedicated nested pages (index/new/edit + destroy), deliberately no
       # nested-form JS. Tenancy is derived through the parent contract; the
@@ -94,3 +107,4 @@ Decidim::ContractsSk::Engine.routes.draw do
   root to: "contracts#index", as: :contracts
   get "/:id", to: "contracts#show", as: :contract
 end
+# rubocop:enable Metrics/BlockLength
diff --git a/db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb b/db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb
new file mode 100644
index 0000000..b2b886b
--- /dev/null
+++ b/db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb
@@ -0,0 +1,37 @@
+# frozen_string_literal: true
+
+# Adds the CRZ filing confirmation to the engine's contracts table
+# (civora-org/civora-platform#125): an editor who has filed an editorial
+# record in the CRZ by hand records the round trip here, after the engine
+# has verified the official record through the ekosystem feed.
+#
+# Three nullable system columns, written only by Admin::ConfirmCrzFiling
+# inside the row lock and never form-writable (like redaction_confirmed_at
+# and review_reason):
+# - `crz_filed_at` (datetime): WHEN the filing was confirmed. Its presence
+#   is the "filed" flag — it replaces the interim `crz_url` proxy of the
+#   #124 deadline tracking and is the marker the CRZ sync reads to treat
+#   the editorial record as the already-linked canonical record of its
+#   CRZ id (no mirror, no collision).
+# - `crz_published_on` (date): the publication date CRZ reports for the
+#   record; nil when CRZ carried none (sentinel or blank).
+# - `crz_filing_reason` (string, 1000): the editor's reason when the
+#   confirmation overrode a mismatch between the editorial record and the
+#   CRZ record; nil for a clean match.
+#
+# Additive, reversible (single `change`), nothing backfilled: records
+# recorded by hand before this migration (a typed crz_url) stay
+# "not confirmed as filed" on purpose — only a verified confirmation may
+# count as filed. No defaults, no indexes (read per record, never queried
+# as a set apart from the deadline scope's NULL test on a small table).
+#
+# Hosts that already ran the engine migrations under their original
+# timestamps copy this file verbatim (README: "install:migrations"
+# paragraph and the host's "Upgrading the engine" procedure).
+class AddCrzFilingToDecidimContractsSkContracts < ActiveRecord::Migration[7.2]
+  def change
+    add_column :decidim_contracts_sk_contracts, :crz_filed_at, :datetime
+    add_column :decidim_contracts_sk_contracts, :crz_published_on, :date
+    add_column :decidim_contracts_sk_contracts, :crz_filing_reason, :string, limit: 1000
+  end
+end
diff --git a/docs/contract-lifecycle.md b/docs/contract-lifecycle.md
index 80571db..e15f3b9 100644
--- a/docs/contract-lifecycle.md
+++ b/docs/contract-lifecycle.md
@@ -90,7 +90,7 @@ Role→user mapping and permission checks (M02-01-B): [roles-and-permissions.md]
 A contract that must be published in the CRZ and is not published within
 three months of its conclusion is deemed never concluded (§ 47a of Act No.
 211/2000 Coll., OZ). The engine shows the days left for every editorial
-record that is not yet recorded as filed in CRZ, so an overdue or at-risk
+record that is not yet confirmed as filed in CRZ, so an overdue or at-risk
 contract cannot be missed.
 
 - **Rule.** Deadline = `signed_on` + `Decidim::ContractsSk.crz_deadline`
@@ -104,12 +104,17 @@ contract cannot be missed.
   (`draft`, `in_review`, `returned`, `approved`, `published`). A signed draft
   is tracked: the clock runs from the signature, not from our workflow.
   `rejected` and `archived` are never tracked.
-- **"Filed" is a proxy.** A record counts as recorded as filed when `crz_url`
-  is present (NOT NULL and not `''`). Until real filing confirmation lands
-  (civora-org/civora-platform#125) the UI says "not recorded as filed in CRZ",
-  never "not published". Caveat: `crz_url` is only writable in the editable
-  states (`draft`, `returned`), so a record that has moved past `returned`
-  without a CRZ link cannot clear the flag until #125 ships.
+- **"Filed" is a verified confirmation (#125).** A record counts as filed
+  when `crz_filed_at` is present — stamped only by the filing confirmation
+  (`Admin::ConfirmCrzFiling`: the editor names the CRZ id, the engine verifies
+  the official record read-only and, on a match or an explained override,
+  records the filing; see [crz-import.md](crz-import.md)). The UI says "not
+  confirmed as filed in CRZ", never "not published". This is a **hard switch**
+  from the interim `crz_url` proxy of #124: a typed CRZ link alone no longer
+  stops tracking, and nothing is backfilled — records the editors considered
+  filed before the confirmation shipped stay tracked until they are confirmed
+  (a published record is confirmed from its index row; the editable-state
+  limit of the `crz_url` field no longer matters).
 - **Where it shows.** Admin index: a badge per tracked row (alert "po termíne"
   when overdue, warning for 0–14 days left, plain beyond; muted dash when
   `signed_on` is unknown), the `deadline=due_soon|overdue` filter and two
@@ -130,7 +135,7 @@ contract cannot be missed.
   conservative (earlier) one. The feature is an aid for editors, **not legal
   advice**.
 - **Follow-ups.** Notifications on approaching deadlines: civora-org/civora-platform#94.
-  Real filing confirmation replacing the `crz_url` proxy: #125.
+  (Real filing confirmation replacing the `crz_url` proxy: shipped in #125.)
 
 ## Public API
 
diff --git a/docs/contracts-domain-notes.md b/docs/contracts-domain-notes.md
index b7fde8e..d677d7a 100644
--- a/docs/contracts-domain-notes.md
+++ b/docs/contracts-domain-notes.md
@@ -365,12 +365,48 @@ the current version):
   migration; the `Contract` scopes (`crz_deadline_tracked`, `crz_overdue`,
   `crz_due_soon`) compare `signed_on` against Ruby-computed thresholds because
   SQL date arithmetic is not portable (month-end clamping).
-- "Filed in CRZ" is a **proxy**: `crz_url` present (NOT NULL and not `''`) —
-  consistent with ADR-002's manual handoff. Real filing confirmation is #125.
-  Only editorial records (`source != "crz"`) in non-terminal states are tracked.
+- "Filed in CRZ" was a **proxy** here (`crz_url` present); #125 replaced it
+  with the verified `crz_filed_at` (below). Only editorial records
+  (`source != "crz"`) in non-terminal states with `crz_filed_at` NULL are
+  tracked.
 - Details, caveats and non-goals in
   [contract-lifecycle.md](contract-lifecycle.md#crz-publication-deadline-124).
 
+## CRZ filing confirmation landed in #125
+
+- **Columns** (one additive, reversible migration, no backfill, all nullable
+  system fields — never form-writable, like `redaction_confirmed_at`):
+  `crz_filed_at` (datetime — the "filed" flag), `crz_published_on` (date, the
+  publication date CRZ reports; nil for the sentinel/blank) and
+  `crz_filing_reason` (string, 1000 — the editor's override reason, nil on a
+  clean match).
+- **Writer:** `Admin::ConfirmCrzFiling` only. Fetch outside any lock
+  (`CrzImport::FilingLookup`), then `contract.with_lock` and an in-lock
+  re-check on the reloaded row: editorial source, `published` state, not
+  already filed, the preview's checksum token still equal to the fresh
+  payload's, the `FilingComparison` re-run against the row as it is now, the
+  reason rule, the id free. The unique `(organization, source_id)` index is
+  the backstop (`RecordNotUnique` → "already linked"). Deterministic specs
+  prove the stale-object paths without threads.
+- **Lock order:** contract first, then the CRZ mirror holding the id — the
+  only place two contract rows are locked, so no inverse order exists. A
+  pristine mirror (no amendments/links/documents) is destroyed and audited as
+  `contract.crz_mirror_absorbed`; the audit row targets the **editorial**
+  record (the destroyed mirror would dangle and drop out of the per-contract
+  trail filter; its own import rows keep their dangling targets as for every
+  contract deletion).
+- **Linked rule (sync):** `UpsertContract` treats a `source != "crz"` record
+  holding the id with `crz_filed_at` present as `:linked` — zero writes, no
+  mirror, not a collision (`Sync::Result#linked`/`linked_ids`). An unfiled
+  editorial record holding the id stays a collision. The sync's failure paths
+  stamp `import_status` only on `source="crz"` rows (`Sync#find_mirror` and
+  `mark_failed!` are scoped to the mirror source), so a filed or colliding
+  editorial record is never stamped.
+- **Audit actions:** `contract.crz_filed`, `contract.crz_filed_override`,
+  `contract.crz_mirror_absorbed`.
+- **Permission:** `:confirm_crz_filing` — editor, editorial, published,
+  unfiled ([roles-and-permissions.md](roles-and-permissions.md)).
+
 ## Known gaps / drift (flagged, unowned)
 
 - ~~The data dictionary does not exist anywhere yet~~ — **resolved 2026-09-03
diff --git a/docs/crz-import.md b/docs/crz-import.md
index a52e4bf..244bd60 100644
--- a/docs/crz-import.md
+++ b/docs/crz-import.md
@@ -24,6 +24,14 @@
   dodávateľ → `contractor`). **Not mirrored:** documents (link-only via
   `crz_url`), currency and the VAT flag (absent upstream — manual fields),
   amendment linkage hints (structurally unreliable per the spike).
+- **Filing-confirmation fields (#125):** the mapper also returns `status_id`
+  (CRZ status code) and `published_on` (from `published_at`, "Dátum
+  zverejnenia v CRZ", spike-verified field) beside the written attributes —
+  they are read only by the filing confirmation and never written by the
+  import or part of the checksum. The spike does not document the format of
+  `published_at`: a plain `YYYY-MM-DD` is taken as is, a timestamp is
+  converted to Europe/Bratislava before taking the date, and the
+  `0000-00-00` sentinel, blanks and garbage map to nil.
 - **Organization scope (civora-org/civora-platform#145):** the ekosystem
   feed carries every contract published anywhere in Slovakia. Only
   records whose parties carry the organization's IČO (as objednávateľ or
@@ -43,7 +51,8 @@
 | A `source="crz"` record exists, payload checksum unchanged | **No-op** (zero writes, `updated_at` untouched). This is what makes re-running the sync safe. |
 | A `source="crz"` record exists, checksum changed, record still `published` | Content fields, parties and provenance are re-mirrored + a `crz_import_update` audit event. Lifecycle state, author and currency are never touched. |
 | A `source="crz"` record exists but left `published` (e.g. archived) | **Skipped** — never resurrected or overwritten. |
-| A record with the same source id has `source != "crz"` (editorial record) | **Never touched** — the collision is counted and logged for manual resolution (see below). |
+| A record with the same source id has `source != "crz"` and **`crz_filed_at` present** (an editorial record confirmed as filed, civora-org/civora-platform#125) | **Linked, no-op** — the filed editorial record is already the canonical record of the CRZ id: zero writes (`updated_at` untouched), no mirror created, counted as `linked` (not a collision). |
+| A record with the same source id has `source != "crz"` and **no filing confirmation** (an editorial record that merely carries the id) | **Never touched** — the collision is counted and logged for manual resolution (see below). |
 
 Provenance on every write: `source="crz"`, `source_id` (the CRZ numeric
 id), `imported_at` (write time), `import_status="succeeded"`,
@@ -95,10 +104,13 @@ bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,2026-09-08T00:
 - The task exits **non-zero** when the sync stopped early (source
   unreachable), so a scheduler can alert. Partial pages already applied
   stay applied; re-running is always safe (idempotent upsert).
-- Summary counters (created/updated/unchanged/collisions/quarantined/
+- Summary counters (created/updated/unchanged/linked/collisions/quarantined/
   failed/skipped/out_of_scope + ids) print at the end; collisions and
   quarantined ids need human follow-up (below). `out_of_scope` is a count
-  only (other organizations' contracts), never a follow-up item.
+  only (other organizations' contracts), never a follow-up item; `linked`
+  (with `linked_ids`) counts editorial records already confirmed as filed —
+  informational, no follow-up. The same `Sync::Result` carries `linked` and
+  `linked_ids`.
 
 #### Pruning mirrors from before the scoping
 
@@ -132,8 +144,41 @@ dry run, check the count, and after pruning re-sync from the go-live
 the form on the admin contracts index. Editor-gated (the `:import_crz`
 permission, role-only). Every outcome is a localized flash: created /
 updated / unchanged / collision / lifecycle guard / invalid data /
-not found / source unavailable. Use it to pull one contract by hand, e.g.
-when a municipal clerk references a specific CRZ record.
+not found / source unavailable, plus **linked** (a filing-confirmed editorial
+record holds the id: nothing changed). Use it to pull one contract by hand,
+e.g. when a municipal clerk references a specific CRZ record.
+
+### 3. Admin filing confirmation (the round trip, civora-org/civora-platform#125)
+
+The import pulls CRZ records **into** the catalogue; the filing confirmation
+closes the loop for a contract the municipality filed in the CRZ **by hand**
+(the ADR-002 handoff aid). From a published editorial record's row on the
+admin index, **"Record CRZ filing"** (`GET /admin/contracts/:id/crz_filing`)
+takes the CRZ id, fetches the official record **read-only** through the same
+ekosystem feed (never written, never logged beyond URL and status) and shows
+it side by side with the editorial record: reference (whitespace/case
+insensitive), supplier IČO (any editorial contractor matches), amount (to the
+cent). Each row is match / mismatch / cannot-be-verified.
+
+- A **full match** confirms with one click; a mismatch or an unverifiable row
+  needs a **reason** (at most 1000 characters), stored on the record and
+  audited as `contract.crz_filed_override`. A clean match audits as
+  `contract.crz_filed`; a reason on a clean match is refused.
+- **Hard refusals** (no override): no organization IČO configured, the record
+  is not the organization's (neither party carries its IČO), or CRZ status
+  cancelled/withdrawn (4/5).
+- The command (`Admin::ConfirmCrzFiling`) fetches outside any lock, then
+  re-checks everything under the contract's row lock — including that the
+  official record is unchanged since the preview (`stale` otherwise).
+- It stamps `crz_filed_at`, `crz_published_on`, `crz_url` and `source_id`;
+  the record **stays editorial** (`source` never changes) and becomes the
+  canonical linked record of the id, which the sync then leaves alone
+  (table above). The #124 deadline stops tracking it.
+- **Mirror absorption:** if the sync already mirrored that id, a *pristine*
+  mirror (no amendments, links or documents) is destroyed and the editorial
+  record claims the id (audited as `contract.crz_mirror_absorbed`); a worked
+  mirror, or another editorial record holding the id, refuses with "already
+  linked" — resolve manually (below).
 
 ### Actor / authorship
 
@@ -171,6 +216,9 @@ engine never fabricates synthetic users.
 | No IČO configured for the organization | The rake task prints the refusal and exits non-zero without calling the source; the admin action flashes "not configured". Nothing is written. | Configure `crz_organization_ico_resolver` in the host (README § Configuration). |
 | Record belongs to another organization | Counted `out_of_scope`, not written; an existing mirror of it is left untouched (remove it with the prune task). The admin action flashes "does not involve this organization". | None — expected for every other organization's contract in the national feed. |
 | Unknown source id (admin action) | Localized "not found" flash; nothing written. | Verify the numeric CRZ id on crz.gov.sk. |
+| Filing confirmation: record not found yet (**ekosystem lag**) | The feed can trail the CRZ by about a day, so a record filed today may answer "not found". The confirmation changes nothing and writes no audit row; the flash says so. | Try again later (next day). |
+| Filing confirmation: source unreachable / unreadable | Same: no change, no audit row, "source unavailable" flash. | Retry later. |
+| Filing confirmation: official record changed since the preview | Refused as `stale`; the preview is shown again. | Re-read the comparison and confirm. |
 | Timeouts | The transport uses explicit timeouts (5s connection / 60s read — the live 2026-09-09 run observed ~50s server-side response times under throttling); timeouts are retried like other transient failures. | None — the run reports itself. |
 | Old mirror, dead `crz_url` | The public CRZ portal serves records only while they are within its publication window; ekosystem keeps its historical harvest indefinitely. A mirror of an old record (e.g. a 2015 contract) can therefore point at a `crz.gov.sk/zmluva/<id>/` URL that now 404s, while the ekosystem payload still says `status_id: 2` (published). Verified live 2026-09-09 (id 2142424). | Expected behaviour, not a bug — keep the canonical URL per ADR-008 attribution; the freshness indicator already signals mirror age. |
 
@@ -207,12 +255,21 @@ import writes — mirrors are labelled, never implied to be real-time
 
 ## Manual resolution steps
 
-- **Editorial collisions** (a manually created record holds a CRZ id):
-  the import never touches them. Resolve by deciding which record is the
+- **Editorial collisions** (an *unfiled* manually created record holds a CRZ
+  id): the import never touches them. A record that the editor confirmed as
+  filed (#125) is not a collision any more — it is counted `linked`. For a
+  genuine collision, if the editorial record IS the contract filed in CRZ,
+  use "Record CRZ filing" on it (verified, audited) instead of editing data
+  by hand; otherwise resolve by deciding which record is the
   source of truth: either (a) delete/merge the manual record and let the
   import mirror the CRZ data, or (b) clear the manual record's
   `source_id` if it was set by mistake. The sync's collision ids list is
   the worklist.
+- **"Already linked" on a filing confirmation:** the CRZ id is held by
+  another editorial record, or by a mirror an editor has worked on
+  (amendments, links or documents). Decide which record is the source of
+  truth: delete or merge the other record (or clear its `source_id` if it was
+  set by mistake), then confirm again.
 - **Quarantined ids**: check ekosystem's record for schema drift; a
   single record can usually be imported via the admin action once the
   source is sane.
@@ -250,6 +307,12 @@ import writes — mirrors are labelled, never implied to be real-time
 
 - No official-CRZ nightly-ZIP fallback/backfill implementation yet
   (designated by ADR-008; a future arc).
+- A filing-confirmed (linked) editorial record is never re-checked against
+  later CRZ changes (e.g. status cancelled/withdrawn after the filing) —
+  follow-up material.
+- No official-CRZ ZIP verification of the filing confirmation: it relies on
+  the ekosystem feed (and its up-to-a-day lag); the ZIP fallback is the same
+  future arc.
 - No document (binary) mirroring — link-only via `crz_url`.
 - No amendment linkage — EK's `kind_id`/`reference` hints are officially
   unreliable; treat any future linking as a separate, heuristic arc.
diff --git a/docs/manual-test-scenarios.md b/docs/manual-test-scenarios.md
index d902608..299cf55 100644
--- a/docs/manual-test-scenarios.md
+++ b/docs/manual-test-scenarios.md
@@ -132,6 +132,20 @@ Sign in as a seeded admin first. Base: `http://localhost:3000/zmluvy/admin`.
 > CRZ mirrors are exempt (their content is already-public upstream data,
 > ADR-008) and publish amendments unstamped.
 
+> **CRZ filing confirmation (#125).** On a published editorial record (e.g.
+> DEMO-2026-006 is already confirmed; publish another editorial record first)
+> the index row offers **Record CRZ filing**. Enter a CRZ id of a contract of
+> the demo organization: the page shows the CRZ record beside yours with
+> match / mismatch / cannot-be-verified rows. With all rows matching, confirm;
+> with a difference the reason field appears (required, 1000 characters max)
+> and the audit trail records `CRZ filing confirmed despite differences`. An
+> unknown id answers "not found — the data source may lag the CRZ by about a
+> day"; an id of another organization, or a cancelled/withdrawn record, is
+> refused outright. After confirming, the record leaves the deadline counters,
+> the public detail page says "Published in CRZ on <date>" with the official
+> link, and a later `import_crz` of the same id answers "already linked"
+> without writing. Needs network access to the ekosystem feed.
+
 ## 4. RSpec-side demo data
 
 `CONTRACTS_SK_DB=1 bundle exec rspec` gains the `ContractsSkDemoData` helper
diff --git a/docs/pilot-operations.md b/docs/pilot-operations.md
index 25ffa8d..867d338 100644
--- a/docs/pilot-operations.md
+++ b/docs/pilot-operations.md
@@ -387,7 +387,7 @@ docs/qa-checklist.md; demo dáta seed-neš podľa § 2.8.
 - [ ] Pilot má aspoň **2 osoby** s rolami enginu (odosielateľ ≠ posudzovateľ; pri predvolenom resolveri 2 org adminov s prijatými admin podmienkami), alebo je v initializeri vedome nastavené `Decidim::ContractsSk.allow_self_review = true` — **pass:** pravidlo štyroch očí (#123).
 - [ ] Osoba, ktorá urobila `submit` (demo: `contracts-editor@example.org`), na riadku záznamu nevidí tlačidlá `approve` / `return` / `reject`; priamy POST na tieto akcie je zamietnutý; druhý admin (demo: `contracts-admin@example.org`) ich vidí a `approve` prejde — **pass:** #123.
 
-- [ ] Lehota CRZ (#124): admin index má stĺpec „Lehota CRZ"; na demo dátach má DEMO-2026-003 oranžový štítok „7 dní" (po novom seede), DEMO-2026-002 a -004 červený „Po termíne", DEMO-2026-001 tlmenú pomlčku (neznámy dátum podpisu), mirror/zamietnuté/archivované záznamy a DEMO-2026-006 žiadny (publikované redakčné záznamy sa sledujú; DEMO-2026-006 nemá štítok len preto, že má CRZ URL, teda je zverejnený); čipy „CRZ po termíne" / „CRZ do 14 dní" majú správne počty a filter `?deadline=overdue` / `?deadline=due_soon` zúži zoznam; edit DEMO-2026-003 ukazuje riadok s lehotou — **pass:** #124 (pomôcka, nie právne poradenstvo; štítky starnú, na obnovu spusti seed znova).
+- [ ] Lehota CRZ (#124): admin index má stĺpec „Lehota CRZ"; na demo dátach má DEMO-2026-003 oranžový štítok „7 dní" (po novom seede), DEMO-2026-002 a -004 červený „Po termíne", DEMO-2026-001 tlmenú pomlčku (neznámy dátum podpisu), mirror/zamietnuté/archivované záznamy a DEMO-2026-006 žiadny (publikované redakčné záznamy sa sledujú; DEMO-2026-006 nemá štítok len preto, že je potvrdený ako zverejnený v CRZ (`crz_filed_at`, #125)); čipy „CRZ po termíne" / „CRZ do 14 dní" majú správne počty a filter `?deadline=overdue` / `?deadline=due_soon` zúži zoznam; edit DEMO-2026-003 ukazuje riadok s lehotou — **pass:** #124 (pomôcka, nie právne poradenstvo; štítky starnú, na obnovu spusti seed znova).
 
 - [ ] `GET /zmluvy/` → 200; vidno publikované demo záznamy (DEMO-2026-006, 008, 009) — **pass:** tri karty, lokalizované.
 - [ ] Prihlásenie adminom; `GET /zmluvy/admin/contracts` bez prihlásenia → redirect na sign-in — **pass:** A1.
diff --git a/docs/qa-checklist.md b/docs/qa-checklist.md
index 5a73c5c..0ca398a 100644
--- a/docs/qa-checklist.md
+++ b/docs/qa-checklist.md
@@ -27,7 +27,7 @@ ideally in both `en` and `sk` where noted.
 - [ ] **New**: one `h1`; every input has a `label` with a unique `id`; back-to-index link present.
 - [ ] **Edit**: one `h1`; `h2` sections (privacy redaction, documents, links, CRZ handoff); lifecycle state, author, organization and `published_at` are not form-writable.
 - [ ] **Index**: one `h1`; table headers localized; localized empty state when the organization has no contracts.
-- [ ] **Index (CRZ deadline, #124)**: a "CRZ deadline" column with `label` badges (overdue = alert, 0–14 days = warning, beyond = plain, unknown = muted dash with a title, filed/mirror/terminal = empty cell); the `deadline` filter and the two counter chips agree with the badges; Slovak plurals read "1 deň" / "3 dni" / "7 dní"; the edit page shows the deadline line (or the "deadline unknown — add signing date" prompt) and nothing for a record recorded as filed.
+- [ ] **Index (CRZ deadline, #124)**: a "CRZ deadline" column with `label` badges (overdue = alert, 0–14 days = warning, beyond = plain, unknown = muted dash with a title, filed/mirror/terminal = empty cell); the `deadline` filter and the two counter chips agree with the badges; Slovak plurals read "1 deň" / "3 dni" / "7 dní"; the edit page shows the deadline line (or the "deadline unknown — add signing date" prompt) and nothing for a record confirmed as filed.
 - [ ] **Index (sk pass)**: state labels and transition button labels render localized (no raw enum values).
 - [ ] Per-state transition buttons only (no event whose edge does not start at the record's state, none for roles that own no edge).
 - [ ] Four-eyes rule (civora-org/civora-platform#123): the user who submitted a record sees no return/approve/reject controls on its row (another admin does), a direct POST by them is denied, and with `allow_self_review = true` they may judge it and the audit viewer labels the row "(self-review)" / "(vlastné posúdenie)".
@@ -88,6 +88,15 @@ ideally in both `en` and `sk` where noted.
 - [ ] Keyboard-only full workflow pass: create → edit → parties → documents → redaction confirmation → submit → return → approve → publish → amendment → archive (return and approve are done by a second admin, four-eyes rule #123, or with `allow_self_review = true`).
 - [ ] Screen-reader spot-check: table headers announced, error list reachable after failed submit, focus returns to the trigger after a confirm dialog closes.
 
+## CRZ filing confirmation (#125)
+
+- [ ] Index row: **Record CRZ filing** shows only for an editor on a published, unfiled editorial record; hidden for reviewers, mirrors, drafts and filed records.
+- [ ] Filing page: id form (numeric only; a non-numeric id never reaches the network), side-by-side comparison with per-row labels (match = success, mismatch = alert, cannot be verified = warning), lag hint visible (en + sk, proper diacritics in sk).
+- [ ] Full match: confirm button only, no reason field; mismatch/unverifiable: reason textarea required, `maxlength` 1000; a stale preview, a missing reason and an already-linked id each flash a distinct message and change nothing.
+- [ ] Not found, source unavailable, other organization, withdrawn/cancelled and no-IČO each refuse with a localized flash and write no audit row.
+- [ ] After confirming: record leaves the deadline counters and filter; audit trail shows `CRZ filing confirmed` (or `... despite differences`, and `CRZ mirror absorbed ...` when a pristine mirror was replaced); public detail shows "Published in CRZ on <date>" (or "Publication in CRZ confirmed" without a date) with the official link.
+- [ ] `import_crz` / sync of a filed record's id: "already linked", no new mirror, `updated_at` unchanged; the rake summary counts it under `linked`.
+
 ## Known gaps and follow-ups
 
 - CRZ handoff section disappears on a failed contract update re-render — civora-org/civora-platform#77.
diff --git a/docs/roles-and-permissions.md b/docs/roles-and-permissions.md
index a85ec8b..0faaf58 100644
--- a/docs/roles-and-permissions.md
+++ b/docs/roles-and-permissions.md
@@ -39,6 +39,7 @@ answers for subjects `:contract`, `:party`, `:document`, `:amendment`,
 | `admin` | `contract` | `download_crz_handoff` | user's engine roles include `editor`, **no lifecycle condition** — fetching the generated handoff aid is role-gated only, any state (M02-05-C, civora-org/civora-platform#74) |
 | `admin` | `contract` | `generate_crz_handoff` | user's engine roles include `editor` **and** the record's state is lifecycle-editable — identical to the `update` rule (generating the aid is editorial work on an editable record, ADR-002) (civora-org/civora-platform#74) |
 | `admin` | `contract` | `import_crz` | user's engine roles include `editor`, **no lifecycle condition** — importing one CRZ record is a record-management act on the catalogue, not an edit of an existing record (ADR-008, civora-org/civora-platform#86) |
+| `admin` | `contract` | `confirm_crz_filing` | user's engine roles include `editor` **and** the record (`context[:contract]`, required — a bare state is denied) is editorial (`source != "crz"`), `published` and not yet confirmed as filed (`crz_filed_at` blank): only a published editorial record handed off to the CRZ can be linked to its official record, and once. The command re-checks all of it inside the row lock (civora-org/civora-platform#125) |
 | `admin` | `contract` | `submit`, `return`, `approve`, `reject`, `publish`, `archive` | `ContractLifecycle.allowed_roles(from: state, event: action)` intersects the user's engine roles |
 | `admin` | `contract` | `read` | user holds **any** engine role (admin index) |
 | `admin` | `party` | `create`, `update`, `destroy` | user's engine roles include `editor` **and** the parent contract's state is lifecycle-editable (`ContractLifecycle.editable?`) — the same rule as `contract`/`update`, applied to party management (civora-org/civora-platform#76) |
diff --git a/lib/decidim/contracts_sk.rb b/lib/decidim/contracts_sk.rb
index dbc425b..fa5f082 100644
--- a/lib/decidim/contracts_sk.rb
+++ b/lib/decidim/contracts_sk.rb
@@ -30,6 +30,8 @@ require_relative "contracts_sk/menu"
 require_relative "contracts_sk/crz_import/transport"
 require_relative "contracts_sk/crz_import/mapper"
 require_relative "contracts_sk/crz_import/client"
+require_relative "contracts_sk/crz_import/filing_comparison"
+require_relative "contracts_sk/crz_import/filing_lookup"
 require_relative "contracts_sk/crz_import/sync"
 require_relative "contracts_sk/crz_import/prune"
 
diff --git a/lib/decidim/contracts_sk/crz_deadline.rb b/lib/decidim/contracts_sk/crz_deadline.rb
index e87baae..fd2dffc 100644
--- a/lib/decidim/contracts_sk/crz_deadline.rb
+++ b/lib/decidim/contracts_sk/crz_deadline.rb
@@ -133,15 +133,16 @@ module Decidim
 
       # Whether a record is subject to deadline tracking: an editorial
       # record (the CRZ mirror is already filed by definition), in a
-      # non-terminal state, not yet recorded as filed. "Filed" is the
-      # +crz_url+ proxy (NULL or empty means not filed) until real filing
-      # confirmation lands (civora-org/civora-platform#125). The unfiled
-      # test is deliberately exactly "NULL or ''" so it matches the SQL
-      # scope; a whitespace-only value counts as filed in both.
-      def tracked?(source:, state:, crz_url:)
+      # non-terminal state, not yet CONFIRMED as filed in CRZ. "Filed" is
+      # the crz_filed_at stamp of the verified filing confirmation
+      # (Admin::ConfirmCrzFiling, civora-org/civora-platform#125) — a hard
+      # switch from the interim +crz_url+ proxy of #124: a typed CRZ link
+      # no longer counts as filed. The unfiled test is exactly "NULL" so it
+      # matches the SQL scope.
+      def tracked?(source:, state:, crz_filed_at:)
         source.to_s != mirror_source &&
           Decidim::ContractsSk::ContractLifecycle::DEADLINE_TRACKED_STATES.include?(state&.to_sym) &&
-          crz_url.to_s.empty?
+          crz_filed_at.nil?
       end
 
       # The provenance value of CRZ mirror rows (single source: the import
diff --git a/lib/decidim/contracts_sk/crz_import/filing_comparison.rb b/lib/decidim/contracts_sk/crz_import/filing_comparison.rb
new file mode 100644
index 0000000..d793d56
--- /dev/null
+++ b/lib/decidim/contracts_sk/crz_import/filing_comparison.rb
@@ -0,0 +1,124 @@
+# frozen_string_literal: true
+
+require "bigdecimal"
+require "active_support/core_ext/object/blank"
+
+module Decidim
+  module ContractsSk
+    module CrzImport
+      # Pure comparison of an editorial contract against the official CRZ
+      # record it is claimed to be filed as (civora-org/civora-platform#125).
+      # It backs the admin filing preview and the Admin::ConfirmCrzFiling
+      # command, which re-runs it inside the row lock — one rule, two
+      # callers. No I/O, no Rails model access beyond reading the contract's
+      # attributes and parties; +record+ is the Mapper.map output.
+      #
+      # Three rows, each :match / :mismatch / :unverifiable:
+      # - reference — both sides stripped of ALL whitespace and Unicode
+      #   case-folded, then compared (CRZ writes "ZP 2026/001" where the
+      #   editor typed "zp2026/001");
+      # - supplier IČO — a match when ANY of the editorial record's
+      #   contractor parties carries the IČO of the CRZ contractor party
+      #   (the mapper already normalized the CRZ side, including the
+      #   integer-CIN leading-zero repair of #145);
+      # - amount — BigDecimal equality to the cent (both sides rounded to
+      #   two places, never Float).
+      # A side that is blank (no reference, no contractor IČO, no amount)
+      # makes the row :unverifiable — it cannot confirm the filing, so the
+      # command treats it like a mismatch (a reason is required to proceed).
+      #
+      # Hard refusals are NOT rows: the CRZ record's status 4 (zrušená,
+      # cancelled) and 5 (stiahnutá, withdrawn) can never be confirmed as a
+      # filing, with or without a reason (.withdrawn?). A blank or other
+      # status is not refused — the status is advisory for those.
+      class FilingComparison
+        Row = Struct.new(:field, :editorial, :crz, :status, keyword_init: true)
+
+        FIELDS = %i[reference supplier_ico amount].freeze
+
+        # CRZ status codes that can never be a confirmed filing.
+        WITHDRAWN_STATUS_IDS = [4, 5].freeze
+
+        # True when the mapped CRZ record carries a status that can never
+        # be confirmed as a filing (see the class comment).
+        def self.withdrawn?(record)
+          WITHDRAWN_STATUS_IDS.include?(record[:status_id])
+        end
+
+        def initialize(contract:, record:)
+          @contract = contract
+          @record = record
+        end
+
+        def rows
+          @rows ||= [reference_row, supplier_row, amount_row]
+        end
+
+        def all_match?
+          rows.all? { |row| row.status == :match }
+        end
+
+        # Any row that is not a :match (a :mismatch OR :unverifiable): the
+        # filing then needs the editor's override reason.
+        def needs_reason?
+          !all_match?
+        end
+
+        private
+
+        attr_reader :contract, :record
+
+        def reference_row
+          editorial = contract.reference.to_s.strip
+          crz = record[:attributes][:reference].to_s.strip
+
+          Row.new(field: :reference, editorial: editorial.presence, crz: crz.presence,
+                  status: compare(normalize_reference(editorial), normalize_reference(crz)))
+        end
+
+        def supplier_row
+          editorial = editorial_contractor_icos
+          crz = record[:parties].find { |party| party[:role] == "contractor" }&.dig(:ico)
+
+          Row.new(field: :supplier_ico, editorial: editorial.presence, crz: crz.presence,
+                  status: supplier_status(editorial, crz))
+        end
+
+        def editorial_contractor_icos
+          contract.parties.select { |party| party.role.to_s == "contractor" }
+                  .filter_map { |party| party.ico.presence }
+        end
+
+        def supplier_status(editorial, crz)
+          return :unverifiable if editorial.empty? || crz.blank?
+
+          editorial.include?(crz) ? :match : :mismatch
+        end
+
+        def amount_row
+          editorial = contract.amount
+          crz = record[:attributes][:amount]
+
+          Row.new(field: :amount, editorial: editorial, crz: crz,
+                  status: compare(cents(editorial), cents(crz)))
+        end
+
+        # Whitespace-free, case-folded. Unicode case folding (not plain
+        # downcase) so "STRAŠE" and "straše" agree on every script.
+        def normalize_reference(value)
+          value.gsub(/\s+/, "").downcase(:fold)
+        end
+
+        def cents(value)
+          value.nil? ? nil : BigDecimal(value.to_s).round(2)
+        end
+
+        def compare(left, right)
+          return :unverifiable if left.blank? || right.blank?
+
+          left == right ? :match : :mismatch
+        end
+      end
+    end
+  end
+end
diff --git a/lib/decidim/contracts_sk/crz_import/filing_lookup.rb b/lib/decidim/contracts_sk/crz_import/filing_lookup.rb
new file mode 100644
index 0000000..ae38b94
--- /dev/null
+++ b/lib/decidim/contracts_sk/crz_import/filing_lookup.rb
@@ -0,0 +1,84 @@
+# frozen_string_literal: true
+
+require "active_support/core_ext/object/blank"
+
+module Decidim
+  module ContractsSk
+    module CrzImport
+      # The read-only verification fetch behind the CRZ filing confirmation
+      # (civora-org/civora-platform#125): resolves a CRZ id to the mapped
+      # official record, or to the reason it cannot serve as one. Shared by
+      # the admin preview (GET, writes nothing) and the
+      # Admin::ConfirmCrzFiling command, so both see the same refusals in the
+      # same order — and so the network call lives in one place, always
+      # OUTSIDE any row lock.
+      #
+      # It is a read-only use of the same primary source as the import
+      # (the ekosystem feed, ADR-008 decision 1): nothing is written, and no
+      # payload is logged (the Client logs URLs and statuses only).
+      #
+      # Refusals, in the order evaluated (all fail closed, none overridable):
+      #   :not_found      — the id is not numeric, or CRZ has no such record
+      #                     (ekosystem may lag CRZ by about a day);
+      #   :not_configured — the organization has no IČO configured;
+      #   :failed         — the source is unreachable / returned garbage;
+      #   :out_of_scope   — neither party carries the organization's IČO;
+      #   :withdrawn      — CRZ status 4 (cancelled) or 5 (withdrawn).
+      class FilingLookup
+        Result = Struct.new(:record, :refusal, keyword_init: true) do
+          def ok?
+            refusal.nil?
+          end
+        end
+
+        def self.call(crz_id:, organization:, client: nil)
+          new(crz_id: crz_id, organization: organization, client: client).call
+        end
+
+        def initialize(crz_id:, organization:, client: nil)
+          @crz_id = crz_id.to_s.strip
+          @organization = organization
+          @client = client
+        end
+
+        def call
+          return refused(:not_found) unless crz_id.match?(/\A\d+\z/)
+
+          ico = ContractsSk.crz_organization_ico(organization)
+          return refused(:not_configured) unless ico
+
+          record = fetch
+          return record if record.is_a?(Result)
+          return refused(:out_of_scope) unless CrzScope.in_scope?(record, ico)
+          return refused(:withdrawn) if FilingComparison.withdrawn?(record)
+
+          Result.new(record: record)
+        end
+
+        private
+
+        attr_reader :crz_id, :organization
+
+        def client
+          @client ||= Client.new
+        end
+
+        # The mapped record, or a refused Result. The mapper's own id must
+        # echo the requested one — a payload for a different record is never
+        # accepted as the answer.
+        def fetch
+          record = Mapper.map(client.contract(crz_id))
+          record[:source_id] == crz_id ? record : refused(:not_found)
+        rescue Client::NotFoundError
+          refused(:not_found)
+        rescue Client::Error, Mapper::Error
+          refused(:failed)
+        end
+
+        def refused(reason)
+          Result.new(refusal: reason)
+        end
+      end
+    end
+  end
+end
diff --git a/lib/decidim/contracts_sk/crz_import/mapper.rb b/lib/decidim/contracts_sk/crz_import/mapper.rb
index b0d546e..467a178 100644
--- a/lib/decidim/contracts_sk/crz_import/mapper.rb
+++ b/lib/decidim/contracts_sk/crz_import/mapper.rb
@@ -1,5 +1,6 @@
 # frozen_string_literal: true
 
+require "active_support/time"
 require "bigdecimal"
 require "date"
 require "digest"
@@ -28,6 +29,12 @@ module Decidim
       # order, so the upsert's checksum gate is stable across runs.
       # `changed_at` drives nothing in the upsert except being part of the
       # checksummed payload.
+      #
+      # Cop note: the module is the single, pure payload→record mapping
+      # (field correspondence plus its tolerant parsers); splitting the
+      # parsers off would scatter the spike-verified correspondence rather
+      # than simplify it.
+      # rubocop:disable Metrics/ModuleLength, Metrics/ClassLength
       module Mapper
         class Error < Decidim::ContractsSk::Error; end
 
@@ -45,7 +52,15 @@ module Decidim
 
         class << self
           # Maps one raw payload Hash into the upsert record:
-          #   { source_id:, attributes: {...}, parties: [...], checksum: }
+          #   { source_id:, attributes: {...}, parties: [...], checksum:,
+          #     status_id:, published_on: }
+          #
+          # status_id (CRZ status code, Integer or nil) and published_on
+          # (Date or nil) are read by the filing confirmation
+          # (civora-org/civora-platform#125) ONLY. They deliberately sit
+          # beside — never inside — :attributes, so the import's written
+          # columns and the checksum (a digest of the raw payload) are
+          # unchanged by them.
           # Raises Mapper::Error on structural invalidity.
           def map(payload)
             raise Error, "CRZ record is not a JSON object" unless payload.is_a?(Hash)
@@ -58,7 +73,7 @@ module Decidim
               attributes: contract_attributes(payload, source_id),
               parties: parties_for(payload),
               checksum: checksum(payload)
-            }
+            }.merge(filing_fields(payload))
           end
 
           # SHA-256 hex of the canonical JSON of the raw payload.
@@ -175,6 +190,30 @@ module Decidim
             nil
           end
 
+          # The filing-confirmation fields (see .map): the CRZ status code
+          # (an Integer or digit string, else nil) and the publication date
+          # (sentinel/blank/garbage → nil) — tolerant like every field.
+          def filing_fields(payload)
+            status = text(payload["status_id"])
+            { status_id: status.match?(/\A\d+\z/) ? status.to_i : nil,
+              published_on: parse_published_on(payload["published_at"]) }
+          end
+
+          # published_at is documented only as "publication date in CRZ"
+          # (spike, verified field) — a plain date today, but a timestamp is
+          # tolerated: it is converted to Europe/Bratislava before taking
+          # the date, so a near-midnight UTC instant lands on the Slovak
+          # calendar day. Sentinel, blank and garbage → nil.
+          def parse_published_on(raw)
+            value = text(raw)
+            return parse_date(value) if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
+            return nil if value.blank?
+
+            Time.find_zone!("Europe/Bratislava").parse(value)&.to_date
+          rescue ArgumentError
+            nil
+          end
+
           def text(raw)
             raw.to_s.strip
           end
@@ -194,6 +233,7 @@ module Decidim
           end
         end
       end
+      # rubocop:enable Metrics/ModuleLength, Metrics/ClassLength
     end
   end
 end
diff --git a/lib/decidim/contracts_sk/crz_import/sync.rb b/lib/decidim/contracts_sk/crz_import/sync.rb
index 8ccd938..35aa2cd 100644
--- a/lib/decidim/contracts_sk/crz_import/sync.rb
+++ b/lib/decidim/contracts_sk/crz_import/sync.rb
@@ -23,8 +23,14 @@ module Decidim
       #   a KNOWN record: the existing mirror row (if any) is stamped
       #   import_status="failed" in its own transaction, its data untouched
       #   (stale fallback).
-      # - collisions — editorial records holding the same source_id: never
-      #   touched; resolved manually (docs/crz-import.md).
+      # - collisions — UNFILED editorial records holding the same source_id:
+      #   never touched; resolved manually (docs/crz-import.md).
+      # - linked — a record whose CRZ id is held by an editorial record that
+      #   was CONFIRMED as filed (civora-org/civora-platform#125): that
+      #   record is already the canonical, linked record of the id, so the
+      #   sync writes nothing and counts it here — neither a mirror nor a
+      #   collision. An editorial record that merely carries the source_id
+      #   (not confirmed as filed) stays a collision.
       # - skipped — imported records that left the published state: the
       #   lifecycle guard refuses the update, data untouched.
       # - out_of_scope — a record whose parties do not carry the
@@ -52,9 +58,10 @@ module Decidim
       class Sync
         # Summary of one run/import: counts + the ids behind them + the
         # stopping error (nil on a clean run).
-        Result = Struct.new(:created, :updated, :unchanged, :collisions, :quarantined,
-                            :failed, :skipped, :out_of_scope, :created_ids, :collision_ids,
-                            :quarantined_ids, :failed_ids, :error, keyword_init: true)
+        Result = Struct.new(:created, :updated, :unchanged, :linked, :collisions, :quarantined,
+                            :failed, :skipped, :out_of_scope, :created_ids, :linked_ids,
+                            :collision_ids, :quarantined_ids, :failed_ids, :error,
+                            keyword_init: true)
 
         class << self
           # Full batch sync of one organization. `since` is an ISO8601
@@ -67,7 +74,7 @@ module Decidim
 
           # Single-record import by CRZ id (the admin action's path).
           # Returns an outcome symbol for the controller's flash mapping:
-          # :created/:updated/:unchanged/:collision/:lifecycle_guard/
+          # :created/:updated/:unchanged/:linked/:collision/:lifecycle_guard/
           # :record_invalid/:quarantined/:not_found/:failed/:out_of_scope/
           # :not_configured.
           def import_one(source_id:, organization:, actor:, client: nil)
@@ -85,10 +92,10 @@ module Decidim
           @actor = actor
           @client = client
           @ico = ContractsSk.crz_organization_ico(organization)
-          @result = Result.new(created: 0, updated: 0, unchanged: 0, collisions: 0,
+          @result = Result.new(created: 0, updated: 0, unchanged: 0, linked: 0, collisions: 0,
                                quarantined: 0, failed: 0, skipped: 0, out_of_scope: 0,
-                               created_ids: [], collision_ids: [], quarantined_ids: [],
-                               failed_ids: [], error: nil)
+                               created_ids: [], linked_ids: [], collision_ids: [],
+                               quarantined_ids: [], failed_ids: [], error: nil)
         end
 
         def run(since)
@@ -153,10 +160,11 @@ module Decidim
           record_error!(payload, e)
         end
 
-        # In scope when the organization's IČO is on either mirrored party.
-        # The party IČOs are the mapper's normalized ekosystem *_cin values.
+        # In scope when the organization's IČO is on either mirrored party
+        # (the predicate is shared with the filing confirmation:
+        # CrzScope.in_scope?).
         def in_scope?(record)
-          record[:parties].any? { |party| party[:ico] == @ico }
+          CrzScope.in_scope?(record, @ico)
         end
 
         def out_of_scope!
@@ -187,6 +195,9 @@ module Decidim
             result.created_ids << contract.id
           when :updated then result.updated += 1
           when :unchanged then result.unchanged += 1
+          when :linked
+            result.linked += 1
+            result.linked_ids << contract.id
           end
         end
 
@@ -216,19 +227,32 @@ module Decidim
         end
 
         def apply_record_invalid!(record, contract)
-          if contract
-            result.failed += 1
-            result.failed_ids << contract.id
-            mark_failed!(record[:source_id], contract)
-          else
-            # Nothing exists to stamp — the record is unimportable, so it
-            # lands in the quarantine bucket.
-            result.quarantined += 1
-            result.quarantined_ids << record[:source_id]
-          end
+          mirror = mirror_only(contract)
+          mirror ? fail_mirror!(record, mirror) : quarantine_unimportable!(record)
           log(:warn, "record #{record[:source_id]}: invalid data, no write")
         end
 
+        def fail_mirror!(record, mirror)
+          result.failed += 1
+          result.failed_ids << mirror.id
+          mark_failed!(record[:source_id], mirror)
+        end
+
+        # Nothing exists to stamp — the record is unimportable, so it lands
+        # in the quarantine bucket.
+        def quarantine_unimportable!(record)
+          result.quarantined += 1
+          result.quarantined_ids << record[:source_id]
+        end
+
+        # Only a mirror can be stamped failed (G4, civora-org/
+        # civora-platform#125): an editorial record surfacing here (a create
+        # that raced one) is left alone and the record counts as
+        # unimportable.
+        def mirror_only(contract)
+          contract if contract&.source == Mapper::SOURCE
+        end
+
         # Quarantine: skip the record, count it, log the id only. When a
         # mirror row already exists for the same source_id, it is stamped
         # failed (stale fallback) and counted as failed instead — prior
@@ -276,7 +300,7 @@ module Decidim
         # the stamped row, or nil when nothing exists to stamp.
         def mark_failed!(source_id, contract = nil)
           fresh = contract ? Contract.find(contract.id) : find_mirror(source_id)
-          return unless fresh
+          return unless fresh&.source == Mapper::SOURCE
 
           fresh.update!(import_status: "failed")
           fresh
@@ -285,8 +309,14 @@ module Decidim
           nil
         end
 
+        # Only a source="crz" row is a mirror: the failure/quarantine paths
+        # stamp import_status on whatever this returns, and an editorial
+        # record that merely carries the source_id (a collision, or a
+        # filing-confirmed link — civora-org/civora-platform#125) must never
+        # be stamped by the import.
         def find_mirror(source_id)
-          source_id && Contract.find_by(organization: @organization, source_id: source_id)
+          source_id && Contract.find_by(organization: @organization, source_id: source_id,
+                                        source: Mapper::SOURCE)
         end
 
         def log(level, message)
diff --git a/lib/decidim/contracts_sk/crz_scope.rb b/lib/decidim/contracts_sk/crz_scope.rb
index 48511db..f22e052 100644
--- a/lib/decidim/contracts_sk/crz_scope.rb
+++ b/lib/decidim/contracts_sk/crz_scope.rb
@@ -21,6 +21,10 @@ module Decidim
     # resolver yields nil — the import then refuses to run rather than
     # mirroring the whole national register.
     #
+    # The scope predicate itself lives in CrzScope.in_scope? (below), shared
+    # by the sync and the filing confirmation (civora-org/civora-platform
+    # #125).
+    #
     # Config-time only: never mutate the resolver at request time.
     class << self
       attr_accessor :crz_organization_ico_resolver
@@ -38,5 +42,20 @@ module Decidim
     rescue StandardError
       nil
     end
+
+    # The record-in-scope predicate (civora-org/civora-platform#145, shared
+    # with #125): a mapped CRZ record is in scope for an organization when
+    # the organization's IČO is on either mirrored party. Pure; +ico+ is
+    # the already-normalized organization IČO — nil (not configured)
+    # answers false, so callers fail closed.
+    module CrzScope
+      module_function
+
+      def in_scope?(record, ico)
+        return false if ico.blank?
+
+        record[:parties].any? { |party| party[:ico] == ico }
+      end
+    end
   end
 end
diff --git a/lib/tasks/decidim_contracts_sk_crz_import.rake b/lib/tasks/decidim_contracts_sk_crz_import.rake
index 8ce75d1..dad25d4 100644
--- a/lib/tasks/decidim_contracts_sk_crz_import.rake
+++ b/lib/tasks/decidim_contracts_sk_crz_import.rake
@@ -62,10 +62,14 @@ namespace :decidim_contracts_sk do
       )
 
       puts "CRZ import for organization ##{organization.id} (since #{since}):"
-      puts "  created=#{result.created} updated=#{result.updated} unchanged=#{result.unchanged}"
+      puts "  created=#{result.created} updated=#{result.updated} unchanged=#{result.unchanged} " \
+           "linked=#{result.linked}"
       puts "  collisions=#{result.collisions} quarantined=#{result.quarantined} " \
            "failed=#{result.failed} skipped=#{result.skipped} out_of_scope=#{result.out_of_scope}"
       puts "  created ids: #{result.created_ids.join(", ")}" if result.created_ids.any?
+      if result.linked_ids.any?
+        puts "  linked ids (editorial records confirmed as filed in CRZ): #{result.linked_ids.join(", ")}"
+      end
       puts "  collision ids: #{result.collision_ids.join(", ")}" if result.collision_ids.any?
       puts "  quarantined source ids: #{result.quarantined_ids.compact.join(", ")}" if result.quarantined_ids.any?
       puts "  failed ids: #{result.failed_ids.compact.join(", ")}" if result.failed_ids.any?
diff --git a/lib/tasks/decidim_contracts_sk_seed_demo.rake b/lib/tasks/decidim_contracts_sk_seed_demo.rake
index ff7562b..183f24d 100644
--- a/lib/tasks/decidim_contracts_sk_seed_demo.rake
+++ b/lib/tasks/decidim_contracts_sk_seed_demo.rake
@@ -154,7 +154,12 @@ namespace :decidim_contracts_sk do
       subject_matter: "Zber a odvoz komunálneho odpadu na území mesta",
       amount: BigDecimal("96800.00"), signed_on: Date.new(2025, 12, 15),
       effective_from: Date.new(2026, 1, 1),
-      crz_url: "https://crz.gov.sk/demo-ukazkovy-zaznam"
+      crz_url: "https://crz.gov.sk/zmluva/900000003/", source_id: "900000003",
+      # Confirmed as filed in CRZ (civora-org/civora-platform#125): the
+      # demo record that carries no deadline badge, and the public
+      # "Zverejnené v CRZ dňa" line. Constant values keep re-seeds
+      # idempotent.
+      crz_filed_at: Time.zone.local(2026, 1, 10, 12), crz_published_on: Date.new(2026, 1, 10)
     )
 
     seed.call(
diff --git a/spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb b/spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb
new file mode 100644
index 0000000..9695869
--- /dev/null
+++ b/spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb
@@ -0,0 +1,121 @@
+# frozen_string_literal: true
+
+# ---------------------------------------------------------------------------
+# Deterministic structural + :db specs for the CRZ filing-confirmation
+# migration (civora-org/civora-platform#125), mirroring the review-decision
+# migration spec: the default run reads the migration as text only; the
+# :db group (CONTRACTS_SK_DB=1) runs up -> down -> up on in-memory SQLite.
+# ---------------------------------------------------------------------------
+
+require "spec_helper"
+
+# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
+RSpec.describe "db/migrate/*_add_crz_filing_to_decidim_contracts_sk_contracts.rb" do
+  subject(:migration_source) { File.read(migration_path) }
+
+  def migration_files
+    Dir.glob(File.join(engine_root, "db", "migrate",
+                       "*_add_crz_filing_to_decidim_contracts_sk_contracts.rb"))
+  end
+
+  def migration_path
+    migration_files.first
+  end
+
+  def migration_class_name
+    "AddCrzFilingToDecidimContractsSkContracts"
+  end
+
+  def base_migration_path
+    Dir.glob(File.join(engine_root, "db", "migrate", "*_create_decidim_contracts_sk_contracts.rb")).first
+  end
+
+  def table_name
+    :decidim_contracts_sk_contracts
+  end
+
+  def stripped_lines
+    migration_source.lines.map(&:strip)
+  end
+
+  def column_line(name)
+    stripped_lines.find { |line| line.match?(/\Aadd_column\s+:#{table_name},\s+:#{name}\b/) }
+  end
+
+  describe "file surface and class shape" do
+    it "has exactly one migration file whose class name matches" do
+      expect(migration_files.size).to eq(1)
+      timestamp, snake_name = File.basename(migration_path, ".rb").split("_", 2)
+
+      expect(timestamp).to match(/\A\d{14}\z/)
+      expect(snake_name.camelize).to eq(migration_class_name)
+      expect(migration_source).to match(/\A#\s+frozen_string_literal: true\s*$/)
+    end
+
+    it "is a single reversible `def change` on ActiveRecord::Migration[7.2]" do
+      expect(migration_source)
+        .to match(/class\s+#{migration_class_name}\s*<\s*ActiveRecord::Migration\[7\.2\]\s*$/)
+      expect(migration_source.scan(/\bdef\s+change\b/).size).to eq(1)
+      expect(migration_source).not_to match(/\bdef\s+(up|down)\b/)
+    end
+  end
+
+  describe "columns" do
+    it "adds exactly the three nullable system columns, with no default, backfill or index" do
+      expect(stripped_lines.grep(/\Aadd_column\s/).size).to eq(3)
+      expect(column_line(:crz_filed_at)).to match(/:datetime\s*$/)
+      expect(column_line(:crz_published_on)).to match(/:date\s*$/)
+      expect(column_line(:crz_filing_reason)).to match(/:string,\s+limit:\s+1000\s*$/)
+      expect(migration_source).not_to match(/\bdefault:/)
+      expect(migration_source).not_to match(/\b(change_column_default|update_all|execute|add_index)\b/)
+    end
+  end
+
+  describe "runnable migration", :db do
+    let(:migration_class) do
+      require migration_path
+      Object.const_get(migration_class_name)
+    end
+
+    let(:base_migration_class) do
+      require base_migration_path
+      Object.const_get("CreateDecidimContractsSkContracts")
+    end
+
+    def column_by_name(name)
+      ActiveRecord::Base.connection.columns(table_name).find { |column| column.name == name }
+    end
+
+    it "adds the nullable columns, leaves existing rows unfiled and reverses cleanly" do
+      base_migration_class.migrate(:up)
+      ActiveRecord::Base.connection.execute(<<~SQL)
+        INSERT INTO decidim_contracts_sk_contracts
+          (decidim_organization_id, decidim_author_id, title, reference, state,
+           source, created_at, updated_at)
+        VALUES
+          (#{organization.id}, #{author.id}, 'Road reconstruction', 'ZP-2026-001', 'draft',
+           'editorial', '2026-09-01 08:00:00.000000', '2026-09-01 08:00:00.000000')
+      SQL
+
+      migration_class.migrate(:up)
+
+      row = ActiveRecord::Base.connection.select_one("SELECT * FROM decidim_contracts_sk_contracts")
+      expect(row.values_at("crz_filed_at", "crz_published_on", "crz_filing_reason")).to eq([nil, nil, nil])
+
+      expect(column_by_name("crz_filed_at").type).to eq(:datetime)
+      expect(column_by_name("crz_published_on").type).to eq(:date)
+      expect(column_by_name("crz_filing_reason").limit).to eq(1000)
+      %w[crz_filed_at crz_published_on crz_filing_reason].each do |name|
+        expect(column_by_name(name).null).to be(true)
+        expect(column_by_name(name).default).to be_nil
+      end
+
+      migration_class.migrate(:down)
+      expect(%w[crz_filed_at crz_published_on crz_filing_reason].map { |n| column_by_name(n) }).to all(be_nil)
+
+      migration_class.migrate(:up)
+      expect(column_by_name("crz_filed_at")).to be_present
+    end
+  end
+end
+# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
diff --git a/spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb b/spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb
index f1b28d1..98e8991 100644
--- a/spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb
+++ b/spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb
@@ -71,11 +71,12 @@ RSpec.describe "db/migrate/*_add_submitted_by_to_decidim_contracts_sk_contracts.
       expect(migration_source).to match(/\A#\s+frozen_string_literal: true\s*$/)
     end
 
-    it "sorts after every earlier engine migration" do
-      timestamps = Dir.glob(File.join(engine_root, "db", "migrate", "*.rb"))
-                      .map { |path| File.basename(path).split("_", 2).first }.sort
+    it "sorts after the migrations it reads (the contracts and audit-trail tables)" do
+      own = File.basename(migration_path).split("_", 2).first
 
-      expect(timestamps.last).to eq(File.basename(migration_path).split("_", 2).first)
+      %w[create_decidim_contracts_sk_contracts create_decidim_contracts_sk_audit_events].each do |suffix|
+        expect(File.basename(migration_path_for(suffix)).split("_", 2).first).to be < own
+      end
     end
   end
 
diff --git a/spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb b/spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb
index 7ac35c4..8e2cb3f 100644
--- a/spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb
+++ b/spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb
@@ -21,9 +21,10 @@ module Decidim
     # mapping must cover every one of them, otherwise a row would fall
     # back to the humanized label.
     EXPECTED_AUDIT_ACTION_KEYS = %w[
-      amendment.publish contract.approve contract.approve_self contract.archive contract.publish
-      contract.redaction_confirmed contract.reject contract.reject_self contract.return
-      contract.return_self contract.submit crz_import_create crz_import_update
+      amendment.publish contract.approve contract.approve_self contract.archive
+      contract.crz_filed contract.crz_filed_override contract.crz_mirror_absorbed
+      contract.publish contract.redaction_confirmed contract.reject contract.reject_self
+      contract.return contract.return_self contract.submit crz_import_create crz_import_update
     ].freeze
 
     RSpec.describe Admin::AuditEventsController do
diff --git a/spec/decidim/contracts_sk/admin/confirm_crz_filing_spec.rb b/spec/decidim/contracts_sk/admin/confirm_crz_filing_spec.rb
new file mode 100644
index 0000000..35a2df6
--- /dev/null
+++ b/spec/decidim/contracts_sk/admin/confirm_crz_filing_spec.rb
@@ -0,0 +1,335 @@
+# frozen_string_literal: true
+
+# ---------------------------------------------------------------------------
+# :db command specs for ConfirmCrzFiling (civora-org/civora-platform#125),
+# run against the real migrations on an in-memory SQLite adapter (see
+# spec/support/contracts_sk_db_helpers.rb; excluded from the default
+# offline run). The CRZ client is stubbed at its exact boundary (the
+# command's injection seam) with recorded-shape payloads from
+# spec/support/crz_import_payloads.rb; the real FilingLookup,
+# FilingComparison and lock machinery run.
+#
+# The lock-doctrine examples follow the deterministic "request-start copy"
+# shape of the TransitionContract specs: a stale pre-loaded object, the row
+# moved directly underneath it — no threads. The unique-index race is
+# simulated at the write boundary (update! raising RecordNotUnique).
+#
+# Synthetic data only ("Obec Ukážková", fake IČO patterns), no real PII.
+# ---------------------------------------------------------------------------
+
+require "spec_helper"
+
+# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, Metrics/AbcSize
+RSpec.describe Decidim::ContractsSk::Admin::ConfirmCrzFiling, :db do
+  include_context "with the CRZ scope configured"
+
+  let(:client_class) { Decidim::ContractsSk::CrzImport::Client }
+  let(:client) { instance_double(client_class) }
+  let(:crz_id) { "2142424" }
+  let(:payload) { crz_payload(crz_id, "status_id" => 2, "published_at" => "2026-04-20") }
+  let(:token) { Decidim::ContractsSk::CrzImport::Mapper.checksum(payload) }
+  let(:contract_class) { Decidim::ContractsSk::Contract }
+  let(:audit_class) { Decidim::ContractsSk::AuditEvent }
+  let(:roles) { %i[editor] }
+  let(:contract) { create_editorial }
+
+  around do |example|
+    original = Decidim::ContractsSk.role_resolver
+    Decidim::ContractsSk.role_resolver = ->(_user, _context) { roles }
+    example.run
+  ensure
+    Decidim::ContractsSk.role_resolver = original
+  end
+
+  before do
+    migrate_engine_schema!
+    allow(client).to receive(:contract).with(crz_id).and_return(payload)
+  end
+
+  # An editorial, published record that matches the payload on every row.
+  def create_editorial(overrides = {})
+    record = contract_class.create!(
+      contract_attributes({ reference: "UKÁŽKA-2026/#{crz_id}", state: "published",
+                            amount: BigDecimal("1043.68") }.merge(overrides))
+    )
+    record.parties.create!(role: "object", name: "Obec Ukážková", ico: "00000001")
+    record.parties.create!(role: "contractor", name: "Demo Dodávky s.r.o.", ico: "00000002")
+    record
+  end
+
+  def call_command(target = contract, reason: nil, checksum: token, id: crz_id, user: author)
+    described_class.call(target, crz_id: id, checksum: checksum, reason: reason, user: user, client: client)
+  end
+
+  def expect_untouched(record)
+    fresh = record.reload
+    expect(fresh.crz_filed_at).to be_nil
+    expect(fresh.source_id).to be_nil
+    expect(fresh.crz_url).to be_nil
+    expect(fresh.crz_filing_reason).to be_nil
+    expect(audit_class.count).to eq(0)
+  end
+
+  describe "a full match" do
+    it "stamps the filing, keeps the record editorial and writes one crz_filed audit row" do
+      events = call_command
+
+      expect(events[:ok]).to eq(:filed)
+
+      contract.reload
+      expect(contract.crz_filed_at).to be_within(5.seconds).of(Time.current)
+      expect(contract.crz_published_on).to eq(Date.new(2026, 4, 20))
+      expect(contract.crz_url).to eq("https://crz.gov.sk/zmluva/2142424/")
+      expect(contract.source_id).to eq("2142424")
+      expect(contract.crz_filing_reason).to be_nil
+      expect(contract.source).to eq("editorial")
+      expect(contract.state).to eq("published")
+
+      audit = audit_class.order(:id).last
+      expect(audit_class.count).to eq(1)
+      expect(audit.action).to eq("contract.crz_filed")
+      expect(audit.target).to eq(contract)
+      expect(audit.actor).to eq(author)
+      expect(audit.organization).to eq(organization)
+    end
+
+    it "stores no published date when CRZ carries the 0000-00-00 sentinel" do
+      payload["published_at"] = "0000-00-00"
+
+      call_command
+
+      expect(contract.reload.crz_published_on).to be_nil
+      expect(contract.crz_filed_at).to be_present
+    end
+
+    it "refuses a reason on a clean match (no write, no audit)" do
+      events = call_command(reason: "no differences, but let me explain")
+
+      expect(events[:invalid]).to eq(:reason_rejected)
+      expect_untouched(contract)
+    end
+  end
+
+  describe "a mismatch or an unverifiable row" do
+    before { contract.update!(amount: BigDecimal("999.00")) }
+
+    it "refuses without a reason and changes nothing" do
+      expect(call_command[:invalid]).to eq(:reason_required)
+      expect(call_command(reason: "   ")[:invalid]).to eq(:reason_required)
+      expect_untouched(contract)
+    end
+
+    it "files with a reason as an override: reason stored stripped, crz_filed_override audited" do
+      events = call_command(reason: "  Amount was corrected in the CRZ after filing.  ")
+
+      expect(events[:ok]).to eq(:filed_override)
+
+      contract.reload
+      expect(contract.crz_filed_at).to be_present
+      expect(contract.crz_filing_reason).to eq("Amount was corrected in the CRZ after filing.")
+      expect(audit_class.pluck(:action)).to eq(["contract.crz_filed_override"])
+    end
+
+    it "treats an unverifiable row like a mismatch" do
+      contract.update!(amount: nil)
+
+      expect(call_command[:invalid]).to eq(:reason_required)
+      expect(call_command(reason: "amount not yet entered")[:ok]).to eq(:filed_override)
+    end
+
+    it "refuses an over-long reason before any network call" do
+      events = call_command(reason: "x" * 1001)
+
+      expect(events[:invalid]).to eq(:reason_rejected)
+      expect(client).not_to have_received(:contract)
+      expect_untouched(contract)
+    end
+  end
+
+  describe "refusals before the lock" do
+    it "answers :not_found for an unknown CRZ id and changes nothing" do
+      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::NotFoundError)
+
+      expect(call_command[:invalid]).to eq(:not_found)
+      expect_untouched(contract)
+    end
+
+    it "answers :failed on a network failure, writing neither fields nor audit" do
+      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::TransportError)
+
+      expect(call_command[:invalid]).to eq(:failed)
+      expect_untouched(contract)
+    end
+
+    it "answers :failed for an unreadable payload" do
+      allow(client).to receive(:contract).with(crz_id).and_return({ "subject" => "no id" })
+
+      expect(call_command[:invalid]).to eq(:failed)
+    end
+
+    it "answers :not_configured without a network call when the organization has no IČO" do
+      Decidim::ContractsSk.crz_organization_ico_resolver = ->(_organization) {}
+
+      expect(call_command[:invalid]).to eq(:not_configured)
+      expect(client).not_to have_received(:contract)
+      expect_untouched(contract)
+    end
+
+    it "answers :out_of_scope for a record of another organization" do
+      payload["contracting_authority_cin"] = "00 000 009"
+      payload["supplier_cin"] = "00 000 008"
+
+      expect(call_command[:invalid]).to eq(:out_of_scope)
+      expect_untouched(contract)
+    end
+
+    it "answers :withdrawn for CRZ status 4 and 5, even with a reason" do
+      [4, 5].each do |status|
+        payload["status_id"] = status
+
+        expect(call_command(reason: "please")[:invalid]).to eq(:withdrawn)
+      end
+      expect_untouched(contract)
+    end
+
+    it "refuses a non-numeric CRZ id without a network call" do
+      expect(call_command(id: "12/34")[:invalid]).to eq(:not_found)
+      expect(client).not_to have_received(:contract)
+    end
+
+    context "when the user has no editor role" do
+      let(:roles) { %i[reviewer] }
+
+      it "refuses without a network call (defense in depth behind the permission layer)" do
+        expect(call_command[:invalid]).to eq(:not_fileable)
+        expect(client).not_to have_received(:contract)
+        expect_untouched(contract)
+      end
+    end
+  end
+
+  describe "in-lock guards" do
+    it "refuses a draft or an archived record" do
+      %w[draft archived].each_with_index do |state, index|
+        record = create_editorial(reference: "ZP-S-#{index}", state: state)
+
+        expect(call_command(record)[:invalid]).to eq(:not_fileable)
+        expect(record.reload.crz_filed_at).to be_nil
+      end
+    end
+
+    it "refuses a CRZ mirror (never an editorial record)" do
+      mirror = create_imported_record(crz_id)
+
+      expect(call_command(mirror)[:invalid]).to eq(:not_fileable)
+    end
+
+    it "refuses an already filed record, keeping the first confirmation" do
+      call_command
+      first = contract.reload.crz_filed_at
+
+      expect(call_command[:invalid]).to eq(:already_filed)
+      expect(contract.reload.crz_filed_at).to eq(first)
+      expect(audit_class.count).to eq(1)
+    end
+
+    it "re-reads the row under the lock: a stale copy of a record archived meanwhile is refused" do
+      stale = contract_class.find(contract.id)
+      contract.update_columns(state: "archived")
+
+      expect(call_command(stale)[:invalid]).to eq(:not_fileable)
+      expect(contract.reload.crz_filed_at).to be_nil
+      expect(audit_class.count).to eq(0)
+    end
+
+    it "re-reads the row under the lock: a stale copy of a record filed meanwhile is refused" do
+      stale = contract_class.find(contract.id)
+      contract.update_columns(crz_filed_at: 1.hour.ago, source_id: crz_id)
+
+      expect(call_command(stale)[:invalid]).to eq(:already_filed)
+      expect(audit_class.count).to eq(0)
+    end
+
+    it "re-runs the comparison on the row as it is NOW: an amount edited after the preview needs a reason" do
+      stale = contract_class.find(contract.id)
+      contract.update_columns(amount: BigDecimal("5.00"))
+
+      expect(call_command(stale)[:invalid]).to eq(:reason_required)
+      expect(contract.reload.crz_filed_at).to be_nil
+    end
+
+    it "refuses with :stale when the official record changed since the preview" do
+      expect(call_command(checksum: "token-of-an-older-payload")[:invalid]).to eq(:stale)
+      expect(call_command(checksum: nil)[:invalid]).to eq(:stale)
+      expect_untouched(contract)
+    end
+
+    it "refuses a record carrying a different source_id" do
+      contract.update_columns(source_id: "999")
+
+      expect(call_command[:invalid]).to eq(:not_fileable)
+    end
+
+    it "rolls the stamp back when the audit write fails (atomicity)" do
+      allow(audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
+
+      expect(call_command[:invalid]).to eq(:not_fileable)
+      expect(contract.reload.crz_filed_at).to be_nil
+      expect(contract.source_id).to be_nil
+    end
+  end
+
+  describe "the CRZ id already held by another record" do
+    it "refuses when another editorial record holds the id" do
+      create_editorial(reference: "ZP-HOLDER", source_id: crz_id)
+
+      expect(call_command[:invalid]).to eq(:already_linked)
+      expect(contract.reload.crz_filed_at).to be_nil
+      expect(audit_class.count).to eq(0)
+    end
+
+    it "absorbs a pristine mirror: the mirror is destroyed, the id claimed, both audit rows written" do
+      mirror = create_imported_record(crz_id)
+      mirror.parties.create!(role: "contractor", name: "Demo Dodávky s.r.o.", ico: "00000002")
+
+      events = call_command
+
+      expect(events[:ok]).to eq(:filed)
+      expect(contract_class.exists?(mirror.id)).to be(false)
+      expect(Decidim::ContractsSk::Party.where(contract_id: mirror.id)).to be_empty
+      expect(contract.reload.source_id).to eq(crz_id)
+      expect(contract.source).to eq("editorial")
+      expect(audit_class.order(:id).pluck(:action)).to eq(%w[contract.crz_mirror_absorbed contract.crz_filed])
+      expect(audit_class.pluck(:target_id).uniq).to eq([contract.id])
+    end
+
+    {
+      "an amendment" => lambda { |mirror, org, user|
+        mirror.amendments.create!(version: 1, summary: "Dodatok", state: "draft", organization: org, author: user)
+      },
+      "a link" => lambda { |mirror, org, _user|
+        mirror.links.create!(target_type: "Decidim::Organization", target_id: org.id)
+      },
+      "a document" => ->(mirror, _org, _user) { mirror.documents.create!(title: "Sken", kind: "annex") }
+    }.each do |label, attach|
+      it "refuses a mirror an editor has worked on (#{label}) and leaves it intact" do
+        mirror = create_imported_record(crz_id)
+        attach.call(mirror, organization, author)
+
+        expect(call_command[:invalid]).to eq(:already_linked)
+        expect(contract_class.exists?(mirror.id)).to be(true)
+        expect_untouched(contract)
+      end
+    end
+
+    it "reroutes a lost unique-index race to :already_linked, rolling the absorption back" do
+      mirror = create_imported_record(crz_id)
+      allow(contract).to receive(:update!).and_raise(ActiveRecord::RecordNotUnique)
+
+      expect(call_command[:invalid]).to eq(:already_linked)
+      expect(contract_class.exists?(mirror.id)).to be(true)
+      expect(audit_class.count).to eq(0)
+    end
+  end
+end
+# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers, Metrics/AbcSize
diff --git a/spec/decidim/contracts_sk/admin/contracts_controller_spec.rb b/spec/decidim/contracts_sk/admin/contracts_controller_spec.rb
index 1d7e7dd..b842d29 100644
--- a/spec/decidim/contracts_sk/admin/contracts_controller_spec.rb
+++ b/spec/decidim/contracts_sk/admin/contracts_controller_spec.rb
@@ -20,13 +20,16 @@ module Decidim
         expect(described_class.superclass).to eq(Admin::ApplicationController)
       end
 
-      it "implements exactly the CRUD + transition + CRZ-handoff + import + redaction actions (no show, no destroy)" do
+      # rubocop:disable RSpec/ExampleLength
+      it "implements exactly the CRUD, transition, CRZ handoff/import/filing and redaction actions (no show/destroy)" do
         expect(described_class.public_instance_methods(false).map(&:to_s).sort)
           .to eq(%w[
-                   approve archive confirm_redaction create download_crz_handoff edit
-                   generate_crz_handoff import_crz index new publish reject return submit update
+                   approve archive confirm_crz_filing confirm_redaction create crz_filing
+                   download_crz_handoff edit generate_crz_handoff import_crz index new publish reject
+                   return submit update
                  ])
       end
+      # rubocop:enable RSpec/ExampleLength
 
       it "does not sit on the engine's public base controller chain" do
         expect(described_class.ancestors)
diff --git a/spec/decidim/contracts_sk/contract_crz_deadline_spec.rb b/spec/decidim/contracts_sk/contract_crz_deadline_spec.rb
index a0173d7..135e82a 100644
--- a/spec/decidim/contracts_sk/contract_crz_deadline_spec.rb
+++ b/spec/decidim/contracts_sk/contract_crz_deadline_spec.rb
@@ -43,12 +43,12 @@ RSpec.describe Decidim::ContractsSk::Contract, :db do
         .to eq(%w[T-0 T-1 T-2 T-3 T-4 T-UNSIGNED])
     end
 
-    it "excludes records recorded as filed (crz_url present) but keeps an empty crz_url tracked" do
-      create_contract!("FILED", crz_url: "https://crz.gov.sk/zmluva/1/")
-      create_contract!("EMPTY", crz_url: "")
+    it "excludes records confirmed as filed (crz_filed_at) but keeps a typed crz_url tracked (#125)" do
+      create_contract!("FILED", crz_url: "https://crz.gov.sk/zmluva/1/", crz_filed_at: Time.current)
+      create_contract!("TYPED-URL", crz_url: "https://crz.gov.sk/zmluva/2/")
       create_contract!("NULL", crz_url: nil)
 
-      expect(references(contract_class.crz_deadline_tracked)).to eq(%w[EMPTY NULL])
+      expect(references(contract_class.crz_deadline_tracked)).to eq(%w[NULL TYPED-URL])
     end
 
     it "excludes CRZ mirrors and terminal states" do
@@ -82,7 +82,7 @@ RSpec.describe Decidim::ContractsSk::Contract, :db do
     end
 
     it "leaves filed, mirror and terminal records out of both scopes" do
-      create_contract!("FILED", crz_url: "https://crz.gov.sk/zmluva/1/", signed_on: Date.new(2025, 1, 1))
+      create_contract!("FILED", crz_filed_at: Time.current, signed_on: Date.new(2025, 1, 1))
       create_contract!("MIRROR", source: "crz", source_id: "900000001", state: "published",
                                  signed_on: Date.new(2025, 1, 1))
       create_contract!("REJECTED", state: "rejected", signed_on: Date.new(2025, 1, 1))
@@ -118,7 +118,7 @@ RSpec.describe Decidim::ContractsSk::Contract, :db do
 
     it "reports :unknown for a tracked record without a signing date and :untracked otherwise" do
       expect(create_contract!("U", signed_on: nil).crz_deadline_status(today: today)).to eq(:unknown)
-      expect(create_contract!("F", crz_url: "https://crz.gov.sk/zmluva/1/")
+      expect(create_contract!("F", crz_filed_at: Time.current)
                .crz_deadline_status(today: today)).to eq(:untracked)
       expect(create_contract!("R", state: "rejected").crz_deadline_status(today: today)).to eq(:untracked)
     end
@@ -130,7 +130,7 @@ RSpec.describe Decidim::ContractsSk::Contract, :db do
       dates.each_with_index do |signed, index|
         records << create_contract!("SET-#{index}", signed_on: signed)
       end
-      records << create_contract!("SET-FILED", crz_url: "https://crz.gov.sk/zmluva/1/",
+      records << create_contract!("SET-FILED", crz_filed_at: Time.current,
                                                signed_on: Date.new(2026, 11, 30))
       records << create_contract!("SET-REJECTED", state: "rejected", signed_on: Date.new(2026, 11, 30))
 
diff --git a/spec/decidim/contracts_sk/crz_deadline_spec.rb b/spec/decidim/contracts_sk/crz_deadline_spec.rb
index a2c443f..035b05a 100644
--- a/spec/decidim/contracts_sk/crz_deadline_spec.rb
+++ b/spec/decidim/contracts_sk/crz_deadline_spec.rb
@@ -102,8 +102,8 @@ RSpec.describe Decidim::ContractsSk::CrzDeadline do
   end
 
   describe ".tracked?" do
-    def tracked?(source: "editorial", state: "draft", crz_url: nil)
-      described_class.tracked?(source: source, state: state, crz_url: crz_url)
+    def tracked?(source: "editorial", state: "draft", crz_filed_at: nil)
+      described_class.tracked?(source: source, state: state, crz_filed_at: crz_filed_at)
     end
 
     it "tracks unfiled editorial records in every non-terminal state" do
@@ -114,10 +114,9 @@ RSpec.describe Decidim::ContractsSk::CrzDeadline do
         .to eq(%i[draft in_review returned approved published])
     end
 
-    it "treats NULL and '' crz_url as not filed, any other value as filed" do
-      expect(tracked?(crz_url: nil)).to be(true)
-      expect(tracked?(crz_url: "")).to be(true)
-      expect(tracked?(crz_url: "https://crz.gov.sk/zmluva/1/")).to be(false)
+    it "treats only a NULL crz_filed_at as not filed (hard switch from the crz_url proxy, #125)" do
+      expect(tracked?(crz_filed_at: nil)).to be(true)
+      expect(tracked?(crz_filed_at: Time.zone.now)).to be(false)
     end
 
     it "excludes CRZ mirrors and terminal states" do
diff --git a/spec/decidim/contracts_sk/crz_import/filing_comparison_spec.rb b/spec/decidim/contracts_sk/crz_import/filing_comparison_spec.rb
new file mode 100644
index 0000000..81a71b2
--- /dev/null
+++ b/spec/decidim/contracts_sk/crz_import/filing_comparison_spec.rb
@@ -0,0 +1,158 @@
+# frozen_string_literal: true
+
+# ---------------------------------------------------------------------------
+# Deterministic, offline specs for the pure CRZ filing comparison
+# (civora-org/civora-platform#125): the editorial contract against the
+# mapped CRZ record, row by row — match, mismatch, unverifiable and the
+# normalization rules (integer CIN, whitespace/case reference, BigDecimal
+# cents), plus the withdrawn-status predicate. No database: the contract is
+# a plain struct standing in for the attributes the comparison reads.
+#
+# Synthetic data only ("Obec Ukážková", fake IČO patterns), no real PII.
+# ---------------------------------------------------------------------------
+
+require "spec_helper"
+
+# Plain structs standing in for the attributes the comparison reads.
+FilingFakeContract = Struct.new(:reference, :amount, :parties, keyword_init: true)
+FilingFakeParty = Struct.new(:role, :ico, keyword_init: true)
+
+# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
+RSpec.describe Decidim::ContractsSk::CrzImport::FilingComparison do
+  def crz_payload(overrides = {})
+    {
+      "id" => 2_142_424,
+      "contract_identifier" => "UKÁŽKA-2026/001",
+      "subject" => "Dodávka výpočtovej techniky",
+      "contract_price_amount" => "1043.68",
+      "contracting_authority_name" => "Obec Ukážková",
+      "contracting_authority_cin" => "00 000 001",
+      "supplier_name" => "Demo Dodávky s.r.o.",
+      "supplier_cin" => "00 000 002"
+    }.merge(overrides)
+  end
+
+  def record(overrides = {})
+    Decidim::ContractsSk::CrzImport::Mapper.map(crz_payload(overrides))
+  end
+
+  def contract(reference: "UKÁŽKA-2026/001", amount: BigDecimal("1043.68"), contractor_icos: ["00000002"])
+    parties = [FilingFakeParty.new(role: "object", ico: "00000001")] +
+              contractor_icos.map { |ico| FilingFakeParty.new(role: "contractor", ico: ico) }
+    FilingFakeContract.new(reference: reference, amount: amount, parties: parties)
+  end
+
+  def statuses(comparison)
+    comparison.rows.to_h { |row| [row.field, row.status] }
+  end
+
+  def compare(contract_overrides = {}, payload_overrides = {})
+    described_class.new(contract: contract(**contract_overrides), record: record(payload_overrides))
+  end
+
+  it "matches every row for an identical record" do
+    comparison = compare
+
+    expect(statuses(comparison)).to eq(reference: :match, supplier_ico: :match, amount: :match)
+    expect(comparison.all_match?).to be(true)
+    expect(comparison.needs_reason?).to be(false)
+  end
+
+  describe "reference" do
+    it "ignores whitespace and case, including non-ASCII case folding" do
+      comparison = compare({ reference: "  ukážka - 2026 / 001 " }, { "contract_identifier" => "UKÁŽKA-2026/001" })
+
+      expect(statuses(comparison)[:reference]).to eq(:match)
+    end
+
+    it "mismatches a different reference" do
+      expect(statuses(compare({ reference: "ZP-2026-999" }))[:reference]).to eq(:mismatch)
+    end
+
+    it "is unverifiable when either side is blank" do
+      aggregate_failures do
+        expect(statuses(compare({ reference: " " }))[:reference]).to eq(:unverifiable)
+        expect(statuses(compare({}, { "contract_identifier" => nil, "reference" => nil }))[:reference])
+          .to eq(:unverifiable)
+      end
+    end
+  end
+
+  describe "supplier IČO" do
+    it "matches when ANY editorial contractor carries the CRZ supplier IČO" do
+      comparison = compare(contractor_icos: %w[00000077 00000002])
+
+      expect(statuses(comparison)[:supplier_ico]).to eq(:match)
+    end
+
+    it "normalizes the integer CIN CRZ serves (leading zeros restored by the mapper)" do
+      comparison = compare({ contractor_icos: ["00000002"] }, { "supplier_cin" => 2 })
+
+      expect(statuses(comparison)[:supplier_ico]).to eq(:match)
+    end
+
+    it "mismatches when no editorial contractor carries it" do
+      expect(statuses(compare(contractor_icos: ["00000077"]))[:supplier_ico]).to eq(:mismatch)
+    end
+
+    it "does not count the object party as a contractor" do
+      object_only = described_class.new(
+        contract: FilingFakeContract.new(reference: "UKÁŽKA-2026/001", amount: BigDecimal("1043.68"),
+                                         parties: [FilingFakeParty.new(role: "object", ico: "00000002")]),
+        record: record
+      )
+
+      expect(statuses(object_only)[:supplier_ico]).to eq(:unverifiable)
+    end
+
+    it "is unverifiable without an editorial contractor IČO or without a CRZ supplier IČO" do
+      aggregate_failures do
+        expect(statuses(compare(contractor_icos: [nil]))[:supplier_ico]).to eq(:unverifiable)
+        expect(statuses(compare(contractor_icos: []))[:supplier_ico]).to eq(:unverifiable)
+        expect(statuses(compare({}, { "supplier_cin" => "bez ičo" }))[:supplier_ico]).to eq(:unverifiable)
+      end
+    end
+  end
+
+  describe "amount" do
+    it "compares BigDecimal cents exactly" do
+      aggregate_failures do
+        expect(statuses(compare({ amount: BigDecimal("1043.68") }))[:amount]).to eq(:match)
+        expect(statuses(compare({ amount: BigDecimal("1043.69") }))[:amount]).to eq(:mismatch)
+        expect(statuses(compare({ amount: BigDecimal("1043.6") }, { "contract_price_amount" => "1043.60" }))[:amount])
+          .to eq(:match)
+      end
+    end
+
+    it "is unverifiable when either side has no amount, but a zero amount is a real value" do
+      aggregate_failures do
+        expect(statuses(compare({ amount: nil }))[:amount]).to eq(:unverifiable)
+        expect(statuses(compare({}, { "contract_price_amount" => nil }))[:amount]).to eq(:unverifiable)
+        expect(statuses(compare({ amount: BigDecimal("0") }, { "contract_price_amount" => "0.00" }))[:amount])
+          .to eq(:match)
+      end
+    end
+  end
+
+  describe "reason requirement" do
+    it "needs a reason for a mismatch and for an unverifiable row alike" do
+      aggregate_failures do
+        expect(compare({ reference: "ZP-2026-999" }).needs_reason?).to be(true)
+        expect(compare({ amount: nil }).needs_reason?).to be(true)
+        expect(compare({ amount: nil }).all_match?).to be(false)
+      end
+    end
+  end
+
+  describe ".withdrawn?" do
+    it "flags only CRZ status 4 (cancelled) and 5 (withdrawn)" do
+      aggregate_failures do
+        expect(described_class.withdrawn?(record("status_id" => 4))).to be(true)
+        expect(described_class.withdrawn?(record("status_id" => 5))).to be(true)
+        expect(described_class.withdrawn?(record("status_id" => 2))).to be(false)
+        expect(described_class.withdrawn?(record)).to be(false)
+      end
+    end
+  end
+end
+# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
diff --git a/spec/decidim/contracts_sk/crz_import/filing_lookup_spec.rb b/spec/decidim/contracts_sk/crz_import/filing_lookup_spec.rb
new file mode 100644
index 0000000..9823bf8
--- /dev/null
+++ b/spec/decidim/contracts_sk/crz_import/filing_lookup_spec.rb
@@ -0,0 +1,88 @@
+# frozen_string_literal: true
+
+# ---------------------------------------------------------------------------
+# Deterministic, offline specs for the read-only CRZ verification fetch
+# behind the filing confirmation (civora-org/civora-platform#125): refusal
+# order and the "never network on a bad id / unconfigured organization"
+# guarantees. The Client is stubbed at its exact boundary.
+# ---------------------------------------------------------------------------
+
+require "spec_helper"
+
+# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
+RSpec.describe Decidim::ContractsSk::CrzImport::FilingLookup do
+  let(:client_class) { Decidim::ContractsSk::CrzImport::Client }
+  let(:client) { instance_double(client_class) }
+  let(:organization) { Object.new }
+  let(:payload) do
+    { "id" => 77, "contract_identifier" => "ZP-77", "contract_price_amount" => "10.00",
+      "contracting_authority_name" => "Obec Ukážková", "contracting_authority_cin" => "00 000 001",
+      "supplier_name" => "Demo s.r.o.", "supplier_cin" => "00 000 002", "status_id" => 2 }
+  end
+
+  around do |example|
+    original = Decidim::ContractsSk.crz_organization_ico_resolver
+    Decidim::ContractsSk.crz_organization_ico_resolver = ->(_organization) { "00000001" }
+    example.run
+  ensure
+    Decidim::ContractsSk.crz_organization_ico_resolver = original
+  end
+
+  def lookup(id = "77")
+    described_class.call(crz_id: id, organization: organization, client: client)
+  end
+
+  it "returns the mapped record for an in-scope, live CRZ record" do
+    allow(client).to receive(:contract).with("77").and_return(payload)
+
+    result = lookup
+
+    expect(result).to be_ok
+    expect(result.record[:source_id]).to eq("77")
+    expect(result.record[:status_id]).to eq(2)
+  end
+
+  it "refuses a non-numeric id before any network call" do
+    allow(client).to receive(:contract)
+
+    expect(lookup("12 34").refusal).to eq(:not_found)
+    expect(lookup("").refusal).to eq(:not_found)
+    expect(client).not_to have_received(:contract)
+  end
+
+  it "fails closed without a configured organization IČO, before any network call" do
+    Decidim::ContractsSk.crz_organization_ico_resolver = ->(_organization) {}
+    allow(client).to receive(:contract)
+
+    expect(lookup.refusal).to eq(:not_configured)
+    expect(client).not_to have_received(:contract)
+  end
+
+  it "maps a missing record to :not_found and source trouble to :failed" do
+    allow(client).to receive(:contract).and_raise(client_class::NotFoundError)
+    expect(lookup.refusal).to eq(:not_found)
+
+    allow(client).to receive(:contract).and_raise(client_class::TransportError)
+    expect(lookup.refusal).to eq(:failed)
+
+    allow(client).to receive(:contract).and_raise(client_class::ParseError)
+    expect(lookup.refusal).to eq(:failed)
+  end
+
+  it "never accepts a payload for a different record id" do
+    allow(client).to receive(:contract).with("78").and_return(payload)
+
+    expect(lookup("78").refusal).to eq(:not_found)
+  end
+
+  it "refuses another organization's record and withdrawn/cancelled records" do
+    allow(client).to receive(:contract).with("77")
+                                       .and_return(payload.merge("contracting_authority_cin" => "00 000 009",
+                                                                 "supplier_cin" => "00 000 008"))
+    expect(lookup.refusal).to eq(:out_of_scope)
+
+    allow(client).to receive(:contract).with("77").and_return(payload.merge("status_id" => 5))
+    expect(lookup.refusal).to eq(:withdrawn)
+  end
+end
+# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
diff --git a/spec/decidim/contracts_sk/crz_import/mapper_spec.rb b/spec/decidim/contracts_sk/crz_import/mapper_spec.rb
index 4417d98..a8d9f02 100644
--- a/spec/decidim/contracts_sk/crz_import/mapper_spec.rb
+++ b/spec/decidim/contracts_sk/crz_import/mapper_spec.rb
@@ -187,6 +187,48 @@ RSpec.describe Decidim::ContractsSk::CrzImport::Mapper do
     end
   end
 
+  describe ".map (filing-confirmation fields, civora-org/civora-platform#125)" do
+    it "maps status_id and the published date beside — never inside — the written attributes" do
+      record = described_class.map(crz_payload("status_id" => 2, "published_at" => "2026-04-20"))
+
+      aggregate_failures do
+        expect(record[:status_id]).to eq(2)
+        expect(record[:published_on]).to eq(Date.new(2026, 4, 20))
+        expect(record[:attributes].keys).not_to include(:status_id, :published_on, :published_at)
+      end
+    end
+
+    it "maps a blank status, a non-numeric status and the 0000-00-00 sentinel to nil" do
+      aggregate_failures do
+        expect(described_class.map(crz_payload)[:status_id]).to be_nil
+        expect(described_class.map(crz_payload("status_id" => "n/a"))[:status_id]).to be_nil
+        expect(described_class.map(crz_payload("status_id" => "4"))[:status_id]).to eq(4)
+        expect(described_class.map(crz_payload("published_at" => "0000-00-00"))[:published_on]).to be_nil
+        expect(described_class.map(crz_payload("published_at" => ""))[:published_on]).to be_nil
+      end
+    end
+
+    it "takes a published_at timestamp on the Slovak calendar day (near-midnight UTC)" do
+      published = lambda do |value|
+        described_class.map(crz_payload("published_at" => value))[:published_on]
+      end
+
+      aggregate_failures do
+        expect(published.call("2026-04-20T22:30:00Z")).to eq(Date.new(2026, 4, 21)) # CEST = UTC+2
+        expect(published.call("2026-01-20T23:30:00Z")).to eq(Date.new(2026, 1, 21)) # CET = UTC+1
+        expect(published.call("2026-04-20T10:00:00Z")).to eq(Date.new(2026, 4, 20))
+        expect(published.call("2026-04-20 00:30:00")).to eq(Date.new(2026, 4, 20)) # zone-less = local
+        expect(published.call("not a date")).to be_nil
+      end
+    end
+
+    it "leaves the checksum a digest of the raw payload only (unchanged by the new keys)" do
+      payload = crz_payload("status_id" => 2, "published_at" => "2026-04-20")
+
+      expect(described_class.map(payload)[:checksum]).to eq(described_class.checksum(payload))
+    end
+  end
+
   describe ".checksum (determinism gate)" do
     it "is stable across key order and consistent across identical payloads" do
       shuffled = crz_payload.to_a.shuffle.to_h
diff --git a/spec/decidim/contracts_sk/crz_import/sync_spec.rb b/spec/decidim/contracts_sk/crz_import/sync_spec.rb
index 15d9a49..dd10507 100644
--- a/spec/decidim/contracts_sk/crz_import/sync_spec.rb
+++ b/spec/decidim/contracts_sk/crz_import/sync_spec.rb
@@ -153,6 +153,98 @@ RSpec.describe Decidim::ContractsSk::CrzImport::Sync, :db do
     end
   end
 
+  describe ".run (filed editorial records, civora-org/civora-platform#125)" do
+    it "counts a filing-confirmed editorial record as linked — not a collision — and writes nothing" do
+      filed = Decidim::ContractsSk::Contract.create!(
+        contract_attributes(reference: "ZP-2026-808", state: "published", source_id: "302",
+                            crz_filed_at: Time.zone.parse("2026-09-01T10:00:00Z"))
+      )
+      unfiled = Decidim::ContractsSk::Contract.create!(
+        contract_attributes(reference: "ZP-2026-809", source_id: "303")
+      )
+      allow(client).to receive(:sync)
+        .and_return(page([crz_payload("302"), crz_payload("303"), crz_payload("400")]))
+      before = filed.updated_at
+
+      result = run_sync
+
+      aggregate_failures do
+        expect(result.linked).to eq(1)
+        expect(result.linked_ids).to eq([filed.id])
+        expect(result.collisions).to eq(1)
+        expect(result.collision_ids).to eq([unfiled.id])
+        expect(result.created).to eq(1)
+        expect(Decidim::ContractsSk::Contract.where(source_id: "302").count).to eq(1)
+        expect(filed.reload.updated_at).to eq(before)
+        expect(filed.title).to eq("Road reconstruction")
+      end
+    end
+
+    it "is repeatable: the next sync of the same filed record links again, never duplicates" do
+      Decidim::ContractsSk::Contract.create!(
+        contract_attributes(reference: "ZP-2026-808", state: "published", source_id: "302",
+                            crz_filed_at: Time.current)
+      )
+      allow(client).to receive(:sync).and_return(page([crz_payload("302")]))
+
+      2.times { expect(run_sync.linked).to eq(1) }
+      expect(Decidim::ContractsSk::Contract.count).to eq(1)
+    end
+
+    it "never stamps import_status on an editorial record when its id is quarantined (G4)" do
+      editorial = Decidim::ContractsSk::Contract.create!(
+        contract_attributes(reference: "ZP-2026-808", source_id: "302")
+      )
+      allow(client).to receive(:sync).and_return(page([{ 1 => "mixed key types", "id" => "302" }]))
+
+      result = run_sync
+
+      aggregate_failures do
+        expect(result.quarantined).to eq(1)
+        expect(result.failed).to eq(0)
+        expect(editorial.reload.import_status).to be_nil
+      end
+    end
+
+    it "never stamps import_status on an editorial record after an unexpected per-record failure (G4)" do
+      editorial = Decidim::ContractsSk::Contract.create!(
+        contract_attributes(reference: "ZP-2026-808", source_id: "302", crz_filed_at: Time.current)
+      )
+      allow(Decidim::ContractsSk::CrzImport::UpsertContract).to receive(:call).and_raise(StandardError, "boom")
+      allow(client).to receive(:sync).and_return(page([crz_payload("302")]))
+
+      run_sync
+
+      expect(editorial.reload.import_status).to be_nil
+    end
+
+    it "never stamps an editorial record when a single import of its id fails (G4)" do
+      editorial = Decidim::ContractsSk::Contract.create!(
+        contract_attributes(reference: "ZP-2026-808", source_id: "302", crz_filed_at: Time.current)
+      )
+      allow(client).to receive(:contract).and_raise(Decidim::ContractsSk::CrzImport::Client::TransportError)
+
+      outcome = described_class.import_one(source_id: "302", organization: organization,
+                                           actor: author, client: client)
+
+      expect(outcome).to eq(:failed)
+      expect(editorial.reload.import_status).to be_nil
+    end
+
+    it "answers :linked for a single import of a filed record's id" do
+      Decidim::ContractsSk::Contract.create!(
+        contract_attributes(reference: "ZP-2026-808", state: "published", source_id: "302",
+                            crz_filed_at: Time.current)
+      )
+      allow(client).to receive(:contract).with("302").and_return(crz_payload("302"))
+
+      outcome = described_class.import_one(source_id: "302", organization: organization,
+                                           actor: author, client: client)
+
+      expect(outcome).to eq(:linked)
+    end
+  end
+
   describe ".run (pagination and stale fallback)" do
     it "follows the Link cursor verbatim across pages" do
       first_page = page([crz_payload("400")],
diff --git a/spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb b/spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb
index 1475cf9..b0cd90e 100644
--- a/spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb
+++ b/spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb
@@ -20,7 +20,7 @@
 
 require "spec_helper"
 
-# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
+# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, Metrics/AbcSize
 RSpec.describe Decidim::ContractsSk::CrzImport::UpsertContract, :db do
   before { migrate_engine_schema! }
 
@@ -188,6 +188,87 @@ RSpec.describe Decidim::ContractsSk::CrzImport::UpsertContract, :db do
     end
   end
 
+  describe "linked path (editorial record confirmed as filed, civora-org/civora-platform#125)" do
+    let!(:filed) do
+      Decidim::ContractsSk::Contract.create!(
+        contract_attributes(reference: "ZP-2026-808", state: "published", source_id: "2142424",
+                            crz_filed_at: Time.zone.parse("2026-09-01T10:00:00Z"))
+      )
+    end
+
+    def expect_linked_without_writes(events)
+      before = filed.updated_at
+
+      expect(events).to have_key(:ok)
+      expect(events[:ok][:outcome]).to eq(:linked)
+      expect(events[:ok][:contract].id).to eq(filed.id)
+      expect(filed.reload.updated_at).to eq(before)
+      expect(filed.source).to eq("editorial")
+      expect(Decidim::ContractsSk::Contract.count).to eq(1)
+      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
+    end
+
+    it "writes nothing and reports :linked — neither a mirror nor a collision" do
+      expect_linked_without_writes(call_command(mapped_crz_record("2142424")))
+    end
+
+    it "stays a no-op however the payload changes (the filed record is canonical)" do
+      call_command(mapped_crz_record("2142424"))
+
+      expect_linked_without_writes(call_command(mapped_crz_record("2142424", "subject" => "Zmenený predmet")))
+      expect(filed.reload.title).to eq("Road reconstruction")
+    end
+
+    it "honours a filing confirmed after the pre-read (create-edge reroute)" do
+      original = Decidim::ContractsSk::Contract.method(:find_by)
+      calls = 0
+      allow(Decidim::ContractsSk::Contract).to receive(:find_by) do |**kwargs|
+        calls += 1
+        calls == 1 ? nil : original.call(**kwargs)
+      end
+
+      expect_linked_without_writes(call_command(mapped_crz_record("2142424")))
+    end
+
+    it "reroutes a lost unique-index race to :linked as well" do
+      original = Decidim::ContractsSk::Contract.method(:find_by)
+      lookups = 0
+      allow(Decidim::ContractsSk::Contract).to receive(:find_by) do |**kwargs|
+        lookups += 1
+        lookups <= 2 ? nil : original.call(**kwargs)
+      end
+      allow(Decidim::ContractsSk::Contract).to receive(:create!)
+        .and_raise(ActiveRecord::RecordNotUnique.new("idx_contracts_sk_contracts_on_org_and_source_id_unique"))
+
+      expect_linked_without_writes(call_command(mapped_crz_record("2142424")))
+    end
+
+    it "ends :linked when the mirror row was absorbed between the pre-read and the lock (L-1)" do
+      filed.update_columns(source_id: nil)
+      mirror = create_imported_record("2142424")
+      stale = Decidim::ContractsSk::Contract.find(mirror.id)
+      mirror.destroy!
+      filed.update_columns(source_id: "2142424")
+
+      original = Decidim::ContractsSk::Contract.method(:find_by)
+      calls = 0
+      allow(Decidim::ContractsSk::Contract).to receive(:find_by) do |**kwargs|
+        calls += 1
+        calls == 1 ? stale : original.call(**kwargs)
+      end
+
+      expect_linked_without_writes(call_command(mapped_crz_record("2142424")))
+    end
+
+    it "still reports :collision for an UNFILED editorial record holding the id" do
+      filed.update_columns(crz_filed_at: nil)
+
+      events = call_command(mapped_crz_record("2142424"))
+
+      expect(events[:invalid][:reason]).to eq(:collision)
+    end
+  end
+
   describe "lifecycle guard" do
     it "never updates an imported record that left the published state (archived stays archived)" do
       contract = create_imported_record("2142424", state: "archived")
@@ -282,4 +363,4 @@ RSpec.describe Decidim::ContractsSk::CrzImport::UpsertContract, :db do
     end
   end
 end
-# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
+# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, Metrics/AbcSize
diff --git a/spec/decidim/contracts_sk/engine_routing_spec.rb b/spec/decidim/contracts_sk/engine_routing_spec.rb
index 9871c6d..59c55ed 100644
--- a/spec/decidim/contracts_sk/engine_routing_spec.rb
+++ b/spec/decidim/contracts_sk/engine_routing_spec.rb
@@ -34,7 +34,10 @@ module EngineRoutingContract
   # CRZ single-record import (ADR-008, civora-org/civora-platform#86) is a
   # collection POST (import by CRZ id, not tied to an existing record) —
   # also outside the lifecycle derivation, as is the ADR-007 redaction-
-  # confirmation member POST (civora-org/civora-platform#91).
+  # confirmation member POST (civora-org/civora-platform#91). The CRZ
+  # filing confirmation (civora-org/civora-platform#125) is another
+  # explicit member pair (GET preview + POST confirm), outside the
+  # derivation too.
   # Parties (civora-org/civora-platform#76) hang off their contract through
   # the nested resource: an index plus the full add/edit/remove surface
   # (update maps to BOTH a PATCH and a PUT route entry, so the party block
@@ -54,6 +57,11 @@ module EngineRoutingContract
   # exactly "/", not "/(.:format)" - unlike a plain `get`), and it maps the
   # `resources` update action to BOTH a PATCH and a PUT route entry, so the
   # admin CRUD block counts 6 route entries, not 5.
+  EXPECTED_ADMIN_ACTIONS = %w[
+    approve archive confirm_crz_filing confirm_redaction create crz_filing download_crz_handoff edit
+    generate_crz_handoff import_crz index new publish reject return submit update
+  ].freeze
+
   EXPECTED_ROUTES = [
     ["GET", "/", "#{PUBLIC_CONTROLLER}#index"],
     ["GET", "/:id(.:format)", "#{PUBLIC_CONTROLLER}#show"],
@@ -64,6 +72,8 @@ module EngineRoutingContract
     ["POST", "/admin/contracts/:id/approve(.:format)", "#{ADMIN_CONTROLLER}#approve"],
     ["POST", "/admin/contracts/:id/archive(.:format)", "#{ADMIN_CONTROLLER}#archive"],
     ["POST", "/admin/contracts/:id/confirm_redaction(.:format)", "#{ADMIN_CONTROLLER}#confirm_redaction"],
+    ["GET", "/admin/contracts/:id/crz_filing(.:format)", "#{ADMIN_CONTROLLER}#crz_filing"],
+    ["POST", "/admin/contracts/:id/crz_filing(.:format)", "#{ADMIN_CONTROLLER}#confirm_crz_filing"],
     ["GET", "/admin/contracts/:id/crz_handoff(.:format)", "#{ADMIN_CONTROLLER}#download_crz_handoff"],
     ["POST", "/admin/contracts/:id/crz_handoff(.:format)", "#{ADMIN_CONTROLLER}#generate_crz_handoff"],
     ["GET", "/admin/contracts/:id/edit(.:format)", "#{ADMIN_CONTROLLER}#edit"],
@@ -241,10 +251,7 @@ RSpec.describe Decidim::ContractsSk::Engine do
     it "exposes exactly the CRUD + transition + CRZ-handoff + import + redaction actions (no show, no destroy)" do
       actions = admin_routes.map { |_, _, endpoint| endpoint.split("#", 2).last }.uniq.sort
 
-      expect(actions).to eq(%w[
-                              approve archive confirm_redaction create download_crz_handoff edit
-                              generate_crz_handoff import_crz index new publish reject return submit update
-                            ])
+      expect(actions).to eq(EngineRoutingContract::EXPECTED_ADMIN_ACTIONS)
     end
   end
 
@@ -275,13 +282,17 @@ RSpec.describe Decidim::ContractsSk::Engine do
     # route table. The CRZ-handoff POST shares the member path shape but is
     # declared explicitly (not a lifecycle event), so it is excluded here —
     # same for the ADR-007 redaction-confirmation POST
-    # (civora-org/civora-platform#91). The derivation equality guards the
+    # (civora-org/civora-platform#91) and the CRZ filing POST
+    # (#125). The derivation equality guards the
     # lifecycle-derived set only.
     def route_transition_events
+      explicit = %w[#generate_crz_handoff #confirm_redaction #confirm_crz_filing]
+
       admin_routes
         .select { |verb, path, _| verb == "POST" && path.start_with?("/admin/contracts/:id/") }
-        .reject { |_, _, endpoint| endpoint.end_with?("#generate_crz_handoff", "#confirm_redaction") }
-        .map { |_, _, endpoint| endpoint.split("#", 2).last.to_sym }
+        .map { |_, _, endpoint| endpoint }
+        .reject { |endpoint| endpoint.end_with?(*explicit) }
+        .map { |endpoint| endpoint.split("#", 2).last.to_sym }
         .sort
     end
 
@@ -328,6 +339,35 @@ RSpec.describe Decidim::ContractsSk::Engine do
     end
   end
 
+  describe "CRZ filing confirmation member routes (civora-org/civora-platform#125)" do
+    include EngineRoutingContract
+
+    let(:url_helpers) { described_class.routes.url_helpers }
+
+    it "shares one member path between the preview (GET) and confirm (POST) actions" do
+      controller = EngineRoutingContract::ADMIN_CONTROLLER
+
+      expect(admin_routes).to include(
+        ["GET", "/admin/contracts/:id/crz_filing(.:format)", "#{controller}#crz_filing"],
+        ["POST", "/admin/contracts/:id/crz_filing(.:format)", "#{controller}#confirm_crz_filing"]
+      )
+    end
+
+    it "names the preview helper crz_filing_admin_contract_path" do
+      expect(url_helpers.crz_filing_admin_contract_path(7)).to eq("/admin/contracts/7/crz_filing")
+    end
+
+    it "names the confirm helper confirm_crz_filing_admin_contract_path" do
+      expect(url_helpers.confirm_crz_filing_admin_contract_path(7)).to eq("/admin/contracts/7/crz_filing")
+    end
+
+    it "keeps the filing routes outside the lifecycle transition derivation" do
+      events = Decidim::ContractsSk::ContractLifecycle::TRANSITIONS.values.flat_map(&:keys).uniq
+
+      expect(events).not_to include(:crz_filing, :confirm_crz_filing)
+    end
+  end
+
   describe "CRZ single-record import collection route (ADR-008, civora-org/civora-platform#86)" do
     include EngineRoutingContract
 
diff --git a/spec/decidim/contracts_sk/permissions_spec.rb b/spec/decidim/contracts_sk/permissions_spec.rb
index a473773..11ff07e 100644
--- a/spec/decidim/contracts_sk/permissions_spec.rb
+++ b/spec/decidim/contracts_sk/permissions_spec.rb
@@ -40,6 +40,10 @@ end
 # holder exercised via context[:contract].
 SpecContract = Struct.new(:state)
 
+# Filing-confirmation stand-in (civora-org/civora-platform#125): the
+# :confirm_crz_filing rule reads the record's state, source and filed flag.
+FilingContract = Struct.new(:state, :source, :crz_filed_at)
+
 # Four-eyes stand-ins (civora-org/civora-platform#123): a user carrying an id
 # (the rule compares it with the record's submitter stamp) and a contract
 # carrying that stamp. Both stay duck-typed, DB-free.
@@ -247,6 +251,65 @@ RSpec.describe Decidim::ContractsSk::Permissions do
     end
   end
 
+  describe "admin scope — confirm_crz_filing (civora-org/civora-platform#125)" do
+    def filing_user_with_roles(*roles)
+      SpecUser.new(engine_roles: roles)
+    end
+
+    def filing_action(user, contract)
+      action_for(user, scope: :admin, action: :confirm_crz_filing, contract: contract)
+    end
+
+    around do |example|
+      original = Decidim::ContractsSk.role_resolver
+      Decidim::ContractsSk.role_resolver = ->(user, _context) { Array(user&.engine_roles) }
+      example.run
+      Decidim::ContractsSk.role_resolver = original
+    end
+
+    it "is allowed for an editor on a published, unfiled editorial record (String or Symbol state)" do
+      [:published, "published"].each do |state|
+        expect(filing_action(filing_user_with_roles(:editor), FilingContract.new(state, "editorial", nil)).allowed?)
+          .to be(true)
+      end
+    end
+
+    it "is denied on every other lifecycle state" do
+      (lifecycle::STATES - [:published]).each do |state|
+        outcome = filing_action(filing_user_with_roles(:editor), FilingContract.new(state, "editorial", nil))
+
+        expect(outcome.allowed?).to be(false), "must not allow filing on #{state}"
+      end
+    end
+
+    it "is denied for a record already confirmed as filed and for a CRZ mirror" do
+      editor = filing_user_with_roles(:editor)
+
+      expect(filing_action(editor, FilingContract.new(:published, "editorial", Time.current)).allowed?).to be(false)
+      expect(filing_action(editor, FilingContract.new(:published, "crz", nil)).allowed?).to be(false)
+    end
+
+    it "is denied for a reviewer and for a roleless user" do
+      record = FilingContract.new(:published, "editorial", nil)
+
+      expect(filing_action(filing_user_with_roles(:reviewer), record).allowed?).to be(false)
+      expect(filing_action(filing_user_with_roles, record).allowed?).to be(false)
+    end
+
+    it "is disallowed (not unset) without a record — a bare state cannot prove source or filed flag" do
+      outcome = action_for(filing_user_with_roles(:editor), scope: :admin, action: :confirm_crz_filing,
+                                                            state: :published)
+
+      expect(outcome.allowed?).to be(false)
+    end
+
+    it "leaves the public-scope action unset (fail-closed)" do
+      expect(unset?(filing_user_with_roles(:editor), scope: :public, action: :confirm_crz_filing,
+                                                     contract: FilingContract.new(:published, "editorial", nil)))
+        .to be(true)
+    end
+  end
+
   describe "admin scope — confirm_redaction (ADR-007, civora-org/civora-platform#91: :update's twin)" do
     # Plain-method helper (not a let) so the group stays within the
     # memoized-helpers budget while every example names its user explicitly.
diff --git a/spec/decidim/contracts_sk_crz_scope_spec.rb b/spec/decidim/contracts_sk_crz_scope_spec.rb
index feb4335..2305530 100644
--- a/spec/decidim/contracts_sk_crz_scope_spec.rb
+++ b/spec/decidim/contracts_sk_crz_scope_spec.rb
@@ -53,4 +53,23 @@ RSpec.describe Decidim::ContractsSk do
       expect([described_class.crz_organization_ico(nil), calls]).to eq([nil, []])
     end
   end
+
+  describe Decidim::ContractsSk::CrzScope do
+    let(:record) { { parties: [{ ico: "00000001" }, { ico: "00000002" }] } }
+
+    it "is in scope when the organization IČO is on either party" do
+      aggregate_failures do
+        expect(described_class.in_scope?(record, "00000001")).to be(true)
+        expect(described_class.in_scope?(record, "00000002")).to be(true)
+      end
+    end
+
+    it "is out of scope for another IČO and fails closed without a configured IČO" do
+      aggregate_failures do
+        expect(described_class.in_scope?(record, "00000009")).to be(false)
+        expect(described_class.in_scope?(record, nil)).to be(false)
+        expect(described_class.in_scope?({ parties: [{ ico: nil }] }, nil)).to be(false)
+      end
+    end
+  end
 end
diff --git a/spec/decidim/contracts_sk_locales_spec.rb b/spec/decidim/contracts_sk_locales_spec.rb
index 9264ddd..8213365 100644
--- a/spec/decidim/contracts_sk_locales_spec.rb
+++ b/spec/decidim/contracts_sk_locales_spec.rb
@@ -293,6 +293,30 @@ module LocaleContract
     }
   }.freeze
 
+  # The CRZ filing-confirmation labels per locale (civora-org/civora-platform
+  # #125): the entry link, the lag-aware not-found wording and the public
+  # "published in CRZ on" line (the date placeholder is part of the pin).
+  CRZ_FILING_LABELS = {
+    en: {
+      "admin.contracts.crz_filing.link" => "Record CRZ filing",
+      "admin.contracts.crz_filing.refusals.not_found" =>
+        "No CRZ contract with id %{crz_id} was found. The data source may lag the CRZ by about a day — " \
+        "try again later.",
+      "contract.crz_filed_on" => "Published in CRZ on %{date}",
+      "contract.crz_filed_confirmed" => "Publication in CRZ confirmed",
+      "admin.audit_events.actions.crz_filed_override" => "CRZ filing confirmed despite differences"
+    },
+    sk: {
+      "admin.contracts.crz_filing.link" => "Zaznamenať zverejnenie v CRZ",
+      "admin.contracts.crz_filing.refusals.not_found" =>
+        "Zmluva s ID %{crz_id} nebola v CRZ nájdená. Zdroj údajov môže za CRZ zaostávať približne o deň — " \
+        "skúste to neskôr.",
+      "contract.crz_filed_on" => "Zverejnené v CRZ dňa %{date}",
+      "contract.crz_filed_confirmed" => "Zverejnenie v CRZ potvrdené",
+      "admin.audit_events.actions.crz_filed_override" => "Zverejnenie v CRZ potvrdené napriek rozdielom"
+    }
+  }.freeze
+
   # The admin privacy-redaction confirmation labels per locale (ADR-007,
   # civora-org/civora-platform#91). The checklist items and the checkbox
   # affirmation are pinned verbatim — the confirmation's wording is the
@@ -530,8 +554,11 @@ module LocaleContract
     "admin.amendments.update.success",
     "admin.audit_events.actions.amendment_publish",
     "admin.audit_events.actions.approve_self",
+    "admin.audit_events.actions.crz_filed",
+    "admin.audit_events.actions.crz_filed_override",
     "admin.audit_events.actions.crz_import_create",
     "admin.audit_events.actions.crz_import_update",
+    "admin.audit_events.actions.crz_mirror_absorbed",
     "admin.audit_events.actions.redaction_confirmed",
     "admin.audit_events.actions.reject_self",
     "admin.audit_events.actions.return_self",
@@ -560,6 +587,46 @@ module LocaleContract
     "admin.contracts.confirm_redaction.title",
     "admin.contracts.create.error",
     "admin.contracts.create.success",
+    "admin.contracts.crz_filing.back",
+    "admin.contracts.crz_filing.comparison.crz",
+    "admin.contracts.crz_filing.comparison.editorial",
+    "admin.contracts.crz_filing.comparison.field",
+    "admin.contracts.crz_filing.comparison.fields.amount",
+    "admin.contracts.crz_filing.comparison.fields.reference",
+    "admin.contracts.crz_filing.comparison.fields.supplier_ico",
+    "admin.contracts.crz_filing.comparison.official_record",
+    "admin.contracts.crz_filing.comparison.published_on",
+    "admin.contracts.crz_filing.comparison.published_on_unknown",
+    "admin.contracts.crz_filing.comparison.result",
+    "admin.contracts.crz_filing.comparison.statuses.match",
+    "admin.contracts.crz_filing.comparison.statuses.mismatch",
+    "admin.contracts.crz_filing.comparison.statuses.unverifiable",
+    "admin.contracts.crz_filing.comparison.title",
+    "admin.contracts.crz_filing.confirm",
+    "admin.contracts.crz_filing.confirm_prompt",
+    "admin.contracts.crz_filing.crz_id_label",
+    "admin.contracts.crz_filing.description",
+    "admin.contracts.crz_filing.filed",
+    "admin.contracts.crz_filing.filed_override",
+    "admin.contracts.crz_filing.invalid_id",
+    "admin.contracts.crz_filing.lag_hint",
+    "admin.contracts.crz_filing.link",
+    "admin.contracts.crz_filing.lookup",
+    "admin.contracts.crz_filing.override.label",
+    "admin.contracts.crz_filing.override.placeholder",
+    "admin.contracts.crz_filing.override.warning",
+    "admin.contracts.crz_filing.refusals.already_filed",
+    "admin.contracts.crz_filing.refusals.already_linked",
+    "admin.contracts.crz_filing.refusals.failed",
+    "admin.contracts.crz_filing.refusals.not_configured",
+    "admin.contracts.crz_filing.refusals.not_fileable",
+    "admin.contracts.crz_filing.refusals.not_found",
+    "admin.contracts.crz_filing.refusals.out_of_scope",
+    "admin.contracts.crz_filing.refusals.reason_rejected",
+    "admin.contracts.crz_filing.refusals.reason_required",
+    "admin.contracts.crz_filing.refusals.stale",
+    "admin.contracts.crz_filing.refusals.withdrawn",
+    "admin.contracts.crz_filing.title",
     "admin.contracts.deadline.badge.overdue",
     "admin.contracts.deadline.badge.today",
     "admin.contracts.deadline.badge.unknown",
@@ -589,6 +656,7 @@ module LocaleContract
     "admin.contracts.import_crz.hint",
     "admin.contracts.import_crz.label",
     "admin.contracts.import_crz.lifecycle_guard",
+    "admin.contracts.import_crz.linked",
     "admin.contracts.import_crz.not_configured",
     "admin.contracts.import_crz.not_found",
     "admin.contracts.import_crz.out_of_scope",
@@ -709,6 +777,9 @@ module LocaleContract
     "admin.parties.update.error",
     "admin.parties.update.success",
     "contract.amount",
+    "contract.crz_filed",
+    "contract.crz_filed_confirmed",
+    "contract.crz_filed_on",
     "contract.crz_url",
     "contract.currency",
     "contract.document.annex",
@@ -1004,6 +1075,14 @@ RSpec.describe Decidim::ContractsSk do
       end
     end
 
+    it "translates the CRZ filing-confirmation labels in both locales (civora-org/civora-platform#125)" do
+      LocaleContract::CRZ_FILING_LABELS.each do |locale, labels|
+        labels.each do |key, value|
+          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
+        end
+      end
+    end
+
     it "translates the admin link-management labels in both locales (M01-87, civora-org/civora-platform#87)" do
       LocaleContract::ADMIN_LINK_LABELS.each do |locale, labels|
         labels.each do |key, value|
diff --git a/spec/requests/admin/audit_events_spec.rb b/spec/requests/admin/audit_events_spec.rb
index ef46e64..7df535d 100644
--- a/spec/requests/admin/audit_events_spec.rb
+++ b/spec/requests/admin/audit_events_spec.rb
@@ -248,6 +248,21 @@ RSpec.describe "admin audit-trail viewer", type: :request do
       end
     end
 
+    it "renders the override reason on a contract.crz_filed_override row (#125)" do
+      filed = create_contract!(state: "published", crz_filed_at: Time.current,
+                               crz_filing_reason: "Amount corrected in CRZ after filing")
+      create_event!(action: "contract.crz_filed_override", target: filed)
+      clean = create_contract!(state: "published", crz_filed_at: Time.current, crz_filing_reason: "Hidden here")
+      create_event!(action: "contract.crz_filed", target: clean)
+
+      get "/admin/audit_events"
+
+      aggregate_failures do
+        expect(response.body).to include("Amount corrected in CRZ after filing")
+        expect(response.body).not_to include("Hidden here")
+      end
+    end
+
     it "renders the localized self-review labels for the _self actions (civora-org/civora-platform#123)" do
       %w[approve_self return_self reject_self].each do |suffix|
         create_event!(action: "contract.#{suffix}")
diff --git a/spec/requests/admin/contracts_crz_deadline_spec.rb b/spec/requests/admin/contracts_crz_deadline_spec.rb
index 730fd26..bead5cb 100644
--- a/spec/requests/admin/contracts_crz_deadline_spec.rb
+++ b/spec/requests/admin/contracts_crz_deadline_spec.rb
@@ -71,9 +71,9 @@ RSpec.describe "admin contracts CRZ deadline tracking", :db, type: :request do
     create_contract!(reference: "ZP-DL-004", signed_on: Date.new(2026, 3, 16))               # 15 left, ok
     create_contract!(reference: "ZP-DL-005", signed_on: nil)                                 # unknown
     create_contract!(reference: "ZP-DL-006", signed_on: Date.new(2026, 1, 1),
-                     crz_url: "https://crz.gov.sk/zmluva/1/", state: "published")            # filed
+                     crz_filed_at: Time.current, state: "published") # filed
     create_contract!(reference: "ZP-DL-007", signed_on: Date.new(2026, 1, 1),
-                     source: "crz", source_id: "900000001", state: "published")              # mirror
+                     source: "crz", source_id: "900000001", state: "published") # mirror
     create_contract!(reference: "ZP-DL-008", signed_on: Date.new(2026, 1, 1), state: "rejected") # terminal
   end
 
@@ -225,7 +225,7 @@ RSpec.describe "admin contracts CRZ deadline tracking", :db, type: :request do
 
     it "renders no badge for filed, mirror and terminal rows" do
       create_contract!(reference: "ZP-DL-201", signed_on: Date.new(2026, 1, 1),
-                       crz_url: "https://crz.gov.sk/zmluva/1/", state: "published")
+                       crz_filed_at: Time.current, state: "published")
       create_contract!(reference: "ZP-DL-202", signed_on: Date.new(2026, 1, 1), source: "crz",
                        source_id: "900000001", state: "published")
       create_contract!(reference: "ZP-DL-203", signed_on: Date.new(2026, 1, 1), state: "archived")
@@ -237,8 +237,9 @@ RSpec.describe "admin contracts CRZ deadline tracking", :db, type: :request do
       expect(response.body).not_to include("Deadline unknown")
     end
 
-    it "counts an empty-string crz_url as not filed" do
-      create_contract!(reference: "ZP-DL-301", signed_on: Date.new(2026, 1, 1), crz_url: "")
+    it "counts a typed crz_url without a filing confirmation as not filed (#125)" do
+      create_contract!(reference: "ZP-DL-301", signed_on: Date.new(2026, 1, 1),
+                       crz_url: "https://crz.gov.sk/zmluva/1/")
 
       get "/admin/contracts"
 
@@ -275,9 +276,9 @@ RSpec.describe "admin contracts CRZ deadline tracking", :db, type: :request do
       expect(response.body).to include("CRZ filing deadline unknown — add signing date")
     end
 
-    it "renders nothing for a record recorded as filed" do
+    it "renders nothing for a record confirmed as filed" do
       record = create_contract!(reference: "ZP-DL-405", signed_on: Date.new(2026, 3, 8),
-                                crz_url: "https://crz.gov.sk/zmluva/1/")
+                                crz_filed_at: Time.current)
 
       get "/admin/contracts/#{record.id}/edit"
 
diff --git a/spec/requests/admin/contracts_spec.rb b/spec/requests/admin/contracts_spec.rb
index d43d3f8..af56280 100644
--- a/spec/requests/admin/contracts_spec.rb
+++ b/spec/requests/admin/contracts_spec.rb
@@ -147,6 +147,16 @@ FakeIndexContract = Struct.new(:title, :reference, :state, :review_reason) do
     "77"
   end
 
+  # The #125 filing-confirmation permission reads the record's source and
+  # filed flag: the offline fake is an unfiled editorial record.
+  def source
+    "editorial"
+  end
+
+  def crz_filed_at
+    nil
+  end
+
   # The #124 CRZ deadline badge reads the record's status; the offline fake
   # is never tracked (the badge cell renders empty).
   def crz_deadline_status(today: nil)
diff --git a/spec/requests/admin/crz_filing_spec.rb b/spec/requests/admin/crz_filing_spec.rb
new file mode 100644
index 0000000..cdcbc65
--- /dev/null
+++ b/spec/requests/admin/crz_filing_spec.rb
@@ -0,0 +1,303 @@
+# frozen_string_literal: true
+
+# ---------------------------------------------------------------------------
+# Request specs for the admin CRZ filing confirmation (civora-org/
+# civora-platform#125), run against the Stage-1 dummy harness (spec/dummy
+# mounts the engine at "/") and the real migrations on in-memory SQLite.
+# The verification fetch is stubbed at the Client boundary (Client.new);
+# the real FilingLookup, FilingComparison, command and locks run.
+#
+# Flash-key discipline (as in crz_import_spec.rb): the harness'
+# authenticate_user! redirects with the literal key
+# :dummy_authentication_required, while NeedsPermission's denial handler
+# uses :alert — every denial proves WHICH gate fired.
+#
+# Synthetic data only ("Obec Ukážková", fake IČO patterns), no real PII.
+# ---------------------------------------------------------------------------
+
+require "spec_helper"
+
+# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/AnyInstance, RSpec/MultipleMemoizedHelpers
+RSpec.describe "admin CRZ filing confirmation", :db, type: :request do
+  include_context "with the CRZ scope configured"
+
+  let(:unauthorized) { "You are not authorized to perform this action." }
+  let(:client_class) { Decidim::ContractsSk::CrzImport::Client }
+  let(:client) { instance_double(client_class) }
+  let(:crz_id) { "2142424" }
+  let(:payload) { crz_payload(crz_id, "status_id" => 2, "published_at" => "2026-04-20") }
+  let(:token) { Decidim::ContractsSk::CrzImport::Mapper.checksum(payload) }
+  let(:resolver_roles) { %i[editor] }
+  let(:path) { "/admin/contracts/#{contract.id}/crz_filing" }
+  let(:contract) do
+    record = Decidim::ContractsSk::Contract.create!(
+      contract_attributes(reference: "UKÁŽKA-2026/#{crz_id}", state: "published", amount: BigDecimal("1043.68"))
+    )
+    record.parties.create!(role: "object", name: "Obec Ukážková", ico: "00000001")
+    record.parties.create!(role: "contractor", name: "Demo Dodávky s.r.o.", ico: "00000002")
+    record
+  end
+
+  around do |example|
+    original = Decidim::ContractsSk.role_resolver
+    Decidim::ContractsSk.role_resolver = ->(_user, _context) { resolver_roles }
+    example.run
+  ensure
+    Decidim::ContractsSk.role_resolver = original
+  end
+
+  def sign_in_as(user = author)
+    controller = Decidim::ContractsSk::Admin::ContractsController
+
+    allow_any_instance_of(controller).to receive(:current_user).and_return(user)
+    allow_any_instance_of(controller).to receive(:user_signed_in?).and_return(true)
+    allow_any_instance_of(controller).to receive(:current_organization).and_return(organization)
+  end
+
+  before do
+    migrate_engine_schema!
+    allow(client_class).to receive(:new).and_return(client)
+    allow(client).to receive(:contract).with(crz_id).and_return(payload)
+  end
+
+  describe "denied paths" do
+    it "bounces an anonymous visitor with the auth flash, not the permission flash" do
+      get path
+
+      expect(response).to redirect_to("/")
+      expect(flash[:dummy_authentication_required]).to be_present
+      expect(flash[:alert]).to be_nil
+    end
+
+    %i[reviewer none].each do |role|
+      context "when the user is #{role == :none ? "roleless" : role}" do
+        let(:resolver_roles) { role == :none ? [] : [role] }
+
+        it "denies GET and POST with the permission flash and writes nothing" do
+          sign_in_as
+
+          get path
+          expect(response).to redirect_to("/")
+          expect(flash[:alert]).to eq(unauthorized)
+
+          post path, params: { crz_id: crz_id, checksum: token }
+          expect(response).to redirect_to("/")
+          expect(flash[:alert]).to eq(unauthorized)
+          expect(contract.reload.crz_filed_at).to be_nil
+          expect(client).not_to have_received(:contract)
+        end
+      end
+    end
+
+    it "denies an editor on a record that is not published (the permission window)" do
+      sign_in_as
+      contract.update_columns(state: "draft")
+
+      get path
+
+      expect(response).to redirect_to("/")
+      expect(flash[:alert]).to eq(unauthorized)
+    end
+
+    it "denies an editor on an already filed record" do
+      sign_in_as
+      contract.update_columns(crz_filed_at: Time.current)
+
+      post path, params: { crz_id: crz_id, checksum: token }
+
+      expect(response).to redirect_to("/")
+      expect(flash[:alert]).to eq(unauthorized)
+    end
+
+    it "answers 404 for another organization's contract (tenant scope)" do
+      sign_in_as
+      other = Decidim::Organization.create!
+      foreign = Decidim::ContractsSk::Contract.create!(
+        contract_attributes(organization: other, reference: "ZP-FOREIGN", state: "published")
+      )
+
+      expect { get "/admin/contracts/#{foreign.id}/crz_filing" }.to raise_error(ActiveRecord::RecordNotFound)
+    end
+  end
+
+  describe "GET preview" do
+    before { sign_in_as }
+
+    it "renders the CRZ id form without any network call when no id is given" do
+      get path
+
+      expect(response).to have_http_status(:ok)
+      expect(response.body).to include("Record filing in CRZ")
+      expect(response.body).to include("name=\"crz_id\"")
+      expect(response.body).not_to include("name=\"checksum\"")
+      expect(client).not_to have_received(:contract)
+    end
+
+    it "refuses a non-numeric id before any network call" do
+      get path, params: { crz_id: "12/34" }
+
+      expect(response).to have_http_status(:ok)
+      expect(flash[:alert]).to eq("Enter the numeric CRZ contract id.")
+      expect(client).not_to have_received(:contract)
+    end
+
+    it "renders the side-by-side comparison with the confirm form (token + id, no reason on a clean match)" do
+      get path, params: { crz_id: crz_id }
+
+      body = response.body
+      aggregate_failures do
+        expect(response).to have_http_status(:ok)
+        expect(body).to include("UKÁŽKA-2026/2142424")
+        expect(body.scan("label success").size).to eq(3)
+        expect(body).to include("name=\"checksum\"")
+        expect(body).to include(token)
+        expect(body).to include("Published in CRZ on")
+        expect(body).to include("20")
+        expect(body).to include("https://crz.gov.sk/zmluva/2142424/")
+        expect(body).not_to include("name=\"reason\"")
+        expect(contract.reload.crz_filed_at).to be_nil
+        expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
+      end
+    end
+
+    it "shows the mismatch and the required reason field when a row differs" do
+      contract.update!(amount: BigDecimal("999.00"))
+
+      get path, params: { crz_id: crz_id }
+
+      aggregate_failures do
+        expect(response.body).to include("label alert")
+        expect(response.body).to include("Mismatch")
+        expect(response.body).to include("name=\"reason\"")
+        expect(response.body).to include("maxlength=\"1000\"")
+      end
+    end
+
+    it "shows the lag-aware not-found wording" do
+      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::NotFoundError)
+
+      get path, params: { crz_id: crz_id }
+
+      expect(flash[:alert]).to eq("No CRZ contract with id 2142424 was found. The data source may lag the CRZ " \
+                                  "by about a day — try again later.")
+      expect(response.body).not_to include("name=\"checksum\"")
+    end
+
+    it "flashes the source-unavailable alert on a network failure" do
+      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::TransportError)
+
+      get path, params: { crz_id: crz_id }
+
+      expect(flash[:alert]).to include("The CRZ data source is unavailable")
+    end
+
+    it "shows the withdrawn and the out-of-scope refusals" do
+      allow(client).to receive(:contract).with(crz_id).and_return(payload.merge("status_id" => 4))
+      get path, params: { crz_id: crz_id }
+      expect(flash[:alert]).to include("cancelled or withdrawn")
+
+      allow(client).to receive(:contract).with(crz_id)
+                                         .and_return(payload.merge("contracting_authority_cin" => "00 000 009",
+                                                                   "supplier_cin" => "00 000 008"))
+      get path, params: { crz_id: crz_id }
+      expect(flash[:alert]).to include("does not involve this organization")
+    end
+  end
+
+  describe "POST confirm" do
+    before { sign_in_as }
+
+    it "files the record on a full match: notice flash, linked fields, record stays editorial" do
+      post path, params: { crz_id: crz_id, checksum: token }
+
+      expect(response).to redirect_to("/admin/contracts")
+      expect(flash[:notice]).to eq("Filing of contract 2142424 in CRZ confirmed and linked.")
+      contract.reload
+      expect(contract.crz_filed_at).to be_present
+      expect(contract.source).to eq("editorial")
+      expect(contract.source_id).to eq(crz_id)
+      expect(contract.crz_published_on).to eq(Date.new(2026, 4, 20))
+    end
+
+    it "files an override with the reason and flashes the override notice" do
+      contract.update!(amount: BigDecimal("999.00"))
+
+      post path, params: { crz_id: crz_id, checksum: token, reason: "Amount corrected in CRZ." }
+
+      expect(response).to redirect_to("/admin/contracts")
+      expect(flash[:notice]).to include("despite differences")
+      expect(contract.reload.crz_filing_reason).to eq("Amount corrected in CRZ.")
+    end
+
+    it "sends a missing reason back to the preview of the same id, changing nothing" do
+      contract.update!(amount: BigDecimal("999.00"))
+
+      post path, params: { crz_id: crz_id, checksum: token }
+
+      expect(response).to redirect_to("#{path}?crz_id=#{crz_id}")
+      expect(flash[:alert]).to include("enter the reason")
+      expect(contract.reload.crz_filed_at).to be_nil
+    end
+
+    it "sends a stale token back to the preview" do
+      post path, params: { crz_id: crz_id, checksum: "old-token" }
+
+      expect(response).to redirect_to("#{path}?crz_id=#{crz_id}")
+      expect(flash[:alert]).to include("changed since you compared")
+      expect(contract.reload.crz_filed_at).to be_nil
+    end
+
+    it "flashes a network failure, leaving the record and the audit trail untouched" do
+      allow(client).to receive(:contract).with(crz_id).and_raise(client_class::TransportError)
+
+      post path, params: { crz_id: crz_id, checksum: token }
+
+      expect(response).to redirect_to(path)
+      expect(flash[:alert]).to include("data source is unavailable")
+      expect(contract.reload.crz_filed_at).to be_nil
+      expect(Decidim::ContractsSk::AuditEvent.count).to eq(0)
+    end
+
+    it "refuses a non-numeric id before any network call" do
+      post path, params: { crz_id: "abc", checksum: token }
+
+      expect(response).to redirect_to(path)
+      expect(client).not_to have_received(:contract)
+    end
+
+    it "reports an id already linked to another record" do
+      Decidim::ContractsSk::Contract.create!(contract_attributes(reference: "ZP-HOLDER", source_id: crz_id))
+
+      post path, params: { crz_id: crz_id, checksum: token }
+
+      expect(response).to redirect_to(path)
+      expect(flash[:alert]).to include("already linked")
+    end
+  end
+
+  describe "index entry point" do
+    before { sign_in_as }
+
+    it "links the filing page for a published, unfiled editorial record and hides it once filed" do
+      contract
+
+      get "/admin/contracts"
+      expect(response.body).to include("Record CRZ filing")
+      expect(response.body).to include("/admin/contracts/#{contract.id}/crz_filing")
+
+      contract.update_columns
```

## Agent Activity
- Tool calls: 0
- Commands: 0
- Checkpoints: 1
- Test runs: 1
- Journal events: 3951

_Generated: 2026-10-03T17:29:00.669Z · schema agent-review/v1_
