# Agent Review

## Task
civora-org/civora-platform#116: Catalogue filters (amount, dates, party, source) and sorting

## Session
- Session ID: 55ab7a8b-12ce-4172-8d89-af2191e27d9f
- Branch: fix/admin-crz-link-and-input-styling
- Started: 2026-10-04T19:20:07.531Z
- Finished: 2026-10-04T20:25:38.102Z

## Summary
Catalogue filter form, locales, styles: Render the filter form (details/fieldsets, normalized prefill), active-filter summary, clear link, no-results variant; pagination carries all PARAM_KEYS; en+sk strings; engine-owned .cs-filters CSS CatalogueQuery, TextSearch (shared search): civora-platform#116: public catalogue filters and sorting as one reusable query object; fix case-sensitive q on PostgreSQL and ineffective LIKE escaping on SQLite for public and admin q via shared TextSearch

## Logical Changes

### 1. CatalogueQuery, TextSearch (shared search)
- What changed: added in `app/queries/decidim/contracts_sk/catalogue_query.rb`, `app/queries/decidim/contracts_sk/catalogue_query/normalizer.rb`, `app/queries/decidim/contracts_sk/catalogue_query/conditions.rb`, `app/queries/decidim/contracts_sk/text_search.rb`, `app/controllers/decidim/contracts_sk/admin/contracts_controller.rb`, `app/controllers/decidim/contracts_sk/contracts_controller.rb`
- Why: civora-platform#116: public catalogue filters and sorting as one reusable query object; fix case-sensitive q on PostgreSQL and ineffective LIKE escaping on SQLite for public and admin q via shared TextSearch
- Expected behavior: Invalid params ignored, reversed ranges swapped, deterministic sorts with NULL amounts last, party via IN-subquery, q case-insensitive with literal % and _
- Risk: medium
- Limitations: SQLite LOWER folds ASCII only; CRZ mirror published_at is import time
### 2. Catalogue filter form, locales, styles
- What changed: modified in `app/views/decidim/contracts_sk/contracts/index.html.erb`, `app/views/decidim/contracts_sk/shared/_public_styles.html.erb`, `app/views/decidim/contracts_sk/shared/_pagination.html.erb`, `app/helpers/decidim/contracts_sk/catalogue_helper.rb`, `config/locales/en.yml`, `config/locales/sk.yml`
- Why: Render the filter form (details/fieldsets, normalized prefill), active-filter summary, clear link, no-results variant; pagination carries all PARAM_KEYS; en+sk strings; engine-owned .cs-filters CSS
- Expected behavior: Accessible GET form, 1/2/4 column grid, filters hidden in print
- Risk: low

## Test Evidence

### Run 1
- Command: `bundle exec rspec`
- Result: **passed** (exit code: 0)
- Duration: 4068 ms
- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
### Run 2
- Command: `bundle exec rubocop`
- Result: **failed** (exit code: 1)
- Duration: 1401 ms
- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
- Notes: stderr captured (342 lines, redacted and truncated)

## Risks
- Working tree was dirty at session start (2 entries) — pre-existing changes may be mixed into the diff.
- 1 test run(s) did not pass (exit codes: 1).
- Large diff: 3185 insertions across 2 files.

## Limitations
- Snapshots cover only files that were changed at checkpoint time.
- Symbol extraction is regex-based, not AST-based.
- Only observed facts are recorded — private model reasoning is not captured.
- SQLite LOWER folds ASCII only
- CRZ mirror published_at is import time

## Changed Files
- `.agent-review/change-package.json` — modified (json, +218/−521)
- `.agent-review/review.md` — modified (markdown, +2967/−4405)

## Diff
```diff
diff --git a/.agent-review/change-package.json b/.agent-review/change-package.json
index 8d210ed..2d7559d 100644
--- a/.agent-review/change-package.json
+++ b/.agent-review/change-package.json
@@ -1,782 +1,119 @@
 {
   "schemaVersion": "agent-review/v1",
   "session": {
-    "id": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-    "startedAt": "2026-10-03T16:51:14.148Z",
-    "endedAt": "2026-10-03T17:29:00.695Z",
-    "status": "ended"
+    "id": "55ab7a8b-12ce-4172-8d89-af2191e27d9f",
+    "startedAt": "2026-10-04T19:20:07.531Z",
+    "endedAt": null,
+    "status": "active"
   },
-  "task": "civora-org/civora-platform#125: CRZ round-trip — confirm the filing and link the official record",
-  "branch": "feat/crz-filing-confirmation",
-  "commits": [
-    {
-      "hash": "c34981147e9420354b899f42e0c40565ceaf7017",
-      "subject": "feat(crz-filing): confirm the CRZ filing and link the official record (civora-org/civora-platform#125)",
-      "author": "Denys Kozlov",
-      "date": "2026-10-03T19:28:40+02:00"
-    }
-  ],
+  "task": "civora-org/civora-platform#116: Catalogue filters (amount, dates, party, source) and sorting",
+  "branch": "fix/admin-crz-link-and-input-styling",
+  "commits": [],
   "changedFiles": [
     {
-      "path": "app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 242,
-      "deletions": 0,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "Admin",
-        "ConfirmCrzFiling",
-        "Refusal",
-        "initialize",
-        "call",
-        "verified_record",
-        "editor?",
-        "normalized_reason"
-      ]
-    },
-    {
-      "path": "app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb",
+      "path": ".agent-review/change-package.json",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 40,
-      "deletions": 6,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "CrzImport",
-        "UpsertContract",
-        "initialize",
-        "call",
-        "perform",
-        "create_transactional",
-        "lost_create_race",
-        "create_or_reroute!"
-      ]
+      "language": "json",
+      "insertions": 218,
+      "deletions": 521
     },
     {
-      "path": "app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 13,
-      "deletions": 2,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "Admin",
-        "AuditEventsController",
-        "index",
-        "filtered_events",
-        "audit_events_scope",
-        "filtered_contract",
-        "contracts_scope",
-        "audit_action_label"
-      ]
-    },
-    {
-      "path": "app/controllers/decidim/contracts_sk/admin/contracts_controller.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 93,
-      "deletions": 2,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "Admin",
-        "ContractsController",
-        "index",
-        "new",
-        "create",
-        "edit",
-        "update",
-        "download_crz_handoff"
-      ]
-    },
-    {
-      "path": "app/models/decidim/contracts_sk/contract.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 6,
-      "deletions": 5,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "Contract",
-        "crz_deadline",
-        "crz_days_left",
-        "crz_deadline_tracked?",
-        "crz_deadline_status"
-      ]
-    },
-    {
-      "path": "app/permissions/decidim/contracts_sk/permissions.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 27,
-      "deletions": 1,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "Permissions",
-        "permissions",
-        "admin_action",
-        "audit_event_action",
-        "contract_action",
-        "self_review_blocked?",
-        "child_record_action",
-        "amendment_action"
-      ]
-    },
-    {
-      "path": "app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb",
-      "kind": "modified",
-      "language": "unknown",
-      "insertions": 99,
-      "deletions": 0
-    },
-    {
-      "path": "app/views/decidim/contracts_sk/admin/contracts/index.html.erb",
-      "kind": "modified",
-      "language": "unknown",
-      "insertions": 11,
-      "deletions": 2
-    },
-    {
-      "path": "app/views/decidim/contracts_sk/contracts/show.html.erb",
-      "kind": "modified",
-      "language": "unknown",
-      "insertions": 19,
-      "deletions": 1
-    },
-    {
-      "path": "config/locales/en.yml",
-      "kind": "modified",
-      "language": "yaml",
-      "insertions": 55,
-      "deletions": 2
-    },
-    {
-      "path": "config/locales/sk.yml",
-      "kind": "modified",
-      "language": "yaml",
-      "insertions": 55,
-      "deletions": 2
-    },
-    {
-      "path": "config/routes.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 14,
-      "deletions": 0
-    },
-    {
-      "path": "db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 37,
-      "deletions": 0,
-      "symbols": [
-        "AddCrzFilingToDecidimContractsSkContracts",
-        "change"
-      ]
-    },
-    {
-      "path": "docs/contract-lifecycle.md",
-      "kind": "modified",
-      "language": "markdown",
-      "insertions": 13,
-      "deletions": 8
-    },
-    {
-      "path": "docs/contracts-domain-notes.md",
+      "path": ".agent-review/review.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 39,
-      "deletions": 3
-    },
-    {
-      "path": "docs/crz-import.md",
-      "kind": "modified",
-      "language": "markdown",
-      "insertions": 70,
-      "deletions": 7
-    },
-    {
-      "path": "docs/manual-test-scenarios.md",
-      "kind": "modified",
-      "language": "markdown",
-      "insertions": 14,
-      "deletions": 0
-    },
-    {
-      "path": "docs/pilot-operations.md",
-      "kind": "modified",
-      "language": "markdown",
-      "insertions": 1,
-      "deletions": 1
-    },
-    {
-      "path": "docs/qa-checklist.md",
-      "kind": "modified",
-      "language": "markdown",
-      "insertions": 10,
-      "deletions": 1
-    },
-    {
-      "path": "docs/roles-and-permissions.md",
-      "kind": "modified",
-      "language": "markdown",
-      "insertions": 1,
-      "deletions": 0
-    },
-    {
-      "path": "lib/decidim/contracts_sk.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 2,
-      "deletions": 0,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "Error"
-      ]
-    },
-    {
-      "path": "lib/decidim/contracts_sk/crz_deadline.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 8,
-      "deletions": 7,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "crz_deadline=",
-        "CrzDeadline",
-        "ThresholdError",
-        "deadline_for",
-        "days_left",
-        "threshold",
-        "status",
-        "tracked?"
-      ]
-    },
-    {
-      "path": "lib/decidim/contracts_sk/crz_import/filing_comparison.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 124,
-      "deletions": 0,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "CrzImport",
-        "FilingComparison",
-        "self",
-        "initialize",
-        "rows",
-        "all_match?",
-        "needs_reason?",
-        "reference_row"
-      ]
-    },
-    {
-      "path": "lib/decidim/contracts_sk/crz_import/filing_lookup.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 84,
-      "deletions": 0,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "CrzImport",
-        "FilingLookup",
-        "ok?",
-        "self",
-        "initialize",
-        "call",
-        "client",
-        "fetch"
-      ]
-    },
-    {
-      "path": "lib/decidim/contracts_sk/crz_import/mapper.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 42,
-      "deletions": 2,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "CrzImport",
-        "Mapper",
-        "Error",
-        "map",
-        "checksum",
-        "contract_attributes",
-        "title_from",
-        "reference_from"
-      ]
-    },
-    {
-      "path": "lib/decidim/contracts_sk/crz_import/sync.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 54,
-      "deletions": 24,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "CrzImport",
-        "Sync",
-        "run",
-        "import_one",
-        "initialize",
-        "run_cursor_pages",
-        "process_page",
-        "upsert_record!"
-      ]
-    },
-    {
-      "path": "lib/decidim/contracts_sk/crz_scope.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 19,
-      "deletions": 0,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "self",
-        "CrzScope",
-        "in_scope?"
-      ]
-    },
-    {
-      "path": "lib/tasks/decidim_contracts_sk_crz_import.rake",
-      "kind": "modified",
-      "language": "unknown",
-      "insertions": 5,
-      "deletions": 1
-    },
-    {
-      "path": "lib/tasks/decidim_contracts_sk_seed_demo.rake",
-      "kind": "modified",
-      "language": "unknown",
-      "insertions": 6,
-      "deletions": 1
-    },
-    {
-      "path": "README.md",
-      "kind": "modified",
-      "language": "markdown",
-      "insertions": 2,
-      "deletions": 2
-    },
-    {
-      "path": "spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 121,
-      "deletions": 0,
-      "symbols": [
-        "migration_files",
-        "migration_path",
-        "migration_class_name",
-        "base_migration_path",
-        "table_name",
-        "stripped_lines",
-        "column_line",
-        "column_by_name"
-      ]
-    },
-    {
-      "path": "spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 5,
-      "deletions": 4,
-      "symbols": [
-        "migration_files",
-        "migration_path",
-        "migration_class_name",
-        "migration_path_for",
-        "table_name",
-        "stripped_lines",
-        "prerequisite_migrations!",
-        "column_by_name",
-        "sql_value",
-        "insert_contract"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk_crz_scope_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 19,
-      "deletions": 0
-    },
-    {
-      "path": "spec/decidim/contracts_sk_locales_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 79,
-      "deletions": 0,
-      "symbols": [
-        "LocaleContract",
-        "locale_file",
-        "translations",
-        "module_tree",
-        "leaf_paths",
-        "leaf_values",
-        "fresh_backend",
-        "PublicCatalogueLabels",
-        "CrzDeadlineLabels"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 4,
-      "deletions": 3,
-      "symbols": [
-        "Decidim",
-        "ContractsSk"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/admin/confirm_crz_filing_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 335,
-      "deletions": 0,
-      "symbols": [
-        "create_editorial",
-        "call_command",
-        "expect_untouched"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/admin/contracts_controller_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 6,
-      "deletions": 3,
-      "symbols": [
-        "Decidim",
-        "ContractsSk"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/contract_crz_deadline_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 7,
-      "deletions": 7,
-      "symbols": [
-        "create_contract!",
-        "references"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/crz_deadline_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 5,
-      "deletions": 6,
-      "symbols": [
-        "date",
-        "tracked?"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/crz_import/filing_comparison_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 158,
-      "deletions": 0,
-      "symbols": [
-        "crz_payload",
-        "record",
-        "contract",
-        "statuses",
-        "compare"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/crz_import/filing_lookup_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 88,
-      "deletions": 0,
-      "symbols": [
-        "lookup"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/crz_import/mapper_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 42,
-      "deletions": 0,
-      "symbols": [
-        "crz_payload"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/crz_import/sync_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 92,
-      "deletions": 0,
-      "symbols": [
-        "page",
-        "run_sync"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 83,
-      "deletions": 2,
-      "symbols": [
-        "call_command",
-        "expect_linked_without_writes"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/engine_routing_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 48,
-      "deletions": 8,
-      "symbols": [
-        "EngineRoutingContract",
-        "route_triples",
-        "public_routes",
-        "admin_routes",
-        "party_routes",
-        "document_routes",
-        "amendment_routes",
-        "link_routes",
-        "audit_event_routes",
-        "controllers_of"
-      ]
-    },
-    {
-      "path": "spec/decidim/contracts_sk/permissions_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 63,
-      "deletions": 0,
-      "symbols": [
-        "admin?",
-        "admin_terms_accepted?",
-        "action_for",
-        "unset?",
-        "resolver_of",
-        "swap_resolver",
-        "user_with_roles",
-        "filing_user_with_roles",
-        "filing_action",
-        "redaction_user_with_roles"
-      ]
-    },
-    {
-      "path": "spec/requests/admin/audit_events_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 15,
-      "deletions": 0,
-      "symbols": [
-        "sign_in",
-        "create_contract!",
-        "create_event!"
-      ]
-    },
-    {
-      "path": "spec/requests/admin/contracts_crz_deadline_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 8,
-      "deletions": 7,
-      "symbols": [
-        "create_contract!",
-        "references_in",
-        "with_slovak",
-        "seed_deadline_set!"
-      ]
-    },
-    {
-      "path": "spec/requests/admin/contracts_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 10,
-      "deletions": 0,
-      "symbols": [
-        "RecordingIndexScope",
-        "initialize",
-        "where",
-        "not",
-        "order",
-        "group",
-        "count",
-        "crz_overdue",
-        "crz_due_soon",
-        "CountingView"
-      ]
-    },
-    {
-      "path": "spec/requests/admin/crz_filing_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 303,
-      "deletions": 0,
-      "symbols": [
-        "sign_in_as"
-      ]
-    },
-    {
-      "path": "spec/requests/admin/crz_import_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 20,
-      "deletions": 0,
-      "symbols": [
-        "sign_in",
-        "stub_transport",
-        "response_with"
-      ]
-    },
-    {
-      "path": "spec/requests/contracts_spec.rb",
-      "kind": "modified",
-      "language": "ruby",
-      "insertions": 41,
-      "deletions": 0,
-      "symbols": [
-        "PublishedContractFixture",
-        "PaginableStub",
-        "initialize",
-        "page",
-        "per",
-        "each",
-        "any?",
-        "current_page",
-        "prev_page",
-        "next_page"
-      ]
+      "insertions": 2967,
+      "deletions": 4405
     }
   ],
   "logicalChanges": [
     {
-      "id": "1a77f7ce-a784-4832-9c60-3e9c8df9cb4c",
-      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-      "recordedAt": "2026-10-03T17:06:39.454Z",
-      "entity": "CRZ filing columns migration",
-      "files": [
-        "db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb",
-        "spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb"
-      ],
-      "changeKind": "added",
-      "reason": "civora-platform#125: store the verified CRZ filing confirmation (filed_at, published_on, override reason) as nullable system columns.",
-      "expectedBehavior": "Additive reversible migration, no backfill, no defaults/indexes.",
-      "risk": "low",
-      "alternatives": [],
-      "limitations": []
-    },
-    {
-      "id": "77e75c1a-89f9-4f75-8b46-230e9df03f7f",
-      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-      "recordedAt": "2026-10-03T17:06:42.120Z",
-      "entity": "Admin::ConfirmCrzFiling command, FilingLookup, FilingComparison, Mapper/CrzScope extensions",
-      "files": [
-        "app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb",
-        "lib/decidim/contracts_sk/crz_import/filing_lookup.rb",
-        "lib/decidim/contracts_sk/crz_import/filing_comparison.rb",
-        "lib/decidim/contracts_sk/crz_import/mapper.rb",
-        "lib/decidim/contracts_sk/crz_scope.rb"
-      ],
-      "changeKind": "added",
-      "reason": "Verify a hand-filed editorial contract against the official CRZ record and stamp the filing under the row lock, with mirror absorption.",
-      "expectedBehavior": "Fetch outside lock; in-lock re-check of source/state/filed/checksum/comparison/reason/id; one transaction with audit row; refusals broadcast as symbols.",
-      "risk": "medium",
-      "alternatives": [
-        "Audit absorbed-mirror row targeting the destroyed mirror (rejected: dangling target)"
-      ],
-      "limitations": []
-    },
-    {
-      "id": "4b9e4cab-db76-4056-931b-84626813c29e",
-      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-      "recordedAt": "2026-10-03T17:06:44.428Z",
-      "entity": "Sync linked rule, G4 fix, deadline hard switch",
+      "id": "1cda3be3-ec2d-4a0c-900e-aa84f6eca9af",
+      "sessionId": "55ab7a8b-12ce-4172-8d89-af2191e27d9f",
+      "recordedAt": "2026-10-04T19:25:08.818Z",
+      "entity": "Catalogue filter form, locales, styles",
       "files": [
-        "app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb",
-        "lib/decidim/contracts_sk/crz_import/sync.rb",
-        "lib/decidim/contracts_sk/crz_deadline.rb",
-        "app/models/decidim/contracts_sk/contract.rb",
-        "lib/tasks/decidim_contracts_sk_crz_import.rake"
+        "app/views/decidim/contracts_sk/contracts/index.html.erb",
+        "app/views/decidim/contracts_sk/shared/_public_styles.html.erb",
+        "app/views/decidim/contracts_sk/shared/_pagination.html.erb",
+        "app/helpers/decidim/contracts_sk/catalogue_helper.rb",
+        "config/locales/en.yml",
+        "config/locales/sk.yml"
       ],
       "changeKind": "modified",
-      "reason": "A filing-confirmed editorial record is the canonical linked record of its CRZ id; sync must not duplicate or flag it. Failure stamps must never touch editorial rows. Deadline tracking keys on crz_filed_at.",
-      "expectedBehavior": ":linked outcome with zero writes at all decision points; linked counters; find_mirror/mark_failed scoped to source crz; tracked? uses crz_filed_at.",
-      "risk": "medium",
+      "reason": "Render the filter form (details/fieldsets, normalized prefill), active-filter summary, clear link, no-results variant; pagination carries all PARAM_KEYS; en+sk strings; engine-owned .cs-filters CSS",
+      "expectedBehavior": "Accessible GET form, 1/2/4 column grid, filters hidden in print",
+      "risk": "low",
       "alternatives": [],
       "limitations": []
     },
     {
-      "id": "6009392a-aba6-4c87-a7d8-a9ba633d95e4",
-      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-      "recordedAt": "2026-10-03T17:06:46.615Z",
-      "entity": "Admin filing UI, permission, routes, public detail, locales, audit labels, docs",
+      "id": "9fe876b8-0a79-41a0-89df-1d3e362d1977",
+      "sessionId": "55ab7a8b-12ce-4172-8d89-af2191e27d9f",
+      "recordedAt": "2026-10-04T19:25:12.320Z",
+      "entity": "CatalogueQuery, TextSearch (shared search)",
       "files": [
+        "app/queries/decidim/contracts_sk/catalogue_query.rb",
+        "app/queries/decidim/contracts_sk/catalogue_query/normalizer.rb",
+        "app/queries/decidim/contracts_sk/catalogue_query/conditions.rb",
+        "app/queries/decidim/contracts_sk/text_search.rb",
         "app/controllers/decidim/contracts_sk/admin/contracts_controller.rb",
-        "app/permissions/decidim/contracts_sk/permissions.rb",
-        "config/routes.rb",
-        "app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb",
-        "app/views/decidim/contracts_sk/contracts/show.html.erb",
-        "config/locales/en.yml",
-        "config/locales/sk.yml",
-        "docs/crz-import.md"
+        "app/controllers/decidim/contracts_sk/contracts_controller.rb"
       ],
       "changeKind": "added",
-      "reason": "Editor-facing round trip: preview comparison page, confirm POST, index entry link, public CRZ publication line.",
-      "expectedBehavior": "GET preview writes nothing; POST runs the command; en/sk parity; editor-only permission on published unfiled editorial records.",
-      "risk": "low",
+      "reason": "civora-platform#116: public catalogue filters and sorting as one reusable query object; fix case-sensitive q on PostgreSQL and ineffective LIKE escaping on SQLite for public and admin q via shared TextSearch",
+      "expectedBehavior": "Invalid params ignored, reversed ranges swapped, deterministic sorts with NULL amounts last, party via IN-subquery, q case-insensitive with literal % and _",
+      "risk": "medium",
       "alternatives": [],
-      "limitations": []
+      "limitations": [
+        "SQLite LOWER folds ASCII only",
+        "CRZ mirror published_at is import time"
+      ]
     }
   ],
   "tests": [
     {
-      "command": "bundle exec rubocop",
-      "startedAt": "2026-10-03T17:06:47.256Z",
-      "finishedAt": "2026-10-03T17:06:48.870Z",
-      "durationMs": 1613,
+      "command": "bundle exec rspec",
+      "startedAt": "2026-10-04T19:48:36.506Z",
+      "finishedAt": "2026-10-04T19:48:40.574Z",
+      "durationMs": 4068,
       "exitCode": 0,
       "status": "passed",
-      "stdoutSummary": "Inspecting 174 files\n..............................................................................................................................................................................\n\n174 files inspected, no offenses detected\n",
+      "stdoutSummary": "Run options: exclude {:db=>true}\n\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n\ndb/migrate/*_add_crz_filing_to_decidim_contracts_sk_contracts.rb\n  file surface and class shape\n    has exactly one migration file whose class name matches\n    is a single reversible `def change` on ActiveRecord::Migration[7.2]\n  columns\n    adds exactly the three nullable system columns, with no default, backfill or index\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_redaction_confirmation_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds only the redaction_confirmed_at column, as a plain nullable datetime\n    attaches no default and no backfill (a fabricated stamp would defeat the gate)\n    adds no index (the stamp is read per-record, never queried as a set)\n\ndb/migrate/*_add_review_decision_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the review_reason and reviewed_at columns\n    adds review_reason as a plain nullable string capped at 1000 characters\n    adds reviewed_at as a plain nullable datetime\n    attaches no default and no backfill (a fabricated judgment would defeat the gate)\n    adds no index (the decision is read per-record, never queried as a set)\n\ndb/migrate/*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  index\n    uniquely indexes (organization, source_id) under the explicit unique name\n    keeps the index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_submitted_by_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n    sorts after the migrations it reads (the contracts and audit-trail tables)\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split at the method level\n    runs the backfill only in the up direction of a reversible block\n  column\n    adds exactly one nullable reference column, decidim_submitted_by\n    attaches no default and no foreign key (the decidim_author_id precedent)\n    adds no index (the stamp is read per-record, never queried as a set)\n  backfill SQL\n    reads the latest contract.submit audit row's actor per contract, deterministically\n\ndb/migrate/*_create_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes version a NOT NULL integer\n    makes summary a NOT NULL string\n  indexes\n    uniquely indexes (contract_id, version) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_audit_events.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant reference NOT NULL with a real FK to the organizations table\n    makes the actor reference NOT NULL with a real FK to the users table\n    makes the target a NOT NULL polymorphic reference\n    makes action a NOT NULL string\n  indexes\n    indexes every reference and created_at under explicit names\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contract_links.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes the target a NOT NULL polymorphic reference with no index of its own\n  indexes\n    uniquely indexes (contract_id, target_type, target_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant and author references NOT NULL\n    makes title and reference NOT NULL strings\n    pins state as NOT NULL defaulting to draft\n    pins source as NOT NULL defaulting to editorial\n    keeps the provenance columns nullable\n  indexes\n    indexes the organization reference under an explicit name\n    indexes the author reference\n    uniquely indexes (organization, reference) under an explicit name\n    indexes (organization, state) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_documents.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL with a real FK to the contracts table\n    makes title NOT NULL\n    pins kind as NOT NULL defaulting to contract\n    keeps the file metadata columns nullable\n  indexes\n    indexes the contract reference under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_parties.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes role and name NOT NULL strings\n    keeps ico as a nullable string with the 8-character limit\n    keeps address nullable\n  indexes\n    compositely indexes (contract_id, role) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\nDecidim::ContractsSk::Admin::AmendmentForm\n  accepts a complete amendment form\n  rejects a blank summary\n  rejects a missing summary\n  caps the summary at 255 characters\n\nDecidim::ContractsSk::Admin::AuditEventsController\n  inherits from the engine's admin base controller\n  implements exactly the index action (read-only viewer)\n  does not sit on the engine's public base controller chain\n  pins the audit action vocabulary actually written by the commands\n  derives the six lifecycle-action ",
+      "stderrSummary": "",
+      "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
+      "commandTruncated": false
+    },
+    {
+      "command": "bundle exec rubocop",
+      "startedAt": "2026-10-04T19:48:40.585Z",
+      "finishedAt": "2026-10-04T19:48:41.986Z",
+      "durationMs": 1401,
+      "exitCode": 1,
+      "status": "failed",
+      "stdoutSummary": "Inspecting 185 files\n......................................................................................................................................C..................................................\n\nOffenses:\n\nspec/decidim/contracts_sk/catalogue_query_spec.rb:90:33: C: RSpec/MessageSpies: Prefer have_received for setting message expectations. Setup normalizer as a spy using allow or instance_spy.\n      expect(normalizer).not_to receive(:BigDecimal)\n                                ^^^^^^^\n\n185 files inspected, 1 offense detected\n",
       "stderrSummary": "The following cops were added to RuboCop, but are not configured. Please set Enabled to either `true` or `false` in your `.rubocop.yml` file.\n\nPlease also note that you can opt-in to new cops by default by adding this to your config:\n  AllCops:\n    NewCops: enable\nGemspec/AddRuntimeDependency: # new in 1.65\n  Enabled: true\nGemspec/AttributeAssignment: # new in 1.77\n  Enabled: true\nGemspec/DeprecatedAttributeAssignment: # new in 1.30\n  Enabled: true\nGemspec/DevelopmentDependencies: # new in 1.44\n  Enabled: true\nGemspec/RequireMFA: # new in 1.23\n  Enabled: true\nLayout/EmptyLinesAfterModuleInclusion: # new in 1.79\n  Enabled: true\nLayout/LineContinuationLeadingSpace: # new in 1.31\n  Enabled: true\nLayout/LineContinuationSpacing: # new in 1.31\n  Enabled: true\nLayout/LineEndStringConcatenationIndentation: # new in 1.18\n  Enabled: true\nLayout/SpaceBeforeBrackets: # new in 1.7\n  Enabled: true\nLint/AmbiguousAssignment: # new in 1.7\n  Enabled: true\nLint/AmbiguousOperatorPrecedence: # new in 1.21\n  Enabled: true\nLint/AmbiguousRange: # new in 1.19\n  Enabled: true\nLint/ArgumentMismatch: # new in 1.90\n  Enabled: true\nLint/ArrayLiteralInRegexp: # new in 1.71\n  Enabled: true\nLint/ConstantOverwrittenInRescue: # new in 1.31\n  Enabled: true\nLint/ConstantReassignment: # new in 1.70\n  Enabled: true\nLint/DataDefineOverride: # new in 1.85\n  Enabled: true\nLint/DeprecatedConstants: # new in 1.8\n  Enabled: true\nLint/DeprecatedReference: # new in 1.89\n  Enabled: true\nLint/DuplicateBranch: # new in 1.3\n  Enabled: true\nLint/DuplicateMagicComment: # new in 1.37\n  Enabled: true\nLint/DuplicateMatchPattern: # new in 1.50\n  Enabled: true\nLint/DuplicateRegexpCharacterClassElement: # new in 1.1\n  Enabled: true\nLint/DuplicateSetElement: # new in 1.67\n  Enabled: true\nLint/EmptyBlock: # new in 1.1\n  Enabled: true\nLint/EmptyClass: # new in 1.3\n  Enabled: true\nLint/EmptyInPattern: # new in 1.16\n  Enabled: true\nLint/HashNewWithKeywordArgumentsAsDefault: # new in 1.69\n  Enabled: true\nLint/IncompatibleIoSelectWithFiberScheduler: # new in 1.21\n  Enabled: true\nLint/ItWithoutArgumentsInBlock: # new in 1.59\n  Enabled: true\nLint/LambdaWithoutLiteralBlock: # new in 1.8\n  Enabled: true\nLint/LiteralAssignmentInCondition: # new in 1.58\n  Enabled: true\nLint/MisplacedMagicComment: # new in 1.91\n  Enabled: true\nLint/MixedCaseRange: # new in 1.53\n  Enabled: true\nLint/NameTypo: # new in 1.89\n  Enabled: true\nLint/NoReturnInBeginEndBlocks: # new in 1.2\n  Enabled: true\nLint/NonAtomicFileOperation: # new in 1.31\n  Enabled: true\nLint/NumberedParameterAssignment: # new in 1.9\n  Enabled: true\nLint/NumericOperationWithConstantResult: # new in 1.69\n  Enabled: true\nLint/OrAssignmentToConstant: # new in 1.9\n  Enabled: true\nLint/RedundantDirGlobSort: # new in 1.8\n  Enabled: true\nLint/RedundantRegexpQuantifiers: # new in 1.53\n  Enabled: true\nLint/RedundantTypeConversion: # new in 1.72\n  Enabled: true\nLint/RefinementImportMethods: # new in 1.27\n  Enabled: true\nLint/RequireRangeParentheses: # new in 1.32\n  Enabled: true\nLint/RequireRelativeSelfPath: # new in 1.22\n  Enabled: true\nLint/SharedMutableDefault: # new in 1.70\n  Enabled: true\nLint/SuperArgumentMismatch: # new in 1.90\n  Enabled: true\nLint/SuppressedExceptionInNumberConversion: # new in 1.72\n  Enabled: true\nLint/SymbolConversion: # new in 1.9\n  Enabled: true\nLint/ToEnumArguments: # new in 1.1\n  Enabled: true\nLint/TripleQuotes: # new in 1.9\n  Enabled: true\nLint/UnescapedBracketInRegexp: # new in 1.68\n  Enabled: true\nLint/UnexpectedBlockArity: # new in 1.5\n  Enabled: true\nLint/UnmodifiedReduceAccumulator: # new in 1.1\n  Enabled: true\nLint/UnreachablePatternBranch: # new in 1.85\n  Enabled: true\nLint/UselessConstantScoping: # new in 1.72\n  Enabled: true\nLint/UselessDefaultValueArgument: # new in 1.76\n  Enabled: true\nLint/UselessDefined: # new in 1.69\n  Enabled: true\nLint/UselessNumericOperation: # new in 1.66\n  Enabled: true\nLint/UselessOr: # new in 1.76\n  Enabled: true\nLint/UselessRescue: # new in 1.43\n  Enabled: true\nLint/UselessRuby2Keywords: # new in 1.23\n  Enabled: true\nMetrics/CollectionLiteralLength: # new in 1.47\n  Enabled: true\nNaming/BlockForwarding: # new in 1.24\n  Enabled: true\nNaming/PredicateMethod: # new in 1.76\n  Enabled: true\nSecurity/CompoundHash: # new in 1.28\n  Enabled: true\nSecurity/IoMethods: # new in 1.22\n  Enabled: true\nStyle/AmbiguousEndlessMethodDefinition: # new in 1.68\n  Enabled: true\nStyle/ArgumentsForwarding: # new in 1.1\n  Enabled: true\nStyle/ArrayIntersect: # new in 1.40\n  Enabled: true\nStyle/ArrayIntersectWithSingleElement: # new in 1.81\n  Enabled: true\nStyle/BitwisePredicate: # new in 1.68\n  Enabled: true\nStyle/CollectionCompact: # new in 1.2\n  Enabled: true\nStyle/CollectionQuerying: # new in 1.77\n  Enabled: true\nStyle/CombinableDefined: # new in 1.68\n  Enabled: true\nStyle/ComparableBetween: # new in 1.74\n  Enabled: true\nStyle/ComparableClamp: # new in 1.44\n  Enabled: true\nStyle/ConcatArrayLiterals: # new in 1.41\n  Enabled: true\nStyle/DataInheritance: # new in 1.49\n  Enabled: true\nStyle/DigChain: # new in 1.69\n  Enabled: true\nStyle/DirEmpty: # new in 1.48\n  Enabled: true\nStyle/DirectiveScope: # new in 1.90\n  Enabled: true\nStyle/DocumentDynamicEvalDefinition: # new in 1.1\n  Enabled: true\nStyle/EmptyClassDefinition: # new in 1.84\n  Enabled: true\nStyle/EmptyHeredoc: # new in 1.32\n  Enabled: true\nStyle/EmptyStringInsideInterpolation: # new in 1.76\n  Enabled: true\nStyle/EndlessMethod: # new in 1.8\n  Enabled: true\nStyle/EnvHome: # new in 1.29\n  Enabled: true\nStyle/ExactRegexpMatch: # new in 1.51\n  Enabled: true\nStyle/FetchEnvVar: # new in 1.28\n  Enabled: true\nStyle/FileEmpty: # new in 1.48\n  Enabled: true\nStyle/FileNull: # new in 1.69\n  Enabled: true\nStyle/FileOpen: # new in 1.85\n  Enabled: true\nStyle/FileRead: # new in 1.24\n  Enabled: true\nStyle/FileTouch: # new in 1.69\n  Enabled: true\nStyle/FileWrite: # new in 1.24\n  Enabled: true\nStyle/HashConversion: # new in 1.10\n  Enabled: true\nStyle/HashExcept: # new in 1.7\n  Enabled: true\nStyle/HashFetchChain: # new in 1.75\n  Enabled: true\nStyle/HashSlice: # new in 1.71\n  Enabled: true\nStyle/IfWithBooleanLiteralBranches: # new in 1.9\n  Enabled: true\nStyle/InPatternThen: # new in 1.16\n  Enabled: true\nStyle/ItAssignment: # new in 1.70\n  Enabled: true\nStyle/ItBlockParameter: # new in 1.75\n  Enabled: true\nStyle/KeywordArgumentsMerging: # new in 1.68\n  Enabled: true\nStyle/MagicCommentFormat: # new in 1.35\n  Enabled: true\nStyle/MapCompactWithConditionalBlock: # new in 1.30\n  Enabled: true\nStyle/MapIntoArray: # new in 1.63\n  Enabled: true\nStyle/MapJoin: # new in 1.85\n  Enabled: true\nStyle/MapToHash: # new in 1.24\n  Enabled: true\nStyle/MapToSet: # new in 1.42\n  Enabled: true\nStyle/MinMaxComparison: # new in 1.42\n  Enabled: true\nStyle/ModuleMemberExistenceCheck: # new in 1.82\n  Enabled: true\nStyle/MultilineInPatternThen: # new in 1.16\n  Enabled: true\nStyle/NegatedIfElseCondition: # new in 1.2\n  Enabled: true\nStyle/NegativeArrayIndex: # new in 1.84\n  Enabled: true\nStyle/NestedFileDirname: # new in 1.26\n  Enabled: true\nStyle/NilLambda: # new in 1.3\n  Enabled: true\nStyle/NumberedParameters: # new in 1.22\n  Enabled: true\nStyle/NumberedParametersLimit: # new in 1.22\n  Enabled: true\nStyle/ObjectThen: # new in 1.28\n  Enabled: true\nStyle/OneClassPerFile: # new in 1.85\n  Enabled: true\nStyle/OpenStructUse: # new in 1.23\n  Enabled: true\nStyle/OperatorMethodCall: # new in 1.37\n  Enabled: true\nStyle/PartitionInsteadOfDoubleSelect: # new in 1.85\n  Enabled: true\nStyle/PredicateWithKind: # new in 1.85\n  Enabled: true\nStyle/QuotedSymbols: # new in 1.16\n  Enabled: true\nStyle/ReduceToHash: # new in 1.85\n  Enabled: true\nStyle/RedundantArgument: # new in 1.4\n  Enabled: true\nStyle/RedundantArrayConstructor: # new in 1.52\n  Enabled: true\nStyle/RedundantArrayFlatten: # new in 1.76\n  Enabled: true\nStyle/RedundantConstantBase: # new in 1.40\n  Enabled: true\nStyle/RedundantCurrentDirectoryInPath: # new in 1.53\n  Enabled: true\nStyle/RedundantDoubleSplatHashBraces: # new in 1.41\n  Enabled: true\nStyle/RedundantEach: # new in 1.38\n  Enabled: true\nStyle/RedundantFilterChain: # new in 1.52\n  Enabled: true\nStyle/RedundantFormat: # new in 1.72\n  Enabled: true\nStyle/RedundantHeredocDelimiterQuotes: # new in 1.45\n  Enabled: true\nStyle/RedundantInitialize: # new in 1.27\n  Enabled: true\nStyle/RedundantInterpolationUnfreeze: # new in 1.66\n  Enabled: true\nStyle/RedundantLineContinuation: # new in 1.49\n  Enabled: true\nStyle/RedundantMinMaxBy: # new in 1.85\n  Enabled: true\nStyle/RedundantRegexpArgument: # new in 1.53\n  Enabled: true\nStyle/RedundantRegexpConstructor: # new in 1.52\n  Enabled: true\nStyle/RedundantSelfAssignmentBranch: # new in 1.19\n  Enabled: true\nStyle/RedundantStringEscape: # new in 1.37\n  Enabled: true\nStyle/ReturnNilInPredicateMethodDefinition: # new in 1.53\n  Enabled: true\nStyle/ReverseFind: # new in 1.84\n  Enabled: true\nStyle/SafeNavigationChainLength: # new in 1.68\n  Enabled: true\nStyle/SelectByKind: # new in 1.85\n  Enabled: true\nStyle/SelectByRange: # new in 1.85\n  Enabled: true\nStyle/SelectByRegexp: # new in 1.22\n  Enabled: true\nStyle/SendWithLiteralMethodName: # new in 1.64\n  Enabled: true\nStyle/SingleLineDoEndBlock: # new in 1.57\n  Enabled: true\nStyle/StringChars: # new in 1.12\n  Enabled: true\nStyle/SuperArguments: # new in 1.64\n  Enabled: true\nStyle/SuperWithArgsParentheses: # new in 1.58\n  Enabled: true\nStyle/SwapValues: # new in 1.1\n  Enabled: true\nStyle/TallyMethod: # new in 1.85\n  Enabled: true\nStyle/TimeNow: # new in 1.90\n  Enabled: true\nStyle/YAMLFileRead: # new in 1.53\n  Enabled: true\nRSpec/DiscardedMatcher: # new in 3.10\n  Enabled: true\nRSpec/IncludeExamples: # new in 3.6\n  Enabled: true\nRSpec/LeakyLocalVariable: # new in 3.8\n  Enabled: true\nRSpec/MatchWithSimpleRegex: # new in 3.10\n  Enabled: true\nRSpec/Output: # new in 3.9\n  Enabled: true\nFor more information: https://docs.rubocop.org/rubocop/versioning.html\n",
       "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
       "commandTruncated": false
     }
   ],
   "risks": [
-    "Large diff: 2757 insertions across 52 files."
+    "Working tree was dirty at session start (2 entries) — pre-existing changes may be mixed into the diff.",
+    "1 test run(s) did not pass (exit codes: 1).",
+    "Large diff: 3185 insertions across 2 files."
   ],
   "limitations": [
     "Snapshots cover only files that were changed at checkpoint time.",
     "Symbol extraction is regex-based, not AST-based.",
-    "Only observed facts are recorded — private model reasoning is not captured."
+    "Only observed facts are recorded — private model reasoning is not captured.",
+    "SQLite LOWER folds ASCII only",
+    "CRZ mirror published_at is import time"
   ],
   "agentMetadata": {
     "toolCalls": 0,
     "commands": 0,
     "checkpoints": 1,
-    "tests": 1,
-    "events": 3951
+    "tests": 2,
+    "events": 4234
   },
-  "generatedAt": "2026-10-03T17:29:00.669Z"
+  "generatedAt": "2026-10-04T20:25:38.085Z"
 }
diff --git a/.agent-review/review.md b/.agent-review/review.md
index e4dcd88..37ab205 100644
--- a/.agent-review/review.md
+++ b/.agent-review/review.md
@@ -1,52 +1,50 @@
 # Agent Review
 
 ## Task
-civora-org/civora-platform#125: CRZ round-trip — confirm the filing and link the official record
+civora-org/civora-platform#126: Admin home — my tasks, states and deadlines at a glance
 
 ## Session
-- Session ID: 3475ce5c-5efe-491e-b0c8-096df82cca8e
-- Branch: feat/crz-filing-confirmation
-- Started: 2026-10-03T16:51:14.148Z
-- Finished: 2026-10-03T17:29:00.695Z
+- Session ID: 1387a40f-616f-41e2-8cf3-0b3b3f5f4871
+- Branch: feat/catalogue-filters
+- Started: 2026-10-03T18:38:36.149Z
+- Finished: 2026-10-04T19:19:51.821Z
 
 ## Summary
-CRZ filing columns migration: civora-platform#125: store the verified CRZ filing confirmation (filed_at, published_on, override reason) as nullable system columns. Admin::ConfirmCrzFiling command, FilingLookup, FilingComparison, Mapper/CrzScope extensions: Verify a hand-filed editorial contract against the official CRZ record and stamp the filing under the row lock, with mirror absorption. Sync linked rule, G4 fix, deadline hard switch: A filing-confirmed editorial record is the canonical linked record of its CRZ id; sync must not duplicate or flag it. Failure stamps must never touch editorial rows. Deadline tracking keys on crz_filed_at. Admin filing UI, permission, routes, public detail, locales, audit labels, docs: Editor-facing round trip: preview comparison page, confirm POST, index entry link, public CRZ publication line.
+Admin dashboard (route, controller, views, menu): civora-platform#126: role-holder landing page at /admin with review queue, returned, approved, CRZ deadline, state counts and recent audit blocks; permission-driven visibility, tenant-scoped, fixed query count; sidebar entry repointed. Contract submitter scopes and index submitter filter: Shared scopes (submitted_by_user, not_submitted_by_user, awaiting_review_by, returned_to) keep the dashboard counts and the new normalized submitter=me|others index filter identical; NULL stamps handled explicitly; twin-consistency with the four-eyes predicate. Audit presentation extraction: Share ACTION_KEYS/label helpers and the table between the audit viewer and the dashboard so the two surfaces never drift. Specs and docs for the dashboard: Request specs per role, tenancy, empty states, limits, links, query-count stability; routing/menu/locale pins; docs.
 
 ## Logical Changes
 
-### 1. Admin::ConfirmCrzFiling command, FilingLookup, FilingComparison, Mapper/CrzScope extensions
-- What changed: added in `app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb`, `lib/decidim/contracts_sk/crz_import/filing_lookup.rb`, `lib/decidim/contracts_sk/crz_import/filing_comparison.rb`, `lib/decidim/contracts_sk/crz_import/mapper.rb`, `lib/decidim/contracts_sk/crz_scope.rb`
-- Why: Verify a hand-filed editorial contract against the official CRZ record and stamp the filing under the row lock, with mirror absorption.
-- Expected behavior: Fetch outside lock; in-lock re-check of source/state/filed/checksum/comparison/reason/id; one transaction with audit row; refusals broadcast as symbols.
-- Risk: medium
-- Alternatives considered: Audit absorbed-mirror row targeting the destroyed mirror (rejected: dangling target)
-### 2. Sync linked rule, G4 fix, deadline hard switch
-- What changed: modified in `app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb`, `lib/decidim/contracts_sk/crz_import/sync.rb`, `lib/decidim/contracts_sk/crz_deadline.rb`, `app/models/decidim/contracts_sk/contract.rb`, `lib/tasks/decidim_contracts_sk_crz_import.rake`
-- Why: A filing-confirmed editorial record is the canonical linked record of its CRZ id; sync must not duplicate or flag it. Failure stamps must never touch editorial rows. Deadline tracking keys on crz_filed_at.
-- Expected behavior: :linked outcome with zero writes at all decision points; linked counters; find_mirror/mark_failed scoped to source crz; tracked? uses crz_filed_at.
-- Risk: medium
-### 3. CRZ filing columns migration
-- What changed: added in `db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb`, `spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb`
-- Why: civora-platform#125: store the verified CRZ filing confirmation (filed_at, published_on, override reason) as nullable system columns.
-- Expected behavior: Additive reversible migration, no backfill, no defaults/indexes.
+### 1. Admin dashboard (route, controller, views, menu)
+- What changed: added in `config/routes.rb`, `app/controllers/decidim/contracts_sk/admin/dashboard_controller.rb`, `app/views/decidim/contracts_sk/admin/dashboard/show.html.erb`, `app/views/decidim/contracts_sk/admin/dashboard/_block.html.erb`, `lib/decidim/contracts_sk/menu.rb`, `config/locales/en.yml`, `config/locales/sk.yml`
+- Why: civora-platform#126: role-holder landing page at /admin with review queue, returned, approved, CRZ deadline, state counts and recent audit blocks; permission-driven visibility, tenant-scoped, fixed query count; sidebar entry repointed.
+- Expected behavior: GET /admin renders blocks per allowed_to? with per-block empty states and Show-all links to the filtered index; roleless denied, anonymous bounced.
 - Risk: low
-### 4. Admin filing UI, permission, routes, public detail, locales, audit labels, docs
-- What changed: added in `app/controllers/decidim/contracts_sk/admin/contracts_controller.rb`, `app/permissions/decidim/contracts_sk/permissions.rb`, `config/routes.rb`, `app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb`, `app/views/decidim/contracts_sk/contracts/show.html.erb`, `config/locales/en.yml`, `config/locales/sk.yml`, `docs/crz-import.md`
-- Why: Editor-facing round trip: preview comparison page, confirm POST, index entry link, public CRZ publication line.
-- Expected behavior: GET preview writes nothing; POST runs the command; en/sk parity; editor-only permission on published unfiled editorial records.
+### 2. Contract submitter scopes and index submitter filter
+- What changed: modified in `app/models/decidim/contracts_sk/contract.rb`, `app/controllers/decidim/contracts_sk/admin/contracts_controller.rb`, `app/views/decidim/contracts_sk/admin/contracts/index.html.erb`
+- Why: Shared scopes (submitted_by_user, not_submitted_by_user, awaiting_review_by, returned_to) keep the dashboard counts and the new normalized submitter=me|others index filter identical; NULL stamps handled explicitly; twin-consistency with the four-eyes predicate.
+- Expected behavior: Index filters by submitter, garbage normalized away, carried by chips/pagination/form.
+- Risk: low
+### 3. Audit presentation extraction
+- What changed: refactored in `app/controllers/concerns/decidim/contracts_sk/admin/audit_event_presentation.rb`, `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb`, `app/views/decidim/contracts_sk/admin/audit_events/_table.html.erb`, `app/views/decidim/contracts_sk/admin/audit_events/index.html.erb`
+- Why: Share ACTION_KEYS/label helpers and the table between the audit viewer and the dashboard so the two surfaces never drift.
+- Expected behavior: Behavior-preserving; AuditEventsController::ACTION_KEYS still resolves.
+- Risk: low
+### 4. Specs and docs for the dashboard
+- What changed: added in `spec/requests/admin/dashboard_spec.rb`, `spec/decidim/contracts_sk/engine_routing_spec.rb`, `spec/decidim/contracts_sk/menu_spec.rb`, `spec/decidim/contracts_sk_locales_spec.rb`, `README.md`, `docs/roles-and-permissions.md`, `docs/public-ui.md`, `docs/manual-test-scenarios.md`, `docs/qa-checklist.md`
+- Why: Request specs per role, tenancy, empty states, limits, links, query-count stability; routing/menu/locale pins; docs.
+- Expected behavior: Deterministic coverage of acceptance criteria.
 - Risk: low
 
 ## Test Evidence
 
 ### Run 1
-- Command: `bundle exec rubocop`
+- Command: `bundle exec rspec`
 - Result: **passed** (exit code: 0)
-- Duration: 1613 ms
+- Duration: 4473 ms
 - Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
-- Notes: stderr captured (342 lines, redacted and truncated)
 
 ## Risks
-- Large diff: 2757 insertions across 52 files.
+- None detected.
 
 ## Limitations
 - Snapshots cover only files that were changed at checkpoint time.
@@ -54,4917 +52,3481 @@ CRZ filing columns migration: civora-platform#125: store the verified CRZ filing
 - Only observed facts are recorded — private model reasoning is not captured.
 
 ## Changed Files
-- `app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb` — modified (ruby, +242/−0)
-- `app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb` — modified (ruby, +40/−6)
-- `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb` — modified (ruby, +13/−2)
-- `app/controllers/decidim/contracts_sk/admin/contracts_controller.rb` — modified (ruby, +93/−2)
-- `app/models/decidim/contracts_sk/contract.rb` — modified (ruby, +6/−5)
-- `app/permissions/decidim/contracts_sk/permissions.rb` — modified (ruby, +27/−1)
-- `app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb` — modified (unknown, +99/−0)
-- `app/views/decidim/contracts_sk/admin/contracts/index.html.erb` — modified (unknown, +11/−2)
-- `app/views/decidim/contracts_sk/contracts/show.html.erb` — modified (unknown, +19/−1)
-- `config/locales/en.yml` — modified (yaml, +55/−2)
-- `config/locales/sk.yml` — modified (yaml, +55/−2)
-- `config/routes.rb` — modified (ruby, +14/−0)
-- `db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb` — modified (ruby, +37/−0)
-- `docs/contract-lifecycle.md` — modified (markdown, +13/−8)
-- `docs/contracts-domain-notes.md` — modified (markdown, +39/−3)
-- `docs/crz-import.md` — modified (markdown, +70/−7)
-- `docs/manual-test-scenarios.md` — modified (markdown, +14/−0)
-- `docs/pilot-operations.md` — modified (markdown, +1/−1)
-- `docs/qa-checklist.md` — modified (markdown, +10/−1)
-- `docs/roles-and-permissions.md` — modified (markdown, +1/−0)
-- `lib/decidim/contracts_sk.rb` — modified (ruby, +2/−0)
-- `lib/decidim/contracts_sk/crz_deadline.rb` — modified (ruby, +8/−7)
-- `lib/decidim/contracts_sk/crz_import/filing_comparison.rb` — modified (ruby, +124/−0)
-- `lib/decidim/contracts_sk/crz_import/filing_lookup.rb` — modified (ruby, +84/−0)
-- `lib/decidim/contracts_sk/crz_import/mapper.rb` — modified (ruby, +42/−2)
-- `lib/decidim/contracts_sk/crz_import/sync.rb` — modified (ruby, +54/−24)
-- `lib/decidim/contracts_sk/crz_scope.rb` — modified (ruby, +19/−0)
-- `lib/tasks/decidim_contracts_sk_crz_import.rake` — modified (unknown, +5/−1)
-- `lib/tasks/decidim_contracts_sk_seed_demo.rake` — modified (unknown, +6/−1)
-- `README.md` — modified (markdown, +2/−2)
-- `spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb` — modified (ruby, +121/−0)
-- `spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb` — modified (ruby, +5/−4)
-- `spec/decidim/contracts_sk_crz_scope_spec.rb` — modified (ruby, +19/−0)
-- `spec/decidim/contracts_sk_locales_spec.rb` — modified (ruby, +79/−0)
-- `spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb` — modified (ruby, +4/−3)
-- `spec/decidim/contracts_sk/admin/confirm_crz_filing_spec.rb` — modified (ruby, +335/−0)
-- `spec/decidim/contracts_sk/admin/contracts_controller_spec.rb` — modified (ruby, +6/−3)
-- `spec/decidim/contracts_sk/contract_crz_deadline_spec.rb` — modified (ruby, +7/−7)
-- `spec/decidim/contracts_sk/crz_deadline_spec.rb` — modified (ruby, +5/−6)
-- `spec/decidim/contracts_sk/crz_import/filing_comparison_spec.rb` — modified (ruby, +158/−0)
-- `spec/decidim/contracts_sk/crz_import/filing_lookup_spec.rb` — modified (ruby, +88/−0)
-- `spec/decidim/contracts_sk/crz_import/mapper_spec.rb` — modified (ruby, +42/−0)
-- `spec/decidim/contracts_sk/crz_import/sync_spec.rb` — modified (ruby, +92/−0)
-- `spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb` — modified (ruby, +83/−2)
-- `spec/decidim/contracts_sk/engine_routing_spec.rb` — modified (ruby, +48/−8)
-- `spec/decidim/contracts_sk/permissions_spec.rb` — modified (ruby, +63/−0)
-- `spec/requests/admin/audit_events_spec.rb` — modified (ruby, +15/−0)
-- `spec/requests/admin/contracts_crz_deadline_spec.rb` — modified (ruby, +8/−7)
-- `spec/requests/admin/contracts_spec.rb` — modified (ruby, +10/−0)
-- `spec/requests/admin/crz_filing_spec.rb` — modified (ruby, +303/−0)
-- `spec/requests/admin/crz_import_spec.rb` — modified (ruby, +20/−0)
-- `spec/requests/contracts_spec.rb` — modified (ruby, +41/−0)
+- `.release-please-manifest.json` — modified (json, +1/−1)
+- `AGENTS.md` — modified (markdown, +1/−1)
+- `app/controllers/concerns/decidim/contracts_sk/admin/audit_event_presentation.rb` — modified (ruby, +146/−0)
+- `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb` — modified (ruby, +6/−123)
+- `app/controllers/decidim/contracts_sk/admin/contracts_controller.rb` — modified (ruby, +43/−7)
+- `app/controllers/decidim/contracts_sk/admin/dashboard_controller.rb` — modified (ruby, +165/−0)
+- `app/models/decidim/contracts_sk/contract.rb` — modified (ruby, +35/−0)
+- `app/views/decidim/contracts_sk/admin/audit_events/_table.html.erb` — modified (unknown, +60/−0)
+- `app/views/decidim/contracts_sk/admin/audit_events/index.html.erb` — modified (unknown, +7/−55)
+- `app/views/decidim/contracts_sk/admin/contracts/index.html.erb` — modified (unknown, +24/−10)
+- `app/views/decidim/contracts_sk/admin/dashboard/_block.html.erb` — modified (unknown, +71/−0)
+- `app/views/decidim/contracts_sk/admin/dashboard/show.html.erb` — modified (unknown, +70/−0)
+- `app/views/decidim/contracts_sk/shared/_admin_styles.html.erb` — modified (unknown, +47/−0)
+- `CHANGELOG.md` — modified (markdown, +15/−0)
+- `config/locales/en.yml` — modified (yaml, +51/−0)
+- `config/locales/sk.yml` — modified (yaml, +51/−0)
+- `config/routes.rb` — modified (ruby, +7/−0)
+- `docs/manual-test-scenarios.md` — modified (markdown, +1/−0)
+- `docs/public-ui.md` — modified (markdown, +15/−0)
+- `docs/qa-checklist.md` — modified (markdown, +10/−0)
+- `docs/roles-and-permissions.md` — modified (markdown, +30/−0)
+- `lib/decidim/contracts_sk/menu.rb` — modified (ruby, +7/−1)
+- `lib/decidim/contracts_sk/version.rb` — modified (ruby, +1/−1)
+- `README.md` — modified (markdown, +2/−1)
+- `spec/decidim/contracts_sk_locales_spec.rb` — modified (ruby, +82/−0)
+- `spec/decidim/contracts_sk/contract_submitter_scopes_spec.rb` — modified (ruby, +118/−0)
+- `spec/decidim/contracts_sk/engine_routing_spec.rb` — modified (ruby, +15/−5)
+- `spec/decidim/contracts_sk/menu_spec.rb` — modified (ruby, +2/−2)
+- `spec/requests/admin/contracts_submitter_filter_spec.rb` — modified (ruby, +113/−0)
+- `spec/requests/admin/dashboard_spec.rb` — modified (ruby, +583/−0)
 
 ## Commits
-- `c34981147e` feat(crz-filing): confirm the CRZ filing and link the official record (civora-org/civora-platform#125) (Denys Kozlov, 2026-10-03T19:28:40+02:00)
+- `fe5b9ef44f` Merge pull request #94 from civora-org/release-please--branches--main (Denys Kozlov, 2026-10-04T21:05:41+02:00)
+- `85fe5a4f48` chore(main): release 1.5.0 (github-actions[bot], 2026-10-04T18:55:38Z)
+- `4fde05b89c` Merge pull request #98 from civora-org/feat/admin-dashboard (Denys Kozlov, 2026-10-04T20:55:13+02:00)
+- `491c62cf7e` feat(admin): add the admin home with my tasks, states and deadlines (civora-org/civora-platform#126) (Denys Kozlov, 2026-10-04T20:38:49+02:00)
 
 ## Diff
 ```diff
 diff --git a/.agent-review/change-package.json b/.agent-review/change-package.json
-index 56ab3ef..70e11ef 100644
+index 8d210ed..1146771 100644
 --- a/.agent-review/change-package.json
 +++ b/.agent-review/change-package.json
-@@ -1,304 +1,749 @@
+@@ -1,66 +1,79 @@
  {
    "schemaVersion": "agent-review/v1",
    "session": {
--    "id": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
--    "startedAt": "2026-10-02T22:26:31.118Z",
--    "endedAt": "2026-10-02T22:27:52.305Z",
+-    "id": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+-    "startedAt": "2026-10-03T16:51:14.148Z",
+-    "endedAt": "2026-10-03T17:29:00.695Z",
 -    "status": "ended"
-+    "id": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-+    "startedAt": "2026-10-03T16:51:14.148Z",
++    "id": "1387a40f-616f-41e2-8cf3-0b3b3f5f4871",
++    "startedAt": "2026-10-03T18:38:36.149Z",
 +    "endedAt": null,
 +    "status": "active"
    },
--  "task": "Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code",
--  "branch": "chore/claude-code-config",
-+  "task": "civora-org/civora-platform#125: CRZ round-trip — confirm the filing and link the official record",
-+  "branch": "feat/crz-filing-confirmation",
+-  "task": "civora-org/civora-platform#125: CRZ round-trip — confirm the filing and link the official record",
+-  "branch": "feat/crz-filing-confirmation",
++  "task": "civora-org/civora-platform#126: Admin home — my tasks, states and deadlines at a glance",
++  "branch": "feat/catalogue-filters",
    "commits": [
      {
--      "hash": "5a3f5102c111c56ea154eb5878727e15e45169e1",
--      "subject": "chore: mirror OpenCode agent setup for Claude Code",
-+      "hash": "c34981147e9420354b899f42e0c40565ceaf7017",
-+      "subject": "feat(crz-filing): confirm the CRZ filing and link the official record (civora-org/civora-platform#125)",
+-      "hash": "c34981147e9420354b899f42e0c40565ceaf7017",
+-      "subject": "feat(crz-filing): confirm the CRZ filing and link the official record (civora-org/civora-platform#125)",
++      "hash": "fe5b9ef44f4b9d6a4a2b69fc639791d90755c2a6",
++      "subject": "Merge pull request #94 from civora-org/release-please--branches--main",
        "author": "Denys Kozlov",
--      "date": "2026-10-03T00:27:48+02:00"
-+      "date": "2026-10-03T19:28:40+02:00"
+-      "date": "2026-10-03T19:28:40+02:00"
++      "date": "2026-10-04T21:05:41+02:00"
++    },
++    {
++      "hash": "85fe5a4f48425a693e09c4463448742b32cd6244",
++      "subject": "chore(main): release 1.5.0",
++      "author": "github-actions[bot]",
++      "date": "2026-10-04T18:55:38Z"
++    },
++    {
++      "hash": "4fde05b89c9d65613604f9180c420b0705777eb5",
++      "subject": "Merge pull request #98 from civora-org/feat/admin-dashboard",
++      "author": "Denys Kozlov",
++      "date": "2026-10-04T20:55:13+02:00"
++    },
++    {
++      "hash": "491c62cf7e7e7bd149d0abbc4fad26b3915e56d7",
++      "subject": "feat(admin): add the admin home with my tasks, states and deadlines (civora-org/civora-platform#126)",
++      "author": "Denys Kozlov",
++      "date": "2026-10-04T20:38:49+02:00"
      }
    ],
    "changedFiles": [
      {
--      "path": ".agent-review/change-package.json",
-+      "path": "app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb",
+-      "path": "app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb",
++      "path": ".release-please-manifest.json",
        "kind": "modified",
--      "language": "json",
--      "insertions": 207,
--      "deletions": 341
-+      "language": "ruby",
-+      "insertions": 242,
+-      "language": "ruby",
+-      "insertions": 242,
+-      "deletions": 0,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk",
+-        "Admin",
+-        "ConfirmCrzFiling",
+-        "Refusal",
+-        "initialize",
+-        "call",
+-        "verified_record",
+-        "editor?",
+-        "normalized_reason"
+-      ]
++      "language": "json",
++      "insertions": 1,
++      "deletions": 1
++    },
++    {
++      "path": "AGENTS.md",
++      "kind": "modified",
++      "language": "markdown",
++      "insertions": 1,
++      "deletions": 1
+     },
+     {
+-      "path": "app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb",
++      "path": "app/controllers/concerns/decidim/contracts_sk/admin/audit_event_presentation.rb",
+       "kind": "modified",
+       "language": "ruby",
+-      "insertions": 40,
+-      "deletions": 6,
++      "insertions": 146,
 +      "deletions": 0,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
+       "symbols": [
+         "Decidim",
+         "ContractsSk",
+-        "CrzImport",
+-        "UpsertContract",
+-        "initialize",
+-        "call",
+-        "perform",
+-        "create_transactional",
+-        "lost_create_race",
+-        "create_or_reroute!"
 +        "Admin",
-+        "ConfirmCrzFiling",
-+        "Refusal",
-+        "initialize",
-+        "call",
-+        "verified_record",
-+        "editor?",
-+        "normalized_reason"
-+      ]
++        "AuditEventPresentation",
++        "audit_action_label",
++        "audit_actor_name",
++        "audit_target_info",
++        "contract_target_info",
++        "amendment_target_info",
++        "audit_reason_for"
+       ]
      },
      {
--      "path": ".agent-review/github/inline-comments.preview.json",
-+      "path": "app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb",
+       "path": "app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb",
        "kind": "modified",
--      "language": "json",
--      "insertions": 18,
--      "deletions": 5
-+      "language": "ruby",
-+      "insertions": 40,
-+      "deletions": 6,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "CrzImport",
-+        "UpsertContract",
-+        "initialize",
-+        "call",
-+        "perform",
-+        "create_transactional",
-+        "lost_create_race",
-+        "create_or_reroute!"
-+      ]
+       "language": "ruby",
+-      "insertions": 13,
+-      "deletions": 2,
++      "insertions": 6,
++      "deletions": 123,
+       "symbols": [
+         "Decidim",
+         "ContractsSk",
+@@ -70,16 +83,15 @@
+         "filtered_events",
+         "audit_events_scope",
+         "filtered_contract",
+-        "contracts_scope",
+-        "audit_action_label"
++        "contracts_scope"
+       ]
      },
      {
--      "path": ".agent-review/github/pr-body.md",
-+      "path": "app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb",
+       "path": "app/controllers/decidim/contracts_sk/admin/contracts_controller.rb",
        "kind": "modified",
--      "language": "markdown",
--      "insertions": 16,
--      "deletions": 9
-+      "language": "ruby",
-+      "insertions": 13,
-+      "deletions": 2,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "Admin",
-+        "AuditEventsController",
-+        "index",
-+        "filtered_events",
-+        "audit_events_scope",
-+        "filtered_contract",
-+        "contracts_scope",
-+        "audit_action_label"
-+      ]
+       "language": "ruby",
+-      "insertions": 93,
+-      "deletions": 2,
++      "insertions": 43,
++      "deletions": 7,
+       "symbols": [
+         "Decidim",
+         "ContractsSk",
+@@ -94,332 +106,174 @@
+       ]
      },
      {
--      "path": ".agent-review/github/pr-preview.json",
-+      "path": "app/controllers/decidim/contracts_sk/admin/contracts_controller.rb",
+-      "path": "app/models/decidim/contracts_sk/contract.rb",
++      "path": "app/controllers/decidim/contracts_sk/admin/dashboard_controller.rb",
        "kind": "modified",
--      "language": "json",
--      "insertions": 23,
--      "deletions": 10
-+      "language": "ruby",
-+      "insertions": 93,
-+      "deletions": 2,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
+       "language": "ruby",
+-      "insertions": 6,
+-      "deletions": 5,
++      "insertions": 165,
++      "deletions": 0,
+       "symbols": [
+         "Decidim",
+         "ContractsSk",
+-        "Contract",
+-        "crz_deadline",
+-        "crz_days_left",
+-        "crz_deadline_tracked?",
+-        "crz_deadline_status"
 +        "Admin",
-+        "ContractsController",
-+        "index",
-+        "new",
-+        "create",
-+        "edit",
-+        "update",
-+        "download_crz_handoff"
-+      ]
++        "DashboardController",
++        "show",
++        "contracts_scope",
++        "dashboard_today",
++        "review_queue_visible?",
++        "returned_visible?",
++        "approved_visible?"
+       ]
      },
      {
--      "path": ".agent-review/github/publish-plan.md",
+-      "path": "app/permissions/decidim/contracts_sk/permissions.rb",
 +      "path": "app/models/decidim/contracts_sk/contract.rb",
        "kind": "modified",
--      "language": "markdown",
--      "insertions": 5,
--      "deletions": 4
-+      "language": "ruby",
-+      "insertions": 6,
-+      "deletions": 5,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
+       "language": "ruby",
+-      "insertions": 27,
+-      "deletions": 1,
++      "insertions": 35,
++      "deletions": 0,
+       "symbols": [
+         "Decidim",
+         "ContractsSk",
+-        "Permissions",
+-        "permissions",
+-        "admin_action",
+-        "audit_event_action",
+-        "contract_action",
+-        "self_review_blocked?",
+-        "child_record_action",
+-        "amendment_action"
 +        "Contract",
 +        "crz_deadline",
 +        "crz_days_left",
 +        "crz_deadline_tracked?",
 +        "crz_deadline_status"
-+      ]
+       ]
      },
      {
--      "path": ".agent-review/review.md",
-+      "path": "app/permissions/decidim/contracts_sk/permissions.rb",
+-      "path": "app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb",
++      "path": "app/views/decidim/contracts_sk/admin/audit_events/_table.html.erb",
        "kind": "modified",
--      "language": "markdown",
--      "insertions": 4156,
--      "deletions": 997
-+      "language": "ruby",
-+      "insertions": 27,
-+      "deletions": 1,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "Permissions",
-+        "permissions",
-+        "admin_action",
-+        "audit_event_action",
-+        "contract_action",
-+        "self_review_blocked?",
-+        "child_record_action",
-+        "amendment_action"
-+      ]
+       "language": "unknown",
+-      "insertions": 99,
++      "insertions": 60,
+       "deletions": 0
      },
      {
--      "path": ".claude/agents/architect.md",
-+      "path": "app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb",
+-      "path": "app/views/decidim/contracts_sk/admin/contracts/index.html.erb",
++      "path": "app/views/decidim/contracts_sk/admin/audit_events/index.html.erb",
        "kind": "modified",
--      "language": "markdown",
--      "insertions": 39,
-+      "language": "unknown",
-+      "insertions": 99,
-       "deletions": 0
+       "language": "unknown",
+-      "insertions": 11,
+-      "deletions": 2
++      "insertions": 7,
++      "deletions": 55
      },
      {
--      "path": ".claude/agents/integration.md",
+-      "path": "app/views/decidim/contracts_sk/contracts/show.html.erb",
 +      "path": "app/views/decidim/contracts_sk/admin/contracts/index.html.erb",
        "kind": "modified",
--      "language": "markdown",
--      "insertions": 34,
--      "deletions": 0
+       "language": "unknown",
+-      "insertions": 19,
+-      "deletions": 1
++      "insertions": 24,
++      "deletions": 10
+     },
+     {
+-      "path": "config/locales/en.yml",
++      "path": "app/views/decidim/contracts_sk/admin/dashboard/_block.html.erb",
+       "kind": "modified",
+-      "language": "yaml",
+-      "insertions": 55,
+-      "deletions": 2
 +      "language": "unknown",
-+      "insertions": 11,
-+      "deletions": 2
++      "insertions": 71,
++      "deletions": 0
      },
      {
--      "path": ".claude/agents/rails.md",
-+      "path": "app/views/decidim/contracts_sk/contracts/show.html.erb",
+-      "path": "config/locales/sk.yml",
++      "path": "app/views/decidim/contracts_sk/admin/dashboard/show.html.erb",
        "kind": "modified",
--      "language": "markdown",
--      "insertions": 27,
--      "deletions": 0
+-      "language": "yaml",
+-      "insertions": 55,
+-      "deletions": 2
 +      "language": "unknown",
-+      "insertions": 19,
-+      "deletions": 1
++      "insertions": 70,
++      "deletions": 0
      },
      {
--      "path": ".claude/agents/retro.md",
+-      "path": "config/routes.rb",
++      "path": "app/views/decidim/contracts_sk/shared/_admin_styles.html.erb",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 14,
++      "language": "unknown",
++      "insertions": 47,
+       "deletions": 0
+     },
+     {
+-      "path": "db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb",
++      "path": "CHANGELOG.md",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 37,
+-      "deletions": 0,
+-      "symbols": [
+-        "AddCrzFilingToDecidimContractsSkContracts",
+-        "change"
+-      ]
++      "language": "markdown",
++      "insertions": 15,
++      "deletions": 0
+     },
+     {
+-      "path": "docs/contract-lifecycle.md",
 +      "path": "config/locales/en.yml",
        "kind": "modified",
 -      "language": "markdown",
--      "insertions": 24,
--      "deletions": 0
+-      "insertions": 13,
+-      "deletions": 8
 +      "language": "yaml",
-+      "insertions": 55,
-+      "deletions": 2
++      "insertions": 51,
++      "deletions": 0
      },
      {
--      "path": ".claude/agents/reviewer.md",
+-      "path": "docs/contracts-domain-notes.md",
 +      "path": "config/locales/sk.yml",
        "kind": "modified",
 -      "language": "markdown",
--      "insertions": 35,
--      "deletions": 0
+-      "insertions": 39,
+-      "deletions": 3
 +      "language": "yaml",
-+      "insertions": 55,
-+      "deletions": 2
++      "insertions": 51,
++      "deletions": 0
      },
      {
--      "path": ".claude/agents/tester.md",
+-      "path": "docs/crz-import.md",
 +      "path": "config/routes.rb",
        "kind": "modified",
 -      "language": "markdown",
--      "insertions": 36,
+-      "insertions": 70,
+-      "deletions": 7
 +      "language": "ruby",
-+      "insertions": 14,
-       "deletions": 0
++      "insertions": 7,
++      "deletions": 0
      },
      {
--      "path": ".claude/settings.json",
-+      "path": "db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb",
+       "path": "docs/manual-test-scenarios.md",
        "kind": "modified",
--      "language": "json",
--      "insertions": 56,
--      "deletions": 0
-+      "language": "ruby",
-+      "insertions": 37,
-+      "deletions": 0,
-+      "symbols": [
-+        "AddCrzFilingToDecidimContractsSkContracts",
-+        "change"
-+      ]
+       "language": "markdown",
+-      "insertions": 14,
++      "insertions": 1,
+       "deletions": 0
      },
      {
--      "path": ".claude/skills/agent-review",
-+      "path": "docs/contract-lifecycle.md",
+-      "path": "docs/pilot-operations.md",
++      "path": "docs/public-ui.md",
        "kind": "modified",
--      "language": "unknown",
+       "language": "markdown",
 -      "insertions": 1,
--      "deletions": 0
-+      "language": "markdown",
-+      "insertions": 13,
-+      "deletions": 8
+-      "deletions": 1
++      "insertions": 15,
++      "deletions": 0
      },
      {
--      "path": ".claude/skills/agent-review-github-status/SKILL.md",
-+      "path": "docs/contracts-domain-notes.md",
+       "path": "docs/qa-checklist.md",
        "kind": "modified",
        "language": "markdown",
--      "insertions": 21,
--      "deletions": 0
-+      "insertions": 39,
-+      "deletions": 3
+       "insertions": 10,
+-      "deletions": 1
++      "deletions": 0
      },
      {
--      "path": ".claude/skills/agent-review-prepare-pr/SKILL.md",
-+      "path": "docs/crz-import.md",
+       "path": "docs/roles-and-permissions.md",
        "kind": "modified",
        "language": "markdown",
--      "insertions": 25,
--      "deletions": 0
-+      "insertions": 70,
-+      "deletions": 7
+-      "insertions": 1,
++      "insertions": 30,
+       "deletions": 0
      },
      {
--      "path": ".claude/skills/agent-review-publish-pr/SKILL.md",
-+      "path": "docs/manual-test-scenarios.md",
+-      "path": "lib/decidim/contracts_sk.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 2,
+-      "deletions": 0,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk",
+-        "Error"
+-      ]
+-    },
+-    {
+-      "path": "lib/decidim/contracts_sk/crz_deadline.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 8,
+-      "deletions": 7,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk",
+-        "crz_deadline=",
+-        "CrzDeadline",
+-        "ThresholdError",
+-        "deadline_for",
+-        "days_left",
+-        "threshold",
+-        "status",
+-        "tracked?"
+-      ]
+-    },
+-    {
+-      "path": "lib/decidim/contracts_sk/crz_import/filing_comparison.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 124,
+-      "deletions": 0,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk",
+-        "CrzImport",
+-        "FilingComparison",
+-        "self",
+-        "initialize",
+-        "rows",
+-        "all_match?",
+-        "needs_reason?",
+-        "reference_row"
+-      ]
+-    },
+-    {
+-      "path": "lib/decidim/contracts_sk/crz_import/filing_lookup.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 84,
+-      "deletions": 0,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk",
+-        "CrzImport",
+-        "FilingLookup",
+-        "ok?",
+-        "self",
+-        "initialize",
+-        "call",
+-        "client",
+-        "fetch"
+-      ]
+-    },
+-    {
+-      "path": "lib/decidim/contracts_sk/crz_import/mapper.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 42,
+-      "deletions": 2,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk",
+-        "CrzImport",
+-        "Mapper",
+-        "Error",
+-        "map",
+-        "checksum",
+-        "contract_attributes",
+-        "title_from",
+-        "reference_from"
+-      ]
+-    },
+-    {
+-      "path": "lib/decidim/contracts_sk/crz_import/sync.rb",
++      "path": "lib/decidim/contracts_sk/menu.rb",
        "kind": "modified",
-       "language": "markdown",
--      "insertions": 26,
-+      "insertions": 14,
-       "deletions": 0
+       "language": "ruby",
+-      "insertions": 54,
+-      "deletions": 24,
++      "insertions": 7,
++      "deletions": 1,
+       "symbols": [
+         "Decidim",
+         "ContractsSk",
+-        "CrzImport",
+-        "Sync",
+-        "run",
+-        "import_one",
+-        "initialize",
+-        "run_cursor_pages",
+-        "process_page",
+-        "upsert_record!"
++        "Menu",
++        "self"
+       ]
      },
      {
--      "path": ".claude/skills/agent-review-update-review/SKILL.md",
-+      "path": "docs/pilot-operations.md",
+-      "path": "lib/decidim/contracts_sk/crz_scope.rb",
++      "path": "lib/decidim/contracts_sk/version.rb",
        "kind": "modified",
-       "language": "markdown",
--      "insertions": 23,
--      "deletions": 0
+       "language": "ruby",
+-      "insertions": 19,
+-      "deletions": 0,
 +      "insertions": 1,
-+      "deletions": 1
++      "deletions": 1,
+       "symbols": [
+         "Decidim",
+-        "ContractsSk",
+-        "self",
+-        "CrzScope",
+-        "in_scope?"
++        "ContractsSk"
+       ]
      },
+-    {
+-      "path": "lib/tasks/decidim_contracts_sk_crz_import.rake",
+-      "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 5,
+-      "deletions": 1
+-    },
+-    {
+-      "path": "lib/tasks/decidim_contracts_sk_seed_demo.rake",
+-      "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 6,
+-      "deletions": 1
+-    },
      {
--      "path": ".claude/skills/feature/SKILL.md",
-+      "path": "docs/qa-checklist.md",
+       "path": "README.md",
        "kind": "modified",
        "language": "markdown",
--      "insertions": 22,
+       "insertions": 2,
+-      "deletions": 2
+-    },
+-    {
+-      "path": "spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 121,
+-      "deletions": 0,
+-      "symbols": [
+-        "migration_files",
+-        "migration_path",
+-        "migration_class_name",
+-        "base_migration_path",
+-        "table_name",
+-        "stripped_lines",
+-        "column_line",
+-        "column_by_name"
+-      ]
+-    },
+-    {
+-      "path": "spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 5,
+-      "deletions": 4,
+-      "symbols": [
+-        "migration_files",
+-        "migration_path",
+-        "migration_class_name",
+-        "migration_path_for",
+-        "table_name",
+-        "stripped_lines",
+-        "prerequisite_migrations!",
+-        "column_by_name",
+-        "sql_value",
+-        "insert_contract"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk_crz_scope_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 19,
 -      "deletions": 0
-+      "insertions": 10,
 +      "deletions": 1
      },
      {
--      "path": ".claude/skills/issue/SKILL.md",
-+      "path": "docs/roles-and-permissions.md",
+       "path": "spec/decidim/contracts_sk_locales_spec.rb",
        "kind": "modified",
-       "language": "markdown",
--      "insertions": 23,
-+      "insertions": 1,
-       "deletions": 0
+       "language": "ruby",
+-      "insertions": 79,
++      "insertions": 82,
+       "deletions": 0,
+       "symbols": [
+         "LocaleContract",
+@@ -434,123 +288,23 @@
+       ]
      },
      {
--      "path": ".claude/skills/retro/SKILL.md",
-+      "path": "lib/decidim/contracts_sk.rb",
+-      "path": "spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb",
++      "path": "spec/decidim/contracts_sk/contract_submitter_scopes_spec.rb",
        "kind": "modified",
--      "language": "markdown",
--      "insertions": 21,
--      "deletions": 0
-+      "language": "ruby",
-+      "insertions": 2,
-+      "deletions": 0,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "Error"
-+      ]
+       "language": "ruby",
+-      "insertions": 4,
+-      "deletions": 3,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk/admin/confirm_crz_filing_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 335,
++      "insertions": 118,
+       "deletions": 0,
+-      "symbols": [
+-        "create_editorial",
+-        "call_command",
+-        "expect_untouched"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk/admin/contracts_controller_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 6,
+-      "deletions": 3,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk/contract_crz_deadline_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 7,
+-      "deletions": 7,
+       "symbols": [
+         "create_contract!",
+-        "references"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk/crz_deadline_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 5,
+-      "deletions": 6,
+-      "symbols": [
+-        "date",
+-        "tracked?"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk/crz_import/filing_comparison_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 158,
+-      "deletions": 0,
+-      "symbols": [
+-        "crz_payload",
+-        "record",
+-        "contract",
+-        "statuses",
+-        "compare"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk/crz_import/filing_lookup_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 88,
+-      "deletions": 0,
+-      "symbols": [
+-        "lookup"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk/crz_import/mapper_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 42,
+-      "deletions": 0,
+-      "symbols": [
+-        "crz_payload"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk/crz_import/sync_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 92,
+-      "deletions": 0,
+-      "symbols": [
+-        "page",
+-        "run_sync"
+-      ]
+-    },
+-    {
+-      "path": "spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 83,
+-      "deletions": 2,
+-      "symbols": [
+-        "call_command",
+-        "expect_linked_without_writes"
++        "references",
++        "seed!"
+       ]
      },
      {
--      "path": ".claude/skills/review/SKILL.md",
-+      "path": "lib/decidim/contracts_sk/crz_deadline.rb",
+       "path": "spec/decidim/contracts_sk/engine_routing_spec.rb",
        "kind": "modified",
--      "language": "markdown",
-+      "language": "ruby",
-+      "insertions": 8,
-+      "deletions": 7,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "crz_deadline=",
-+        "CrzDeadline",
-+        "ThresholdError",
-+        "deadline_for",
-+        "days_left",
-+        "threshold",
-+        "status",
-+        "tracked?"
-+      ]
-+    },
-+    {
-+      "path": "lib/decidim/contracts_sk/crz_import/filing_comparison.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 124,
-+      "deletions": 0,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "CrzImport",
-+        "FilingComparison",
-+        "self",
-+        "initialize",
-+        "rows",
-+        "all_match?",
-+        "needs_reason?",
-+        "reference_row"
-+      ]
-+    },
-+    {
-+      "path": "lib/decidim/contracts_sk/crz_import/filing_lookup.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 84,
-+      "deletions": 0,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "CrzImport",
-+        "FilingLookup",
-+        "ok?",
-+        "self",
-+        "initialize",
-+        "call",
-+        "client",
-+        "fetch"
-+      ]
-+    },
-+    {
-+      "path": "lib/decidim/contracts_sk/crz_import/mapper.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 42,
-+      "deletions": 2,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "CrzImport",
-+        "Mapper",
-+        "Error",
-+        "map",
-+        "checksum",
-+        "contract_attributes",
-+        "title_from",
-+        "reference_from"
-+      ]
-+    },
-+    {
-+      "path": "lib/decidim/contracts_sk/crz_import/sync.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 54,
-+      "deletions": 24,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "CrzImport",
-+        "Sync",
-+        "run",
-+        "import_one",
-+        "initialize",
-+        "run_cursor_pages",
-+        "process_page",
-+        "upsert_record!"
-+      ]
-+    },
-+    {
-+      "path": "lib/decidim/contracts_sk/crz_scope.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-       "insertions": 19,
--      "deletions": 0
-+      "deletions": 0,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk",
-+        "self",
-+        "CrzScope",
-+        "in_scope?"
-+      ]
+       "language": "ruby",
+-      "insertions": 48,
+-      "deletions": 8,
++      "insertions": 15,
++      "deletions": 5,
+       "symbols": [
+         "EngineRoutingContract",
+         "route_triples",
+@@ -565,185 +319,130 @@
+       ]
      },
      {
--      "path": ".claude/skills/verify/SKILL.md",
-+      "path": "lib/tasks/decidim_contracts_sk_crz_import.rake",
+-      "path": "spec/decidim/contracts_sk/permissions_spec.rb",
++      "path": "spec/decidim/contracts_sk/menu_spec.rb",
        "kind": "modified",
--      "language": "markdown",
--      "insertions": 20,
--      "deletions": 0
-+      "language": "unknown",
-+      "insertions": 5,
-+      "deletions": 1
+       "language": "ruby",
+-      "insertions": 63,
+-      "deletions": 0,
++      "insertions": 2,
++      "deletions": 2,
+       "symbols": [
+         "admin?",
+         "admin_terms_accepted?",
+-        "action_for",
+-        "unset?",
+-        "resolver_of",
++        "decidim_contracts_sk",
++        "items_for",
+         "swap_resolver",
+-        "user_with_roles",
+-        "filing_user_with_roles",
+-        "filing_action",
+-        "redaction_user_with_roles"
++        "recording_resolver",
++        "org_scoped_resolver"
+       ]
      },
      {
--      "path": ".mcp.json",
-+      "path": "lib/tasks/decidim_contracts_sk_seed_demo.rake",
+-      "path": "spec/requests/admin/audit_events_spec.rb",
++      "path": "spec/requests/admin/contracts_submitter_filter_spec.rb",
        "kind": "modified",
--      "language": "json",
--      "insertions": 16,
--      "deletions": 0
-+      "language": "unknown",
-+      "insertions": 6,
-+      "deletions": 1
+       "language": "ruby",
+-      "insertions": 15,
++      "insertions": 113,
+       "deletions": 0,
+       "symbols": [
+-        "sign_in",
+-        "create_contract!",
+-        "create_event!"
+-      ]
+-    },
+-    {
+-      "path": "spec/requests/admin/contracts_crz_deadline_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 8,
+-      "deletions": 7,
+-      "symbols": [
+-        "create_contract!",
+-        "references_in",
+-        "with_slovak",
+-        "seed_deadline_set!"
+-      ]
+-    },
+-    {
+-      "path": "spec/requests/admin/contracts_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 10,
+-      "deletions": 0,
+-      "symbols": [
+-        "RecordingIndexScope",
+-        "initialize",
+-        "where",
+-        "not",
+-        "order",
+-        "group",
+-        "count",
+-        "crz_overdue",
+-        "crz_due_soon",
+-        "CountingView"
+-      ]
+-    },
+-    {
+-      "path": "spec/requests/admin/crz_filing_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 303,
+-      "deletions": 0,
+-      "symbols": [
+-        "sign_in_as"
++        "references"
+       ]
      },
      {
--      "path": "AGENTS.md",
-+      "path": "README.md",
+-      "path": "spec/requests/admin/crz_import_spec.rb",
++      "path": "spec/requests/admin/dashboard_spec.rb",
        "kind": "modified",
-       "language": "markdown",
--      "insertions": 1,
--      "deletions": 0
-+      "insertions": 2,
-+      "deletions": 2
-     },
+       "language": "ruby",
+-      "insertions": 20,
++      "insertions": 583,
+       "deletions": 0,
+       "symbols": [
+         "sign_in",
+-        "stub_transport",
+-        "response_with"
+-      ]
+-    },
+-    {
+-      "path": "spec/requests/contracts_spec.rb",
+-      "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 41,
+-      "deletions": 0,
+-      "symbols": [
+-        "PublishedContractFixture",
+-        "PaginableStub",
+-        "initialize",
+-        "page",
+-        "per",
+-        "each",
+-        "any?",
+-        "current_page",
+-        "prev_page",
+-        "next_page"
++        "create_contract!",
++        "create_event!",
++        "queue_item!",
++        "returned_item!",
++        "approved_item!",
++        "overdue_signed_on",
++        "due_soon_signed_on",
++        "body",
++        "count_queries"
+       ]
+     }
+   ],
+   "logicalChanges": [
      {
--      "path": "CLAUDE.md",
-+      "path": "spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb",
-       "kind": "modified",
--      "language": "markdown",
--      "insertions": 25,
-+      "language": "ruby",
-+      "insertions": 121,
-+      "deletions": 0,
-+      "symbols": [
-+        "migration_files",
-+        "migration_path",
-+        "migration_class_name",
-+        "base_migration_path",
-+        "table_name",
-+        "stripped_lines",
-+        "column_line",
-+        "column_by_name"
-+      ]
-+    },
-+    {
-+      "path": "spec/db/migrate/add_submitted_by_to_decidim_contracts_sk_contracts_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 5,
-+      "deletions": 4,
-+      "symbols": [
-+        "migration_files",
-+        "migration_path",
-+        "migration_class_name",
-+        "migration_path_for",
-+        "table_name",
-+        "stripped_lines",
-+        "prerequisite_migrations!",
-+        "column_by_name",
-+        "sql_value",
-+        "insert_contract"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk_crz_scope_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 19,
-       "deletions": 0
--    }
--  ],
--  "logicalChanges": [
-+    },
+-      "id": "1a77f7ce-a784-4832-9c60-3e9c8df9cb4c",
+-      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+-      "recordedAt": "2026-10-03T17:06:39.454Z",
+-      "entity": "CRZ filing columns migration",
++      "id": "fcd00ed1-4442-4109-b7b0-f9a0a466bbdc",
++      "sessionId": "1387a40f-616f-41e2-8cf3-0b3b3f5f4871",
++      "recordedAt": "2026-10-03T18:46:47.486Z",
++      "entity": "Admin dashboard (route, controller, views, menu)",
+       "files": [
+-        "db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb",
+-        "spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb"
++        "config/routes.rb",
++        "app/controllers/decidim/contracts_sk/admin/dashboard_controller.rb",
++        "app/views/decidim/contracts_sk/admin/dashboard/show.html.erb",
++        "app/views/decidim/contracts_sk/admin/dashboard/_block.html.erb",
++        "lib/decidim/contracts_sk/menu.rb",
++        "config/locales/en.yml",
++        "config/locales/sk.yml"
+       ],
+       "changeKind": "added",
+-      "reason": "civora-platform#125: store the verified CRZ filing confirmation (filed_at, published_on, override reason) as nullable system columns.",
+-      "expectedBehavior": "Additive reversible migration, no backfill, no defaults/indexes.",
++      "reason": "civora-platform#126: role-holder landing page at /admin with review queue, returned, approved, CRZ deadline, state counts and recent audit blocks; permission-driven visibility, tenant-scoped, fixed query count; sidebar entry repointed.",
++      "expectedBehavior": "GET /admin renders blocks per allowed_to? with per-block empty states and Show-all links to the filtered index; roleless denied, anonymous bounced.",
+       "risk": "low",
+       "alternatives": [],
+-      "limitations": []
++      "limitations": [],
++      "evidence": "CONTRACTS_SK_DB=1 bundle exec rspec: 1482 examples, 0 failures; offline 909, 0 failures; rubocop clean"
+     },
      {
--      "id": "31f58dca-257b-42df-b67e-cf78fb49b15a",
--      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
--      "recordedAt": "2026-10-02T22:26:44.812Z",
--      "entity": "Claude Code subagents",
--      "files": [
--        ".claude/agents/architect.md",
--        ".claude/agents/reviewer.md",
--        ".claude/agents/rails.md",
--        ".claude/agents/tester.md",
--        ".claude/agents/integration.md",
--        ".claude/agents/retro.md"
+-      "id": "77e75c1a-89f9-4f75-8b46-230e9df03f7f",
+-      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+-      "recordedAt": "2026-10-03T17:06:42.120Z",
+-      "entity": "Admin::ConfirmCrzFiling command, FilingLookup, FilingComparison, Mapper/CrzScope extensions",
++      "id": "d7caf568-eea1-4723-887c-20286e53ca46",
++      "sessionId": "1387a40f-616f-41e2-8cf3-0b3b3f5f4871",
++      "recordedAt": "2026-10-03T18:46:49.972Z",
++      "entity": "Contract submitter scopes and index submitter filter",
+       "files": [
+-        "app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb",
+-        "lib/decidim/contracts_sk/crz_import/filing_lookup.rb",
+-        "lib/decidim/contracts_sk/crz_import/filing_comparison.rb",
+-        "lib/decidim/contracts_sk/crz_import/mapper.rb",
+-        "lib/decidim/contracts_sk/crz_scope.rb"
 -      ],
 -      "changeKind": "added",
--      "reason": "Port .opencode/agents to Claude Code subagents so both harnesses share the same roles",
--      "expectedBehavior": "architect/reviewer run on opus with read-only tools; rails/tester/integration/retro on sonnet; bodies identical to the OpenCode agents",
--      "risk": "low",
+-      "reason": "Verify a hand-filed editorial contract against the official CRZ record and stamp the filing under the row lock, with mirror absorption.",
+-      "expectedBehavior": "Fetch outside lock; in-lock re-check of source/state/filed/checksum/comparison/reason/id; one transaction with audit row; refusals broadcast as symbols.",
+-      "risk": "medium",
 -      "alternatives": [
--        "Keep GLM-only OpenCode agents"
--      ],
--      "limitations": [
--        "The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md"
-+      "path": "spec/decidim/contracts_sk_locales_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 79,
-+      "deletions": 0,
-+      "symbols": [
-+        "LocaleContract",
-+        "locale_file",
-+        "translations",
-+        "module_tree",
-+        "leaf_paths",
-+        "leaf_values",
-+        "fresh_backend",
-+        "PublicCatalogueLabels",
-+        "CrzDeadlineLabels"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/admin/audit_events_controller_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 4,
-+      "deletions": 3,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/admin/confirm_crz_filing_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 335,
-+      "deletions": 0,
-+      "symbols": [
-+        "create_editorial",
-+        "call_command",
-+        "expect_untouched"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/admin/contracts_controller_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 6,
-+      "deletions": 3,
-+      "symbols": [
-+        "Decidim",
-+        "ContractsSk"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/contract_crz_deadline_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 7,
-+      "deletions": 7,
-+      "symbols": [
-+        "create_contract!",
-+        "references"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/crz_deadline_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 5,
-+      "deletions": 6,
-+      "symbols": [
-+        "date",
-+        "tracked?"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/crz_import/filing_comparison_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 158,
-+      "deletions": 0,
-+      "symbols": [
-+        "crz_payload",
-+        "record",
-+        "contract",
-+        "statuses",
-+        "compare"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/crz_import/filing_lookup_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 88,
-+      "deletions": 0,
-+      "symbols": [
-+        "lookup"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/crz_import/mapper_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 42,
-+      "deletions": 0,
-+      "symbols": [
-+        "crz_payload"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/crz_import/sync_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 92,
-+      "deletions": 0,
-+      "symbols": [
-+        "page",
-+        "run_sync"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/crz_import/upsert_contract_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 83,
-+      "deletions": 2,
-+      "symbols": [
-+        "call_command",
-+        "expect_linked_without_writes"
-+      ]
-+    },
-+    {
-+      "path": "spec/decidim/contracts_sk/engine_routing_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 48,
-+      "deletions": 8,
-+      "symbols": [
-+        "EngineRoutingContract",
-+        "route_triples",
-+        "public_routes",
-+        "admin_routes",
-+        "party_routes",
-+        "document_routes",
-+        "amendment_routes",
-+        "link_routes",
-+        "audit_event_routes",
-+        "controllers_of"
-       ]
-     },
-     {
--      "id": "52236dd7-6925-41b6-9df3-c8d3c80bd018",
--      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
--      "recordedAt": "2026-10-02T22:26:44.912Z",
--      "entity": "Claude Code slash-command skills",
-+      "path": "spec/decidim/contracts_sk/permissions_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 63,
-+      "deletions": 0,
-+      "symbols": [
-+        "admin?",
-+        "admin_terms_accepted?",
-+        "action_for",
-+        "unset?",
-+        "resolver_of",
-+        "swap_resolver",
-+        "user_with_roles",
-+        "filing_user_with_roles",
-+        "filing_action",
-+        "redaction_user_with_roles"
-+      ]
-+    },
-+    {
-+      "path": "spec/requests/admin/audit_events_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 15,
-+      "deletions": 0,
-+      "symbols": [
-+        "sign_in",
-+        "create_contract!",
-+        "create_event!"
-+      ]
-+    },
-+    {
-+      "path": "spec/requests/admin/contracts_crz_deadline_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 8,
-+      "deletions": 7,
-+      "symbols": [
-+        "create_contract!",
-+        "references_in",
-+        "with_slovak",
-+        "seed_deadline_set!"
-+      ]
-+    },
-+    {
-+      "path": "spec/requests/admin/contracts_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 10,
-+      "deletions": 0,
-+      "symbols": [
-+        "RecordingIndexScope",
-+        "initialize",
-+        "where",
-+        "not",
-+        "order",
-+        "group",
-+        "count",
-+        "crz_overdue",
-+        "crz_due_soon",
-+        "CountingView"
-+      ]
-+    },
-+    {
-+      "path": "spec/requests/admin/crz_filing_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 303,
-+      "deletions": 0,
-+      "symbols": [
-+        "sign_in_as"
-+      ]
-+    },
-+    {
-+      "path": "spec/requests/admin/crz_import_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 20,
-+      "deletions": 0,
-+      "symbols": [
-+        "sign_in",
-+        "stub_transport",
-+        "response_with"
-+      ]
-+    },
-+    {
-+      "path": "spec/requests/contracts_spec.rb",
-+      "kind": "modified",
-+      "language": "ruby",
-+      "insertions": 41,
-+      "deletions": 0,
-+      "symbols": [
-+        "PublishedContractFixture",
-+        "PaginableStub",
-+        "initialize",
-+        "page",
-+        "per",
-+        "each",
-+        "any?",
-+        "current_page",
-+        "prev_page",
-+        "next_page"
-+      ]
-+    }
-+  ],
-+  "logicalChanges": [
-+    {
-+      "id": "1a77f7ce-a784-4832-9c60-3e9c8df9cb4c",
-+      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-+      "recordedAt": "2026-10-03T17:06:39.454Z",
-+      "entity": "CRZ filing columns migration",
-       "files": [
--        ".claude/skills/issue/SKILL.md",
--        ".claude/skills/feature/SKILL.md",
--        ".claude/skills/review/SKILL.md",
--        ".claude/skills/verify/SKILL.md",
--        ".claude/skills/retro/SKILL.md",
--        ".claude/skills/agent-review-github-status/SKILL.md",
--        ".claude/skills/agent-review-prepare-pr/SKILL.md",
--        ".claude/skills/agent-review-publish-pr/SKILL.md",
--        ".claude/skills/agent-review-update-review/SKILL.md"
-+        "db/migrate/20261003000002_add_crz_filing_to_decidim_contracts_sk_contracts.rb",
-+        "spec/db/migrate/add_crz_filing_to_decidim_contracts_sk_contracts_spec.rb"
-       ],
-       "changeKind": "added",
--      "reason": "Port the 9 .opencode/commands to Claude Code skills invoked as /<name>",
--      "expectedBehavior": "/issue reads civora-org/civora-platform issues via gh; publish-pr, update-review and retro are user-invoked only (disable-model-invocation)",
-+      "reason": "civora-platform#125: store the verified CRZ filing confirmation (filed_at, published_on, override reason) as nullable system columns.",
-+      "expectedBehavior": "Additive reversible migration, no backfill, no defaults/indexes.",
-       "risk": "low",
-       "alternatives": [],
-       "limitations": []
-     },
-     {
--      "id": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
--      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
--      "recordedAt": "2026-10-02T22:26:45.009Z",
--      "entity": "agent-review skill, MCP servers and journaling hook",
-+      "id": "77e75c1a-89f9-4f75-8b46-230e9df03f7f",
-+      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-+      "recordedAt": "2026-10-03T17:06:42.120Z",
-+      "entity": "Admin::ConfirmCrzFiling command, FilingLookup, FilingComparison, Mapper/CrzScope extensions",
-       "files": [
--        ".claude/skills/agent-review",
--        ".mcp.json",
--        ".claude/settings.json"
-+        "app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb",
-+        "lib/decidim/contracts_sk/crz_import/filing_lookup.rb",
-+        "lib/decidim/contracts_sk/crz_import/filing_comparison.rb",
-+        "lib/decidim/contracts_sk/crz_import/mapper.rb",
-+        "lib/decidim/contracts_sk/crz_scope.rb"
-       ],
-       "changeKind": "added",
--      "reason": "Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers",
--      "expectedBehavior": "Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active",
-+      "reason": "Verify a hand-filed editorial contract against the official CRZ record and stamp the filing under the row lock, with mirror absorption.",
-+      "expectedBehavior": "Fetch outside lock; in-lock re-check of source/state/filed/checksum/comparison/reason/id; one transaction with audit row; refusals broadcast as symbols.",
-       "risk": "medium",
--      "alternatives": [],
--      "limitations": [
--        "Absolute machine paths in .mcp.json (same as opencode.jsonc)",
--        "Hook assumes agent-review is a sibling checkout",
--        "Skill is a symlink into ../agent-review"
-+      "alternatives": [
-+        "Audit absorbed-mirror row targeting the destroyed mirror (rejected: dangling target)"
+-        "Audit absorbed-mirror row targeting the destroyed mirror (rejected: dangling target)"
++        "app/models/decidim/contracts_sk/contract.rb",
++        "app/controllers/decidim/contracts_sk/admin/contracts_controller.rb",
++        "app/views/decidim/contracts_sk/admin/contracts/index.html.erb"
        ],
--      "evidence": "agent-review npm test: 70/70 pass incl. MCP listTools + hook mapping; stdio smoke call agent_review_status returned status inactive"
-+      "limitations": []
+-      "limitations": []
++      "changeKind": "modified",
++      "reason": "Shared scopes (submitted_by_user, not_submitted_by_user, awaiting_review_by, returned_to) keep the dashboard counts and the new normalized submitter=me|others index filter identical; NULL stamps handled explicitly; twin-consistency with the four-eyes predicate.",
++      "expectedBehavior": "Index filters by submitter, garbage normalized away, carried by chips/pagination/form.",
++      "risk": "low",
++      "alternatives": [],
++      "limitations": [],
++      "evidence": "contract_submitter_scopes_spec + contracts_submitter_filter_spec green"
      },
      {
--      "id": "6c1abf82-4513-47c1-a072-4edf4f90e454",
--      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
--      "recordedAt": "2026-10-02T22:26:45.110Z",
--      "entity": "Claude Code permissions",
-+      "id": "4b9e4cab-db76-4056-931b-84626813c29e",
-+      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-+      "recordedAt": "2026-10-03T17:06:44.428Z",
-+      "entity": "Sync linked rule, G4 fix, deadline hard switch",
+-      "id": "4b9e4cab-db76-4056-931b-84626813c29e",
+-      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+-      "recordedAt": "2026-10-03T17:06:44.428Z",
+-      "entity": "Sync linked rule, G4 fix, deadline hard switch",
++      "id": "e61ad27a-7101-4838-952e-ed8ae4fc7127",
++      "sessionId": "1387a40f-616f-41e2-8cf3-0b3b3f5f4871",
++      "recordedAt": "2026-10-03T18:46:52.076Z",
++      "entity": "Audit presentation extraction",
        "files": [
--        ".claude/settings.json"
-+        "app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb",
-+        "lib/decidim/contracts_sk/crz_import/sync.rb",
-+        "lib/decidim/contracts_sk/crz_deadline.rb",
-+        "app/models/decidim/contracts_sk/contract.rb",
-+        "lib/tasks/decidim_contracts_sk_crz_import.rake"
+-        "app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb",
+-        "lib/decidim/contracts_sk/crz_import/sync.rb",
+-        "lib/decidim/contracts_sk/crz_deadline.rb",
+-        "app/models/decidim/contracts_sk/contract.rb",
+-        "lib/tasks/decidim_contracts_sk_crz_import.rake"
++        "app/controllers/concerns/decidim/contracts_sk/admin/audit_event_presentation.rb",
++        "app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb",
++        "app/views/decidim/contracts_sk/admin/audit_events/_table.html.erb",
++        "app/views/decidim/contracts_sk/admin/audit_events/index.html.erb"
        ],
--      "changeKind": "added",
--      "reason": "Mirror opencode.jsonc permissions",
--      "expectedBehavior": "git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied",
--      "risk": "low",
-+      "changeKind": "modified",
-+      "reason": "A filing-confirmed editorial record is the canonical linked record of its CRZ id; sync must not duplicate or flag it. Failure stamps must never touch editorial rows. Deadline tracking keys on crz_filed_at.",
-+      "expectedBehavior": ":linked outcome with zero writes at all decision points; linked counters; find_mirror/mark_failed scoped to source crz; tracked? uses crz_filed_at.",
-+      "risk": "medium",
+-      "changeKind": "modified",
+-      "reason": "A filing-confirmed editorial record is the canonical linked record of its CRZ id; sync must not duplicate or flag it. Failure stamps must never touch editorial rows. Deadline tracking keys on crz_filed_at.",
+-      "expectedBehavior": ":linked outcome with zero writes at all decision points; linked counters; find_mirror/mark_failed scoped to source crz; tracked? uses crz_filed_at.",
+-      "risk": "medium",
++      "changeKind": "refactored",
++      "reason": "Share ACTION_KEYS/label helpers and the table between the audit viewer and the dashboard so the two surfaces never drift.",
++      "expectedBehavior": "Behavior-preserving; AuditEventsController::ACTION_KEYS still resolves.",
++      "risk": "low",
        "alternatives": [],
--      "limitations": [
--        "edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates"
--      ]
-+      "limitations": []
+-      "limitations": []
++      "limitations": [],
++      "evidence": "existing audit_events specs green"
      },
      {
--      "id": "e272f979-badc-4ead-b674-6708421f71f1",
--      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
--      "recordedAt": "2026-10-02T22:26:45.213Z",
--      "entity": "CLAUDE.md and AGENTS.md pointer",
-+      "id": "6009392a-aba6-4c87-a7d8-a9ba633d95e4",
-+      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
-+      "recordedAt": "2026-10-03T17:06:46.615Z",
-+      "entity": "Admin filing UI, permission, routes, public detail, locales, audit labels, docs",
+-      "id": "6009392a-aba6-4c87-a7d8-a9ba633d95e4",
+-      "sessionId": "3475ce5c-5efe-491e-b0c8-096df82cca8e",
+-      "recordedAt": "2026-10-03T17:06:46.615Z",
+-      "entity": "Admin filing UI, permission, routes, public detail, locales, audit labels, docs",
++      "id": "373da3d3-638d-499e-b24f-f3f10197ed5b",
++      "sessionId": "1387a40f-616f-41e2-8cf3-0b3b3f5f4871",
++      "recordedAt": "2026-10-03T18:46:53.866Z",
++      "entity": "Specs and docs for the dashboard",
        "files": [
--        "CLAUDE.md",
--        "AGENTS.md"
-+        "app/controllers/decidim/contracts_sk/admin/contracts_controller.rb",
-+        "app/permissions/decidim/contracts_sk/permissions.rb",
-+        "config/routes.rb",
-+        "app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb",
-+        "app/views/decidim/contracts_sk/contracts/show.html.erb",
-+        "config/locales/en.yml",
-+        "config/locales/sk.yml",
-+        "docs/crz-import.md"
+-        "app/controllers/decidim/contracts_sk/admin/contracts_controller.rb",
+-        "app/permissions/decidim/contracts_sk/permissions.rb",
+-        "config/routes.rb",
+-        "app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb",
+-        "app/views/decidim/contracts_sk/contracts/show.html.erb",
+-        "config/locales/en.yml",
+-        "config/locales/sk.yml",
+-        "docs/crz-import.md"
++        "spec/requests/admin/dashboard_spec.rb",
++        "spec/decidim/contracts_sk/engine_routing_spec.rb",
++        "spec/decidim/contracts_sk/menu_spec.rb",
++        "spec/decidim/contracts_sk_locales_spec.rb",
++        "README.md",
++        "docs/roles-and-permissions.md",
++        "docs/public-ui.md",
++        "docs/manual-test-scenarios.md",
++        "docs/qa-checklist.md"
        ],
        "changeKind": "added",
--      "reason": "Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router",
--      "expectedBehavior": "CLAUDE.md imports @AGENTS.md; AGENTS.md lists the Claude Code mirror to keep in sync",
-+      "reason": "Editor-facing round trip: preview comparison page, confirm POST, index entry link, public CRZ publication line.",
-+      "expectedBehavior": "GET preview writes nothing; POST runs the command; en/sk parity; editor-only permission on published unfiled editorial records.",
+-      "reason": "Editor-facing round trip: preview comparison page, confirm POST, index entry link, public CRZ publication line.",
+-      "expectedBehavior": "GET preview writes nothing; POST runs the command; en/sk parity; editor-only permission on published unfiled editorial records.",
++      "reason": "Request specs per role, tenancy, empty states, limits, links, query-count stability; routing/menu/locale pins; docs.",
++      "expectedBehavior": "Deterministic coverage of acceptance criteria.",
        "risk": "low",
        "alternatives": [],
        "limitations": []
-@@ -306,63 +751,32 @@
+@@ -751,21 +450,19 @@
    ],
    "tests": [
      {
--      "command": "bundle exec rspec",
--      "startedAt": "2026-10-02T22:26:52.256Z",
--      "finishedAt": "2026-10-02T22:26:55.393Z",
--      "durationMs": 3133,
-+      "command": "bundle exec rubocop",
-+      "startedAt": "2026-10-03T17:06:47.256Z",
-+      "finishedAt": "2026-10-03T17:06:48.870Z",
-+      "durationMs": 1613,
+-      "command": "bundle exec rubocop",
+-      "startedAt": "2026-10-03T17:06:47.256Z",
+-      "finishedAt": "2026-10-03T17:06:48.870Z",
+-      "durationMs": 1613,
++      "command": "bundle exec rspec",
++      "startedAt": "2026-10-03T18:46:56.120Z",
++      "finishedAt": "2026-10-03T18:47:00.593Z",
++      "durationMs": 4473,
        "exitCode": 0,
        "status": "passed",
--      "stdoutSummary": "Run options: exclude {:db=>true}\n\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_redaction_confirmation_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds only the redaction_confirmed_at column, as a plain nullable datetime\n    attaches no default and no backfill (a fabricated stamp would defeat the gate)\n    adds no index (the stamp is read per-record, never queried as a set)\n\ndb/migrate/*_add_review_decision_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the review_reason and reviewed_at columns\n    adds review_reason as a plain nullable string capped at 1000 characters\n    adds reviewed_at as a plain nullable datetime\n    attaches no default and no backfill (a fabricated judgment would defeat the gate)\n    adds no index (the decision is read per-record, never queried as a set)\n\ndb/migrate/*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  index\n    uniquely indexes (organization, source_id) under the explicit unique name\n    keeps the index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_create_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes version a NOT NULL integer\n    makes summary a NOT NULL string\n  indexes\n    uniquely indexes (contract_id, version) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_audit_events.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant reference NOT NULL with a real FK to the organizations table\n    makes the actor reference NOT NULL with a real FK to the users table\n    makes the target a NOT NULL polymorphic reference\n    makes action a NOT NULL string\n  indexes\n    indexes every reference and created_at under explicit names\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contract_links.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes the target a NOT NULL polymorphic reference with no index of its own\n  indexes\n    uniquely indexes (contract_id, target_type, target_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant and author references NOT NULL\n    makes title and reference NOT NULL strings\n    pins state as NOT NULL defaulting to draft\n    pins source as NOT NULL defaulting to editorial\n    keeps the provenance columns nullable\n  indexes\n    indexes the organization reference under an explicit name\n    indexes the author reference\n    uniquely indexes (organization, reference) under an explicit name\n    indexes (organization, state) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_documents.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL with a real FK to the contracts table\n    makes title NOT NULL\n    pins kind as NOT NULL defaulting to contract\n    keeps the file metadata columns nullable\n  indexes\n    indexes the contract reference under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_parties.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes role and name NOT NULL strings\n    keeps ico as a nullable string with the 8-character limit\n    keeps address nullable\n  indexes\n    compositely indexes (contract_id, role) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\nDecidim::ContractsSk::Admin::AmendmentForm\n  accepts a complete amendment form\n  rejects a blank summary\n  rejects a missing summary\n  caps the summary at 255 characters\n\nDecidim::ContractsSk::Admin::AuditEventsController\n  inherits from the engine's admin base controller\n  implements exactly the index action (read-only viewer)\n  does not sit on the engine's public base controller chain\n  pins the audit action vocabulary actually written by the commands\n  derives the six lifecycle-action keys from the transition table, never hand-enumerated\n\nDecidim::ContractsSk::Admin::ContractForm\n  accepts dotted decimal strings\n  accepts proper numerics without the string guard (spec/API compatibility)\n  accepts the decimal(12,2) ceiling itself\n  accepts a nil amount (the value may be unknown while drafting)\n  rejects non-numeric strings instead of letting the cast zero them\n  rejects comma decimals (the Slovak '12,50' habit, caught deliberately)\n  rejects scientific notation (the format guard stays strict)\n  rejects negative amounts\n  rejects amounts beyond the decimal(12,2) column's ceiling\n  rejects over-ceiling strings too (raw input, same cap)\n\nDecidim::ContractsSk::Admin::ContractsController\n  inherits from the engine's admin base controller\n  implements exactly the CRUD + transition + CRZ-handoff + import + redaction actions (no show, no destroy)\n  does not sit on the engine's public base controller chain\n\nDecidim::ContractsSk::Admin::DocumentForm\n  accepts a complete form\n  defaults the kind to the model's column default\n  accepts every kind of the form's editor vocabulary\n  narrows the mod",
--      "stderrSummary": "",
-+      "stdoutSummary": "Inspecting 174 files\n..............................................................................................................................................................................\n\n174 files inspected, no offenses detected\n",
-+      "stderrSummary": "The following cops were added to RuboCop, but are not configured. Please set Enabled to either `true` or `false` in your `.rubocop.yml` file.\n\nPlease also note that you can opt-in to new cops by default by adding this to your config:\n  AllCops:\n    NewCops: enable\nGemspec/AddRuntimeDependency: # new in 1.65\n  Enabled: true\nGemspec/AttributeAssignment: # new in 1.77\n  Enabled: true\nGemspec/DeprecatedAttributeAssignment: # new in 1.30\n  Enabled: true\nGemspec/DevelopmentDependencies: # new in 1.44\n  Enabled: true\nGemspec/RequireMFA: # new in 1.23\n  Enabled: true\nLayout/EmptyLinesAfterModuleInclusion: # new in 1.79\n  Enabled: true\nLayout/LineContinuationLeadingSpace: # new in 1.31\n  Enabled: true\nLayout/LineContinuationSpacing: # new in 1.31\n  Enabled: true\nLayout/LineEndStringConcatenationIndentation: # new in 1.18\n  Enabled: true\nLayout/SpaceBeforeBrackets: # new in 1.7\n  Enabled: true\nLint/AmbiguousAssignment: # new in 1.7\n  Enabled: true\nLint/AmbiguousOperatorPrecedence: # new in 1.21\n  Enabled: true\nLint/AmbiguousRange: # new in 1.19\n  Enabled: true\nLint/ArgumentMismatch: # new in 1.90\n  Enabled: true\nLint/ArrayLiteralInRegexp: # new in 1.71\n  Enabled: true\nLint/ConstantOverwrittenInRescue: # new in 1.31\n  Enabled: true\nLint/ConstantReassignment: # new in 1.70\n  Enabled: true\nLint/DataDefineOverride: # new in 1.85\n  Enabled: true\nLint/DeprecatedConstants: # new in 1.8\n  Enabled: true\nLint/DeprecatedReference: # new in 1.89\n  Enabled: true\nLint/DuplicateBranch: # new in 1.3\n  Enabled: true\nLint/DuplicateMagicComment: # new in 1.37\n  Enabled: true\nLint/DuplicateMatchPattern: # new in 1.50\n  Enabled: true\nLint/DuplicateRegexpCharacterClassElement: # new in 1.1\n  Enabled: true\nLint/DuplicateSetElement: # new in 1.67\n  Enabled: true\nLint/EmptyBlock: # new in 1.1\n  Enabled: true\nLint/EmptyClass: # new in 1.3\n  Enabled: true\nLint/EmptyInPattern: # new in 1.16\n  Enabled: true\nLint/HashNewWithKeywordArgumentsAsDefault: # new in 1.69\n  Enabled: true\nLint/IncompatibleIoSelectWithFiberScheduler: # new in 1.21\n  Enabled: true\nLint/ItWithoutArgumentsInBlock: # new in 1.59\n  Enabled: true\nLint/LambdaWithoutLiteralBlock: # new in 1.8\n  Enabled: true\nLint/LiteralAssignmentInCondition: # new in 1.58\n  Enabled: true\nLint/MisplacedMagicComment: # new in 1.91\n  Enabled: true\nLint/MixedCaseRange: # new in 1.53\n  Enabled: true\nLint/NameTypo: # new in 1.89\n  Enabled: true\nLint/NoReturnInBeginEndBlocks: # new in 1.2\n  Enabled: true\nLint/NonAtomicFileOperation: # new in 1.31\n  Enabled: true\nLint/NumberedParameterAssignment: # new in 1.9\n  Enabled: true\nLint/NumericOperationWithConstantResult: # new in 1.69\n  Enabled: true\nLint/OrAssignmentToConstant: # new in 1.9\n  Enabled: true\nLint/RedundantDirGlobSort: # new in 1.8\n  Enabled: true\nLint/RedundantRegexpQuantifiers: # new in 1.53\n  Enabled: true\nLint/RedundantTypeConversion: # new in 1.72\n  Enabled: true\nLint/RefinementImportMethods: # new in 1.27\n  Enabled: true\nLint/RequireRangeParentheses: # new in 1.32\n  Enabled: true\nLint/RequireRelativeSelfPath: # new in 1.22\n  Enabled: true\nLint/SharedMutableDefault: # new in 1.70\n  Enabled: true\nLint/SuperArgumentMismatch: # new in 1.90\n  Enabled: true\nLint/SuppressedExceptionInNumberConversion: # new in 1.72\n  Enabled: true\nLint/SymbolConversion: # new in 1.9\n  Enabled: true\nLint/ToEnumArguments: # new in 1.1\n  Enabled: true\nLint/TripleQuotes: # new in 1.9\n  Enabled: true\nLint/UnescapedBracketInRegexp: # new in 1.68\n  Enabled: true\nLint/UnexpectedBlockArity: # new in 1.5\n  Enabled: true\nLint/UnmodifiedReduceAccumulator: # new in 1.1\n  Enabled: true\nLint/UnreachablePatternBranch: # new in 1.85\n  Enabled: true\nLint/UselessConstantScoping: # new in 1.72\n  Enabled: true\nLint/UselessDefaultValueArgument: # new in 1.76\n  Enabled: true\nLint/UselessDefined: # new in 1.69\n  Enabled: true\nLint/UselessNumericOperation: # new in 1.66\n  Enabled: true\nLint/UselessOr: # new in 1.76\n  Enabled: true\nLint/UselessRescue: # new in 1.43\n  Enabled: true\nLint/UselessRuby2Keywords: # new in 1.23\n  Enabled: true\nMetrics/CollectionLiteralLength: # new in 1.47\n  Enabled: true\nNaming/BlockForwarding: # new in 1.24\n  Enabled: true\nNaming/PredicateMethod: # new in 1.76\n  Enabled: true\nSecurity/CompoundHash: # new in 1.28\n  Enabled: true\nSecurity/IoMethods: # new in 1.22\n  Enabled: true\nStyle/AmbiguousEndlessMethodDefinition: # new in 1.68\n  Enabled: true\nStyle/ArgumentsForwarding: # new in 1.1\n  Enabled: true\nStyle/ArrayIntersect: # new in 1.40\n  Enabled: true\nStyle/ArrayIntersectWithSingleElement: # new in 1.81\n  Enabled: true\nStyle/BitwisePredicate: # new in 1.68\n  Enabled: true\nStyle/CollectionCompact: # new in 1.2\n  Enabled: true\nStyle/CollectionQuerying: # new in 1.77\n  Enabled: true\nStyle/CombinableDefined: # new in 1.68\n  Enabled: true\nStyle/ComparableBetween: # new in 1.74\n  Enabled: true\nStyle/ComparableClamp: # new in 1.44\n  Enabled: true\nStyle/ConcatArrayLiterals: # new in 1.41\n  Enabled: true\nStyle/DataInheritance: # new in 1.49\n  Enabled: true\nStyle/DigChain: # new in 1.69\n  Enabled: true\nStyle/DirEmpty: # new in 1.48\n  Enabled: true\nStyle/DirectiveScope: # new in 1.90\n  Enabled: true\nStyle/DocumentDynamicEvalDefinition: # new in 1.1\n  Enabled: true\nStyle/EmptyClassDefinition: # new in 1.84\n  Enabled: true\nStyle/EmptyHeredoc: # new in 1.32\n  Enabled: true\nStyle/EmptyStringInsideInterpolation: # new in 1.76\n  Enabled: true\nStyle/EndlessMethod: # new in 1.8\n  Enabled: true\nStyle/EnvHome: # new in 1.29\n  Enabled: true\nStyle/ExactRegexpMatch: # new in 1.51\n  Enabled: true\nStyle/FetchEnvVar: # new in 1.28\n  Enabled: true\nStyle/FileEmpty: # new in 1.48\n  Enabled: true\nStyle/FileNull: # new in 1.69\n  Enabled: true\nStyle/FileOpen: # new in 1.85\n  Enabled: true\nStyle/FileRead: # new in 1.24\n  Enabled: true\nStyle/FileTouch: # new in 1.69\n  Enabled: true\nStyle/FileWrite: # new in 1.24\n  Enabled: true\nStyle/HashConversion: # new in 1.10\n  Enabled: true\nStyle/HashExcept: # new in 1.7\n  Enabled: true\nStyle/HashFetchChain: # new in 1.75\n  Enabled: true\nStyle/HashSlice: # new in 1.71\n  Enabled: true\nStyle/IfWithBooleanLiteralBranches: # new in 1.9\n  Enabled: true\nStyle/InPatternThen: # new in 1.16\n  Enabled: true\nStyle/ItAssignment: # new in 1.70\n  Enabled: true\nStyle/ItBlockParameter: # new in 1.75\n  Enabled: true\nStyle/KeywordArgumentsMerging: # new in 1.68\n  Enabled: true\nStyle/MagicCommentFormat: # new in 1.35\n  Enabled: true\nStyle/MapCompactWithConditionalBlock: # new in 1.30\n  Enabled: true\nStyle/MapIntoArray: # new in 1.63\n  Enabled: true\nStyle/MapJoin: # new in 1.85\n  Enabled: true\nStyle/MapToHash: # new in 1.24\n  Enabled: true\nStyle/MapToSet: # new in 1.42\n  Enabled: true\nStyle/MinMaxComparison: # new in 1.42\n  Enabled: true\nStyle/ModuleMemberExistenceCheck: # new in 1.82\n  Enabled: true\nStyle/MultilineInPatternThen: # new in 1.16\n  Enabled: true\nStyle/NegatedIfElseCondition: # new in 1.2\n  Enabled: true\nStyle/NegativeArrayIndex: # new in 1.84\n  Enabled: true\nStyle/NestedFileDirname: # new in 1.26\n  Enabled: true\nStyle/NilLambda: # new in 1.3\n  Enabled: true\nStyle/NumberedParameters: # new in 1.22\n  Enabled: true\nStyle/NumberedParametersLimit: # new in 1.22\n  Enabled: true\nStyle/ObjectThen: # new in 1.28\n  Enabled: true\nStyle/OneClassPerFile: # new in 1.85\n  Enabled: true\nStyle/OpenStructUse: # new in 1.23\n  Enabled: true\nStyle/OperatorMethodCall: # new in 1.37\n  Enabled: true\nStyle/PartitionInsteadOfDoubleSelect: # new in 1.85\n  Enabled: true\nStyle/PredicateWithKind: # new in 1.85\n  Enabled: true\nStyle/QuotedSymbols: # new in 1.16\n  Enabled: true\nStyle/ReduceToHash: # new in 1.85\n  Enabled: true\nStyle/RedundantArgument: # new in 1.4\n  Enabled: true\nStyle/RedundantArrayConstructor: # new in 1.52\n  Enabled: true\nStyle/RedundantArrayFlatten: # new in 1.76\n  Enabled: true\nStyle/RedundantConstantBase: # new in 1.40\n  Enabled: true\nStyle/RedundantCurrentDirectoryInPath: # new in 1.53\n  Enabled: true\nStyle/RedundantDoubleSplatHashBraces: # new in 1.41\n  Enabled: true\nStyle/RedundantEach: # new in 1.38\n  Enabled: true\nStyle/RedundantFilterChain: # new in 1.52\n  Enabled: true\nStyle/RedundantFormat: # new in 1.72\n  Enabled: true\nStyle/RedundantHeredocDelimiterQuotes: # new in 1.45\n  Enabled: true\nStyle/RedundantInitialize: # new in 1.27\n  Enabled: true\nStyle/RedundantInterpolationUnfreeze: # new in 1.66\n  Enabled: true\nStyle/RedundantLineContinuation: # new in 1.49\n  Enabled: true\nStyle/RedundantMinMaxBy: # new in 1.85\n  Enabled: true\nStyle/RedundantRegexpArgument: # new in 1.53\n  Enabled: true\nStyle/RedundantRegexpConstructor: # new in 1.52\n  Enabled: true\nStyle/RedundantSelfAssignmentBranch: # new in 1.19\n  Enabled: true\nStyle/RedundantStringEscape: # new in 1.37\n  Enabled: true\nStyle/ReturnNilInPredicateMethodDefinition: # new in 1.53\n  Enabled: true\nStyle/ReverseFind: # new in 1.84\n  Enabled: true\nStyle/SafeNavigationChainLength: # new in 1.68\n  Enabled: true\nStyle/SelectByKind: # new in 1.85\n  Enabled: true\nStyle/SelectByRange: # new in 1.85\n  Enabled: true\nStyle/SelectByRegexp: # new in 1.22\n  Enabled: true\nStyle/SendWithLiteralMethodName: # new in 1.64\n  Enabled: true\nStyle/SingleLineDoEndBlock: # new in 1.57\n  Enabled: true\nStyle/StringChars: # new in 1.12\n  Enabled: true\nStyle/SuperArguments: # new in 1.64\n  Enabled: true\nStyle/SuperWithArgsParentheses: # new in 1.58\n  Enabled: true\nStyle/SwapValues: # new in 1.1\n  Enabled: true\nStyle/TallyMethod: # new in 1.85\n  Enabled: true\nStyle/TimeNow: # new in 1.90\n  Enabled: true\nStyle/YAMLFileRead: # new in 1.53\n  Enabled: true\nRSpec/DiscardedMatcher: # new in 3.10\n  Enabled: true\nRSpec/IncludeExamples: # new in 3.6\n  Enabled: true\nRSpec/LeakyLocalVariable: # new in 3.8\n  Enabled: true\nRSpec/MatchWithSimpleRegex: # new in 3.10\n  Enabled: true\nRSpec/Output: # new in 3.9\n  Enabled: true\nFor more information: https://docs.rubocop.org/rubocop/versioning.html\n",
+-      "stdoutSummary": "Inspecting 174 files\n..............................................................................................................................................................................\n\n174 files inspected, no offenses detected\n",
+-      "stderrSummary": "The following cops were added to RuboCop, but are not configured. Please set Enabled to either `true` or `false` in your `.rubocop.yml` file.\n\nPlease also note that you can opt-in to new cops by default by adding this to your config:\n  AllCops:\n    NewCops: enable\nGemspec/AddRuntimeDependency: # new in 1.65\n  Enabled: true\nGemspec/AttributeAssignment: # new in 1.77\n  Enabled: true\nGemspec/DeprecatedAttributeAssignment: # new in 1.30\n  Enabled: true\nGemspec/DevelopmentDependencies: # new in 1.44\n  Enabled: true\nGemspec/RequireMFA: # new in 1.23\n  Enabled: true\nLayout/EmptyLinesAfterModuleInclusion: # new in 1.79\n  Enabled: true\nLayout/LineContinuationLeadingSpace: # new in 1.31\n  Enabled: true\nLayout/LineContinuationSpacing: # new in 1.31\n  Enabled: true\nLayout/LineEndStringConcatenationIndentation: # new in 1.18\n  Enabled: true\nLayout/SpaceBeforeBrackets: # new in 1.7\n  Enabled: true\nLint/AmbiguousAssignment: # new in 1.7\n  Enabled: true\nLint/AmbiguousOperatorPrecedence: # new in 1.21\n  Enabled: true\nLint/AmbiguousRange: # new in 1.19\n  Enabled: true\nLint/ArgumentMismatch: # new in 1.90\n  Enabled: true\nLint/ArrayLiteralInRegexp: # new in 1.71\n  Enabled: true\nLint/ConstantOverwrittenInRescue: # new in 1.31\n  Enabled: true\nLint/ConstantReassignment: # new in 1.70\n  Enabled: true\nLint/DataDefineOverride: # new in 1.85\n  Enabled: true\nLint/DeprecatedConstants: # new in 1.8\n  Enabled: true\nLint/DeprecatedReference: # new in 1.89\n  Enabled: true\nLint/DuplicateBranch: # new in 1.3\n  Enabled: true\nLint/DuplicateMagicComment: # new in 1.37\n  Enabled: true\nLint/DuplicateMatchPattern: # new in 1.50\n  Enabled: true\nLint/DuplicateRegexpCharacterClassElement: # new in 1.1\n  Enabled: true\nLint/DuplicateSetElement: # new in 1.67\n  Enabled: true\nLint/EmptyBlock: # new in 1.1\n  Enabled: true\nLint/EmptyClass: # new in 1.3\n  Enabled: true\nLint/EmptyInPattern: # new in 1.16\n  Enabled: true\nLint/HashNewWithKeywordArgumentsAsDefault: # new in 1.69\n  Enabled: true\nLint/IncompatibleIoSelectWithFiberScheduler: # new in 1.21\n  Enabled: true\nLint/ItWithoutArgumentsInBlock: # new in 1.59\n  Enabled: true\nLint/LambdaWithoutLiteralBlock: # new in 1.8\n  Enabled: true\nLint/LiteralAssignmentInCondition: # new in 1.58\n  Enabled: true\nLint/MisplacedMagicComment: # new in 1.91\n  Enabled: true\nLint/MixedCaseRange: # new in 1.53\n  Enabled: true\nLint/NameTypo: # new in 1.89\n  Enabled: true\nLint/NoReturnInBeginEndBlocks: # new in 1.2\n  Enabled: true\nLint/NonAtomicFileOperation: # new in 1.31\n  Enabled: true\nLint/NumberedParameterAssignment: # new in 1.9\n  Enabled: true\nLint/NumericOperationWithConstantResult: # new in 1.69\n  Enabled: true\nLint/OrAssignmentToConstant: # new in 1.9\n  Enabled: true\nLint/RedundantDirGlobSort: # new in 1.8\n  Enabled: true\nLint/RedundantRegexpQuantifiers: # new in 1.53\n  Enabled: true\nLint/RedundantTypeConversion: # new in 1.72\n  Enabled: true\nLint/RefinementImportMethods: # new in 1.27\n  Enabled: true\nLint/RequireRangeParentheses: # new in 1.32\n  Enabled: true\nLint/RequireRelativeSelfPath: # new in 1.22\n  Enabled: true\nLint/SharedMutableDefault: # new in 1.70\n  Enabled: true\nLint/SuperArgumentMismatch: # new in 1.90\n  Enabled: true\nLint/SuppressedExceptionInNumberConversion: # new in 1.72\n  Enabled: true\nLint/SymbolConversion: # new in 1.9\n  Enabled: true\nLint/ToEnumArguments: # new in 1.1\n  Enabled: true\nLint/TripleQuotes: # new in 1.9\n  Enabled: true\nLint/UnescapedBracketInRegexp: # new in 1.68\n  Enabled: true\nLint/UnexpectedBlockArity: # new in 1.5\n  Enabled: true\nLint/UnmodifiedReduceAccumulator: # new in 1.1\n  Enabled: true\nLint/UnreachablePatternBranch: # new in 1.85\n  Enabled: true\nLint/UselessConstantScoping: # new in 1.72\n  Enabled: true\nLint/UselessDefaultValueArgument: # new in 1.76\n  Enabled: true\nLint/UselessDefined: # new in 1.69\n  Enabled: true\nLint/UselessNumericOperation: # new in 1.66\n  Enabled: true\nLint/UselessOr: # new in 1.76\n  Enabled: true\nLint/UselessRescue: # new in 1.43\n  Enabled: true\nLint/UselessRuby2Keywords: # new in 1.23\n  Enabled: true\nMetrics/CollectionLiteralLength: # new in 1.47\n  Enabled: true\nNaming/BlockForwarding: # new in 1.24\n  Enabled: true\nNaming/PredicateMethod: # new in 1.76\n  Enabled: true\nSecurity/CompoundHash: # new in 1.28\n  Enabled: true\nSecurity/IoMethods: # new in 1.22\n  Enabled: true\nStyle/AmbiguousEndlessMethodDefinition: # new in 1.68\n  Enabled: true\nStyle/ArgumentsForwarding: # new in 1.1\n  Enabled: true\nStyle/ArrayIntersect: # new in 1.40\n  Enabled: true\nStyle/ArrayIntersectWithSingleElement: # new in 1.81\n  Enabled: true\nStyle/BitwisePredicate: # new in 1.68\n  Enabled: true\nStyle/CollectionCompact: # new in 1.2\n  Enabled: true\nStyle/CollectionQuerying: # new in 1.77\n  Enabled: true\nStyle/CombinableDefined: # new in 1.68\n  Enabled: true\nStyle/ComparableBetween: # new in 1.74\n  Enabled: true\nStyle/ComparableClamp: # new in 1.44\n  Enabled: true\nStyle/ConcatArrayLiterals: # new in 1.41\n  Enabled: true\nStyle/DataInheritance: # new in 1.49\n  Enabled: true\nStyle/DigChain: # new in 1.69\n  Enabled: true\nStyle/DirEmpty: # new in 1.48\n  Enabled: true\nStyle/DirectiveScope: # new in 1.90\n  Enabled: true\nStyle/DocumentDynamicEvalDefinition: # new in 1.1\n  Enabled: true\nStyle/EmptyClassDefinition: # new in 1.84\n  Enabled: true\nStyle/EmptyHeredoc: # new in 1.32\n  Enabled: true\nStyle/EmptyStringInsideInterpolation: # new in 1.76\n  Enabled: true\nStyle/EndlessMethod: # new in 1.8\n  Enabled: true\nStyle/EnvHome: # new in 1.29\n  Enabled: true\nStyle/ExactRegexpMatch: # new in 1.51\n  Enabled: true\nStyle/FetchEnvVar: # new in 1.28\n  Enabled: true\nStyle/FileEmpty: # new in 1.48\n  Enabled: true\nStyle/FileNull: # new in 1.69\n  Enabled: true\nStyle/FileOpen: # new in 1.85\n  Enabled: true\nStyle/FileRead: # new in 1.24\n  Enabled: true\nStyle/FileTouch: # new in 1.69\n  Enabled: true\nStyle/FileWrite: # new in 1.24\n  Enabled: true\nStyle/HashConversion: # new in 1.10\n  Enabled: true\nStyle/HashExcept: # new in 1.7\n  Enabled: true\nStyle/HashFetchChain: # new in 1.75\n  Enabled: true\nStyle/HashSlice: # new in 1.71\n  Enabled: true\nStyle/IfWithBooleanLiteralBranches: # new in 1.9\n  Enabled: true\nStyle/InPatternThen: # new in 1.16\n  Enabled: true\nStyle/ItAssignment: # new in 1.70\n  Enabled: true\nStyle/ItBlockParameter: # new in 1.75\n  Enabled: true\nStyle/KeywordArgumentsMerging: # new in 1.68\n  Enabled: true\nStyle/MagicCommentFormat: # new in 1.35\n  Enabled: true\nStyle/MapCompactWithConditionalBlock: # new in 1.30\n  Enabled: true\nStyle/MapIntoArray: # new in 1.63\n  Enabled: true\nStyle/MapJoin: # new in 1.85\n  Enabled: true\nStyle/MapToHash: # new in 1.24\n  Enabled: true\nStyle/MapToSet: # new in 1.42\n  Enabled: true\nStyle/MinMaxComparison: # new in 1.42\n  Enabled: true\nStyle/ModuleMemberExistenceCheck: # new in 1.82\n  Enabled: true\nStyle/MultilineInPatternThen: # new in 1.16\n  Enabled: true\nStyle/NegatedIfElseCondition: # new in 1.2\n  Enabled: true\nStyle/NegativeArrayIndex: # new in 1.84\n  Enabled: true\nStyle/NestedFileDirname: # new in 1.26\n  Enabled: true\nStyle/NilLambda: # new in 1.3\n  Enabled: true\nStyle/NumberedParameters: # new in 1.22\n  Enabled: true\nStyle/NumberedParametersLimit: # new in 1.22\n  Enabled: true\nStyle/ObjectThen: # new in 1.28\n  Enabled: true\nStyle/OneClassPerFile: # new in 1.85\n  Enabled: true\nStyle/OpenStructUse: # new in 1.23\n  Enabled: true\nStyle/OperatorMethodCall: # new in 1.37\n  Enabled: true\nStyle/PartitionInsteadOfDoubleSelect: # new in 1.85\n  Enabled: true\nStyle/PredicateWithKind: # new in 1.85\n  Enabled: true\nStyle/QuotedSymbols: # new in 1.16\n  Enabled: true\nStyle/ReduceToHash: # new in 1.85\n  Enabled: true\nStyle/RedundantArgument: # new in 1.4\n  Enabled: true\nStyle/RedundantArrayConstructor: # new in 1.52\n  Enabled: true\nStyle/RedundantArrayFlatten: # new in 1.76\n  Enabled: true\nStyle/RedundantConstantBase: # new in 1.40\n  Enabled: true\nStyle/RedundantCurrentDirectoryInPath: # new in 1.53\n  Enabled: true\nStyle/RedundantDoubleSplatHashBraces: # new in 1.41\n  Enabled: true\nStyle/RedundantEach: # new in 1.38\n  Enabled: true\nStyle/RedundantFilterChain: # new in 1.52\n  Enabled: true\nStyle/RedundantFormat: # new in 1.72\n  Enabled: true\nStyle/RedundantHeredocDelimiterQuotes: # new in 1.45\n  Enabled: true\nStyle/RedundantInitialize: # new in 1.27\n  Enabled: true\nStyle/RedundantInterpolationUnfreeze: # new in 1.66\n  Enabled: true\nStyle/RedundantLineContinuation: # new in 1.49\n  Enabled: true\nStyle/RedundantMinMaxBy: # new in 1.85\n  Enabled: true\nStyle/RedundantRegexpArgument: # new in 1.53\n  Enabled: true\nStyle/RedundantRegexpConstructor: # new in 1.52\n  Enabled: true\nStyle/RedundantSelfAssignmentBranch: # new in 1.19\n  Enabled: true\nStyle/RedundantStringEscape: # new in 1.37\n  Enabled: true\nStyle/ReturnNilInPredicateMethodDefinition: # new in 1.53\n  Enabled: true\nStyle/ReverseFind: # new in 1.84\n  Enabled: true\nStyle/SafeNavigationChainLength: # new in 1.68\n  Enabled: true\nStyle/SelectByKind: # new in 1.85\n  Enabled: true\nStyle/SelectByRange: # new in 1.85\n  Enabled: true\nStyle/SelectByRegexp: # new in 1.22\n  Enabled: true\nStyle/SendWithLiteralMethodName: # new in 1.64\n  Enabled: true\nStyle/SingleLineDoEndBlock: # new in 1.57\n  Enabled: true\nStyle/StringChars: # new in 1.12\n  Enabled: true\nStyle/SuperArguments: # new in 1.64\n  Enabled: true\nStyle/SuperWithArgsParentheses: # new in 1.58\n  Enabled: true\nStyle/SwapValues: # new in 1.1\n  Enabled: true\nStyle/TallyMethod: # new in 1.85\n  Enabled: true\nStyle/TimeNow: # new in 1.90\n  Enabled: true\nStyle/YAMLFileRead: # new in 1.53\n  Enabled: true\nRSpec/DiscardedMatcher: # new in 3.10\n  Enabled: true\nRSpec/IncludeExamples: # new in 3.6\n  Enabled: true\nRSpec/LeakyLocalVariable: # new in 3.8\n  Enabled: true\nRSpec/MatchWithSimpleRegex: # new in 3.10\n  Enabled: true\nRSpec/Output: # new in 3.9\n  Enabled: true\nFor more information: https://docs.rubocop.org/rubocop/versioning.html\n",
++      "stdoutSummary": "Run options: exclude {:db=>true}\n\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n\ndb/migrate/*_add_crz_filing_to_decidim_contracts_sk_contracts.rb\n  file surface and class shape\n    has exactly one migration file whose class name matches\n    is a single reversible `def change` on ActiveRecord::Migration[7.2]\n  columns\n    adds exactly the three nullable system columns, with no default, backfill or index\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_redaction_confirmation_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds only the redaction_confirmed_at column, as a plain nullable datetime\n    attaches no default and no backfill (a fabricated stamp would defeat the gate)\n    adds no index (the stamp is read per-record, never queried as a set)\n\ndb/migrate/*_add_review_decision_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the review_reason and reviewed_at columns\n    adds review_reason as a plain nullable string capped at 1000 characters\n    adds reviewed_at as a plain nullable datetime\n    attaches no default and no backfill (a fabricated judgment would defeat the gate)\n    adds no index (the decision is read per-record, never queried as a set)\n\ndb/migrate/*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  index\n    uniquely indexes (organization, source_id) under the explicit unique name\n    keeps the index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_submitted_by_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n    sorts after the migrations it reads (the contracts and audit-trail tables)\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split at the method level\n    runs the backfill only in the up direction of a reversible block\n  column\n    adds exactly one nullable reference column, decidim_submitted_by\n    attaches no default and no foreign key (the decidim_author_id precedent)\n    adds no index (the stamp is read per-record, never queried as a set)\n  backfill SQL\n    reads the latest contract.submit audit row's actor per contract, deterministically\n\ndb/migrate/*_create_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes version a NOT NULL integer\n    makes summary a NOT NULL string\n  indexes\n    uniquely indexes (contract_id, version) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_audit_events.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant reference NOT NULL with a real FK to the organizations table\n    makes the actor reference NOT NULL with a real FK to the users table\n    makes the target a NOT NULL polymorphic reference\n    makes action a NOT NULL string\n  indexes\n    indexes every reference and created_at under explicit names\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contract_links.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes the target a NOT NULL polymorphic reference with no index of its own\n  indexes\n    uniquely indexes (contract_id, target_type, target_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant and author references NOT NULL\n    makes title and reference NOT NULL strings\n    pins state as NOT NULL defaulting to draft\n    pins source as NOT NULL defaulting to editorial\n    keeps the provenance columns nullable\n  indexes\n    indexes the organization reference under an explicit name\n    indexes the author reference\n    uniquely indexes (organization, reference) under an explicit name\n    indexes (organization, state) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_documents.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL with a real FK to the contracts table\n    makes title NOT NULL\n    pins kind as NOT NULL defaulting to contract\n    keeps the file metadata columns nullable\n  indexes\n    indexes the contract reference under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_parties.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes role and name NOT NULL strings\n    keeps ico as a nullable string with the 8-character limit\n    keeps address nullable\n  indexes\n    compositely indexes (contract_id, role) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\nDecidim::ContractsSk::Admin::AmendmentForm\n  accepts a complete amendment form\n  rejects a blank summary\n  rejects a missing summary\n  caps the summary at 255 characters\n\nDecidim::ContractsSk::Admin::AuditEventsController\n  inherits from the engine's admin base controller\n  implements exactly the index action (read-only viewer)\n  does not sit on the engine's public base controller chain\n  pins the audit action vocabulary actually written by the commands\n  derives the six lifecycle-action ",
++      "stderrSummary": "",
        "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
        "commandTruncated": false
      }
    ],
-   "risks": [
--    "Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.",
--    "Large diff: 4919 insertions across 26 files."
-+    "Large diff: 2757 insertions across 52 files."
-   ],
+-  "risks": [
+-    "Large diff: 2757 insertions across 52 files."
+-  ],
++  "risks": [],
    "limitations": [
      "Snapshots cover only files that were changed at checkpoint time.",
      "Symbol extraction is regex-based, not AST-based.",
--    "Only observed facts are recorded — private model reasoning is not captured.",
--    "The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md",
--    "Absolute machine paths in .mcp.json (same as opencode.jsonc)",
--    "Hook assumes agent-review is a sibling checkout",
--    "Skill is a symlink into ../agent-review",
--    "edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates"
-+    "Only observed facts are recorded — private model reasoning is not captured."
-   ],
-   "agentMetadata": {
-     "toolCalls": 0,
+@@ -776,7 +473,7 @@
      "commands": 0,
      "checkpoints": 1,
      "tests": 1,
--    "events": 3816
-+    "events": 3951
+-    "events": 3951
++    "events": 4145
    },
--  "generatedAt": "2026-10-02T22:28:12.683Z",
--  "github": {
--    "repository": null,
--    "baseBranch": "main",
--    "headBranch": "chore/claude-code-config",
--    "pullRequestNumber": null,
--    "pullRequestUrl": null,
--    "headCommit": "5a3f5102c111c56ea154eb5878727e15e45169e1",
--    "status": "preview_ready",
--    "inlineComments": [
--      {
--        "logicalChangeId": "6c1abf82-4513-47c1-a072-4edf4f90e454",
--        "path": ".claude/settings.json",
--        "line": 1,
--        "side": "RIGHT",
--        "status": "preview"
--      },
--      {
--        "logicalChangeId": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
--        "path": ".claude/skills/agent-review",
--        "line": 1,
--        "side": "RIGHT",
--        "status": "preview"
--      }
--    ]
--  }
-+  "generatedAt": "2026-10-03T17:29:00.669Z"
+-  "generatedAt": "2026-10-03T17:29:00.669Z"
++  "generatedAt": "2026-10-04T19:19:51.796Z"
  }
-diff --git a/README.md b/README.md
-index 15bc2dd..42bcb82 100644
---- a/README.md
-+++ b/README.md
-@@ -51,7 +51,7 @@ bin/rails decidim_contracts_sk:install:migrations
- bin/rails db:migrate
- ```
+diff --git a/.release-please-manifest.json b/.release-please-manifest.json
+index 4c313f9..dd8fde7 100644
+--- a/.release-please-manifest.json
++++ b/.release-please-manifest.json
+@@ -1,3 +1,3 @@
+ {
+-  ".": "1.4.0"
++  ".": "1.5.0"
+ }
+diff --git a/AGENTS.md b/AGENTS.md
+index 96b4981..76b24b5 100644
+--- a/AGENTS.md
++++ b/AGENTS.md
+@@ -18,7 +18,7 @@ This repository is a focused Decidim engine, not the full Civora platform. Agent
+ Current route-level scope in the repository:
  
--The engine ships its tables as migrations (contracts, parties, documents, amendments, audit events, contract links; later additive migrations extend the contracts table, e.g. the submitter stamp behind the four-eyes rule); `install:migrations` copies them into the host. It re-stamps their timestamps, which is fine for a new host. A host that already ran the engine migrations under their original timestamps should keep copying new ones verbatim instead — the reference host documents that procedure in its README ("Upgrading the engine"). The host owns the ActiveStorage schema (see *Known limitations*).
-+The engine ships its tables as migrations (contracts, parties, documents, amendments, audit events, contract links; later additive migrations extend the contracts table, e.g. the submitter stamp behind the four-eyes rule and the CRZ filing confirmation columns `crz_filed_at`/`crz_published_on`/`crz_filing_reason`); `install:migrations` copies them into the host. It re-stamps their timestamps, which is fine for a new host. A host that already ran the engine migrations under their original timestamps should keep copying new ones verbatim instead — the reference host documents that procedure in its README ("Upgrading the engine"). The host owns the ActiveStorage schema (see *Known limitations*).
+ - Public routes: `contracts#index`, `contracts#show`.
+-- Admin routes: `admin/contracts` CRUD namespace.
++- Admin routes (namespace `admin`): the root dashboard (`admin/dashboard#show`, the role holder's overview); `contracts` CRUD plus member routes (lifecycle transitions, CRZ handoff, redaction confirmation, CRZ filing) and a CRZ import collection POST; nested `parties`, `documents`, `amendments` and `links` managers; and the read-only `audit_events` index.
  
- Mount the engine in your app's `config/routes.rb` (mount point is your choice; the reference host uses `/contracts`):
+ ## Project Conventions
  
-@@ -69,7 +69,7 @@ With the engine mounted at `/zmluvy`:
+diff --git a/CHANGELOG.md b/CHANGELOG.md
+index c139852..6190c34 100644
+--- a/CHANGELOG.md
++++ b/CHANGELOG.md
+@@ -1,5 +1,20 @@
+ ## [Unreleased]
+ 
++## [1.5.0](https://github.com/civora-org/decidim-contracts_sk/compare/v1.4.0...v1.5.0) (2026-10-04)
++
++
++### Features
++
++* **admin:** add the admin home with my tasks, states and deadlines (civora-org/civora-platform[#126](https://github.com/civora-org/decidim-contracts_sk/issues/126)) ([491c62c](https://github.com/civora-org/decidim-contracts_sk/commit/491c62cf7e7e7bd149d0abbc4fad26b3915e56d7))
++* **admin:** track the CRZ publication deadline (civora-org/civora-platform[#124](https://github.com/civora-org/decidim-contracts_sk/issues/124)) ([9b8d542](https://github.com/civora-org/decidim-contracts_sk/commit/9b8d542eb9ae3cc273c2f8e68c800795fcc8348a))
++* **crz-filing:** confirm the CRZ filing and link the official record (civora-org/civora-platform[#125](https://github.com/civora-org/decidim-contracts_sk/issues/125)) ([c349811](https://github.com/civora-org/decidim-contracts_sk/commit/c34981147e9420354b899f42e0c40565ceaf7017))
++* **transitions:** enforce per-person four-eyes review (civora-org/civora-platform[#123](https://github.com/civora-org/decidim-contracts_sk/issues/123)) ([4315388](https://github.com/civora-org/decidim-contracts_sk/commit/4315388d31a09679b0c18878a55d6420818442ab))
++
++
++### Bug Fixes
++
++* **admin:** fold review findings into CRZ deadline tracking (civora-org/civora-platform[#124](https://github.com/civora-org/decidim-contracts_sk/issues/124)) ([6b67501](https://github.com/civora-org/decidim-contracts_sk/commit/6b675012203ff99dbec035484fc99aacc12fca95))
++
+ ## [1.4.0](https://github.com/civora-org/decidim-contracts_sk/compare/v1.3.0...v1.4.0) (2026-10-03)
+ 
+ 
+diff --git a/README.md b/README.md
+index 42bcb82..d81a058 100644
+--- a/README.md
++++ b/README.md
+@@ -69,9 +69,10 @@ With the engine mounted at `/zmluvy`:
  
  - **Public catalogue** — `GET /zmluvy` (list, with a `q` free-text filter and pagination) and `GET /zmluvy/:id` (detail). Published records of the current organization only — no authentication required; anything else (draft, in-review, rejected, archived, another organization's, nonexistent) is an indistinguishable 404. The list paginates at 25 records per page. The detail page also renders the public version history: the live fields are the current version, above the published amendments' frozen content snapshots (newest first, published-only — drafts are never publicly visible) (civora-org/civora-platform#65). When the record carries project/result links, a "Links" section renders them (labelled and URL'd live through the [link target resolver](#configuration)); dangling or unresolvable targets are hidden, and the section disappears entirely when nothing renderable remains (civora-org/civora-platform#87).
  - **Provenance and freshness for CRZ mirrors** — records mirrored from the CRZ register (`source: "crz"`) are labelled externally confirmed, never presented as a legal publication (ADR-002 rule 1, ADR-008 decisions 4/6): the catalogue list shows the "Externally confirmed" badge with the mirror date on each imported record's card, and the detail page adds a provenance block with the badge, the mirror date and the preserved attribution note (data via ekosystem.slovensko.digital; informational only; the canonical record lives at crz.gov.sk). When a mirror is stale, the detail page additionally warns readers to verify the canonical record: a mirror counts as stale when its `imported_at` is older than `Decidim::ContractsSk.stale_after` (default 48 h — twice the recommended nightly sync cadence), when its last import was stamped `failed`, or when it carries no import timestamp at all (freshness cannot be proven). The stale indicator is detail-only; cards stay lean (civora-org/civora-platform#88).
--- **Admin** — `/zmluvy/admin/contracts` (list, create and edit contract records and drive lifecycle transitions — one POST action per event; sign-in plus an engine role required, each transition gated to the role that owns its edge in the [lifecycle table](docs/contract-lifecycle.md): `editor` for submit/publish/archive, `reviewer` for return/approve/reject, and the person who last submitted a record can never return, approve or reject it themselves (four-eyes rule, civora-org/civora-platform#123, [docs/roles-and-permissions.md](docs/roles-and-permissions.md)); `update` only while the record's lifecycle state is editable; publish additionally requires the record's privacy-redaction confirmation, below). The reviewer `return`/`reject` decisions carry a mandatory decision reason (up to 1000 characters) through an inline form on the index row — the reason and its timestamp render as a "Reviewer decision" banner on the record's edit page until resubmission clears them, and any other transition refuses a passed reason (civora-org/civora-platform#90). The index paginates at 25 records per page and filters by lifecycle state, provenance source (`crz` import vs. `editorial`) and a case-insensitive title/reference search — GET params preserved across page links, unknown values falling back to the defaults (civora-org/civora-platform#86b). The index header also renders per-state counter chips — one grouped query over the unfiltered tenant scope, so the counts are honest navigation that ignore the active filter, each chip linking to its `state=` filter while preserving the others — and a distinct no-matches empty state with a clear-filters link when active filters return zero rows (civora-org/civora-platform#93). It also tracks the CRZ publication deadline (§ 47a OZ, civora-org/civora-platform#124): every editorial record not yet recorded as filed in CRZ (`crz_url` empty, a proxy until real filing confirmation lands) gets a deadline badge in the index (overdue / days left, `signed_on` + 3 months, computed never stored), a `deadline` filter (due within 14 days / overdue) and two counters next to the state chips, and the edit page shows the deadline line (or "deadline unknown — add signing date") — an aid, not legal advice; see [docs/contract-lifecycle.md](docs/contract-lifecycle.md#crz-publication-deadline-124). Each contract also has a nested party manager at `/zmluvy/admin/contracts/:contract_id/parties` — add/edit/remove the object/contractor parties, `editor`-gated and available only while the record's lifecycle state is editable. The contract edit page also hosts the document manager — attach/replace/remove files, `editor`-gated on an editable-state contract (civora-org/civora-platform#73) — and the CRZ handoff export: generate/regenerate the PDF aid (`editor`-gated on an editable-state contract) and download it (`editor`-gated on any lifecycle state); the PDF is labelled a handoff aid for the clerical CRZ record, never a legal publication (civora-org/civora-platform#74). Each contract also has a nested amendment manager at `/zmluvy/admin/contracts/:contract_id/amendments` — draft version-history entries published by one explicit POST per event: create is `editor`-gated on a published contract; update/destroy/publish are `editor`-gated on a draft amendment (publish additionally requires the contract still published); published amendments are immutable (civora-org/civora-platform#65). The contract edit page also hosts the project/result link manager — add/remove links to platform-level entities (`editor`-gated on an editable-state contract; create/destroy only — links have no editable content), with an explicit flag next to links whose target no longer resolves so editors can clean them up (civora-org/civora-platform#87). The contract edit page also hosts the privacy-redaction confirmation gate (ADR-007, civora-org/civora-platform#91): before the record may be published, an editor must confirm the localized redaction checklist — personal names/addresses of natural persons, bank/account details, amounts tying the contract to identifiable persons, sensitive content inside attached documents — through one required-checkbox POST whose affirmation value is consumed server-side (`POST /zmluvy/admin/contracts/:contract_id/confirm_redaction`, `editor`-gated on a confirmable contract — the editable states plus `approved`, so a reviewer-approved record can still be stamped right before publish; the publish transition refuses while the stamp is missing, and amendment publication backstops on the same stamp for editorial records — CRZ mirrors are exempt, their content being already-public upstream data per ADR-008). Once confirmed, the edit page shows the confirmation stamp line instead of the checkbox form. The contract edit page also links to the read-only audit trail — `/zmluvy/admin/audit_events` (civora-org/civora-platform#92), a paginated, newest-first listing of the organization's append-only audit events (lifecycle transitions, the privacy-redaction confirmation, amendment publications and CRZ-import actions), optionally filtered to one contract through `?contract_id=<id>`; every engine role may consult it, each row shows the localized action, the target record (dangling targets render a "record no longer exists" label — the trail outlives what it observed), the acting user and the date and time, plus the reviewer decision reason for records sitting in a decision state.
-+- **Admin** — `/zmluvy/admin/contracts` (list, create and edit contract records and drive lifecycle transitions — one POST action per event; sign-in plus an engine role required, each transition gated to the role that owns its edge in the [lifecycle table](docs/contract-lifecycle.md): `editor` for submit/publish/archive, `reviewer` for return/approve/reject, and the person who last submitted a record can never return, approve or reject it themselves (four-eyes rule, civora-org/civora-platform#123, [docs/roles-and-permissions.md](docs/roles-and-permissions.md)); `update` only while the record's lifecycle state is editable; publish additionally requires the record's privacy-redaction confirmation, below). The reviewer `return`/`reject` decisions carry a mandatory decision reason (up to 1000 characters) through an inline form on the index row — the reason and its timestamp render as a "Reviewer decision" banner on the record's edit page until resubmission clears them, and any other transition refuses a passed reason (civora-org/civora-platform#90). The index paginates at 25 records per page and filters by lifecycle state, provenance source (`crz` import vs. `editorial`) and a case-insensitive title/reference search — GET params preserved across page links, unknown values falling back to the defaults (civora-org/civora-platform#86b). The index header also renders per-state counter chips — one grouped query over the unfiltered tenant scope, so the counts are honest navigation that ignore the active filter, each chip linking to its `state=` filter while preserving the others — and a distinct no-matches empty state with a clear-filters link when active filters return zero rows (civora-org/civora-platform#93). It also tracks the CRZ publication deadline (§ 47a OZ, civora-org/civora-platform#124): every editorial record not yet confirmed as filed in CRZ (`crz_filed_at` empty — the verified filing confirmation of civora-org/civora-platform#125, replacing the interim `crz_url` proxy; nothing is backfilled) gets a deadline badge in the index (overdue / days left, `signed_on` + 3 months, computed never stored), a `deadline` filter (due within 14 days / overdue) and two counters next to the state chips, and the edit page shows the deadline line (or "deadline unknown — add signing date") — an aid, not legal advice; see [docs/contract-lifecycle.md](docs/contract-lifecycle.md#crz-publication-deadline-124). The CRZ round trip (civora-org/civora-platform#125): a published, unfiled editorial record offers **Record CRZ filing** on its index row (`GET`/`POST /zmluvy/admin/contracts/:id/crz_filing`, `editor`-gated) — the editor names the CRZ id, the engine fetches the official record read-only from the ekosystem feed (which may lag the CRZ by about a day), compares reference, supplier IČO and amount side by side, and confirms the filing on a match (any difference needs a stored, audited reason; hard refusals for another organization's record, a cancelled/withdrawn record or an unconfigured IČO). The record stays editorial and becomes the linked record of the CRZ id: the sync then neither mirrors nor flags it (`linked`), a pristine mirror already holding the id is absorbed, and the public detail page says "Published in CRZ on <date>" with the official link; see [docs/crz-import.md](docs/crz-import.md). Each contract also has a nested party manager at `/zmluvy/admin/contracts/:contract_id/parties` — add/edit/remove the object/contractor parties, `editor`-gated and available only while the record's lifecycle state is editable. The contract edit page also hosts the document manager — attach/replace/remove files, `editor`-gated on an editable-state contract (civora-org/civora-platform#73) — and the CRZ handoff export: generate/regenerate the PDF aid (`editor`-gated on an editable-state contract) and download it (`editor`-gated on any lifecycle state); the PDF is labelled a handoff aid for the clerical CRZ record, never a legal publication (civora-org/civora-platform#74). Each contract also has a nested amendment manager at `/zmluvy/admin/contracts/:contract_id/amendments` — draft version-history entries published by one explicit POST per event: create is `editor`-gated on a published contract; update/destroy/publish are `editor`-gated on a draft amendment (publish additionally requires the contract still published); published amendments are immutable (civora-org/civora-platform#65). The contract edit page also hosts the project/result link manager — add/remove links to platform-level entities (`editor`-gated on an editable-state contract; create/destroy only — links have no editable content), with an explicit flag next to links whose target no longer resolves so editors can clean them up (civora-org/civora-platform#87). The contract edit page also hosts the privacy-redaction confirmation gate (ADR-007, civora-org/civora-platform#91): before the record may be published, an editor must confirm the localized redaction checklist — personal names/addresses of natural persons, bank/account details, amounts tying the contract to identifiable persons, sensitive content inside attached documents — through one required-checkbox POST whose affirmation value is consumed server-side (`POST /zmluvy/admin/contracts/:contract_id/confirm_redaction`, `editor`-gated on a confirmable contract — the editable states plus `approved`, so a reviewer-approved record can still be stamped right before publish; the publish transition refuses while the stamp is missing, and amendment publication backstops on the same stamp for editorial records — CRZ mirrors are exempt, their content being already-public upstream data per ADR-008). Once confirmed, the edit page shows the confirmation stamp line instead of the checkbox form. The contract edit page also links to the read-only audit trail — `/zmluvy/admin/audit_events` (civora-org/civora-platform#92), a paginated, newest-first listing of the organization's append-only audit events (lifecycle transitions, the privacy-redaction confirmation, amendment publications, CRZ filing confirmations and CRZ-import actions), optionally filtered to one contract through `?contract_id=<id>`; every engine role may consult it, each row shows the localized action, the target record (dangling targets render a "record no longer exists" label — the trail outlives what it observed), the acting user and the date and time, plus the reviewer decision reason for records sitting in a decision state.
++- **Admin overview** — `/zmluvy/admin` (civora-org/civora-platform#126), the landing page for role holders and the target of the Decidim admin sidebar entry: "waiting for my review" (`reviewer`: in-review records you did not submit — four-eyes — or all of them under `allow_self_review`), "returned to me" (`editor`: your submissions a reviewer sent back), "approved, ready to publish" (`editor`, with a "redaction not confirmed" flag), the CRZ deadline watch (overdue / due within 14 days, every role), counts per lifecycle state and the last 10 audit events. Role-specific blocks render only when the permission layer lets the user perform the event the block is about (no separate role logic); every list is a 10-row preview with a "Show all (N)" link to the matching filtered contracts index (`?state=in_review&submitter=others`, `?state=returned&submitter=me`, `?state=approved`, `?deadline=overdue|due_soon`), and each block has its own empty state. Gate: any engine role (the contracts index's `:read`). The contracts index gained a `submitter=me|others` filter (others includes records with no submitter stamp) and both it and the audit trail link back to the overview.
+ - **Admin** — `/zmluvy/admin/contracts` (list, create and edit contract records and drive lifecycle transitions — one POST action per event; sign-in plus an engine role required, each transition gated to the role that owns its edge in the [lifecycle table](docs/contract-lifecycle.md): `editor` for submit/publish/archive, `reviewer` for return/approve/reject, and the person who last submitted a record can never return, approve or reject it themselves (four-eyes rule, civora-org/civora-platform#123, [docs/roles-and-permissions.md](docs/roles-and-permissions.md)); `update` only while the record's lifecycle state is editable; publish additionally requires the record's privacy-redaction confirmation, below). The reviewer `return`/`reject` decisions carry a mandatory decision reason (up to 1000 characters) through an inline form on the index row — the reason and its timestamp render as a "Reviewer decision" banner on the record's edit page until resubmission clears them, and any other transition refuses a passed reason (civora-org/civora-platform#90). The index paginates at 25 records per page and filters by lifecycle state, provenance source (`crz` import vs. `editorial`) and a case-insensitive title/reference search — GET params preserved across page links, unknown values falling back to the defaults (civora-org/civora-platform#86b). The index header also renders per-state counter chips — one grouped query over the unfiltered tenant scope, so the counts are honest navigation that ignore the active filter, each chip linking to its `state=` filter while preserving the others — and a distinct no-matches empty state with a clear-filters link when active filters return zero rows (civora-org/civora-platform#93). It also tracks the CRZ publication deadline (§ 47a OZ, civora-org/civora-platform#124): every editorial record not yet confirmed as filed in CRZ (`crz_filed_at` empty — the verified filing confirmation of civora-org/civora-platform#125, replacing the interim `crz_url` proxy; nothing is backfilled) gets a deadline badge in the index (overdue / days left, `signed_on` + 3 months, computed never stored), a `deadline` filter (due within 14 days / overdue) and two counters next to the state chips, and the edit page shows the deadline line (or "deadline unknown — add signing date") — an aid, not legal advice; see [docs/contract-lifecycle.md](docs/contract-lifecycle.md#crz-publication-deadline-124). The CRZ round trip (civora-org/civora-platform#125): a published, unfiled editorial record offers **Record CRZ filing** on its index row (`GET`/`POST /zmluvy/admin/contracts/:id/crz_filing`, `editor`-gated) — the editor names the CRZ id, the engine fetches the official record read-only from the ekosystem feed (which may lag the CRZ by about a day), compares reference, supplier IČO and amount side by side, and confirms the filing on a match (any difference needs a stored, audited reason; hard refusals for another organization's record, a cancelled/withdrawn record or an unconfigured IČO). The record stays editorial and becomes the linked record of the CRZ id: the sync then neither mirrors nor flags it (`linked`), a pristine mirror already holding the id is absorbed, and the public detail page says "Published in CRZ on <date>" with the official link; see [docs/crz-import.md](docs/crz-import.md). Each contract also has a nested party manager at `/zmluvy/admin/contracts/:contract_id/parties` — add/edit/remove the object/contractor parties, `editor`-gated and available only while the record's lifecycle state is editable. The contract edit page also hosts the document manager — attach/replace/remove files, `editor`-gated on an editable-state contract (civora-org/civora-platform#73) — and the CRZ handoff export: generate/regenerate the PDF aid (`editor`-gated on an editable-state contract) and download it (`editor`-gated on any lifecycle state); the PDF is labelled a handoff aid for the clerical CRZ record, never a legal publication (civora-org/civora-platform#74). Each contract also has a nested amendment manager at `/zmluvy/admin/contracts/:contract_id/amendments` — draft version-history entries published by one explicit POST per event: create is `editor`-gated on a published contract; update/destroy/publish are `editor`-gated on a draft amendment (publish additionally requires the contract still published); published amendments are immutable (civora-org/civora-platform#65). The contract edit page also hosts the project/result link manager — add/remove links to platform-level entities (`editor`-gated on an editable-state contract; create/destroy only — links have no editable content), with an explicit flag next to links whose target no longer resolves so editors can clean them up (civora-org/civora-platform#87). The contract edit page also hosts the privacy-redaction confirmation gate (ADR-007, civora-org/civora-platform#91): before the record may be published, an editor must confirm the localized redaction checklist — personal names/addresses of natural persons, bank/account details, amounts tying the contract to identifiable persons, sensitive content inside attached documents — through one required-checkbox POST whose affirmation value is consumed server-side (`POST /zmluvy/admin/contracts/:contract_id/confirm_redaction`, `editor`-gated on a confirmable contract — the editable states plus `approved`, so a reviewer-approved record can still be stamped right before publish; the publish transition refuses while the stamp is missing, and amendment publication backstops on the same stamp for editorial records — CRZ mirrors are exempt, their content being already-public upstream data per ADR-008). Once confirmed, the edit page shows the confirmation stamp line instead of the checkbox form. The contract edit page also links to the read-only audit trail — `/zmluvy/admin/audit_events` (civora-org/civora-platform#92), a paginated, newest-first listing of the organization's append-only audit events (lifecycle transitions, the privacy-redaction confirmation, amendment publications, CRZ filing confirmations and CRZ-import actions), optionally filtered to one contract through `?contract_id=<id>`; every engine role may consult it, each row shows the localized action, the target record (dangling targets render a "record no longer exists" label — the trail outlives what it observed), the acting user and the date and time, plus the reviewer decision reason for records sitting in a decision state.
  - **Roles and permissions** — the engine-logical `editor`/`reviewer` roles map onto Decidim permissions via a config-time resolver; see [docs/roles-and-permissions.md](docs/roles-and-permissions.md).
- - **Navigation** — a "Contracts / Zmluvy" entry in Decidim's main menu (and its mobile menu twin) pointing at the public catalogue, and a "Contracts" entry in the Decidim admin sidebar pointing at the admin contracts index — the sidebar entry renders only for users holding an engine role. Both sit at position 2.4, next to the other content modules; hosts can re-order, override or remove them per Decidim menu conventions (`Decidim.menu :menu do |menu| menu.move :contracts_sk, ... end`, `menu.remove_item :contracts_sk`) (civora-org/civora-platform#86c).
+-- **Navigation** — a "Contracts / Zmluvy" entry in Decidim's main menu (and its mobile menu twin) pointing at the public catalogue, and a "Contracts" entry in the Decidim admin sidebar pointing at the admin contracts index — the sidebar entry renders only for users holding an engine role. Both sit at position 2.4, next to the other content modules; hosts can re-order, override or remove them per Decidim menu conventions (`Decidim.menu :menu do |menu| menu.move :contracts_sk, ... end`, `menu.remove_item :contracts_sk`) (civora-org/civora-platform#86c).
++- **Navigation** — a "Contracts / Zmluvy" entry in Decidim's main menu (and its mobile menu twin) pointing at the public catalogue, and a "Contracts" entry in the Decidim admin sidebar pointing at the admin overview (`/zmluvy/admin`, from where the contracts index and the audit trail are one click away; it stays highlighted on every engine admin page) — the sidebar entry renders only for users holding an engine role. Both sit at position 2.4, next to the other content modules; hosts can re-order, override or remove them per Decidim menu conventions (`Decidim.menu :menu do |menu| menu.move :contracts_sk, ... end`, `menu.remove_item :contracts_sk`) (civora-org/civora-platform#86c).
  - **CRZ import** — an editor-gated `POST /zmluvy/admin/contracts/import_crz` (form on the admin contracts index) pulls one CRZ record by its numeric id, and the host-scheduled `bin/rails "decidim_contracts_sk:crz_import:sync[<organization_id>,<SINCE ISO8601>]"` task mirrors updated records in batch (SINCE also via the `SINCE` env var). Mirrors land `published` with full provenance and an audit event; re-running is always safe. Operations, scheduling, failure modes and the manual collision resolution in [docs/crz-import.md](docs/crz-import.md).
-diff --git a/app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb b/app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb
+ 
+ Locales: English and Slovak.
+diff --git a/app/controllers/concerns/decidim/contracts_sk/admin/audit_event_presentation.rb b/app/controllers/concerns/decidim/contracts_sk/admin/audit_event_presentation.rb
 new file mode 100644
-index 0000000..0dc713d
+index 0000000..d5fd8b6
 --- /dev/null
-+++ b/app/commands/decidim/contracts_sk/admin/confirm_crz_filing.rb
-@@ -0,0 +1,242 @@
++++ b/app/controllers/concerns/decidim/contracts_sk/admin/audit_event_presentation.rb
+@@ -0,0 +1,146 @@
 +# frozen_string_literal: true
 +
 +module Decidim
 +  module ContractsSk
 +    module Admin
-+      # Confirms that an editorial contract was filed in the CRZ and links the
-+      # official record (civora-org/civora-platform#125, the round trip after
-+      # the manual handoff of #74/ADR-002): the editor names the CRZ id, the
-+      # engine verifies the official record through the ekosystem feed
-+      # (read-only, CrzImport::FilingLookup) and, when it matches, stamps the
-+      # confirmation on the editorial record. The record stays editorial
-+      # (source never changes) — it becomes the canonical, linked record of
-+      # the CRZ id, which the sync then leaves alone (UpsertContract :linked).
-+      #
-+      # Order of work:
-+      # 1. Pre-lock, request-shaped refusals: the editor role, a configured
-+      #    organization IČO, the reason's length cap.
-+      # 2. The network fetch (FilingLookup) — ALWAYS outside any lock, so a
-+      #    slow or dead source never holds a row lock. A failed or empty
-+      #    fetch changes nothing and writes no audit row.
-+      # 3. The in-lock decision on the RELOADED row (with_lock reloads — the
-+      #    #69 TOCTOU doctrine, no pre-lock read or stale caller copy ever
-+      #    admits a write): editorial source, published state, not already
-+      #    filed, the preview's checksum token still equal to the fresh
-+      #    payload's checksum (else :stale — the official record changed
-+      #    since the editor looked), the comparison re-run against the
-+      #    row as it is NOW, the reason rule, and the id being free.
-+      #
-+      # Reason rule: any comparison row that is not a :match (mismatch OR
-+      # unverifiable) demands a stripped, non-blank reason of at most
-+      # MAX_REASON_LENGTH characters — the editor's override, stored in
-+      # crz_filing_reason and audited as "contract.crz_filed_override". A
-+      # clean match takes NO reason (a reason on a full match is refused, the
-+      # TransitionContract reason-shape doctrine) and audits as
-+      # "contract.crz_filed". Hard refusals (no override possible): no
-+      # configured IČO, record out of the organization's scope, CRZ status
-+      # cancelled/withdrawn (FilingLookup).
-+      #
-+      # Writes (one transaction under the contract's lock): crz_url
-+      # (the canonical CRZ template), crz_filed_at, source_id,
-+      # crz_published_on, crz_filing_reason and the audit row — all or
-+      # nothing. These are system fields, never form-writable.
-+      #
-+      # Mirror absorption (Gate-1 decision D5-B): the unique
-+      # (organization, source_id) index means a CRZ mirror that the sync
-+      # already imported under this id would block the claim. Lock order is
-+      # CONTRACT FIRST, THEN MIRROR (the only place two contract rows are
-+      # locked, so no inverse order exists to deadlock against). A PRISTINE
-+      # mirror (no amendments, links or documents — nothing an editor made
-+      # of it) is destroyed and the editorial record claims the id; a
-+      # "contract.crz_mirror_absorbed" audit row records it. Its audit
-+      # target is the EDITORIAL record: the mirror row no longer exists, and
-+      # a dangling target would render as "record no longer exists" and
-+      # drop out of the per-contract trail filter, whereas the claiming
-+      # record is the one the trail should explain (the destroyed mirror's
-+      # own import rows keep their dangling targets, as for every contract
-+      # deletion). A non-pristine mirror, or another editorial record
-+      # holding the id, refuses with :already_linked — resolved manually
-+      # (docs/crz-import.md). A concurrent claim that still slips through
-+      # trips the unique index (RecordNotUnique), rescued to the same
-+      # :already_linked.
-+      #
-+      # Broadcasts (bare symbols, for the controller's flash mapping):
-+      #   on(:ok)      { |outcome| } — :filed | :filed_override
-+      #   on(:invalid) { |reason| }  — :not_found, :failed, :not_configured,
-+      #     :out_of_scope, :withdrawn, :stale, :reason_required,
-+      #     :reason_rejected, :already_filed, :not_fileable, :already_linked
-+      #
-+      # Cop note: the class stays deliberately cohesive — the ordered guard
-+      # chain and the lock doctrine are one contract, and splitting it would
-+      # scatter the in-lock decision rather than simplify it.
-+      # rubocop:disable Metrics/ClassLength
-+      class ConfirmCrzFiling < Decidim::Command
-+        MAX_REASON_LENGTH = TransitionContract::MAX_REASON_LENGTH
-+
-+        AUDIT_FILED = "contract.crz_filed"
-+        AUDIT_FILED_OVERRIDE = "contract.crz_filed_override"
-+        AUDIT_MIRROR_ABSORBED = "contract.crz_mirror_absorbed"
-+
-+        # Internal control flow: an in-lock refusal unwinds the transaction
-+        # (nothing was written before any refusal, so the rollback is a
-+        # no-op) and carries the broadcast reason out.
-+        class Refusal < StandardError
-+          attr_reader :reason
-+
-+          def initialize(reason)
-+            super(reason.to_s)
-+            @reason = reason
-+          end
++      # Audit-event presentation shared by the audit-trail viewer
++      # (civora-org/civora-platform#92) and the admin dashboard's
++      # recent-activity block (civora-org/civora-platform#126): ONE action
++      # vocabulary and ONE set of label/actor/target/reason helpers, so the
++      # two surfaces can never drift apart. Included into an admin
++      # controller; the helpers are exposed to its views and rely on the
++      # controller's route helpers and #t.
++      module AuditEventPresentation
++        extend ActiveSupport::Concern
++
++        included do
++          helper_method :audit_action_label, :audit_actor_name, :audit_target_info,
++                        :audit_reason_for
 +        end
 +
-+        # +checksum+ is the token the preview rendered (Mapper checksum of
-+        # the payload the editor compared); +client+ is the injection seam
-+        # for the verification fetch (specs stub it at its exact boundary).
-+        # rubocop:disable Metrics/ParameterLists
-+        def initialize(contract, crz_id:, checksum:, user:, reason: nil, client: nil)
-+          super()
-+          @contract = contract
-+          @crz_id = crz_id.to_s.strip
-+          @checksum = checksum.to_s
-+          @user = user
-+          @reason = reason
-+          @client = client
-+        end
-+        # rubocop:enable Metrics/ParameterLists
-+
-+        def call
-+          broadcast(:ok, file_locked(verified_record))
-+        rescue Refusal => e
-+          broadcast(:invalid, e.reason)
-+        rescue ActiveRecord::RecordNotUnique
-+          broadcast(:invalid, :already_linked)
-+        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
-+          broadcast(:invalid, :not_fileable)
-+        end
++        # Deterministic newest-first ordering of the trail, id as the
++        # tiebreaker (a total order, so a page never repeats or drops a row);
++        # shared by the viewer and the dashboard's recent-activity block.
++        INDEX_ORDER = { created_at: :desc, id: :desc }.freeze
++
++        # The polymorphic target_type string the commands stamp on
++        # contract-targeted audit events; the events for one contract are
++        # filtered by (target_type, target_id) — plain column names on the
++        # (table-prefixed) audit_events table.
++        CONTRACT_TARGET_TYPE = "Decidim::ContractsSk::Contract"
++
++        # The audit action vocabulary actually written by the commands,
++        # mapped to their localized labels: the six lifecycle events reuse
++        # the admin transition vocabulary verbatim (one vocabulary, never a
++        # second one), while the CRZ-import, redaction-confirmation and
++        # amendment-publish actions carry their own keys under
++        # admin.audit_events.actions. Any unknown action falls back to a
++        # humanized string — the label helper never raises (fail-closed,
++        # the link_targets.rb precedent), so a future command action can
++        # never 500 the viewer before its locale keys land.
++        ACTION_KEYS = {
++          "contract.submit" => "decidim.contracts_sk.admin.contracts.transition.submit",
++          "contract.return" => "decidim.contracts_sk.admin.contracts.transition.return",
++          "contract.approve" => "decidim.contracts_sk.admin.contracts.transition.approve",
++          "contract.reject" => "decidim.contracts_sk.admin.contracts.transition.reject",
++          "contract.return_self" => "decidim.contracts_sk.admin.audit_events.actions.return_self",
++          "contract.approve_self" => "decidim.contracts_sk.admin.audit_events.actions.approve_self",
++          "contract.reject_self" => "decidim.contracts_sk.admin.audit_events.actions.reject_self",
++          "contract.publish" => "decidim.contracts_sk.admin.contracts.transition.publish",
++          "contract.archive" => "decidim.contracts_sk.admin.contracts.transition.archive",
++          "contract.redaction_confirmed" => "decidim.contracts_sk.admin.audit_events.actions.redaction_confirmed",
++          "amendment.publish" => "decidim.contracts_sk.admin.audit_events.actions.amendment_publish",
++          "contract.crz_filed" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed",
++          "contract.crz_filed_override" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed_override",
++          "contract.crz_mirror_absorbed" => "decidim.contracts_sk.admin.audit_events.actions.crz_mirror_absorbed",
++          "crz_import_create" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_create",
++          "crz_import_update" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_update"
++        }.freeze
 +
 +        private
 +
-+        attr_reader :contract, :crz_id, :checksum, :user, :reason
-+
-+        # The pre-lock phase: request-shaped refusals that depend on no row
-+        # state (the editor role — defense in depth behind the permission
-+        # layer, fail-closed — and the reason's length cap), then the
-+        # network fetch, outside any lock. Returns the mapped CRZ record or
-+        # raises the Refusal that ends the command.
-+        def verified_record
-+          raise Refusal, :not_fileable unless editor?
-+          raise Refusal, :reason_rejected if normalized_reason.length > MAX_REASON_LENGTH
-+
-+          lookup = CrzImport::FilingLookup.call(crz_id: crz_id, organization: contract.organization,
-+                                                client: @client)
-+          raise Refusal, lookup.refusal unless lookup.ok?
-+
-+          lookup.record
-+        end
-+
-+        def editor?
-+          Array(Decidim::ContractsSk.role_resolver.call(user, {})).include?(:editor)
-+        end
-+
-+        def normalized_reason
-+          @normalized_reason ||= reason.to_s.strip
-+        end
-+
-+        # The locked decision + writes; returns the ok outcome symbol, or
-+        # raises Refusal (rolling the transaction back, nothing written).
-+        def file_locked(record)
-+          contract.with_lock { decide_and_write(record) }
-+        end
-+
-+        # The in-lock body, in guard order; returns the ok outcome.
-+        def decide_and_write(record)
-+          guard_row!
-+          guard_checksum!(record)
-+          comparison = CrzImport::FilingComparison.new(contract: contract, record: record)
-+          guard_reason!(comparison)
-+          mirror = claimable_mirror!(record)
-+
-+          write_filing!(record, mirror)
-+          outcome = comparison.all_match? ? :filed : :filed_override
-+          record_audit!(outcome)
-+          outcome
-+        end
-+
-+        # The row-state guards, read from the reloaded row.
-+        def guard_row!
-+          raise Refusal, :already_filed if contract.crz_filed_at.present?
-+          raise Refusal, :not_fileable unless fileable_row?
-+        end
++        # The localized action label for an event: the frozen
++        # command-vocabulary mapping above, or a humanized fallback for any
++        # unknown action string — never a raise, never raw internals.
++        def audit_action_label(action)
++          key = ACTION_KEYS.fetch(action.to_s) { return action.to_s.humanize }
 +
-+        # An editorial, published record that carries no OTHER CRZ id.
-+        def fileable_row?
-+          contract.source == "editorial" && contract.state.to_s == "published" &&
-+            (contract.source_id.blank? || contract.source_id == crz_id)
++          t(key)
 +        end
 +
-+        # The official record must still be the one the editor compared.
-+        def guard_checksum!(record)
-+          raise Refusal, :stale unless record[:checksum] == checksum
++        # The acting user's display name, nil-guarded: the actor column is
++        # NOT NULL at write time, but the user row itself can be deleted
++        # later, leaving the event's actor association empty on read. An
++        # empty/missing name degrades to the localized unknown-actor label.
++        def audit_actor_name(event)
++          event.actor&.name.presence || t("decidim.contracts_sk.admin.audit_events.unknown_actor")
 +        end
 +
-+        # A non-match (mismatch or unverifiable) needs the override reason;
-+        # a clean match takes none.
-+        def guard_reason!(comparison)
-+          if comparison.needs_reason?
-+            raise Refusal, :reason_required if normalized_reason.blank?
-+          elsif normalized_reason.present?
-+            raise Refusal, :reason_rejected
++        # Display info for the event's target: { label:, url: } when the
++        # polymorphic row resolves, nil when it dangles (row gone) or its
++        # class no longer loads (constantize raises inside the association
++        # access). The rescue is the fail-closed boundary (the
++        # resolve_link_target precedent): an unresolvable target can never
++        # raise or leak internals — the view renders the localized
++        # deleted-target label instead.
++        #
++        # Contract targets link to the record's edit page (the admin hub);
++        # amendment targets label themselves by version and link to their
++        # parent contract's amendment manager (nil url when the parent is
++        # gone — the label then renders as plain text).
++        def audit_target_info(event)
++          target = event.target
++          return nil if target.blank?
++
++          case target
++          when Contract
++            contract_target_info(target)
++          when Amendment
++            amendment_target_info(target)
 +          end
++        rescue StandardError
++          nil
 +        end
 +
-+        # The id must be free. Returns a destroyable pristine mirror (to be
-+        # absorbed), nil when nothing holds the id; raises :already_linked
-+        # for any other holder. The mirror is locked AFTER the contract
-+        # (lock order — see the class comment).
-+        def claimable_mirror!(record)
-+          holder = Contract.where(organization: contract.organization, source_id: record[:source_id])
-+                           .where.not(id: contract.id).lock.first
-+          return nil unless holder
-+          raise Refusal, :already_linked unless holder.source == CrzImport::Mapper::SOURCE && pristine?(holder)
-+
-+          holder
++        def contract_target_info(contract)
++          { label: contract.title, url: edit_admin_contract_path(contract) }
 +        end
 +
-+        # Nothing an editor made of the mirror: no amendments, links or
-+        # documents (parties are the import's own mirrored rows).
-+        def pristine?(mirror)
-+          !mirror.amendments.exists? && !mirror.links.exists? && !mirror.documents.exists?
++        def amendment_target_info(amendment)
++          parent = amendment.contract
++          {
++            label: t("decidim.contracts_sk.admin.audit_events.amendment_target",
++                     version: amendment.version),
++            url: parent && admin_contract_amendments_path(parent)
++          }
 +        end
 +
-+        def write_filing!(record, mirror)
-+          absorb!(mirror) if mirror
++        # The reviewer decision reason an event row may carry: only for a
++        # live Contract target sitting in a decision state
++        # (ContractLifecycle::DECISION_STATES) with a non-blank
++        # review_reason — the same gate the edit page's decision banner
++        # uses. Everything else the commands may have observed stays out of
++        # the viewer (nothing payload-like beyond the identity title).
++        def audit_reason_for(event)
++          return nil unless event.target_type == CONTRACT_TARGET_TYPE
 +
-+          contract.update!(
-+            crz_url: format(CrzImport::Mapper::CRZ_URL_TEMPLATE, record[:source_id]),
-+            crz_filed_at: Time.current,
-+            source_id: record[:source_id],
-+            crz_published_on: record[:published_on],
-+            crz_filing_reason: normalized_reason.presence
-+          )
-+        end
++          contract = event.target
++          # The override reason of a CRZ filing confirmation (civora-org/
++          # civora-platform#125) is shown on its own audit row.
++          return contract&.crz_filing_reason.presence if event.action == "contract.crz_filed_override"
 +
-+        # The mirror's row must be gone before the claim (the unique index);
-+        # its absorption is audited against the claiming record.
-+        def absorb!(mirror)
-+          mirror.destroy!
-+          write_audit!(AUDIT_MIRROR_ABSORBED)
++          decision_reason(contract)
++        rescue StandardError
++          nil
 +        end
 +
-+        def record_audit!(outcome)
-+          write_audit!(outcome == :filed ? AUDIT_FILED : AUDIT_FILED_OVERRIDE)
-+        end
++        def decision_reason(contract)
++          return nil unless contract.present? && contract.review_reason.present?
++          return nil unless ContractLifecycle::DECISION_STATES.include?(contract.state&.to_sym)
 +
-+        def write_audit!(action)
-+          AuditEvent.create!(action: action, target: contract,
-+                             organization: contract.organization, actor: user)
++          contract.review_reason
 +        end
 +      end
-+      # rubocop:enable Metrics/ClassLength
 +    end
 +  end
 +end
-diff --git a/app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb b/app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb
-index 47ef381..5f35ac6 100644
---- a/app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb
-+++ b/app/commands/decidim/contracts_sk/crz_import/upsert_contract.rb
-@@ -24,8 +24,15 @@ module Decidim
-       #   provenance are re-mirrored; state/author/currency are never
-       #   touched; a "crz_import_update" audit event rides the same
-       #   transaction.
-+      # - LINKED when a record with the same source_id has a different
-+      #   source (an editorial record) that was CONFIRMED as filed
-+      #   (crz_filed_at present, Admin::ConfirmCrzFiling,
-+      #   civora-org/civora-platform#125): that record is already the
-+      #   canonical, linked record of the CRZ id — ZERO writes (updated_at
-+      #   untouched), outcome :linked. Not a mirror, not a collision.
-       # - COLLISION when a record with the same source_id has a different
--      #   source (an editorial record): never touched, reason :collision —
-+      #   source and is NOT confirmed as filed (an editorial record that
-+      #   merely carries the id): never touched, reason :collision —
-       #   logged for manual resolution by the caller.
-       # - UNCHANGED when the checksum matches: zero writes (updated_at
-       #   untouched — the idempotency guarantee).
-@@ -50,7 +57,7 @@ module Decidim
-       #
-       # Broadcast payloads (single-arg hashes; the EventRecorder captures
-       # them whole):
--      #   on(:ok)      { |result| } — result[:outcome] :created|:updated|:unchanged,
-+      #   on(:ok)      { |result| } — result[:outcome] :created|:updated|:unchanged|:linked,
-       #                               result[:contract]
-       #   on(:invalid) { |result| } — result[:reason]
-       #                               :collision|:lifecycle_guard|:record_invalid,
-@@ -95,7 +102,7 @@ module Decidim
-         def perform
-           existing = find_existing
- 
--          return invalid_outcome(:collision, existing) if existing && existing.source != SOURCE
-+          return foreign_holder_outcome(existing) if existing && existing.source != SOURCE
-           return update_locked(existing) if existing
- 
-           create_transactional
-@@ -121,7 +128,7 @@ module Decidim
-         # stamp the race winner failed.
-         def lost_create_race
-           fresh = find_existing
--          return invalid_outcome(:collision, fresh) if fresh && fresh.source != SOURCE
-+          return foreign_holder_outcome(fresh) if fresh && fresh.source != SOURCE
-           return update_locked(fresh) if fresh
- 
-           # Unreachable in practice (the index fired, so a row committed);
-@@ -138,7 +145,7 @@ module Decidim
-           return create! if fresh.nil?
-           return update_locked(fresh) if fresh.source == SOURCE
- 
--          invalid_outcome(:collision, fresh)
-+          foreign_holder_outcome(fresh)
+diff --git a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
+index f3b91b0..dea7be1 100644
+--- a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
++++ b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
+@@ -25,47 +25,12 @@ module Decidim
+       # (redirect + alert). The :audit_event/:read permission mirrors the
+       # admin contracts index (:read :contract): any engine role.
+       class AuditEventsController < Admin::ApplicationController
+-        helper_method :audit_action_label, :audit_actor_name, :audit_target_info,
+-                      :audit_reason_for
+-
+-        # Deterministic index ordering: newest events first, id as the
+-        # tiebreaker (same doctrine as the contracts index — a total order,
+-        # so a page can never repeat or drop a row across page boundaries).
+-        INDEX_ORDER = { created_at: :desc, id: :desc }.freeze
+-
+-        # The polymorphic target_type string the commands stamp on
+-        # contract-targeted audit events; the events for one contract are
+-        # filtered by (target_type, target_id) — plain column names on the
+-        # (table-prefixed) audit_events table.
+-        CONTRACT_TARGET_TYPE = "Decidim::ContractsSk::Contract"
+-
+-        # The audit action vocabulary actually written by the commands,
+-        # mapped to their localized labels: the six lifecycle events reuse
+-        # the admin transition vocabulary verbatim (one vocabulary, never a
+-        # second one), while the CRZ-import, redaction-confirmation and
+-        # amendment-publish actions carry their own keys under
+-        # admin.audit_events.actions. Any unknown action falls back to a
+-        # humanized string — the label helper never raises (fail-closed,
+-        # the link_targets.rb precedent), so a future command action can
+-        # never 500 the viewer before its locale keys land.
+-        ACTION_KEYS = {
+-          "contract.submit" => "decidim.contracts_sk.admin.contracts.transition.submit",
+-          "contract.return" => "decidim.contracts_sk.admin.contracts.transition.return",
+-          "contract.approve" => "decidim.contracts_sk.admin.contracts.transition.approve",
+-          "contract.reject" => "decidim.contracts_sk.admin.contracts.transition.reject",
+-          "contract.return_self" => "decidim.contracts_sk.admin.audit_events.actions.return_self",
+-          "contract.approve_self" => "decidim.contracts_sk.admin.audit_events.actions.approve_self",
+-          "contract.reject_self" => "decidim.contracts_sk.admin.audit_events.actions.reject_self",
+-          "contract.publish" => "decidim.contracts_sk.admin.contracts.transition.publish",
+-          "contract.archive" => "decidim.contracts_sk.admin.contracts.transition.archive",
+-          "contract.redaction_confirmed" => "decidim.contracts_sk.admin.audit_events.actions.redaction_confirmed",
+-          "amendment.publish" => "decidim.contracts_sk.admin.audit_events.actions.amendment_publish",
+-          "contract.crz_filed" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed",
+-          "contract.crz_filed_override" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed_override",
+-          "contract.crz_mirror_absorbed" => "decidim.contracts_sk.admin.audit_events.actions.crz_mirror_absorbed",
+-          "crz_import_create" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_create",
+-          "crz_import_update" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_update"
+-        }.freeze
++        # The action/actor/target/reason presentation helpers and the
++        # action vocabulary (ACTION_KEYS, CONTRACT_TARGET_TYPE) live in the
++        # concern shared with the admin dashboard's recent-activity block
++        # (civora-org/civora-platform#126); AuditEventsController::ACTION_KEYS
++        # still resolves through the include.
++        include AuditEventPresentation
+ 
+         def index
+           enforce_permission_to :read, :audit_event
+@@ -115,88 +80,6 @@ module Decidim
+         def contracts_scope
+           Contract.where(organization: current_organization)
          end
- 
-         def create!
-@@ -168,13 +175,28 @@ module Decidim
-           result
-         rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
-           invalid_outcome(:record_invalid, contract)
-+        rescue ActiveRecord::RecordNotFound
-+          lost_row_race
+-
+-        # The localized action label for an event: the frozen
+-        # command-vocabulary mapping above, or a humanized fallback for any
+-        # unknown action string — never a raise, never raw internals.
+-        def audit_action_label(action)
+-          key = ACTION_KEYS.fetch(action.to_s) { return action.to_s.humanize }
+-
+-          t(key)
+-        end
+-
+-        # The acting user's display name, nil-guarded: the actor column is
+-        # NOT NULL at write time, but the user row itself can be deleted
+-        # later, leaving the event's actor association empty on read. An
+-        # empty/missing name degrades to the localized unknown-actor label.
+-        def audit_actor_name(event)
+-          event.actor&.name.presence || t("decidim.contracts_sk.admin.audit_events.unknown_actor")
+-        end
+-
+-        # Display info for the event's target: { label:, url: } when the
+-        # polymorphic row resolves, nil when it dangles (row gone) or its
+-        # class no longer loads (constantize raises inside the association
+-        # access). The rescue is the fail-closed boundary (the
+-        # resolve_link_target precedent): an unresolvable target can never
+-        # raise or leak internals — the view renders the localized
+-        # deleted-target label instead.
+-        #
+-        # Contract targets link to the record's edit page (the admin hub);
+-        # amendment targets label themselves by version and link to their
+-        # parent contract's amendment manager (nil url when the parent is
+-        # gone — the label then renders as plain text).
+-        def audit_target_info(event)
+-          target = event.target
+-          return nil if target.blank?
+-
+-          case target
+-          when Contract
+-            contract_target_info(target)
+-          when Amendment
+-            amendment_target_info(target)
+-          end
+-        rescue StandardError
+-          nil
+-        end
+-
+-        def contract_target_info(contract)
+-          { label: contract.title, url: edit_admin_contract_path(contract) }
+-        end
+-
+-        def amendment_target_info(amendment)
+-          parent = amendment.contract
+-          {
+-            label: t("decidim.contracts_sk.admin.audit_events.amendment_target",
+-                     version: amendment.version),
+-            url: parent && admin_contract_amendments_path(parent)
+-          }
+-        end
+-
+-        # The reviewer decision reason an event row may carry: only for a
+-        # live Contract target sitting in a decision state
+-        # (ContractLifecycle::DECISION_STATES) with a non-blank
+-        # review_reason — the same gate the edit page's decision banner
+-        # uses. Everything else the commands may have observed stays out of
+-        # the viewer (nothing payload-like beyond the identity title).
+-        def audit_reason_for(event)
+-          return nil unless event.target_type == CONTRACT_TARGET_TYPE
+-
+-          contract = event.target
+-          # The override reason of a CRZ filing confirmation (civora-org/
+-          # civora-platform#125) is shown on its own audit row.
+-          return contract&.crz_filing_reason.presence if event.action == "contract.crz_filed_override"
+-
+-          decision_reason(contract)
+-        rescue StandardError
+-          nil
+-        end
+-
+-        def decision_reason(contract)
+-          return nil unless contract.present? && contract.review_reason.present?
+-          return nil unless ContractLifecycle::DECISION_STATES.include?(contract.state&.to_sym)
+-
+-          contract.review_reason
+-        end
+       end
+     end
+   end
+diff --git a/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb b/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb
+index 2bdec90..1a1b7e6 100644
+--- a/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb
++++ b/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb
+@@ -31,6 +31,10 @@ module Decidim
+       # and an unknown value falls back to the default instead of erroring.
+       # The deadline filter (civora-org/civora-platform#124) narrows to the
+       # tracked records due within 14 days or overdue for filing in CRZ.
++      # The submitter filter (civora-org/civora-platform#126) narrows to
++      # records the signed-in user submitted (me) or everyone else's, NULL
++      # stamps included (others) — the filter the admin dashboard's review
++      # queue and returned-to-me links point at.
+       #
+       # Cop note: the class stays deliberately cohesive — the six transition
+       # shells exist so the derived routes map onto readable actions, and
+@@ -52,7 +56,8 @@ module Decidim
+                       :index_counter_label, :index_counter_path, :index_counter_classes,
+                       :index_deadline_options, :index_deadline_counts,
+                       :index_deadline_counter_label, :index_deadline_counter_path,
+-                      :index_deadline_counter_classes, :index_today
++                      :index_deadline_counter_classes, :index_today,
++                      :index_submitter_options
+ 
+         # Case-insensitive free-text match for the index :q filter over the
+         # two editorial identity fields; :pattern is always pre-escaped with
+@@ -70,12 +75,16 @@ module Decidim
+         # :crz / :editorial or nil ("all sources"), q is the stripped search
+         # term. Carries request-derived values only — never persisted.
+         # deadline (civora-org/civora-platform#124) is :due_soon / :overdue
+-        # or nil ("any deadline").
+-        IndexFilters = Struct.new(:state, :source, :q, :deadline, keyword_init: true)
++        # or nil ("any deadline"). submitter (civora-org/civora-platform#126)
++        # is :me / :others or nil ("any submitter").
++        IndexFilters = Struct.new(:state, :source, :q, :deadline, :submitter, keyword_init: true)
+ 
+         # The deadline filter vocabulary (civora-org/civora-platform#124).
+         DEADLINE_FILTERS = %i[due_soon overdue].freeze
+ 
++        # The submitter filter vocabulary (civora-org/civora-platform#126).
++        SUBMITTER_FILTERS = %i[me others].freeze
++
+         def index
+           enforce_permission_to :read, :contract
+ 
+@@ -539,7 +548,19 @@ module Decidim
+         # never to a 500.
+         def filtered_contracts
+           scope = contracts_scope.order(INDEX_ORDER)
+-          apply_deadline_filter(apply_q_filter(apply_source_filter(apply_state_filter(scope))))
++          apply_deadline_filter(apply_q_filter(apply_source_filter(apply_submitter_filter(apply_state_filter(scope)))))
 +        end
 +
-+        # The row vanished between the pre-read and the lock's reload (a
-+        # filing confirmation absorbed this mirror, civora-org/
-+        # civora-platform#125): re-find AFTER the rollback and reroute like
-+        # lost_create_race, so the sync ends :linked instead of a spurious
-+        # failure.
-+        def lost_row_race
-+          fresh = find_existing
-+          return create_transactional unless fresh
-+          return foreign_holder_outcome(fresh) if fresh.source != SOURCE
-+
-+          update_locked(fresh)
++        # Submitter filter (civora-org/civora-platform#126): "me" is the
++        # signed-in user's own submissions, "others" everyone else's AND
++        # records with no submitter stamp (the shared Contract scopes, so the
++        # dashboard's queue counts and this filter always agree).
++        def apply_submitter_filter(scope)
++          case index_filters.submitter
++          when :me then scope.submitted_by_user(current_user)
++          when :others then scope.not_submitted_by_user(current_user)
++          else scope
++          end
          end
  
-         # The in-lock decision, read from the RELOADED row (with_lock
-         # refetches under the row lock) — the TOCTOU doctrine: a pre-lock
-         # read or a stale caller's copy never admits a write.
-         def in_lock_update_outcome(contract)
--          return invalid_outcome(:collision, contract) if contract.source != SOURCE
-+          return foreign_holder_outcome(contract) if contract.source != SOURCE
-           return ok_outcome(:unchanged, contract) if unchanged_checksum?(contract)
-           return invalid_outcome(:lifecycle_guard, contract) if update_guarded?(contract)
- 
-@@ -182,6 +204,18 @@ module Decidim
-           ok_outcome(:updated, contract)
+         # CRZ deadline filter (civora-org/civora-platform#124): composes on
+@@ -587,10 +608,16 @@ module Decidim
+             state: index_state_param,
+             source: index_source_param,
+             q: params[:q].to_s.strip,
+-            deadline: index_deadline_param
++            deadline: index_deadline_param,
++            submitter: index_submitter_param
+           )
          end
  
-+        # A non-mirror record holds the source_id (civora-org/civora-platform
-+        # #125): confirmed as filed → :linked, zero writes; otherwise the
-+        # protected editorial :collision. Every decision point calls this
-+        # with the record as that point sees it — the in-lock call reads the
-+        # RELOADED row, so a filing confirmed between the pre-read and the
-+        # lock is honoured.
-+        def foreign_holder_outcome(contract)
-+          return ok_outcome(:linked, contract) if contract.crz_filed_at.present?
-+
-+          invalid_outcome(:collision, contract)
++        def index_submitter_param
++          candidate = params[:submitter].to_s.presence&.to_sym
++          candidate if SUBMITTER_FILTERS.include?(candidate)
 +        end
 +
-         # The provenance stamps every import write carries; on create it
-         # joins the mirroring identity (source + source_id).
-         def provenance_attributes
-diff --git a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
-index 0fd78a8..f3b91b0 100644
---- a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
-+++ b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
-@@ -60,6 +60,9 @@ module Decidim
-           "contract.archive" => "decidim.contracts_sk.admin.contracts.transition.archive",
-           "contract.redaction_confirmed" => "decidim.contracts_sk.admin.audit_events.actions.redaction_confirmed",
-           "amendment.publish" => "decidim.contracts_sk.admin.audit_events.actions.amendment_publish",
-+          "contract.crz_filed" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed",
-+          "contract.crz_filed_override" => "decidim.contracts_sk.admin.audit_events.actions.crz_filed_override",
-+          "contract.crz_mirror_absorbed" => "decidim.contracts_sk.admin.audit_events.actions.crz_mirror_absorbed",
-           "crz_import_create" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_create",
-           "crz_import_update" => "decidim.contracts_sk.admin.audit_events.actions.crz_import_update"
-         }.freeze
-@@ -179,12 +182,20 @@ module Decidim
-           return nil unless event.target_type == CONTRACT_TARGET_TYPE
+         def index_deadline_param
+           candidate = params[:deadline].to_s.presence&.to_sym
+           candidate if DEADLINE_FILTERS.include?(candidate)
+@@ -632,6 +659,13 @@ module Decidim
+             end
+         end
  
-           contract = event.target
-+          # The override reason of a CRZ filing confirmation (civora-org/
-+          # civora-platform#125) is shown on its own audit row.
-+          return contract&.crz_filing_reason.presence if event.action == "contract.crz_filed_override"
-+
-+          decision_reason(contract)
-+        rescue StandardError
-+          nil
++        def index_submitter_options
++          [[t("decidim.contracts_sk.admin.contracts.index.filters.submitters.any"), ""]] +
++            SUBMITTER_FILTERS.map do |submitter|
++              [t("decidim.contracts_sk.admin.contracts.index.filters.submitters.#{submitter}"), submitter]
++            end
 +        end
 +
-+        def decision_reason(contract)
-           return nil unless contract.present? && contract.review_reason.present?
-           return nil unless ContractLifecycle::DECISION_STATES.include?(contract.state&.to_sym)
- 
-           contract.review_reason
--        rescue StandardError
--          nil
+         def index_source_options
+           [[t("decidim.contracts_sk.admin.contracts.index.filters.sources.all"), ""]] +
+             %i[crz editorial].map do |source|
+@@ -663,7 +697,8 @@ module Decidim
+         # the filtered wording over the true-empty one.
+         def index_filters_active?
+           index_filters.state.present? || index_filters.source.present? ||
+-            index_filters.q.present? || index_filters.deadline.present?
++            index_filters.q.present? || index_filters.deadline.present? ||
++            index_filters.submitter.present?
          end
-       end
-     end
-diff --git a/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb b/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb
-index 0076589..2bdec90 100644
---- a/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb
-+++ b/app/controllers/decidim/contracts_sk/admin/contracts_controller.rb
-@@ -10,7 +10,10 @@ module Decidim
-       # civora-org/civora-platform#86), the ADR-007 privacy-redaction
-       # confirmation POST (civora-org/civora-platform#91) and the
-       # reviewer-decision-reason pass-through on the transition actions
--      # (civora-org/civora-platform#90).
-+      # (civora-org/civora-platform#90), and the CRZ filing confirmation
-+      # pair (civora-org/civora-platform#125: a read-only side-by-side
-+      # preview and the verifying POST, both editor-gated on a published,
-+      # unfiled editorial record).
-       #
-       # index/new/create open with enforce_permission_to before anything
-       # else; edit/update and the transition actions load the record first,
-@@ -209,6 +212,40 @@ module Decidim
-           end
+ 
+         # CRZ deadline counters (civora-org/civora-platform#124): due-soon
+@@ -698,7 +733,8 @@ module Decidim
+         # The normalized, ACTIVE filters as link params (never raw params).
+         def index_filter_params
+           { state: index_filters.state, source: index_filters.source,
+-            q: index_filters.q.presence, deadline: index_filters.deadline }.compact
++            q: index_filters.q.presence, deadline: index_filters.deadline,
++            submitter: index_filters.submitter }.compact
          end
  
-+        # CRZ filing confirmation (civora-org/civora-platform#125), GET: the
-+        # CRZ-id form and — with ?crz_id= — the read-only side-by-side
-+        # comparison of this record against the official one fetched
-+        # through the ekosystem feed. WRITES NOTHING: the confirm form it
-+        # renders carries the preview's checksum token, which the POST's
-+        # command re-verifies inside the row lock. The id is validated
-+        # (`\A\d+\z`) before any network call (the import_crz precedent).
-+        # A refusal re-renders the id form with a localized alert.
-+        def crz_filing
-+          @contract = contracts_scope.find(params[:id])
-+
-+          enforce_permission_to :confirm_crz_filing, :contract, contract: @contract
-+
-+          @crz_id = params[:crz_id].to_s.strip
-+          load_filing_preview if @crz_id.present?
+         # Chip label: the localized state label (the shared contract_states.*
+diff --git a/app/controllers/decidim/contracts_sk/admin/dashboard_controller.rb b/app/controllers/decidim/contracts_sk/admin/dashboard_controller.rb
+new file mode 100644
+index 0000000..a9daab1
+--- /dev/null
++++ b/app/controllers/decidim/contracts_sk/admin/dashboard_controller.rb
+@@ -0,0 +1,165 @@
++# frozen_string_literal: true
++
++module Decidim
++  module ContractsSk
++    module Admin
++      # The admin landing page for role holders (civora-org/civora-platform
++      # #126): what waits for ME, per role, plus the organization-wide
++      # state counts, the CRZ deadline watch and the last audit events.
++      # Read-only; every list is a capped preview that links to the
++      # matching filtered contracts index (the "Show all (N)" counts are the
++      # index's own, because both sides use the same Contract scopes).
++      #
++      # Gate: the same :read :contract permission as the contracts index
++      # (any engine role); a roleless user gets the usual NeedsPermission
++      # redirect + alert, an anonymous visitor the auth floor. The role-
++      # specific blocks are NOT gated by new role logic: each one asks the
++      # permission layer whether the user may perform the event the block
++      # is about (:approve on in_review, :submit on returned, :publish on
++      # approved, :read on the audit trail), so the dashboard can never
++      # drift from the permission table — and, being a read surface, shows
++      # nothing the index would not.
++      #
++      # Everything is tenant-scoped from the current organization. Query
++      # count is independent of the number of rows: per block one capped
++      # list query and one COUNT (the review queue adds one preload for the
++      # submitters), one grouped state count, and one audit list with
++      # bounded preloads (actors, targets, amendment parent contracts).
++      class DashboardController < Admin::ApplicationController
++        include AuditEventPresentation
++
++        # Preview cap per list (the "Show all (N)" link covers the rest).
++        LIST_LIMIT = 10
++
++        # One block of the page: the capped rows, the full total and the
++        # filtered-index target. Blocks the user may not see are simply never
++        # built (the view gates them through the visibility predicates).
++        Block = Struct.new(:records, :total, :path, keyword_init: true)
++
++        helper_method :review_queue, :returned_list, :approved_list, :overdue_list,
++                      :due_soon_list, :state_counts, :total_count, :recent_events,
++                      :dashboard_today, :audit_trail_visible?,
++                      :review_queue_visible?, :returned_visible?, :approved_visible?
++
++        def show
++          enforce_permission_to :read, :contract
++        end
++
++        private
++
++        def contracts_scope
++          Contract.where(organization: current_organization)
 +        end
 +
-+        # CRZ filing confirmation, POST: the verifying command. Every
-+        # outcome is a PRG redirect with a localized flash — success to the
-+        # index (a filed record is published and no longer editable); a
-+        # refusal the editor can act on (stale preview, reason problems)
-+        # back to the preview of the same id, the others to the id form or
-+        # the index (see FILING_PREVIEW_REASONS / #filing_failed).
-+        def confirm_crz_filing
-+          @contract = contracts_scope.find(params[:id])
++        def dashboard_today
++          @dashboard_today ||= Date.current
++        end
 +
-+          enforce_permission_to :confirm_crz_filing, :contract, contract: @contract
++        # --- visibility: the permission layer decides, no role logic here ---
 +
-+          crz_id = params[:crz_id].to_s.strip
-+          return filing_failed(:not_found, crz_id) unless crz_id.match?(CRZ_ID_FORMAT)
++        def review_queue_visible?
++          allowed_to?(:approve, :contract, state: :in_review)
++        end
 +
-+          run_filing_confirmation(crz_id)
++        def returned_visible?
++          allowed_to?(:submit, :contract, state: :returned)
 +        end
 +
-         # One explicit action per lifecycle transition event. The route set
-         # is derived from ContractLifecycle::TRANSITIONS in config/routes.rb;
-         # these named shells exist so the derived routes map onto readable
-@@ -239,7 +276,15 @@ module Decidim
- 
-         # The import outcome vocabulary mirrors CrzImport outcomes 1:1;
-         # the successful trio flashes :notice, everything else :alert.
--        IMPORT_NOTICE_OUTCOMES = %i[created updated unchanged].freeze
-+        IMPORT_NOTICE_OUTCOMES = %i[created updated unchanged linked].freeze
-+
-+        # Filing-confirmation refusals that redirect back to the PREVIEW of
-+        # the same id (the editor can correct the reason, or must re-read a
-+        # changed official record); every other refusal returns to the bare
-+        # id form, and :already_filed / :not_fileable to the index.
-+        CRZ_ID_FORMAT = /\A\d+\z/
-+        FILING_PREVIEW_REASONS = %i[stale reason_required reason_rejected].freeze
-+        FILING_INDEX_REASONS = %i[already_filed not_fileable].freeze
- 
-         private
- 
-@@ -256,6 +301,52 @@ module Decidim
-           redirect_to admin_contracts_path
-         end
- 
-+        # The preview fetch (read-only, FilingLookup): sets the comparison
-+        # and checksum token for the view, or re-renders the id form with a
-+        # localized refusal. A non-numeric id never reaches the network.
-+        def load_filing_preview
-+          return filing_invalid_id unless @crz_id.match?(CRZ_ID_FORMAT)
++        def approved_visible?
++          allowed_to?(:publish, :contract, state: :approved)
++        end
 +
-+          lookup = CrzImport::FilingLookup.call(crz_id: @crz_id, organization: current_organization)
-+          return flash.now[:alert] = filing_message(lookup.refusal, @crz_id) unless lookup.ok?
++        def audit_trail_visible?
++          allowed_to?(:read, :audit_event)
++        end
 +
-+          @crz_record = lookup.record
-+          @comparison = CrzImport::FilingComparison.new(contract: @contract, record: @crz_record)
++        # --- blocks ---
++
++        # In-review records the user may judge (four-eyes: own submissions
++        # excluded unless the allow_self_review seam is on, in which case the
++        # index link carries no submitter narrowing either).
++        def review_queue
++          @review_queue ||= begin
++            scope = contracts_scope.awaiting_review_by(current_user)
++            link = { state: :in_review }
++            link[:submitter] = :others unless Decidim::ContractsSk.allow_self_review
++            build_block(scope.includes(:submitted_by).order(updated_at: :asc, id: :asc), scope, link)
++          end
 +        end
 +
-+        def filing_invalid_id
-+          flash.now[:alert] = t("decidim.contracts_sk.admin.contracts.crz_filing.invalid_id")
++        def returned_list
++          @returned_list ||= begin
++            scope = contracts_scope.returned_to(current_user)
++            build_block(scope.order(Arel.sql("reviewed_at IS NULL"), reviewed_at: :desc, id: :desc), scope,
++                        state: :returned, submitter: :me)
++          end
 +        end
 +
-+        def run_filing_confirmation(crz_id)
-+          ConfirmCrzFiling.call(@contract, crz_id: crz_id, checksum: params[:checksum],
-+                                           reason: params[:reason], user: current_user) do
-+            on(:ok) { |outcome| filing_succeeded(outcome, crz_id) }
-+            on(:invalid) { |reason| filing_failed(reason, crz_id) }
++        def approved_list
++          @approved_list ||= begin
++            scope = contracts_scope.approved
++            build_block(scope.order(updated_at: :asc, id: :asc), scope, state: :approved)
 +          end
 +        end
 +
-+        def filing_message(reason, crz_id)
-+          t("decidim.contracts_sk.admin.contracts.crz_filing.refusals.#{reason}", crz_id: crz_id)
++        def overdue_list
++          @overdue_list ||= deadline_block(contracts_scope.crz_overdue(dashboard_today), :overdue)
++        end
++
++        def due_soon_list
++          @due_soon_list ||= deadline_block(contracts_scope.crz_due_soon(dashboard_today), :due_soon)
++        end
++
++        def deadline_block(scope, deadline)
++          build_block(scope.order(signed_on: :asc, id: :asc), scope, deadline: deadline)
++        end
++
++        def build_block(ordered, counted, link_params)
++          Block.new(records: ordered.limit(LIST_LIMIT).to_a,
++                    total: counted.count,
++                    path: admin_contracts_path(link_params))
 +        end
 +
-+        def filing_succeeded(outcome, crz_id)
-+          flash[:notice] = t("decidim.contracts_sk.admin.contracts.crz_filing.#{outcome}", crz_id: crz_id)
-+          redirect_to admin_contracts_path
++        # One grouped COUNT over the tenant scope, zeros included, in the
++        # lifecycle's own order (the vocabulary is never hand-enumerated).
++        def state_counts
++          @state_counts ||= begin
++            grouped = contracts_scope.group(:state).count.transform_keys(&:to_sym)
++            ContractLifecycle::STATES.to_h { |state| [state, grouped.fetch(state, 0)] }
++          end
 +        end
 +
-+        def filing_failed(reason, crz_id)
-+          flash[:alert] = filing_message(reason, crz_id)
++        def total_count
++          @total_count ||= state_counts.values.sum
++        end
 +
-+          if FILING_INDEX_REASONS.include?(reason)
-+            redirect_to admin_contracts_path
-+          elsif FILING_PREVIEW_REASONS.include?(reason)
-+            redirect_to crz_filing_admin_contract_path(@contract, crz_id: crz_id)
-+          else
-+            redirect_to crz_filing_admin_contract_path(@contract)
++        # The last audit events of the organization (tenancy explicit on the
++        # rows), newest first under the viewer's own total order. Actors and
++        # targets are preloaded; an amendment target's parent contract (which
++        # the target label links through) is preloaded in one more query, so
++        # the page's query count never depends on the rows.
++        def recent_events
++          @recent_events ||= begin
++            events = recent_events_scope.includes(:actor, :target).to_a
++            amendments = events.map(&:target).grep(Amendment)
++            ActiveRecord::Associations::Preloader.new(records: amendments, associations: :contract).call
++            events
++          rescue NameError => e
++            raise if e.is_a?(NoMethodError)
++
++            # A target_type whose class no longer loads cannot be preloaded;
++            # fall back to the lazy per-row resolution, whose helper is
++            # fail-closed (the viewer's dangling-target doctrine).
++            recent_events_scope.includes(:actor).to_a
 +          end
 +        end
 +
-         # PRG on success: notice + back to the admin index.
-         def create_succeeded
-           flash[:notice] = t("decidim.contracts_sk.admin.contracts.create.success")
++        def recent_events_scope
++          AuditEvent.where(organization: current_organization)
++                    .order(INDEX_ORDER)
++                    .limit(LIST_LIMIT)
++        end
++      end
++    end
++  end
++end
 diff --git a/app/models/decidim/contracts_sk/contract.rb b/app/models/decidim/contracts_sk/contract.rb
-index adee019..0d6df4d 100644
+index 0d6df4d..19bdda4 100644
 --- a/app/models/decidim/contracts_sk/contract.rb
 +++ b/app/models/decidim/contracts_sk/contract.rb
-@@ -162,15 +162,16 @@ module Decidim
-       # the instance helpers and the scopes agree by construction.
-       #
-       # Tracked = an editorial record (source != the CRZ mirror's), in a
--      # DEADLINE_TRACKED_STATES state, with crz_url NULL or '' — "not
--      # recorded as filed in CRZ", the interim filed proxy until real filing
--      # confirmation lands (civora-org/civora-platform#125). Records with an
-+      # DEADLINE_TRACKED_STATES state, with crz_filed_at NULL — "not
-+      # confirmed as filed in CRZ" (the verified filing confirmation of
-+      # civora-org/civora-platform#125 replaced the #124 crz_url proxy;
-+      # a typed crz_url alone no longer counts). Records with an
-       # unknown signed_on ARE tracked here (the edit page and the row badge
-       # flag them) but belong to neither the overdue nor the due-soon scope.
-       scope :crz_deadline_tracked, lambda {
-         where.not(source: CrzImport::Mapper::SOURCE)
-              .where(state: ContractLifecycle::DEADLINE_TRACKED_STATES.map(&:to_s))
--             .where(crz_url: [nil, ""])
-+             .where(crz_filed_at: nil)
-       }
- 
-       # Tracked records whose deadline lies before +today+:
-@@ -202,7 +203,7 @@ module Decidim
-       # Whether this record is subject to deadline tracking (the instance
-       # twin of the crz_deadline_tracked scope).
-       def crz_deadline_tracked?
--        CrzDeadline.tracked?(source: source, state: state, crz_url: crz_url)
-+        CrzDeadline.tracked?(source: source, state: state, crz_filed_at: crz_filed_at)
-       end
- 
-       # :untracked (filed, mirror or terminal), :unknown (tracked, no
-diff --git a/app/permissions/decidim/contracts_sk/permissions.rb b/app/permissions/decidim/contracts_sk/permissions.rb
-index 237cc37..0e7bb5c 100644
---- a/app/permissions/decidim/contracts_sk/permissions.rb
-+++ b/app/permissions/decidim/contracts_sk/permissions.rb
-@@ -33,6 +33,14 @@ module Decidim
-     #   role-gated only, so an editor can retrieve it on any lifecycle
-     #   state (unlike :update, which stays editable-state-gated for the
-     #   generating twin action).
-+    # - :confirm_crz_filing (civora-org/civora-platform#125) is allowed when
-+    #   the user's engine roles include :editor AND the record
-+    #   (context[:contract] — required, a bare :state context is denied
-+    #   fail-closed) is editorial (source != the CRZ mirror's), published and
-+    #   not yet confirmed as filed (crz_filed_at blank): only a published
-+    #   editorial record that has been handed off to the CRZ can be linked to
-+    #   its official record, and once. Reviewers are denied. The command
-+    #   re-checks all of it inside the row lock.
-     # - Transition events (:submit, :return, :approve, :reject, :publish,
-     #   :archive) are allowed when ContractLifecycle.allowed_roles for the
-     #   record's state intersect the user's engine roles. The event list is
-@@ -112,6 +120,10 @@ module Decidim
-     # at class-body load; this file is only ever loaded through the gem's
-     # lib require chain (which defines ContractLifecycle first), never
-     # standalone.
-+    # Cop note: the class stays deliberately cohesive — one rule table per
-+    # subject, every gate readable in one file; splitting it would scatter
-+    # the permission contract rather than simplify it.
-+    # rubocop:disable Metrics/ClassLength
-     class Permissions < Decidim::DefaultPermissions
-       TRANSITION_EVENTS = ContractLifecycle::TRANSITIONS.values
-                                                         .flat_map(&:keys)
-@@ -163,7 +175,7 @@ module Decidim
-         # consult different lifecycle windows (see #action_state_window):
-         # the stamp may still land on an approved record right before
-         # publish, while editability itself is never widened.
--        when :update, :confirm_redaction
-+        when :update, :confirm_redaction, :confirm_crz_filing
-           toggle_allow(contract_write_allowed?)
-         when :read
-           toggle_allow(roles_for_user.any?)
-@@ -222,6 +234,8 @@ module Decidim
-       # The shared gate behind :update and :confirm_redaction: the editor
-       # role plus the action's lifecycle window (see #action_state_window).
-       def contract_write_allowed?
-+        return editor? && crz_filing_allowed? if action == :confirm_crz_filing
-+
-         editor? && action_state_window.include?(state)
-       end
- 
-@@ -239,6 +253,17 @@ module Decidim
-         end
-       end
- 
-+      # The CRZ filing confirmation window (civora-org/civora-platform#125):
-+      # an editorial, published, not-yet-filed record. Needs the record
-+      # itself — the filed flag and the source are not derivable from a bare
-+      # state, so a context without :contract denies.
-+      def crz_filing_allowed?
-+        record = context[:contract]
-+        return false unless record
-+
-+        record.source.to_s != CrzImport::Mapper::SOURCE && state == :published && record.crz_filed_at.blank?
-+      end
-+
-       def amendment_edit_allowed?
-         editor? && amendment_draft?
-       end
-@@ -287,5 +312,6 @@ module Decidim
-         Array(Decidim::ContractsSk.role_resolver.call(user, context)) & ContractLifecycle::ROLES
-       end
-     end
-+    # rubocop:enable Metrics/ClassLength
-   end
- end
-diff --git a/app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb b/app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb
+@@ -29,6 +29,12 @@ module Decidim
+     # civora-org/civora-platform#123): TransitionContract stamps the acting
+     # user on every submit, the rule forbids that person to return, approve
+     # or reject the record, and no form or the CRZ upsert ever writes it.
++    # The column has no index and was introduced as read per record; since
++    # the admin dashboard (civora-org/civora-platform#126) it IS also queried
++    # as a set — the submitter scopes below back the review queue, the
++    # returned-to-me list and the index submitter filter — always on the
++    # small, tenant-scoped, state-narrowed relation, so the original
++    # no-index decision stands.
+     #
+     # The source/source_id/imported_at/import_status columns are
+     # CRZ-mirror provenance metadata (docs/contracts-domain-notes.md);
+@@ -154,6 +160,35 @@ module Decidim
+       # ContractState and the permissions layer normalize via #to_sym.
+       enum :state, STATE_VALUES, default: "draft"
+ 
++      # Submitter scopes (civora-org/civora-platform#126), shared by the admin
++      # dashboard and the contracts index submitter filter so both always
++      # agree. The stamp is nullable (legacy/never-submitted records), so the
++      # negative form is spelled out as "NULL OR <> id" — a bare where.not
++      # would silently drop the NULL rows (SQL three-valued logic).
++      # A nil user matches nothing (never the NULL stamps: "me" is nobody).
++      scope :submitted_by_user, lambda { |user|
++        user ? where(decidim_submitted_by_id: user.id) : none
++      }
++      scope :not_submitted_by_user, lambda { |user|
++        where(decidim_submitted_by_id: nil).or(where.not(decidim_submitted_by_id: user&.id))
++      }
++
++      # The reviewer's queue: in_review records the user may judge. The set
++      # twin of Decidim::ContractsSk.self_review_blocked?(contract, user,
++      # :approve) (the four-eyes rule, #123): a record is in the queue
++      # exactly when that predicate is false. With the allow_self_review
++      # seam on the submitter clause drops, as the predicate then never
++      # blocks. Note the predicate reads the CONFIG seam; +allow_self+
++      # defaults to it and is a keyword only so specs can pin both modes.
++      scope :awaiting_review_by, lambda { |user, allow_self: Decidim::ContractsSk.allow_self_review|
++        queue = in_review
++        allow_self ? queue : queue.merge(not_submitted_by_user(user))
++      }
++
++      # Records the user submitted that a reviewer sent back: the submitter's
++      # "returned to me" list (the resubmit edge is theirs).
++      scope :returned_to, ->(user) { returned.merge(submitted_by_user(user)) }
++
+       # CRZ publication deadline tracking (§ 47a OZ, civora-org/civora-platform
+       # #124). The deadline is computed from signed_on and the config seam
+       # Decidim::ContractsSk.crz_deadline — never stored — and the arithmetic
+diff --git a/app/views/decidim/contracts_sk/admin/audit_events/_table.html.erb b/app/views/decidim/contracts_sk/admin/audit_events/_table.html.erb
 new file mode 100644
-index 0000000..53216ad
+index 0000000..f3781b9
 --- /dev/null
-+++ b/app/views/decidim/contracts_sk/admin/contracts/crz_filing.html.erb
-@@ -0,0 +1,99 @@
-+<%# CRZ filing confirmation page (civora-org/civora-platform#125): the
-+    editor names the CRZ id of the record they filed by hand; with ?crz_id=
-+    the controller has fetched the official record (read-only) and the page
-+    shows it side by side with this one. Nothing is written by this page.
-+    Ivars: @contract, @crz_id, and — when the fetch succeeded —
-+    @crz_record (the mapped record) and @comparison (FilingComparison).
-+    The confirm form carries the preview's checksum token and the CRZ id as
-+    hidden fields; the command re-verifies the token, the comparison and the
-+    reason rule inside the row lock, so nothing here is the gate. Plain
-+    form_with tag helpers (the import_crz form precedent). %>
-+<% scope = "decidim.contracts_sk.admin.contracts.crz_filing" %>
-+<div class="item_show__header">
-+  <h1 class="item_show__header-title">
-+    <%= t("#{scope}.title") %>
-+  </h1>
++++ b/app/views/decidim/contracts_sk/admin/audit_events/_table.html.erb
+@@ -0,0 +1,60 @@
++<%# The audit-event table (civora-org/civora-platform#92), shared by the
++    audit-trail viewer and the admin dashboard's recent-activity block
++    (civora-org/civora-platform#126). Local: events - the rows to render. The
++    label/actor/target/reason helpers come from the including controller
++    (Admin::AuditEventPresentation). %>
++<%# table-list--selectable is Decidim admin's own modifier that
++    left-aligns the second column (the table-list default centres every
++    column after the first, which floated the record titles mid-cell). %>
++<div class="table-scroll">
++  <table class="table-list table-list--selectable">
++    <thead>
++      <tr>
++        <th><%= t("decidim.contracts_sk.admin.audit_events.index.headers.action") %></th>
++        <th><%= t("decidim.contracts_sk.admin.audit_events.index.headers.record") %></th>
++        <th><%= t("decidim.contracts_sk.admin.audit_events.index.headers.user") %></th>
++        <th><%= t("decidim.contracts_sk.admin.audit_events.index.headers.when") %></th>
++        <th><%= t("decidim.contracts_sk.admin.contracts.transition.review_reason.label") %></th>
++      </tr>
++    </thead>
++    <tbody>
++      <% events.each do |event| %>
++        <% target_info = audit_target_info(event) %>
++        <% reason = audit_reason_for(event) %>
++        <tr>
++          <td><%= audit_action_label(event.action) %></td>
++          <td>
++            <%# Dangling target (row gone or class unloadable): the
++                localized label in place of the title link — graceful,
++                no internals leaked (fail-closed at the helper). %>
++            <% if target_info %>
++              <% if target_info[:url].present? %>
++                <%= link_to target_info[:label], target_info[:url] %>
++              <% else %>
++                <%= target_info[:label] %>
++              <% end %>
++            <% else %>
++              <span class="text-warning"><%= t("decidim.contracts_sk.admin.audit_events.deleted_target") %></span>
++            <% end %>
++          </td>
++          <td><%= audit_actor_name(event) %></td>
++          <%# The row timestamp renders through the shared locale-aware
++              helpers (civora-org/civora-platform#81) directly in the
++              view — the helper chain is the view's, not the
++              controller's. Date AND time: several events per contract
++              share a day, and the trail must be readable in order. %>
++          <td style="white-space: nowrap"><%= format_datetime(event.created_at) %></td>
++          <%# No reason recorded: an explicit muted dash, so the column
++              reads as "none" rather than as missing data. %>
++          <td>
++            <% if reason.present? %>
++              <%= reason %>
++            <% else %>
++              <span aria-hidden="true">—</span>
++            <% end %>
++          </td>
++        </tr>
++      <% end %>
++    </tbody>
++  </table>
 +</div>
-+
-+<p><strong><%= @contract.title %></strong> (<%= @contract.reference %>)</p>
-+<p><%= t("#{scope}.description") %></p>
-+
-+<div class="card">
-+  <div class="card-section">
-+    <%= form_with url: crz_filing_admin_contract_path(@contract), method: :get, local: true do %>
+diff --git a/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb b/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
+index 471456a..9149fe9 100644
+--- a/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
++++ b/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
+@@ -1,8 +1,14 @@
++<%= render "decidim/contracts_sk/shared/admin_styles" %>
+ <div class="card">
+   <div class="item_show__header">
+     <h1 class="item_show__header-title">
+       <%= t("decidim.contracts_sk.admin.audit_events.index.title") %>
+     </h1>
++    <%# Admin overview (civora-org/civora-platform#126). %>
++    <div class="cs-admin-actions">
++      <%= link_to t("decidim.contracts_sk.admin.dashboard.overview_link"), admin_root_path,
++                  class: "button button__sm button__secondary" %>
++    </div>
+   </div>
+ 
+   <%# Contract-scoped mode (civora-org/civora-platform#92): the banner
+@@ -19,61 +25,7 @@
+   <% end %>
+ 
+   <% if @audit_events.any? %>
+-    <%# table-list--selectable is Decidim admin's own modifier that
+-        left
```

## Agent Activity
- Tool calls: 0
- Commands: 0
- Checkpoints: 1
- Test runs: 2
- Journal events: 4234

_Generated: 2026-10-04T20:25:38.085Z · schema agent-review/v1_
