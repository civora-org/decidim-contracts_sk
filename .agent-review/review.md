# Agent Review

## Task
Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code

## Session
- Session ID: d89b86e3-d25a-4b4e-aa50-1bd7560e389d
- Branch: chore/claude-code-config
- Started: 2026-10-02T22:26:31.118Z
- Finished: 2026-10-02T22:27:52.305Z

## Summary
Claude Code subagents: Port .opencode/agents to Claude Code subagents so both harnesses share the same roles Claude Code slash-command skills: Port the 9 .opencode/commands to Claude Code skills invoked as /<name> agent-review skill, MCP servers and journaling hook: Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers Claude Code permissions: Mirror opencode.jsonc permissions CLAUDE.md and AGENTS.md pointer: Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router

## Logical Changes

### 1. agent-review skill, MCP servers and journaling hook
- What changed: added in `.claude/skills/agent-review`, `.mcp.json`, `.claude/settings.json`
- Why: Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers
- Expected behavior: Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active
- Risk: medium
- Limitations: Absolute machine paths in .mcp.json (same as opencode.jsonc); Hook assumes agent-review is a sibling checkout; Skill is a symlink into ../agent-review
### 2. Claude Code subagents
- What changed: added in `.claude/agents/architect.md`, `.claude/agents/reviewer.md`, `.claude/agents/rails.md`, `.claude/agents/tester.md`, `.claude/agents/integration.md`, `.claude/agents/retro.md`
- Why: Port .opencode/agents to Claude Code subagents so both harnesses share the same roles
- Expected behavior: architect/reviewer run on opus with read-only tools; rails/tester/integration/retro on sonnet; bodies identical to the OpenCode agents
- Risk: low
- Alternatives considered: Keep GLM-only OpenCode agents
- Limitations: The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md
### 3. Claude Code slash-command skills
- What changed: added in `.claude/skills/issue/SKILL.md`, `.claude/skills/feature/SKILL.md`, `.claude/skills/review/SKILL.md`, `.claude/skills/verify/SKILL.md`, `.claude/skills/retro/SKILL.md`, `.claude/skills/agent-review-github-status/SKILL.md`, `.claude/skills/agent-review-prepare-pr/SKILL.md`, `.claude/skills/agent-review-publish-pr/SKILL.md`, `.claude/skills/agent-review-update-review/SKILL.md`
- Why: Port the 9 .opencode/commands to Claude Code skills invoked as /<name>
- Expected behavior: /issue reads civora-org/civora-platform issues via gh; publish-pr, update-review and retro are user-invoked only (disable-model-invocation)
- Risk: low
### 4. Claude Code permissions
- What changed: added in `.claude/settings.json`
- Why: Mirror opencode.jsonc permissions
- Expected behavior: git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied
- Risk: low
- Limitations: edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates
### 5. CLAUDE.md and AGENTS.md pointer
- What changed: added in `CLAUDE.md`, `AGENTS.md`
- Why: Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router
- Expected behavior: CLAUDE.md imports @AGENTS.md; AGENTS.md lists the Claude Code mirror to keep in sync
- Risk: low

## Test Evidence

### Run 1
- Command: `bundle exec rspec`
- Result: **passed** (exit code: 0)
- Duration: 3133 ms
- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`

## Risks
- Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.
- Large diff: 4919 insertions across 26 files.

## Limitations
- Snapshots cover only files that were changed at checkpoint time.
- Symbol extraction is regex-based, not AST-based.
- Only observed facts are recorded — private model reasoning is not captured.
- The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md
- Absolute machine paths in .mcp.json (same as opencode.jsonc)
- Hook assumes agent-review is a sibling checkout
- Skill is a symlink into ../agent-review
- edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates

## Changed Files
- `.agent-review/change-package.json` — modified (json, +207/−341)
- `.agent-review/github/inline-comments.preview.json` — modified (json, +18/−5)
- `.agent-review/github/pr-body.md` — modified (markdown, +16/−9)
- `.agent-review/github/pr-preview.json` — modified (json, +23/−10)
- `.agent-review/github/publish-plan.md` — modified (markdown, +5/−4)
- `.agent-review/review.md` — modified (markdown, +4156/−997)
- `.claude/agents/architect.md` — modified (markdown, +39/−0)
- `.claude/agents/integration.md` — modified (markdown, +34/−0)
- `.claude/agents/rails.md` — modified (markdown, +27/−0)
- `.claude/agents/retro.md` — modified (markdown, +24/−0)
- `.claude/agents/reviewer.md` — modified (markdown, +35/−0)
- `.claude/agents/tester.md` — modified (markdown, +36/−0)
- `.claude/settings.json` — modified (json, +56/−0)
- `.claude/skills/agent-review` — modified (unknown, +1/−0)
- `.claude/skills/agent-review-github-status/SKILL.md` — modified (markdown, +21/−0)
- `.claude/skills/agent-review-prepare-pr/SKILL.md` — modified (markdown, +25/−0)
- `.claude/skills/agent-review-publish-pr/SKILL.md` — modified (markdown, +26/−0)
- `.claude/skills/agent-review-update-review/SKILL.md` — modified (markdown, +23/−0)
- `.claude/skills/feature/SKILL.md` — modified (markdown, +22/−0)
- `.claude/skills/issue/SKILL.md` — modified (markdown, +23/−0)
- `.claude/skills/retro/SKILL.md` — modified (markdown, +21/−0)
- `.claude/skills/review/SKILL.md` — modified (markdown, +19/−0)
- `.claude/skills/verify/SKILL.md` — modified (markdown, +20/−0)
- `.mcp.json` — modified (json, +16/−0)
- `AGENTS.md` — modified (markdown, +1/−0)
- `CLAUDE.md` — modified (markdown, +25/−0)

## Commits
- `5a3f5102c1` chore: mirror OpenCode agent setup for Claude Code (Denys Kozlov, 2026-10-03T00:27:48+02:00)

## Diff
```diff
diff --git a/.agent-review/change-package.json b/.agent-review/change-package.json
index 75b47a1..498b04e 100644
--- a/.agent-review/change-package.json
+++ b/.agent-review/change-package.json
@@ -1,409 +1,305 @@
 {
   "schemaVersion": "agent-review/v1",
   "session": {
-    "id": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
-    "startedAt": "2026-09-28T15:48:32.593Z",
-    "endedAt": "2026-09-28T16:25:37.886Z",
+    "id": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
+    "startedAt": "2026-10-02T22:26:31.118Z",
+    "endedAt": "2026-10-02T22:27:52.305Z",
     "status": "ended"
   },
-  "task": "Pilot demo UX polish: guard blank live fields on public detail (#80), admin form a11y (#78), input hints + currency select (#79), localized money/date rendering + PDF timestamp UTC label (#81)",
-  "branch": "polish/pilot-demo-ux",
-  "commits": [],
+  "task": "Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code",
+  "branch": "chore/claude-code-config",
+  "commits": [
+    {
+      "hash": "5a3f5102c111c56ea154eb5878727e15e45169e1",
+      "subject": "chore: mirror OpenCode agent setup for Claude Code",
+      "author": "Denys Kozlov",
+      "date": "2026-10-03T00:27:48+02:00"
+    }
+  ],
   "changedFiles": [
     {
-      "path": ".opencode/commands/agent-review-github-status.md",
-      "kind": "added",
-      "language": "markdown",
-      "insertions": 16,
-      "deletions": 0
-    },
-    {
-      "path": ".opencode/commands/agent-review-prepare-pr.md",
-      "kind": "added",
-      "language": "markdown",
-      "insertions": 19,
-      "deletions": 0
-    },
-    {
-      "path": ".opencode/commands/agent-review-publish-pr.md",
-      "kind": "added",
-      "language": "markdown",
-      "insertions": 19,
-      "deletions": 0
-    },
-    {
-      "path": ".opencode/commands/agent-review-update-review.md",
-      "kind": "added",
-      "language": "markdown",
-      "insertions": 16,
-      "deletions": 0
-    },
-    {
-      "path": ".opencode/plugins/agent-review.ts",
-      "kind": "added",
-      "language": "typescript",
-      "insertions": 357,
-      "deletions": 0,
-      "symbols": [
-        "serialize",
-        "errorMessage",
-        "recordIfActive"
-      ]
-    },
-    {
-      "path": ".opencode/skills/agent-review",
-      "kind": "added",
-      "language": "unknown",
-      "insertions": 0,
-      "deletions": 0
-    },
-    {
-      "path": "AGENTS.md",
+      "path": ".agent-review/change-package.json",
       "kind": "modified",
-      "language": "markdown",
-      "insertions": 2,
-      "deletions": 0
+      "language": "json",
+      "insertions": 207,
+      "deletions": 341
     },
     {
-      "path": "app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb",
+      "path": ".agent-review/github/inline-comments.preview.json",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 1,
-      "deletions": 7,
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
+      "language": "json",
+      "insertions": 18,
+      "deletions": 5
     },
     {
-      "path": "app/helpers/decidim/contracts_sk/application_helper.rb",
+      "path": ".agent-review/github/pr-body.md",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 67,
-      "deletions": 0,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "ApplicationHelper",
-        "imported_contract?",
-        "format_amount",
-        "format_date",
-        "format_timestamp",
-        "mirror_stale?",
-        "localized_amount"
-      ]
+      "language": "markdown",
+      "insertions": 16,
+      "deletions": 9
     },
     {
-      "path": "app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb",
+      "path": ".agent-review/github/pr-preview.json",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 28,
-      "deletions": 9,
-      "symbols": [
-        "Decidim",
-        "ContractsSk",
-        "CrzHandoffPdf",
-        "initialize",
-        "render",
-        "document",
-        "render_header",
-        "render_field_rows",
-        "render_parties",
-        "render_footer"
-      ]
+      "language": "json",
+      "insertions": 23,
+      "deletions": 10
     },
     {
-      "path": "app/views/decidim/contracts_sk/admin/amendments/_form.html.erb",
+      "path": ".agent-review/github/publish-plan.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 6,
+      "language": "markdown",
+      "insertions": 5,
       "deletions": 4
     },
     {
-      "path": "app/views/decidim/contracts_sk/admin/audit_events/index.html.erb",
+      "path": ".agent-review/review.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 4,
-      "deletions": 1
+      "language": "markdown",
+      "insertions": 4156,
+      "deletions": 997
     },
     {
-      "path": "app/views/decidim/contracts_sk/admin/contracts/_form.html.erb",
+      "path": ".claude/agents/architect.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 25,
-      "deletions": 7
+      "language": "markdown",
+      "insertions": 39,
+      "deletions": 0
     },
     {
-      "path": "app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb",
+      "path": ".claude/agents/integration.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 1,
-      "deletions": 1
+      "language": "markdown",
+      "insertions": 34,
+      "deletions": 0
     },
     {
-      "path": "app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb",
+      "path": ".claude/agents/rails.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 1,
-      "deletions": 1
+      "language": "markdown",
+      "insertions": 27,
+      "deletions": 0
     },
     {
-      "path": "app/views/decidim/contracts_sk/admin/documents/_form.html.erb",
+      "path": ".claude/agents/retro.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 6,
-      "deletions": 3
+      "language": "markdown",
+      "insertions": 24,
+      "deletions": 0
     },
     {
-      "path": "app/views/decidim/contracts_sk/admin/parties/_form.html.erb",
+      "path": ".claude/agents/reviewer.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 8,
-      "deletions": 5
+      "language": "markdown",
+      "insertions": 35,
+      "deletions": 0
     },
     {
-      "path": "app/views/decidim/contracts_sk/contracts/index.html.erb",
+      "path": ".claude/agents/tester.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 5,
-      "deletions": 4
+      "language": "markdown",
+      "insertions": 36,
+      "deletions": 0
     },
     {
-      "path": "app/views/decidim/contracts_sk/contracts/show.html.erb",
+      "path": ".claude/settings.json",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 54,
-      "deletions": 22
+      "language": "json",
+      "insertions": 56,
+      "deletions": 0
     },
     {
-      "path": "config/locales/en.yml",
+      "path": ".claude/skills/agent-review",
       "kind": "modified",
-      "language": "yaml",
-      "insertions": 4,
+      "language": "unknown",
+      "insertions": 1,
       "deletions": 0
     },
     {
-      "path": "config/locales/sk.yml",
+      "path": ".claude/skills/agent-review-github-status/SKILL.md",
       "kind": "modified",
-      "language": "yaml",
-      "insertions": 4,
+      "language": "markdown",
+      "insertions": 21,
       "deletions": 0
     },
     {
-      "path": "docs/crz-import.md",
+      "path": ".claude/skills/agent-review-prepare-pr/SKILL.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 1,
-      "deletions": 1
+      "insertions": 25,
+      "deletions": 0
     },
     {
-      "path": "docs/qa-checklist.md",
+      "path": ".claude/skills/agent-review-publish-pr/SKILL.md",
       "kind": "modified",
       "language": "markdown",
-      "insertions": 7,
-      "deletions": 6
+      "insertions": 26,
+      "deletions": 0
     },
     {
-      "path": "opencode.jsonc",
+      "path": ".claude/skills/agent-review-update-review/SKILL.md",
       "kind": "modified",
-      "language": "unknown",
-      "insertions": 6,
+      "language": "markdown",
+      "insertions": 23,
       "deletions": 0
     },
     {
-      "path": "spec/decidim/contracts_sk_locales_spec.rb",
+      "path": ".claude/skills/feature/SKILL.md",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 30,
-      "deletions": 0,
-      "symbols": [
-        "LocaleContract",
-        "locale_file",
-        "translations",
-        "module_tree",
-        "leaf_paths",
-        "leaf_values",
-        "fresh_backend",
-        "PublicCatalogueLabels"
-      ]
+      "language": "markdown",
+      "insertions": 22,
+      "deletions": 0
     },
     {
-      "path": "spec/decidim/contracts_sk/application_helper_spec.rb",
-      "kind": "added",
-      "language": "ruby",
-      "insertions": 116,
-      "deletions": 0,
-      "symbols": [
-        "with_locale"
-      ]
+      "path": ".claude/skills/issue/SKILL.md",
+      "kind": "modified",
+      "language": "markdown",
+      "insertions": 23,
+      "deletions": 0
     },
     {
-      "path": "spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb",
+      "path": ".claude/skills/retro/SKILL.md",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 9,
-      "deletions": 0,
-      "symbols": [
-        "blank_optional_fields"
-      ]
+      "language": "markdown",
+      "insertions": 21,
+      "deletions": 0
     },
     {
-      "path": "spec/requests/admin/amendments_spec.rb",
+      "path": ".claude/skills/review/SKILL.md",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 8,
-      "deletions": 0,
-      "symbols": [
-        "sign_in",
-        "stub_record_lookups",
-        "create_contract!"
-      ]
+      "language": "markdown",
+      "insertions": 19,
+      "deletions": 0
     },
     {
-      "path": "spec/requests/admin/contracts_spec.rb",
+      "path": ".claude/skills/verify/SKILL.md",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 34,
-      "deletions": 0,
-      "symbols": [
-        "RecordingIndexScope",
-        "initialize",
-        "where",
-        "not",
-        "order",
-        "group",
-        "count",
-        "page",
-        "per",
-        "prev_page"
-      ]
+      "language": "markdown",
+      "insertions": 20,
+      "deletions": 0
     },
     {
-      "path": "spec/requests/admin/documents_spec.rb",
+      "path": ".mcp.json",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 8,
-      "deletions": 0,
-      "symbols": [
-        "sign_in",
-        "stub_record_lookups",
-        "sample_fixture",
-        "upload",
-        "hostile_upload"
-      ]
+      "language": "json",
+      "insertions": 16,
+      "deletions": 0
     },
     {
-      "path": "spec/requests/admin/parties_spec.rb",
+      "path": "AGENTS.md",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 10,
-      "deletions": 0,
-      "symbols": [
-        "sign_in",
-        "stub_record_lookups"
-      ]
+      "language": "markdown",
+      "insertions": 1,
+      "deletions": 0
     },
     {
-      "path": "spec/requests/contracts_spec.rb",
+      "path": "CLAUDE.md",
       "kind": "modified",
-      "language": "ruby",
-      "insertions": 31,
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
+      "language": "markdown",
+      "insertions": 25,
+      "deletions": 0
     }
   ],
   "logicalChanges": [
     {
-      "id": "1ceab998-6ab9-4d37-9100-567c6777205d",
-      "sessionId": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
-      "recordedAt": "2026-09-28T15:59:51.598Z",
-      "entity": "Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.html.erb)",
+      "id": "31f58dca-257b-42df-b67e-cf78fb49b15a",
+      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
+      "recordedAt": "2026-10-02T22:26:44.812Z",
+      "entity": "Claude Code subagents",
       "files": [
-        "app/views/decidim/contracts_sk/contracts/show.html.erb"
+        ".claude/agents/architect.md",
+        ".claude/agents/reviewer.md",
+        ".claude/agents/rails.md",
+        ".claude/agents/tester.md",
+        ".claude/agents/integration.md",
+        ".claude/agents/retro.md"
       ],
-      "changeKind": "modified",
-      "reason": "civora-org/civora-platform#80: the live dt/dd pairs (and the metadata line's date/amount spans) render unconditionally except crz_url, so a sparse published record shows an empty subject dd and a dangling EUR dd; each optional pair is now guarded on value presence, mirroring the frozen-snapshot section and the PDF export which already drop blank rows; title/reference stay unconditional (NOT NULL)",
-      "expectedBehavior": "A published record carrying only title+reference renders no empty subject dd, no dangling EUR dd/span, no empty published-on/signed-on/effective-from dds; a full record renders unchanged; the metadata line under the title hides its date/amount spans when blank",
+      "changeKind": "added",
+      "reason": "Port .opencode/agents to Claude Code subagents so both harnesses share the same roles",
+      "expectedBehavior": "architect/reviewer run on opus with read-only tools; rails/tester/integration/retro on sonnet; bodies identical to the OpenCode agents",
       "risk": "low",
-      "alternatives": [],
-      "limitations": []
+      "alternatives": [
+        "Keep GLM-only OpenCode agents"
+      ],
+      "limitations": [
+        "The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md"
+      ]
     },
     {
-      "id": "58841712-37c6-4efb-8864-cf936ce24632",
-      "sessionId": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
-      "recordedAt": "2026-09-28T16:00:02.159Z",
-      "entity": "Admin form partials accessibility (contracts/parties/documents/amendments _form.html.erb)",
+      "id": "52236dd7-6925-41b6-9df3-c8d3c80bd018",
+      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
+      "recordedAt": "2026-10-02T22:26:44.912Z",
+      "entity": "Claude Code slash-command skills",
       "files": [
-        "app/views/decidim/contracts_sk/admin/contracts/_form.html.erb",
-        "app/views/decidim/contracts_sk/admin/parties/_form.html.erb",
-        "app/views/decidim/contracts_sk/admin/documents/_form.html.erb",
-        "app/views/decidim/contracts_sk/admin/amendments/_form.html.erb"
+        ".claude/skills/issue/SKILL.md",
+        ".claude/skills/feature/SKILL.md",
+        ".claude/skills/review/SKILL.md",
+        ".claude/skills/verify/SKILL.md",
+        ".claude/skills/retro/SKILL.md",
+        ".claude/skills/agent-review-github-status/SKILL.md",
+        ".claude/skills/agent-review-prepare-pr/SKILL.md",
+        ".claude/skills/agent-review-publish-pr/SKILL.md",
+        ".claude/skills/agent-review-update-review/SKILL.md"
       ],
-      "changeKind": "modified",
-      "reason": "civora-org/civora-platform#78: validation-error summaries render as a bare ul on 422 re-render and presence-validated inputs carry no required attribute; the ul gets role=\"alert\" tabindex=\"-1\" autofocus and required: true lands on contract title/reference, party name, amendment summary, document file — minimal engine-side a11y, matching the Decidim FormBuilder's supported field options",
-      "expectedBehavior": "On a 422 re-render the error summary ul carries role=\"alert\" tabindex=\"-1\" autofocus; the presence-validated inputs render the required HTML attribute; no field-level aria-invalid/aria-describedby beyond the item-3 hints",
+      "changeKind": "added",
+      "reason": "Port the 9 .opencode/commands to Claude Code skills invoked as /<name>",
+      "expectedBehavior": "/issue reads civora-org/civora-platform issues via gh; publish-pr, update-review and retro are user-invoked only (disable-model-invocation)",
       "risk": "low",
       "alternatives": [],
       "limitations": []
     },
     {
-      "id": "9f6b85e5-7639-4398-a8be-d2c70e33db82",
-      "sessionId": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
-      "recordedAt": "2026-09-28T16:00:12.997Z",
-      "entity": "Admin contract form amount input + IČO hint + currency select",
+      "id": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
+      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
+      "recordedAt": "2026-10-02T22:26:45.009Z",
+      "entity": "agent-review skill, MCP servers and journaling hook",
+      "files": [
+        ".claude/skills/agent-review",
+        ".mcp.json",
+        ".claude/settings.json"
+      ],
+      "changeKind": "added",
+      "reason": "Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers",
+      "expectedBehavior": "Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active",
+      "risk": "medium",
+      "alternatives": [],
+      "limitations": [
+        "Absolute machine paths in .mcp.json (same as opencode.jsonc)",
+        "Hook assumes agent-review is a sibling checkout",
+        "Skill is a symlink into ../agent-review"
+      ],
+      "evidence": "agent-review npm test: 70/70 pass incl. MCP listTools + hook mapping; stdio smoke call agent_review_status returned status inactive"
+    },
+    {
+      "id": "6c1abf82-4513-47c1-a072-4edf4f90e454",
+      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
+      "recordedAt": "2026-10-02T22:26:45.110Z",
+      "entity": "Claude Code permissions",
       "files": [
-        "app/views/decidim/contracts_sk/admin/contracts/_form.html.erb",
-        "app/views/decidim/contracts_sk/admin/parties/_form.html.erb",
-        "config/locales/en.yml",
-        "config/locales/sk.yml",
-        "spec/decidim/contracts_sk_locales_spec.rb"
+        ".claude/settings.json"
       ],
-      "changeKind": "modified",
-      "reason": "civora-org/civora-platform#79: the amount field accepts only dot-decimals (STRICT_AMOUNT_FORMAT on the form) but says nothing about it, the IČO format rule is invisible to editors, and currency is a free-text input over a one-entry allowlist; hints get explicit ids wired with aria-describedby (the pinned Decidim FormBuilder's help_text: option renders neither id nor aria), and the select copies the role/kind select pattern over the frozen vocabulary",
-      "expectedBehavior": "Amount input carries inputmode=\"decimal\" and aria-describedby pointing at a localized hint that only dot-decimals are accepted; IČO input carries a localized blank-or-8-digits hint wired the same way; currency renders as a select over Contract::SUPPORTED_CURRENCIES (selected preserved) instead of a free-text input; hints shipped in en.yml and sk.yml and registered in the locale key-surface contract",
+      "changeKind": "added",
+      "reason": "Mirror opencode.jsonc permissions",
+      "expectedBehavior": "git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied",
       "risk": "low",
       "alternatives": [],
-      "limitations": []
+      "limitations": [
+        "edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates"
+      ]
     },
     {
-      "id": "51ae51c3-9fe4-47a9-b704-ac08e36decbc",
-      "sessionId": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
-      "recordedAt": "2026-09-28T16:00:26.858Z",
-      "entity": "Localized money/date rendering + CRZ handoff PDF timestamp zone label",
+      "id": "e272f979-badc-4ead-b674-6708421f71f1",
+      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
+      "recordedAt": "2026-10-02T22:26:45.213Z",
+      "entity": "CLAUDE.md and AGENTS.md pointer",
       "files": [
-        "app/helpers/decidim/contracts_sk/application_helper.rb",
-        "app/views/decidim/contracts_sk/contracts/show.html.erb",
-        "app/views/decidim/contracts_sk/contracts/index.html.erb",
-        "app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb",
-        "app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb",
-        "app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb",
-        "app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb",
-        "config/locales/en.yml",
-        "config/locales/sk.yml"
+        "CLAUDE.md",
+        "AGENTS.md"
       ],
-      "changeKind": "modified",
-      "reason": "civora-org/civora-platform#81: \"1250.5 EUR\" renders locale-blind while the audience is Slovak, every date renders naive to_fs(:db), and the PDF footer stamps a naive server-local time with no zone; a small helper in the base ApplicationHelper (number_with_precision with explicit sk separators; I18n.l with an explicit engine-shipped format string — the harness has no rails-i18n sk data, so named formats/day names would not resolve) replaces every to_fs(:db) date render and both amount renders, and the PDF footer converts to UTC explicitly",
-      "expectedBehavior": "Amounts render locale-aware: sk \"1 250,50 EUR\" (regular-space grouping, comma decimals — documented decision), en keeps the current fixed-point \"1250.5 EUR\"; dates render through a thin format_date helper backed by engine-shipped date_formats.default keys (sk \"%d. %m. %Y\", en \"%Y-%m-%d\" — no host-app locale data dependency); the PDF footer timestamp renders Time.current converted to UTC with an explicit \" UTC\" suffix; helper is PORO-safe (included by the PDF class)",
-      "risk": "medium",
+      "changeKind": "added",
+      "reason": "Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router",
+      "expectedBehavior": "CLAUDE.md imports @AGENTS.md; AGENTS.md lists the Claude Code mirror to keep in sync",
+      "risk": "low",
       "alternatives": [],
       "limitations": []
     }
@@ -411,67 +307,37 @@
   "tests": [
     {
       "command": "bundle exec rspec",
-      "startedAt": "2026-09-28T15:59:13.070Z",
-      "finishedAt": "2026-09-28T15:59:19.400Z",
-      "durationMs": 6330,
+      "startedAt": "2026-10-02T22:26:52.256Z",
+      "finishedAt": "2026-10-02T22:26:55.393Z",
+      "durationMs": 3133,
       "exitCode": 0,
       "status": "passed",
       "stdoutSummary": "Run options: exclude {:db=>true}\n\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_redaction_confirmation_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds only the redaction_confirmed_at column, as a plain nullable datetime\n    attaches no default and no backfill (a fabricated stamp would defeat the gate)\n    adds no index (the stamp is read per-record, never queried as a set)\n\ndb/migrate/*_add_review_decision_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the review_reason and reviewed_at columns\n    adds review_reason as a plain nullable string capped at 1000 characters\n    adds reviewed_at as a plain nullable datetime\n    attaches no default and no backfill (a fabricated judgment would defeat the gate)\n    adds no index (the decision is read per-record, never queried as a set)\n\ndb/migrate/*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  index\n    uniquely indexes (organization, source_id) under the explicit unique name\n    keeps the index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_create_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes version a NOT NULL integer\n    makes summary a NOT NULL string\n  indexes\n    uniquely indexes (contract_id, version) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_audit_events.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant reference NOT NULL with a real FK to the organizations table\n    makes the actor reference NOT NULL with a real FK to the users table\n    makes the target a NOT NULL polymorphic reference\n    makes action a NOT NULL string\n  indexes\n    indexes every reference and created_at under explicit names\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contract_links.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes the target a NOT NULL polymorphic reference with no index of its own\n  indexes\n    uniquely indexes (contract_id, target_type, target_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant and author references NOT NULL\n    makes title and reference NOT NULL strings\n    pins state as NOT NULL defaulting to draft\n    pins source as NOT NULL defaulting to editorial\n    keeps the provenance columns nullable\n  indexes\n    indexes the organization reference under an explicit name\n    indexes the author reference\n    uniquely indexes (organization, reference) under an explicit name\n    indexes (organization, state) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_documents.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL with a real FK to the contracts table\n    makes title NOT NULL\n    pins kind as NOT NULL defaulting to contract\n    keeps the file metadata columns nullable\n  indexes\n    indexes the contract reference under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_parties.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes role and name NOT NULL strings\n    keeps ico as a nullable string with the 8-character limit\n    keeps address nullable\n  indexes\n    compositely indexes (contract_id, role) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\nDecidim::ContractsSk::Admin::AmendmentForm\n  accepts a complete amendment form\n  rejects a blank summary\n  rejects a missing summary\n  caps the summary at 255 characters\n\nDecidim::ContractsSk::Admin::AuditEventsController\n  inherits from the engine's admin base controller\n  implements exactly the index action (read-only viewer)\n  does not sit on the engine's public base controller chain\n  pins the audit action vocabulary actually written by the commands\n  derives the six lifecycle-action keys from the transition table, never hand-enumerated\n\nDecidim::ContractsSk::Admin::ContractForm\n  accepts dotted decimal strings\n  accepts proper numerics without the string guard (spec/API compatibility)\n  accepts the decimal(12,2) ceiling itself\n  accepts a nil amount (the value may be unknown while drafting)\n  rejects non-numeric strings instead of letting the cast zero them\n  rejects comma decimals (the Slovak '12,50' habit, caught deliberately)\n  rejects scientific notation (the format guard stays strict)\n  rejects negative amounts\n  rejects amounts beyond the decimal(12,2) column's ceiling\n  rejects over-ceiling strings too (raw input, same cap)\n\nDecidim::ContractsSk::Admin::ContractsController\n  inherits from the engine's admin base controller\n  implements exactly the CRUD + transition + CRZ-handoff + import + redaction actions (no show, no destroy)\n  does not sit on the engine's public base controller chain\n\nDecidim::ContractsSk::Admin::DocumentForm\n  accepts a complete form\n  defaults the kind to the model's column default\n  accepts every kind of the form's editor vocabulary\n  narrows the mod",
       "stderrSummary": "",
       "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
       "commandTruncated": false
-    },
-    {
-      "command": "bundle exec rspec",
-      "startedAt": "2026-09-28T16:24:19.457Z",
-      "finishedAt": "2026-09-28T16:24:28.126Z",
-      "durationMs": 8669,
-      "exitCode": 0,
-      "status": "passed",
-      "stdoutSummary": "Run options: exclude {:db=>true}\n\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_redaction_confirmation_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds only the redaction_confirmed_at column, as a plain nullable datetime\n    attaches no default and no backfill (a fabricated stamp would defeat the gate)\n    adds no index (the stamp is read per-record, never queried as a set)\n\ndb/migrate/*_add_review_decision_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the review_reason and reviewed_at columns\n    adds review_reason as a plain nullable string capped at 1000 characters\n    adds reviewed_at as a plain nullable datetime\n    attaches no default and no backfill (a fabricated judgment would defeat the gate)\n    adds no index (the decision is read per-record, never queried as a set)\n\ndb/migrate/*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  index\n    uniquely indexes (organization, source_id) under the explicit unique name\n    keeps the index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_create_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes version a NOT NULL integer\n    makes summary a NOT NULL string\n  indexes\n    uniquely indexes (contract_id, version) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_audit_events.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant reference NOT NULL with a real FK to the organizations table\n    makes the actor reference NOT NULL with a real FK to the users table\n    makes the target a NOT NULL polymorphic reference\n    makes action a NOT NULL string\n  indexes\n    indexes every reference and created_at under explicit names\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contract_links.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes the target a NOT NULL polymorphic reference with no index of its own\n  indexes\n    uniquely indexes (contract_id, target_type, target_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant and author references NOT NULL\n    makes title and reference NOT NULL strings\n    pins state as NOT NULL defaulting to draft\n    pins source as NOT NULL defaulting to editorial\n    keeps the provenance columns nullable\n  indexes\n    indexes the organization reference under an explicit name\n    indexes the author reference\n    uniquely indexes (organization, reference) under an explicit name\n    indexes (organization, state) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_documents.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL with a real FK to the contracts table\n    makes title NOT NULL\n    pins kind as NOT NULL defaulting to contract\n    keeps the file metadata columns nullable\n  indexes\n    indexes the contract reference under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_parties.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes role and name NOT NULL strings\n    keeps ico as a nullable string with the 8-character limit\n    keeps address nullable\n  indexes\n    compositely indexes (contract_id, role) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\nDecidim::ContractsSk::Admin::AmendmentForm\n  accepts a complete amendment form\n  rejects a blank summary\n  rejects a missing summary\n  caps the summary at 255 characters\n\nDecidim::ContractsSk::Admin::AuditEventsController\n  inherits from the engine's admin base controller\n  implements exactly the index action (read-only viewer)\n  does not sit on the engine's public base controller chain\n  pins the audit action vocabulary actually written by the commands\n  derives the six lifecycle-action keys from the transition table, never hand-enumerated\n\nDecidim::ContractsSk::Admin::ContractForm\n  accepts dotted decimal strings\n  accepts proper numerics without the string guard (spec/API compatibility)\n  accepts the decimal(12,2) ceiling itself\n  accepts a nil amount (the value may be unknown while drafting)\n  rejects non-numeric strings instead of letting the cast zero them\n  rejects comma decimals (the Slovak '12,50' habit, caught deliberately)\n  rejects scientific notation (the format guard stays strict)\n  rejects negative amounts\n  rejects amounts beyond the decimal(12,2) column's ceiling\n  rejects over-ceiling strings too (raw input, same cap)\n\nDecidim::ContractsSk::Admin::ContractsController\n  inherits from the engine's admin base controller\n  implements exactly the CRUD + transition + CRZ-handoff + import + redaction actions (no show, no destroy)\n  does not sit on the engine's public base controller chain\n\nDecidim::ContractsSk::Admin::DocumentForm\n  accepts a complete form\n  defaults the kind to the model's column default\n  accepts every kind of the form's editor vocabulary\n  narrows the mod",
-      "stderrSummary": "",
-      "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
-      "commandTruncated": false
-    },
-    {
-      "command": "CONTRACTS_SK_DB=1 bundle exec rspec",
-      "startedAt": "2026-09-28T16:24:32.663Z",
-      "finishedAt": "2026-09-28T16:24:32.672Z",
-      "durationMs": 8,
-      "exitCode": null,
-      "status": "error",
-      "stdoutSummary": "",
-      "stderrSummary": "Executable not found in $PATH: \"CONTRACTS_SK_DB=1\"",
-      "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk"
-    },
-    {
-      "command": "env CONTRACTS_SK_DB=1 bundle exec rspec",
-      "startedAt": "2026-09-28T16:24:40.755Z",
-      "finishedAt": "2026-09-28T16:25:31.244Z",
-      "durationMs": 50489,
-      "exitCode": 0,
-      "status": "passed",
-      "stdoutSummary": "\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n  runnable migration\n==  CreateActiveStorageTables: migrating ======================================\n-- create_table(:active_storage_blobs, {:id=>:primary_key})\n   -> 0.0011s\n-- create_table(:active_storage_attachments, {:id=>:primary_key})\n   -> 0.0009s\n-- create_table(:active_storage_variant_records, {:id=>:primary_key})\n   -> 0.0004s\n==  CreateActiveStorageTables: migrated (0.0026s) =============================\n\n==  CreateDecidimContractsSkContracts: migrating ==============================\n-- create_table(:decidim_contracts_sk_contracts)\n   -> 0.0008s\n-- add_index(:decidim_contracts_sk_contracts, [:decidim_organization_id, :reference], {:unique=>true, :name=>\"idx_contracts_sk_contracts_on_organization_id_and_reference\"})\n   -> 0.0002s\n-- add_index(:decidim_contracts_sk_contracts, [:decidim_organization_id, :state], {:name=>\"idx_contracts_sk_contracts_on_organization_id_and_state\"})\n   -> 0.0002s\n==  CreateDecidimContractsSkContracts: migrated (0.0013s) =====================\n\n==  CreateDecidimContractsSkAmendments: migrating =============================\n-- create_table(:decidim_contracts_sk_amendments)\n   -> 0.0004s\n-- add_index(:decidim_contracts_sk_amendments, [:contract_id, :version], {:unique=>true, :name=>\"idx_contracts_sk_amendments_on_contract_id_and_version\"})\n   -> 0.0002s\n==  CreateDecidimContractsSkAmendments: migrated (0.0006s) ====================\n\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: migrating ============\n-- add_column(:decidim_contracts_sk_amendments, :state, :string, {:null=>false, :default=>\"draft\"})\n   -> 0.0006s\n-- add_column(:decidim_contracts_sk_amendments, :published_at, :datetime)\n   -> 0.0005s\n-- add_reference(:decidim_contracts_sk_amendments, :decidim_organization, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_organizations}, :index=>{:name=>\"idx_contracts_sk_amendments_on_organization_id\"}})\n   -> 0.0086s\n-- add_reference(:decidim_contracts_sk_amendments, :decidim_author, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_users}, :index=>true})\n   -> 0.0098s\n-- add_column(:decidim_contracts_sk_amendments, :content_snapshot, :json)\n   -> 0.0004s\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: migrated (0.0202s) ===\n\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: reverting ============\n-- remove_column(:decidim_contracts_sk_amendments, :content_snapshot, :json)\n   -> 0.0116s\n-- remove_reference(:decidim_contracts_sk_amendments, :decidim_author, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_users}, :index=>true})\n   -> 0.0166s\n-- remove_reference(:decidim_contracts_sk_amendments, :decidim_organization, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_organizations}, :index=>{:name=>\"idx_contracts_sk_amendments_on_organization_id\"}})\n   -> 0.0124s\n-- remove_column(:decidim_contracts_sk_amendments, :published_at, :datetime)\n   -> 0.0050s\n-- remove_column(:decidim_contracts_sk_amendments, :state, :string, {:null=>false, :default=>\"draft\"})\n   -> 0.0044s\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: reverted (0.0552s) ===\n\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: migrating ============\n-- add_column(:decidim_contracts_sk_amendments, :state, :string, {:null=>false, :default=>\"draft\"})\n   -> 0.0003s\n-- add_column(:decidim_contracts_sk_amendments, :published_at, :datetime)\n   -> 0.0002s\n-- add_reference(:decidim_contracts_sk_amendments, :decidim_organization, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_organizations}, :index=>{:name=>\"idx_contracts_sk_amendments_on_organization_id\"}})\n   -> 0.0068s\n-- add_reference(:decidim_contracts_sk_amendments, :decidim_author, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_users}, :index=>true})\n   -> 0.0092s\n-- add_column(:decidim_contracts_sk_amendments, :content_snapshot, :json)\n   -> 0.0006s\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: migrated (0.0175s) ===\n\n    adds the columns, defaults pre-lifecycle rows to draft, and reverses cleanly\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n  runnable migration\n==  CreateActiveStorageTables: migrating ======================================\n-- create_table(:active_storage_blobs, {:id=>:primary_key})\n   -> 0.0005s\n-- create_table(:active_storage_attachments, {:id=>:primary_key})\n   -> 0.0006s\n-- create_table(:active_storage_variant_records, {:id=>:primary_key})\n   -> 0.0004s\n==  CreateActiveStorageTables: migrated (0.0017s) =============================\n\n==  CreateDecidimContractsSkContracts: migrating ==============================\n-- create_table(:decidim_contracts_sk_contracts)\n   -> 0.0011s\n-- add_index(:decidim_contracts_sk_contracts, [:decidim_organization_id, :reference], {:unique=>true, :name=>\"idx_contracts_sk_contracts_on_organization_id_and_reference\"})\n   -> 0.0002s\n-- add_index(:decidim_contracts_sk_contracts, [:decidim_organization_id, :state], {:name=>\"idx_contracts_sk_contracts_on_organization_id_and_state\"})\n   -> 0.0002s\n==  CreateDecidimContractsSkContracts: migrated (0.0015s) =====================\n\n==  AddContentFieldsToDecidimContractsSkContracts: migrating ==================\n-- add_column(:decidim_contracts_sk_contracts, :subject_matter, :text)\n   -> 0.0004s\n-- add_column(:decidim_contracts_sk_contracts, :amount, :decimal, {:precision=>12, :scale=>2})\n   -> 0.0002s\n-- add_column(:decidim_contracts_sk_contracts, :currency, :string, {:limit=>3, :null=>false, :default=>\"EUR\"})\n   -> 0.0003s\n-- add_column(:decidim_contracts_sk_contracts, :signed_on, :date)\n   -> 0.0002s\n-- add_column(:decidim_contracts_sk_contracts, :effective_from, :date)\n   -> 0.0002s\n-- add_column(:decidim_contracts_sk_contracts, :published_at, :datetime)\n   -> 0.0002s\n-- add_column(:decidim_contracts_sk_contracts, :crz_url, :string)\n   -> 0.0004s\n-- execute(\"UPDATE decidim_contracts_sk_contracts\\nSET published_at = updated_at\\nWHERE state = 'published' AND published_at IS NULL\\n\")\n   -> 0.0001s\n==  AddContentFieldsToDecidimContractsSkContracts: migrated (0.0022s) =========\n\n==  AddContentFieldsToDecidimContractsSkContracts: reverting ==================\n-- remove_column(:decidim_contracts_sk_contracts, :crz_url, :string)\n   -> 0.0135s\n-- remove_column(:decidim_contracts_sk_contracts, :published_at, :datetime)\n   -> 0.0119s\n-- remove_column(:decidim_contracts_sk_contracts, :effective_from, :date)\n   -> 0.0107s\n-- remove_column(:decidim_contracts_sk_contracts, :signed_on, :date)\n   -> 0.0129s\n-- remove_column(:decidim_contracts_sk_contracts, :currency, :string, {:limit=>3, :null=>false, :default=>\"EUR\"})\n   -> 0.0218s\n-- remove_column(:decidim_contracts_sk_contracts, :amount, :decimal, {:precision=>12, :scale=>2})\n   -> 0.0114s\n-- remove_column(:decidim_contracts_sk_contracts, :subject_matter, :text)\n   -> 0.0124s\n==  AddContentFieldsToDecidimContractsSkContracts: reverted (0.0957s) =========\n\n==  AddContentFieldsToDecidimContractsSkContracts: migrating ==================\n-- add_column(:decidim_contracts_sk_contracts, :subject_matter, :text)\n   -> 0.0005s\n-- add_column(:decidim_contracts_sk_contracts, :amount, :decimal, {:precision=>12, :scale=>2})\n   -> 0.0004s\n-- add_column(:decidim_contracts_sk_contracts, :currency, :string, {:limit=>3, :null=>false, :default=>\"EUR\"})\n   -> 0.0004s\n-- add_column(:decidim_contracts_sk_contracts, :signed_on, :date)\n   -> 0.0005s\n-- add_column(:decidim_contracts_sk_contracts, :effective_from, :date)\n   -> 0.0004s\n-- add_column(:decidim_contracts_sk_contracts, :published_at, :datetime)\n   -> 0.0003s\n-- add_column(:decidim_contracts_sk_contracts, :crz_url, :string)\n   -> 0.0002s\n-- execute(\"UPDATE decidim_contracts_sk_contracts\\nSET published_at = updated_at\\nWHERE state = 'published' AND published_at IS NULL\\n\")\n   -> 0.0002s\n==  AddContentFieldsToDecidimContractsSkContracts: migrated (0.0032s) =========\n\n    adds the columns, backfills published rows, and reverses cleanly\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  runnable migration\n==  CreateActiveStorageTables: migrating ======================================\n-- create_table(:active_storage_blobs, {:id=>:primary_key})\n   -> 0.0006s\n-- create_table(:active_storage_attachments, {:id=>:primary_key})\n   -> 0.0006s\n-- create_table(:active_storage_variant_records, {:id=>:primary_key})\n   -> 0.0004s\n==  CreateActiveStorageTables: migrated (0.0016s) =============================\n\n==  CreateDecidimContractsSkContracts: migrating ==============================\n-- create_table(:decidim_contracts_sk_contracts)\n   -> 0.0006s\n-- add_index(:decidim_contracts_",
-      "stderrSummary": "",
-      "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
-      "commandTruncated": false
     }
   ],
   "risks": [
-    "Working tree was dirty at session start (17 entries) — pre-existing changes may be mixed into the diff.",
-    "1 test run(s) did not pass (exit codes: signal)."
+    "Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.",
+    "Large diff: 4919 insertions across 26 files."
   ],
   "limitations": [
     "Snapshots cover only files that were changed at checkpoint time.",
     "Symbol extraction is regex-based, not AST-based.",
-    "Only observed facts are recorded — private model reasoning is not captured."
+    "Only observed facts are recorded — private model reasoning is not captured.",
+    "The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md",
+    "Absolute machine paths in .mcp.json (same as opencode.jsonc)",
+    "Hook assumes agent-review is a sibling checkout",
+    "Skill is a symlink into ../agent-review",
+    "edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates"
   ],
   "agentMetadata": {
-    "toolCalls": 110,
-    "commands": 40,
-    "checkpoints": 3,
-    "tests": 4,
-    "events": 3791
+    "toolCalls": 0,
+    "commands": 0,
+    "checkpoints": 1,
+    "tests": 1,
+    "events": 3816
   },
-  "generatedAt": "2026-09-28T16:25:37.850Z"
+  "generatedAt": "2026-10-02T22:28:12.683Z"
 }
diff --git a/.agent-review/github/inline-comments.preview.json b/.agent-review/github/inline-comments.preview.json
index fe4f652..7824628 100644
--- a/.agent-review/github/inline-comments.preview.json
+++ b/.agent-review/github/inline-comments.preview.json
@@ -1,20 +1,33 @@
 {
   "schemaVersion": "agent-review-inline-comments/v1",
-  "branch": "m03-92-audit-trail-viewer",
+  "branch": "chore/claude-code-config",
   "baseBranch": "main",
   "comments": [
     {
       "id": "comment_001",
-      "logicalChangeId": "4fa1dda2-92d7-4b00-b687-9134fa8a2f7c",
-      "path": "config/routes.rb",
-      "line": 82,
+      "logicalChangeId": "6c1abf82-4513-47c1-a072-4edf4f90e454",
+      "path": ".claude/settings.json",
+      "line": 1,
       "side": "RIGHT",
-      "body": "### Agent context\n\n**What changed:** added — Audit-trail viewer (civora-org/civora-platform#92)\n\n**Why:** The append-only audit trail has no read surface; roles doc promises \"view audit trail\" to every engine role. Gate-1: single GET /admin/audit_events index, contract filter via tenant-scoped contract_id query param, :read :audit_event permission for any engine role, Kaminari 25/page, dangling-target-safe rendering, #90 reason display on live contracts.\n\n**Expected behavior:** Read-only org-scoped audit index (newest first, paged), contract-filtered via tenant-scoped contract_id param, any engine role admitted, dangling targets render gracefully, #90 review reason displayed on live decision-state contracts.\n\n**Evidence:** `bundle exec rspec` executed (recorded test run).\n\n**Risk:** Low\n\n<!-- agent-review:session=54a881af-6d32-4e7c-a6b6-5c9c14c22113;change=4fa1dda2-92d7-4b00-b687-9134fa8a2f7c;version=1 -->",
+      "body": "### Agent context\n\n**What changed:** added — Claude Code permissions\n\n**Why:** Mirror opencode.jsonc permissions\n\n**Expected behavior:** git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied\n\n**Evidence:** `bundle exec rspec` executed (recorded test run).\n\n**Risk:** Low — edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates\n\n<!-- agent-review:session=d89b86e3-d25a-4b4e-aa50-1bd7560e389d;change=6c1abf82-4513-47c1-a072-4edf4f90e454;version=1 -->",
       "risk": "low",
       "evidenceRefs": [
         "test_001"
       ],
       "status": "preview"
+    },
+    {
+      "id": "comment_002",
+      "logicalChangeId": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
+      "path": ".claude/skills/agent-review",
+      "line": 1,
+      "side": "RIGHT",
+      "body": "### Agent context\n\n**What changed:** added — agent-review skill, MCP servers and journaling hook\n\n**Why:** Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers\n\n**Expected behavior:** Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active\n\n**Evidence:** `agent-review npm test: 70/70 pass incl. MCP listTools + hook mapping; stdio smoke call agent_review_status returned status inactive` executed.\n\n**Risk:** Medium — Absolute machine paths in .mcp.json (same as opencode.jsonc); Hook assumes agent-review is a sibling checkout; Skill is a symlink into ../agent-review\n\n<!-- agent-review:session=d89b86e3-d25a-4b4e-aa50-1bd7560e389d;change=ac3edcfd-5a8f-4604-aae8-ca1d3c290a57;version=1 -->",
+      "risk": "medium",
+      "evidenceRefs": [
+        "test_001"
+      ],
+      "status": "preview"
     }
   ]
 }
diff --git a/.agent-review/github/pr-body.md b/.agent-review/github/pr-body.md
index d8a5596..bc6bef9 100644
--- a/.agent-review/github/pr-body.md
+++ b/.agent-review/github/pr-body.md
@@ -1,26 +1,33 @@
 # Agent Review
 
 ## Summary
-- 1 logical changes / 23 files changed
-- Tests: 1 passed (2 failed/error)
-- Risks: 1 low
+- 5 logical changes / 74 files changed
+- Tests: 1 passed
+- Risks: 1 medium, 4 low
 
 ## What changed
-1. **Audit-trail viewer (civora-org/civora-platform#92)** — The append-only audit trail has no read surface; roles doc promises "view audit trail" to every engine role. Gate-1: single GET /admin/audit_events index, contract filter via tenant-scoped contract_id query param, :read :audit_event permission for any engine role, Kaminari 25/page, dangling-target-safe rendering, #90 reason display on live contracts.
+1. **Claude Code subagents** — Port .opencode/agents to Claude Code subagents so both harnesses share the same roles
+2. **Claude Code slash-command skills** — Port the 9 .opencode/commands to Claude Code skills invoked as /<name>
+3. **agent-review skill, MCP servers and journaling hook** — Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers
+4. **Claude Code permissions** — Mirror opencode.jsonc permissions
+5. **CLAUDE.md and AGENTS.md pointer** — Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router
 
 ## Evidence
-- `bundle exec rspec`: FAILED (exit 1)
-- `env CONTRACTS_SK_DB=1 bundle exec rspec`: FAILED (exit 1)
 - `bundle exec rspec`: passed
 
 ## Risks and limitations
-- Working tree was dirty at session start (17 entries) — pre-existing changes may be mixed into the diff.
-- 2 test run(s) did not pass (exit codes: 1, 1).
+- Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.
+- Large diff: 10373 insertions across 74 files.
 - Limitation: Snapshots cover only files that were changed at checkpoint time.
 - Limitation: Symbol extraction is regex-based, not AST-based.
 - Limitation: Only observed facts are recorded — private model reasoning is not captured.
+- Limitation: The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md
+- Limitation: Absolute machine paths in .mcp.json (same as opencode.jsonc)
+- Limitation: Hook assumes agent-review is a sibling checkout
+- Limitation: Skill is a symlink into ../agent-review
+- Limitation: edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates
 
 ## Review guidance
-Start with the inline comments marked `Agent context` (1 comment on the current diff).
+Start with the inline comments marked `Agent context` (2 comments on the current diff).
 
 _This summary and the inline comments are review CONTEXT, not guarantees of correctness._
diff --git a/.agent-review/github/pr-preview.json b/.agent-review/github/pr-preview.json
index 36a8325..3142db8 100644
--- a/.agent-review/github/pr-preview.json
+++ b/.agent-review/github/pr-preview.json
@@ -2,31 +2,44 @@
   "schemaVersion": "agent-review-pr-preview/v1",
   "repository": null,
   "baseBranch": "main",
-  "headBranch": "m03-92-audit-trail-viewer",
-  "title": "Admin audit-trail viewer (civora-org/civora-platform#92): read-only org-level + contract-filtered index",
+  "headBranch": "chore/claude-code-config",
+  "title": "Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code",
   "draft": true,
   "summary": {
-    "logicalChanges": 1,
-    "filesChanged": 23,
+    "logicalChanges": 5,
+    "filesChanged": 74,
     "testsPassed": 1,
     "risks": [
-      "Working tree was dirty at session start (17 entries) — pre-existing changes may be mixed into the diff.",
-      "2 test run(s) did not pass (exit codes: 1, 1)."
+      "Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.",
+      "Large diff: 10373 insertions across 74 files."
     ]
   },
   "inlineComments": [
     {
       "id": "comment_001",
-      "logicalChangeId": "4fa1dda2-92d7-4b00-b687-9134fa8a2f7c",
-      "path": "config/routes.rb",
-      "line": 82,
+      "logicalChangeId": "6c1abf82-4513-47c1-a072-4edf4f90e454",
+      "path": ".claude/settings.json",
+      "line": 1,
       "side": "RIGHT",
-      "body": "### Agent context\n\n**What changed:** added — Audit-trail viewer (civora-org/civora-platform#92)\n\n**Why:** The append-only audit trail has no read surface; roles doc promises \"view audit trail\" to every engine role. Gate-1: single GET /admin/audit_events index, contract filter via tenant-scoped contract_id query param, :read :audit_event permission for any engine role, Kaminari 25/page, dangling-target-safe rendering, #90 reason display on live contracts.\n\n**Expected behavior:** Read-only org-scoped audit index (newest first, paged), contract-filtered via tenant-scoped contract_id param, any engine role admitted, dangling targets render gracefully, #90 review reason displayed on live decision-state contracts.\n\n**Evidence:** `bundle exec rspec` executed (recorded test run).\n\n**Risk:** Low\n\n<!-- agent-review:session=54a881af-6d32-4e7c-a6b6-5c9c14c22113;change=4fa1dda2-92d7-4b00-b687-9134fa8a2f7c;version=1 -->",
+      "body": "### Agent context\n\n**What changed:** added — Claude Code permissions\n\n**Why:** Mirror opencode.jsonc permissions\n\n**Expected behavior:** git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied\n\n**Evidence:** `bundle exec rspec` executed (recorded test run).\n\n**Risk:** Low — edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates\n\n<!-- agent-review:session=d89b86e3-d25a-4b4e-aa50-1bd7560e389d;change=6c1abf82-4513-47c1-a072-4edf4f90e454;version=1 -->",
       "risk": "low",
       "evidenceRefs": [
         "test_001"
       ],
       "status": "preview"
+    },
+    {
+      "id": "comment_002",
+      "logicalChangeId": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
+      "path": ".claude/skills/agent-review",
+      "line": 1,
+      "side": "RIGHT",
+      "body": "### Agent context\n\n**What changed:** added — agent-review skill, MCP servers and journaling hook\n\n**Why:** Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers\n\n**Expected behavior:** Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active\n\n**Evidence:** `agent-review npm test: 70/70 pass incl. MCP listTools + hook mapping; stdio smoke call agent_review_status returned status inactive` executed.\n\n**Risk:** Medium — Absolute machine paths in .mcp.json (same as opencode.jsonc); Hook assumes agent-review is a sibling checkout; Skill is a symlink into ../agent-review\n\n<!-- agent-review:session=d89b86e3-d25a-4b4e-aa50-1bd7560e389d;change=ac3edcfd-5a8f-4604-aae8-ca1d3c290a57;version=1 -->",
+      "risk": "medium",
+      "evidenceRefs": [
+        "test_001"
+      ],
+      "status": "preview"
     }
   ],
   "fileLevelNotes": [],
diff --git a/.agent-review/github/publish-plan.md b/.agent-review/github/publish-plan.md
index 34b0c19..3b03510 100644
--- a/.agent-review/github/publish-plan.md
+++ b/.agent-review/github/publish-plan.md
@@ -1,9 +1,10 @@
 # Publish plan
 
-- Draft PR: `m03-92-audit-trail-viewer` → `main`
-- Title: Admin audit-trail viewer (civora-org/civora-platform#92): read-only org-level + contract-filtered index
-- Inline comments: 1
-  - `config/routes.rb`:82
+- Draft PR: `chore/claude-code-config` → `main`
+- Title: Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code
+- Inline comments: 2
+  - `.claude/settings.json`:1
+  - `.claude/skills/agent-review`:1
 - Skipped: 0
 
 Nothing has been pushed or published. Publishing requires explicit user confirmation.
diff --git a/.agent-review/review.md b/.agent-review/review.md
index 7e84630..9f65da3 100644
--- a/.agent-review/review.md
+++ b/.agent-review/review.md
@@ -1,38 +1,47 @@
 # Agent Review
 
 ## Task
-Pilot demo UX polish: guard blank live fields on public detail (#80), admin form a11y (#78), input hints + currency select (#79), localized money/date rendering + PDF timestamp UTC label (#81)
+Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code
 
 ## Session
-- Session ID: 6b2892c2-9985-4b7a-9031-fc723f7302c9
-- Branch: polish/pilot-demo-ux
-- Started: 2026-09-28T15:48:32.593Z
-- Finished: 2026-09-28T16:25:37.886Z
+- Session ID: d89b86e3-d25a-4b4e-aa50-1bd7560e389d
+- Branch: chore/claude-code-config
+- Started: 2026-10-02T22:26:31.118Z
+- Finished: 2026-10-02T22:28:12.492Z
 
 ## Summary
-Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.html.erb): civora-org/civora-platform#80: the live dt/dd pairs (and the metadata line's date/amount spans) render unconditionally except crz_url, so a sparse published record shows an empty subject dd and a dangling EUR dd; each optional pair is now guarded on value presence, mirroring the frozen-snapshot section and the PDF export which already drop blank rows; title/reference stay unconditional (NOT NULL) Admin form partials accessibility (contracts/parties/documents/amendments _form.html.erb): civora-org/civora-platform#78: validation-error summaries render as a bare ul on 422 re-render and presence-validated inputs carry no required attribute; the ul gets role="alert" tabindex="-1" autofocus and required: true lands on contract title/reference, party name, amendment summary, document file — minimal engine-side a11y, matching the Decidim FormBuilder's supported field options Admin contract form amount input + IČO hint + currency select: civora-org/civora-platform#79: the amount field accepts only dot-decimals (STRICT_AMOUNT_FORMAT on the form) but says nothing about it, the IČO format rule is invisible to editors, and currency is a free-text input over a one-entry allowlist; hints get explicit ids wired with aria-describedby (the pinned Decidim FormBuilder's help_text: option renders neither id nor aria), and the select copies the role/kind select pattern over the frozen vocabulary Localized money/date rendering + CRZ handoff PDF timestamp zone label: civora-org/civora-platform#81: "1250.5 EUR" renders locale-blind while the audience is Slovak, every date renders naive to_fs(:db), and the PDF footer stamps a naive server-local time with no zone; a small helper in the base ApplicationHelper (number_with_precision with explicit sk separators; I18n.l with an explicit engine-shipped format string — the harness has no rails-i18n sk data, so named formats/day names would not resolve) replaces every to_fs(:db) date render and both amount renders, and the PDF footer converts to UTC explicitly
+Claude Code subagents: Port .opencode/agents to Claude Code subagents so both harnesses share the same roles Claude Code slash-command skills: Port the 9 .opencode/commands to Claude Code skills invoked as /<name> agent-review skill, MCP servers and journaling hook: Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers Claude Code permissions: Mirror opencode.jsonc permissions CLAUDE.md and AGENTS.md pointer: Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router
 
 ## Logical Changes
 
-### 1. Localized money/date rendering + CRZ handoff PDF timestamp zone label
-- What changed: modified in `app/helpers/decidim/contracts_sk/application_helper.rb`, `app/views/decidim/contracts_sk/contracts/show.html.erb`, `app/views/decidim/contracts_sk/contracts/index.html.erb`, `app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb`, `app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb`, `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb`, `app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb`, `config/locales/en.yml`, `config/locales/sk.yml`
-- Why: civora-org/civora-platform#81: "1250.5 EUR" renders locale-blind while the audience is Slovak, every date renders naive to_fs(:db), and the PDF footer stamps a naive server-local time with no zone; a small helper in the base ApplicationHelper (number_with_precision with explicit sk separators; I18n.l with an explicit engine-shipped format string — the harness has no rails-i18n sk data, so named formats/day names would not resolve) replaces every to_fs(:db) date render and both amount renders, and the PDF footer converts to UTC explicitly
-- Expected behavior: Amounts render locale-aware: sk "1 250,50 EUR" (regular-space grouping, comma decimals — documented decision), en keeps the current fixed-point "1250.5 EUR"; dates render through a thin format_date helper backed by engine-shipped date_formats.default keys (sk "%d. %m. %Y", en "%Y-%m-%d" — no host-app locale data dependency); the PDF footer timestamp renders Time.current converted to UTC with an explicit " UTC" suffix; helper is PORO-safe (included by the PDF class)
+### 1. agent-review skill, MCP servers and journaling hook
+- What changed: added in `.claude/skills/agent-review`, `.mcp.json`, `.claude/settings.json`
+- Why: Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers
+- Expected behavior: Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active
 - Risk: medium
-### 2. Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.html.erb)
-- What changed: modified in `app/views/decidim/contracts_sk/contracts/show.html.erb`
-- Why: civora-org/civora-platform#80: the live dt/dd pairs (and the metadata line's date/amount spans) render unconditionally except crz_url, so a sparse published record shows an empty subject dd and a dangling EUR dd; each optional pair is now guarded on value presence, mirroring the frozen-snapshot section and the PDF export which already drop blank rows; title/reference stay unconditional (NOT NULL)
-- Expected behavior: A published record carrying only title+reference renders no empty subject dd, no dangling EUR dd/span, no empty published-on/signed-on/effective-from dds; a full record renders unchanged; the metadata line under the title hides its date/amount spans when blank
+- Limitations: Absolute machine paths in .mcp.json (same as opencode.jsonc); Hook assumes agent-review is a sibling checkout; Skill is a symlink into ../agent-review
+### 2. Claude Code subagents
+- What changed: added in `.claude/agents/architect.md`, `.claude/agents/reviewer.md`, `.claude/agents/rails.md`, `.claude/agents/tester.md`, `.claude/agents/integration.md`, `.claude/agents/retro.md`
+- Why: Port .opencode/agents to Claude Code subagents so both harnesses share the same roles
+- Expected behavior: architect/reviewer run on opus with read-only tools; rails/tester/integration/retro on sonnet; bodies identical to the OpenCode agents
 - Risk: low
-### 3. Admin form partials accessibility (contracts/parties/documents/amendments _form.html.erb)
-- What changed: modified in `app/views/decidim/contracts_sk/admin/contracts/_form.html.erb`, `app/views/decidim/contracts_sk/admin/parties/_form.html.erb`, `app/views/decidim/contracts_sk/admin/documents/_form.html.erb`, `app/views/decidim/contracts_sk/admin/amendments/_form.html.erb`
-- Why: civora-org/civora-platform#78: validation-error summaries render as a bare ul on 422 re-render and presence-validated inputs carry no required attribute; the ul gets role="alert" tabindex="-1" autofocus and required: true lands on contract title/reference, party name, amendment summary, document file — minimal engine-side a11y, matching the Decidim FormBuilder's supported field options
-- Expected behavior: On a 422 re-render the error summary ul carries role="alert" tabindex="-1" autofocus; the presence-validated inputs render the required HTML attribute; no field-level aria-invalid/aria-describedby beyond the item-3 hints
+- Alternatives considered: Keep GLM-only OpenCode agents
+- Limitations: The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md
+### 3. Claude Code slash-command skills
+- What changed: added in `.claude/skills/issue/SKILL.md`, `.claude/skills/feature/SKILL.md`, `.claude/skills/review/SKILL.md`, `.claude/skills/verify/SKILL.md`, `.claude/skills/retro/SKILL.md`, `.claude/skills/agent-review-github-status/SKILL.md`, `.claude/skills/agent-review-prepare-pr/SKILL.md`, `.claude/skills/agent-review-publish-pr/SKILL.md`, `.claude/skills/agent-review-update-review/SKILL.md`
+- Why: Port the 9 .opencode/commands to Claude Code skills invoked as /<name>
+- Expected behavior: /issue reads civora-org/civora-platform issues via gh; publish-pr, update-review and retro are user-invoked only (disable-model-invocation)
 - Risk: low
-### 4. Admin contract form amount input + IČO hint + currency select
-- What changed: modified in `app/views/decidim/contracts_sk/admin/contracts/_form.html.erb`, `app/views/decidim/contracts_sk/admin/parties/_form.html.erb`, `config/locales/en.yml`, `config/locales/sk.yml`, `spec/decidim/contracts_sk_locales_spec.rb`
-- Why: civora-org/civora-platform#79: the amount field accepts only dot-decimals (STRICT_AMOUNT_FORMAT on the form) but says nothing about it, the IČO format rule is invisible to editors, and currency is a free-text input over a one-entry allowlist; hints get explicit ids wired with aria-describedby (the pinned Decidim FormBuilder's help_text: option renders neither id nor aria), and the select copies the role/kind select pattern over the frozen vocabulary
-- Expected behavior: Amount input carries inputmode="decimal" and aria-describedby pointing at a localized hint that only dot-decimals are accepted; IČO input carries a localized blank-or-8-digits hint wired the same way; currency renders as a select over Contract::SUPPORTED_CURRENCIES (selected preserved) instead of a free-text input; hints shipped in en.yml and sk.yml and registered in the locale key-surface contract
+### 4. Claude Code permissions
+- What changed: added in `.claude/settings.json`
+- Why: Mirror opencode.jsonc permissions
+- Expected behavior: git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied
+- Risk: low
+- Limitations: edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates
+### 5. CLAUDE.md and AGENTS.md pointer
+- What changed: added in `CLAUDE.md`, `AGENTS.md`
+- Why: Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router
+- Expected behavior: CLAUDE.md imports @AGENTS.md; AGENTS.md lists the Claude Code mirror to keep in sync
 - Risk: low
 
 ## Test Evidence
@@ -40,1016 +49,4166 @@ Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.
 ### Run 1
 - Command: `bundle exec rspec`
 - Result: **passed** (exit code: 0)
-- Duration: 6330 ms
-- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
-### Run 2
-- Command: `bundle exec rspec`
-- Result: **passed** (exit code: 0)
-- Duration: 8669 ms
-- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
-### Run 3
-- Command: `CONTRACTS_SK_DB=1 bundle exec rspec`
-- Result: **error** (exit code: signal)
-- Duration: 8 ms
-- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
-- Notes: stderr captured (1 lines, redacted and truncated)
-### Run 4
-- Command: `env CONTRACTS_SK_DB=1 bundle exec rspec`
-- Result: **passed** (exit code: 0)
-- Duration: 50489 ms
+- Duration: 3133 ms
 - Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
 
 ## Risks
-- Working tree was dirty at session start (17 entries) — pre-existing changes may be mixed into the diff.
-- 1 test run(s) did not pass (exit codes: signal).
+- Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.
+- Large diff: 5541 insertions across 26 files.
 
 ## Limitations
 - Snapshots cover only files that were changed at checkpoint time.
 - Symbol extraction is regex-based, not AST-based.
 - Only observed facts are recorded — private model reasoning is not captured.
+- The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md
+- Absolute machine paths in .mcp.json (same as opencode.jsonc)
+- Hook assumes agent-review is a sibling checkout
+- Skill is a symlink into ../agent-review
+- edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates
 
 ## Changed Files
-- `.opencode/commands/agent-review-github-status.md` — added (markdown, +16/−0)
-- `.opencode/commands/agent-review-prepare-pr.md` — added (markdown, +19/−0)
-- `.opencode/commands/agent-review-publish-pr.md` — added (markdown, +19/−0)
-- `.opencode/commands/agent-review-update-review.md` — added (markdown, +16/−0)
-- `.opencode/plugins/agent-review.ts` — added (typescript, +357/−0)
-- `.opencode/skills/agent-review` — added (unknown, +0/−0)
-- `AGENTS.md` — modified (markdown, +2/−0)
-- `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb` — modified (ruby, +1/−7)
-- `app/helpers/decidim/contracts_sk/application_helper.rb` — modified (ruby, +67/−0)
-- `app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb` — modified (ruby, +28/−9)
-- `app/views/decidim/contracts_sk/admin/amendments/_form.html.erb` — modified (unknown, +6/−4)
-- `app/views/decidim/contracts_sk/admin/audit_events/index.html.erb` — modified (unknown, +4/−1)
-- `app/views/decidim/contracts_sk/admin/contracts/_form.html.erb` — modified (unknown, +25/−7)
-- `app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb` — modified (unknown, +1/−1)
-- `app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb` — modified (unknown, +1/−1)
-- `app/views/decidim/contracts_sk/admin/documents/_form.html.erb` — modified (unknown, +6/−3)
-- `app/views/decidim/contracts_sk/admin/parties/_form.html.erb` — modified (unknown, +8/−5)
-- `app/views/decidim/contracts_sk/contracts/index.html.erb` — modified (unknown, +5/−4)
-- `app/views/decidim/contracts_sk/contracts/show.html.erb` — modified (unknown, +54/−22)
-- `config/locales/en.yml` — modified (yaml, +4/−0)
-- `config/locales/sk.yml` — modified (yaml, +4/−0)
-- `docs/crz-import.md` — modified (markdown, +1/−1)
-- `docs/qa-checklist.md` — modified (markdown, +7/−6)
-- `opencode.jsonc` — modified (unknown, +6/−0)
-- `spec/decidim/contracts_sk_locales_spec.rb` — modified (ruby, +30/−0)
-- `spec/decidim/contracts_sk/application_helper_spec.rb` — added (ruby, +116/−0)
-- `spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb` — modified (ruby, +9/−0)
-- `spec/requests/admin/amendments_spec.rb` — modified (ruby, +8/−0)
-- `spec/requests/admin/contracts_spec.rb` — modified (ruby, +34/−0)
-- `spec/requests/admin/documents_spec.rb` — modified (ruby, +8/−0)
-- `spec/requests/admin/parties_spec.rb` — modified (ruby, +10/−0)
-- `spec/requests/contracts_spec.rb` — modified (ruby, +31/−0)
+- `.agent-review/change-package.json` — modified (json, +551/−290)
+- `.agent-review/github/inline-comments.preview.json` — modified (json, +18/−5)
+- `.agent-review/github/pr-body.md` — modified (markdown, +16/−9)
+- `.agent-review/github/pr-preview.json` — modified (json, +23/−10)
+- `.agent-review/github/publish-plan.md` — modified (markdown, +5/−4)
+- `.agent-review/review.md` — modified (markdown, +4434/−1002)
+- `.claude/agents/architect.md` — modified (markdown, +39/−0)
+- `.claude/agents/integration.md` — modified (markdown, +34/−0)
+- `.claude/agents/rails.md` — modified (markdown, +27/−0)
+- `.claude/agents/retro.md` — modified (markdown, +24/−0)
+- `.claude/agents/reviewer.md` — modified (markdown, +35/−0)
+- `.claude/agents/tester.md` — modified (markdown, +36/−0)
+- `.claude/settings.json` — modified (json, +56/−0)
+- `.claude/skills/agent-review` — modified (unknown, +1/−0)
+- `.claude/skills/agent-review-github-status/SKILL.md` — modified (markdown, +21/−0)
+- `.claude/skills/agent-review-prepare-pr/SKILL.md` — modified (markdown, +25/−0)
+- `.claude/skills/agent-review-publish-pr/SKILL.md` — modified (markdown, +26/−0)
+- `.claude/skills/agent-review-update-review/SKILL.md` — modified (markdown, +23/−0)
+- `.claude/skills/feature/SKILL.md` — modified (markdown, +22/−0)
+- `.claude/skills/issue/SKILL.md` — modified (markdown, +23/−0)
+- `.claude/skills/retro/SKILL.md` — modified (markdown, +21/−0)
+- `.claude/skills/review/SKILL.md` — modified (markdown, +19/−0)
+- `.claude/skills/verify/SKILL.md` — modified (markdown, +20/−0)
+- `.mcp.json` — modified (json, +16/−0)
+- `AGENTS.md` — modified (markdown, +1/−0)
+- `CLAUDE.md` — modified (markdown, +25/−0)
+
+## Commits
+- `5a3f5102c1` chore: mirror OpenCode agent setup for Claude Code (Denys Kozlov, 2026-10-03T00:27:48+02:00)
 
 ## Diff
 ```diff
-diff --git a/AGENTS.md b/AGENTS.md
-index d07b8da..1c4ccc3 100644
---- a/AGENTS.md
-+++ b/AGENTS.md
-@@ -133,6 +133,8 @@ Current lessons:
- 
- - **The `with_lock` + in-lock re-check discipline applies to every command that writes state another request can change — not just lifecycle transitions.** Any guard (`draft?`, `published?`, `editable?`) evaluated on a request-loaded object is TOCTOU-bypassable: two concurrent publishes both pass the stale re-check and double-write. Wrap the write in `with_lock` (which reloads under lock) and re-check inside; read attributes the write depends on (snapshots, sequence numbers) from the post-lock instance. Test it deterministically with a stale pre-loaded object, no threads (proven in the #65 arc: reviewer H-1 on the amendment commands; `TransitionContract` was already the precedent).
- 
-+- **Close the previous agent-review session before starting a new arc, and expect `confirm:true` not to pass through.** A stale active session (e.g. a dry-run left over from a prior arc) blocks `agent_review_start` until the old session is finalized with `agent_review_build_package`; and the plugin's branch-creation confirmation can loop on `confirm:true`, in which case create the approved branch with plain `git checkout -b` and start the session on it (proven in the #87 arc).
-+
- *Archived lessons (tracker & issue hygiene; engine mount-design; tooling & verification hygiene; host-app & ops; engine implementation mechanics; release-please; Decidim view & asset mechanics; live-source operations; issue & planning hygiene clusters) live in [`docs/retro-lessons.md`](docs/retro-lessons.md).*
- 
- ## Testing Expectations
-diff --git a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
-index 6db8a76..1f56f5f 100644
---- a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
-+++ b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
-@@ -26,7 +26,7 @@ module Decidim
-       # admin contracts index (:read :contract): any engine role.
-       class AuditEventsController < Admin::ApplicationController
-         helper_method :audit_action_label, :audit_actor_name, :audit_target_info,
--                      :audit_reason_for, :audit_recorded_on
-+                      :audit_reason_for
- 
-         # Deterministic index ordering: newest events first, id as the
-         # tiebreaker (same doctrine as the contracts index — a total order,
-@@ -183,12 +183,6 @@ module Decidim
-         rescue StandardError
-           nil
-         end
--
--        # The event's timestamp, ISO date like the decision banner's
--        # decided-on line (nil-guarded the same way).
--        def audit_recorded_on(event)
--          event.created_at&.to_date&.to_fs(:db)
--        end
-       end
-     end
-   end
-diff --git a/app/helpers/decidim/contracts_sk/application_helper.rb b/app/helpers/decidim/contracts_sk/application_helper.rb
-index 37d94a3..f55f5c2 100644
---- a/app/helpers/decidim/contracts_sk/application_helper.rb
-+++ b/app/helpers/decidim/contracts_sk/application_helper.rb
-@@ -9,7 +9,15 @@ module Decidim
-     # imported records "externally confirmed" data — never a legal
-     # publication — and ADR-008 decisions 4/6 require a freshness signal
-     # that never implies real-time accuracy.
-+    #
-+    # Also carries the engine's locale-aware money/date/timestamp rendering
-+    # (civora-org/civora-platform#81). The three formatters are deliberately
-+    # PORO-safe — no view-context dependencies, I18n only — so the CRZ
-+    # handoff PDF (a plain object) can include this module and share one
-+    # formatting vocabulary with the views, never a second one.
-     module ApplicationHelper
-+      include ActionView::Helpers::NumberHelper
-+
-       # True when the record is a CRZ metadata mirror created by the import
-       # ETL (ADR-008) rather than an editorial record. Drives every
-       # provenance-labelled render in the catalogue; editorial records are
-@@ -18,6 +26,47 @@ module Decidim
-         contract.source == "crz"
-       end
- 
-+      # Locale-aware amount rendering (civora-org/civora-platform#81).
-+      # Under :sk the value is grouped and comma-decimalized — "1 250,50" —
-+      # through number_with_precision with EXPLICIT separators: regular
-+      # spaces (not non-breaking ones) were chosen on purpose, so the
-+      # engine ships no glyph-dependent markup and the same string renders
-+      # identically in HTML and in the PDF. Under every other locale the
-+      # historical fixed-point form is kept verbatim (BigDecimal#to_s("F"),
-+      # which also guards huge amounts against scientific notation). A
-+      # blank amount renders empty; a blank currency renders the bare
-+      # number — the PDF's drop-the-row semantics rely on both.
-+      def format_amount(amount, currency = nil)
-+        return "" if amount.blank?
-+
-+        formatted = localized_amount(amount)
-+        return formatted if currency.blank?
-+
-+        "#{formatted} #{currency}"
-+      end
-+
-+      # Locale-aware date rendering (civora-org/civora-platform#81): the
-+      # format STRING is resolved from the engine's own
-+      # decidim.contracts_sk.date_formats vocabulary and handed to I18n.l
-+      # explicitly — never a named format, so no host-app or rails-i18n
-+      # locale data can ever be required for the render to resolve. Blank
-+      # renders empty, so guarded views may call it unconditionally.
-+      def format_date(date)
-+        return "" if date.blank?
-+
-+        I18n.l(date, format: I18n.t("decidim.contracts_sk.date_formats.default"))
-+      end
-+
-+      # The PDF footer's generation stamp (civora-org/civora-platform#81):
-+      # the timestamp is converted to UTC BEFORE formatting, so the naive
-+      # to_fs(:db) digits can never silently carry the server's local zone
-+      # — the label is explicit and true.
-+      def format_timestamp(time)
-+        return "" if time.blank?
-+
-+        "#{time.utc.to_fs(:db)} UTC"
-+      end
-+
-       # True when a mirrored record must carry the stale notice (ADR-008
-       # decision 4): the last import was stamped "failed" (the engine-side
-       # stale-fallback signal — the record kept its last-good mirror data
-@@ -38,6 +87,24 @@ module Decidim
- 
-         contract.imported_at < Decidim::ContractsSk.stale_after.to_i.seconds.ago
-       end
-+
-+      private
-+
-+      # The locale branch of format_amount. Under :sk the value is grouped
-+      # and comma-decimalized through number_with_precision; under every
-+      # other locale the historical fixed-point form is kept verbatim —
-+      # "F" on BigDecimal keeps extreme magnitudes out of scientific
-+      # notation (plain BigDecimal#to_s goes scientific), while the frozen
-+      # content snapshots' plain Strings render as stored.
-+      def localized_amount(amount)
-+        if I18n.locale == :sk
-+          number_with_precision(amount, precision: 2, delimiter: " ", separator: ",")
-+        elsif amount.is_a?(BigDecimal)
-+          amount.to_s("F")
-+        else
-+          amount.to_s
-+        end
-+      end
-     end
-   end
- end
-diff --git a/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb b/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb
-index c714c2f..9e28f62 100644
---- a/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb
-+++ b/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb
-@@ -31,7 +31,17 @@ module Decidim
-     # The contract is duck-typed (title, reference, state, subject_matter,
-     # amount, currency, signed_on, effective_from, crz_url, parties), so the
-     # renderer is testable without ActiveRecord.
-+    #
-+    # Money, dates and the footer stamp render through the engine's shared
-+    # ApplicationHelper formatters (civora-org/civora-platform#81) — the
-+    # PDF runs under I18n.with_locale(:sk), so they come out locale-aware
-+    # ("1 250,50 EUR", "31. 01. 2026") — one formatting vocabulary with the
-+    # views, never a second one. The footer stamp additionally converts the
-+    # generation time to UTC explicitly and labels it, so the printed
-+    # moment is never naive server-local time.
-     class CrzHandoffPdf
-+      include Decidim::ContractsSk::ApplicationHelper
-+
-       def initialize(contract)
-         super()
-         @contract = contract
-@@ -82,7 +92,15 @@ module Decidim
- 
-       def render_footer(pdf)
-         pdf.move_down 12
--        pdf.text "#{t("decidim.contracts_sk.crz_handoff_pdf.generated_on")} #{Time.current.to_fs(:db)}", size: 9
-+        pdf.text "#{t("decidim.contracts_sk.crz_handoff_pdf.generated_on")} #{generated_stamp}", size: 9
-+      end
-+
-+      # The footer's generation stamp (civora-org/civora-platform#81): the
-+      # moment is converted to UTC BEFORE formatting and carries an explicit
-+      # zone label, so a naive server-local "2026-09-27 09:53:07" can never
-+      # be misread as registry time.
-+      def generated_stamp
-+        format_timestamp(Time.current)
-       end
- 
-       # The identity + content field rows, in the data dictionary's order,
-@@ -103,8 +121,8 @@ module Decidim
-           [t("decidim.contracts_sk.contract.status"), state_label],
-           [t("decidim.contracts_sk.contract.subject_matter"), contract.subject_matter],
-           [t("decidim.contracts_sk.contract.amount"), amount_value],
--          [t("decidim.contracts_sk.contract.signed_on"), contract.signed_on&.to_fs(:db)],
--          [t("decidim.contracts_sk.contract.effective_from"), contract.effective_from&.to_fs(:db)],
-+          [t("decidim.contracts_sk.contract.signed_on"), format_date(contract.signed_on)],
-+          [t("decidim.contracts_sk.contract.effective_from"), format_date(contract.effective_from)],
-           [t("decidim.contracts_sk.contract.crz_url"), contract.crz_url]
-         ].select { |_, value| value.present? }
-       end
-@@ -119,15 +137,16 @@ module Decidim
-         I18n.t("decidim.contracts_sk.contract_states.#{contract.state}", default: contract.state.to_s)
-       end
- 
--      # Fixed-point rendering on purpose: BigDecimal#to_s alone is
--      # scientific ("0.125e4"); the public catalogue's ERB interpolation
--      # hides that, a plain text draw would not. Nil when the amount is
--      # blank, so the row drops out of the field list.
-+      # Locale-aware rendering on purpose (civora-org/civora-platform#81):
-+      # under the PDF's forced :sk locale the shared formatter groups the
-+      # thousands with regular spaces and comma-decimalizes ("12 345,67"),
-+      # which also keeps BigDecimal's scientific to_s ("0.125e4") out of a
-+      # plain text draw. Nil when the amount is blank, so the row drops out
-+      # of the field list; a blank currency renders the bare number.
-       def amount_value
-         return nil if contract.amount.blank?
--        return contract.amount.to_s("F") if contract.currency.blank?
- 
--        "#{contract.amount.to_s("F")} #{contract.currency}"
-+        format_amount(contract.amount, contract.currency)
-       end
- 
-       def t(key)
-diff --git a/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb b/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb
-index 46afb5d..39a41bf 100644
---- a/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb
-+++ b/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb
-@@ -2,14 +2,16 @@
-     the summary is rendered — a draft amendment carries nothing else
-     content-wise: the version is sequenced by the command and the content
-     snapshot is taken at publish time from the contract's live fields
--    (civora-org/civora-platform#65, ADR-006). %>
--<%= form_with url: url, method: method, html: { class: "form form-defaults" } do |form| %>
-+    (civora-org/civora-platform#65, ADR-006). The summary is the only
-+    presence-validated input, so it alone carries the required attribute
-+    (civora-org/civora-platform#78). %>
-+<%= form_with model: @form, url: url, method: method, html: { class: "form form-defaults" } do |form| %>
-   <div class="card">
-     <div class="card-section">
-       <div class="form__wrapper">
-         <% if @form.errors.any? %>
-           <div class="flash alert">
--            <ul>
-+            <ul role="alert" tabindex="-1" autofocus>
-               <% @form.errors.full_messages.each do |message| %>
-                 <li><%= message %></li>
-               <% end %>
-@@ -18,7 +20,7 @@
-         <% end %>
- 
-         <div class="row column">
--          <%= form.text_field :summary, label: t("decidim.contracts_sk.admin.amendments.form.summary"), label_options: { for: "amendment_summary" }, id: "amendment_summary", name: "amendment[summary]", value: @form.summary %>
-+          <%= form.text_field :summary, label: t("decidim.contracts_sk.admin.amendments.form.summary"), label_options: { for: "amendment_summary" }, id: "amendment_summary", name: "amendment[summary]", value: @form.summary, required: true %>
-         </div>
-       </div>
-     </div>
-diff --git a/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb b/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
-index b93dc6e..1918976 100644
---- a/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
-+++ b/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
-@@ -51,7 +51,10 @@
-                 <% end %>
-               </td>
-               <td><%= audit_actor_name(event) %></td>
--              <td><%= audit_recorded_on(event) %></td>
-+              <%# The row date renders through the shared locale-aware helper
-+                  (civora-org/civora-platform#81) directly in the view — the
-+                  helper chain is the view's, not the controller's. %>
-+              <td><%= format_date(event.created_at) %></td>
-               <td><%= reason %></td>
-             </tr>
-           <% end %>
-diff --git a/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb b/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb
-index e52fb35..cdcee94 100644
---- a/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb
-+++ b/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb
-@@ -2,14 +2,23 @@
-     the editorial identity fields and the contract content fields
-     (civora-org/civora-platform#75) are rendered — the lifecycle state and
-     the system-stamped published_at are intentionally absent from every
--    admin form. %>
--<%= form_with url: url, method: method, html: { class: "form form-defaults" } do |form| %>
-+    admin form.
-+    Accessibility surface (civora-org/civora-platform#78/#79): the error
-+    summary is announced as a live alert and focused on the 422 re-render;
-+    the presence-validated identity inputs carry the required attribute
-+    (the builder is bound to @form — the Decidim builder's required path
-+    needs the object, and the explicit name/id options keep every field
-+    name stable); the amount input declares its decimal keyboard and its
-+    dot-decimal hint through aria-describedby (the Decidim builder's
-+    help_text option wires neither an id nor the aria relation, so the
-+    hint element is explicit). %>
-+<%= form_with model: @form, url: url, method: method, html: { class: "form form-defaults" } do |form| %>
-   <div class="card">
-     <div class="card-section">
-       <div class="form__wrapper">
-         <% if @form.errors.any? %>
-           <div class="flash alert">
--            <ul>
-+            <ul role="alert" tabindex="-1" autofocus>
-               <% @form.errors.full_messages.each do |message| %>
-                 <li><%= message %></li>
-               <% end %>
-@@ -18,11 +27,11 @@
-         <% end %>
- 
-         <div class="row column">
--          <%= form.text_field :title, label: t("decidim.contracts_sk.admin.contracts.form.title"), label_options: { for: "contract_title" }, id: "contract_title", name: "contract[title]", value: @form.title %>
-+          <%= form.text_field :title, label: t("decidim.contracts_sk.admin.contracts.form.title"), label_options: { for: "contract_title" }, id: "contract_title", name: "contract[title]", value: @form.title, required: true %>
-         </div>
- 
-         <div class="row column">
--          <%= form.text_field :reference, label: t("decidim.contracts_sk.admin.contracts.form.reference"), label_options: { for: "contract_reference" }, id: "contract_reference", name: "contract[reference]", value: @form.reference %>
-+          <%= form.text_field :reference, label: t("decidim.contracts_sk.admin.contracts.form.reference"), label_options: { for: "contract_reference" }, id: "contract_reference", name: "contract[reference]", value: @form.reference, required: true %>
-         </div>
- 
-         <div class="row column">
-@@ -30,11 +39,20 @@
-         </div>
- 
-         <div class="row column">
--          <%= form.text_field :amount, label: t("decidim.contracts_sk.admin.contracts.form.amount"), label_options: { for: "contract_amount" }, id: "contract_amount", name: "contract[amount]", value: @form.amount %>
-+          <%= form.text_field :amount, label: t("decidim.contracts_sk.admin.contracts.form.amount"), label_options: { for: "contract_amount" }, id: "contract_amount", name: "contract[amount]", value: @form.amount, inputmode: "decimal", aria: { describedby: "contract_amount_hint" } %>
-+          <span class="help-text" id="contract_amount_hint"><%= t("decidim.contracts_sk.admin.contracts.form.amount_hint") %></span>
-         </div>
- 
-         <div class="row column">
--          <%= form.text_field :currency, label: t("decidim.contracts_sk.admin.contracts.form.currency"), label_options: { for: "contract_currency" }, id: "contract_currency", name: "contract[currency]", value: @form.currency %>
-+          <%# The options come from the model's frozen SUPPORTED_CURRENCIES
-+              vocabulary (D1 of #75), never hand-enumerated. Currency ISO
-+              codes are locale-neutral, so each option labels itself —
-+              unlike the role/kind selects, no second localized vocabulary
-+              is invented. %>
-+          <% currency_options = Decidim::ContractsSk::Contract::SUPPORTED_CURRENCIES.map do |currency|
-+               [currency, currency]
-+             end %>
-+          <%= form.select :currency, currency_options, { selected: @form.currency, label: t("decidim.contracts_sk.admin.contracts.form.currency"), label_options: { for: "contract_currency" } }, id: "contract_currency", name: "contract[currency]" %>
-         </div>
- 
-         <div class="row column">
-diff --git a/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb b/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb
-index ff35bd4..122e891 100644
---- a/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb
-+++ b/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb
-@@ -12,7 +12,7 @@
-                  (the index can show several confirmable rows on one page),
-                  while the name stays the server-side contract. %>
- <% if contract.redaction_confirmed_at.present? %>
--  <p><%= t("decidim.contracts_sk.admin.contracts.confirm_redaction.confirmed_on", confirmed_at: contract.redaction_confirmed_at.to_date.to_fs(:db)) %></p>
-+  <p><%= t("decidim.contracts_sk.admin.contracts.confirm_redaction.confirmed_on", confirmed_at: format_date(contract.redaction_confirmed_at)) %></p>
- <% else %>
-   <p><%= t("decidim.contracts_sk.admin.contracts.confirm_redaction.description") %></p>
-   <ul>
-diff --git a/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb b/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb
-index 328b99c..33e2cb1 100644
---- a/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb
-+++ b/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb
-@@ -9,6 +9,6 @@
- <p>
-   <strong><%= t(contract.state, scope: "decidim.contracts_sk.contract_states") %></strong>
-   — <%= t("decidim.contracts_sk.admin.contracts.review_decision.decided_on",
--          reviewed_at: contract.reviewed_at&.to_date&.to_fs(:db)) %>
-+          reviewed_at: format_date(contract.reviewed_at)) %>
- </p>
- <p><%= contract.review_reason %></p>
-diff --git a/app/views/decidim/contracts_sk/admin/documents/_form.html.erb b/app/views/decidim/contracts_sk/admin/documents/_form.html.erb
-index d68b2df..a0a5efb 100644
---- a/app/views/decidim/contracts_sk/admin/documents/_form.html.erb
-+++ b/app/views/decidim/contracts_sk/admin/documents/_form.html.erb
-@@ -5,13 +5,13 @@
-     civora-org/civora-platform#73). The kind options are derived from the
-     form's EDITOR_KINDS vocabulary, never hand-enumerated, with localized
-     labels. The form is multipart: the file travels with the request. %>
--<%= form_with url: url, method: method, html: { multipart: true, class: "form form-defaults" } do |form| %>
-+<%= form_with model: @form, url: url, method: method, html: { multipart: true, class: "form form-defaults" } do |form| %>
-   <div class="card">
-     <div class="card-section">
-       <div class="form__wrapper">
-         <% if @form.errors.any? %>
-           <div class="flash alert">
--            <ul>
-+            <ul role="alert" tabindex="-1" autofocus>
-               <% @form.errors.full_messages.each do |message| %>
-                 <li><%= message %></li>
-               <% end %>
-@@ -38,7 +38,10 @@
-         <% end %>
- 
-         <div class="row column">
--          <%= form.file_field :file, label: t("decidim.contracts_sk.admin.documents.form.file"), label_options: { for: "document_file" }, id: "document_file", name: "document[file]" %>
-+          <%# The file is presence-validated on the form, so it carries the
-+              required attribute on both the attach and the replace page
-+              (civora-org/civora-platform#78). %>
-+          <%= form.file_field :file, label: t("decidim.contracts_sk.admin.documents.form.file"), label_options: { for: "document_file" }, id: "document_file", name: "document[file]", required: true %>
-         </div>
-       </div>
-     </div>
-diff --git a/app/views/decidim/contracts_sk/admin/parties/_form.html.erb b/app/views/decidim/contracts_sk/admin/parties/_form.html.erb
-index 8da1183..6f7a9c2 100644
---- a/app/views/decidim/contracts_sk/admin/parties/_form.html.erb
-+++ b/app/views/decidim/contracts_sk/admin/parties/_form.html.erb
-@@ -2,14 +2,16 @@
-     the party's content fields are rendered — the parent contract is never
-     form-writable (civora-org/civora-platform#76). The role options are
-     derived from the model's frozen ROLES vocabulary, never hand-enumerated,
--    with localized labels. %>
--<%= form_with url: url, method: method, html: { class: "form form-defaults" } do |form| %>
-+    with localized labels. The IČO hint (civora-org/civora-platform#79)
-+    states the blank-or-8-digits rule the form validates, wired to the
-+    input through aria-describedby. %>
-+<%= form_with model: @form, url: url, method: method, html: { class: "form form-defaults" } do |form| %>
-   <div class="card">
-     <div class="card-section">
-       <div class="form__wrapper">
-         <% if @form.errors.any? %>
-           <div class="flash alert">
--            <ul>
-+            <ul role="alert" tabindex="-1" autofocus>
-               <% @form.errors.full_messages.each do |message| %>
-                 <li><%= message %></li>
-               <% end %>
-@@ -26,11 +28,12 @@
-         </div>
- 
-         <div class="row column">
--          <%= form.text_field :name, label: t("decidim.contracts_sk.admin.parties.form.name"), label_options: { for: "party_name" }, id: "party_name", name: "party[name]", value: @form.name %>
-+          <%= form.text_field :name, label: t("decidim.contracts_sk.admin.parties.form.name"), label_options: { for: "party_name" }, id: "party_name", name: "party[name]", value: @form.name, required: true %>
-         </div>
- 
-         <div class="row column">
--          <%= form.text_field :ico, label: t("decidim.contracts_sk.admin.parties.form.ico"), label_options: { for: "party_ico" }, id: "party_ico", name: "party[ico]", value: @form.ico %>
-+          <%= form.text_field :ico, label: t("decidim.contracts_sk.admin.parties.form.ico"), label_options: { for: "party_ico" }, id: "party_ico", name: "party[ico]", value: @form.ico, aria: { describedby: "party_ico_hint" } %>
-+          <span class="help-text" id="party_ico_hint"><%= t("decidim.contracts_sk.admin.parties.form.ico_hint") %></span>
-         </div>
- 
-         <div class="row column">
-diff --git a/app/views/decidim/contracts_sk/contracts/index.html.erb b/app/views/decidim/contracts_sk/contracts/index.html.erb
-index c8f9e43..653d6e7 100644
---- a/app/views/decidim/contracts_sk/contracts/index.html.erb
-+++ b/app/views/decidim/contracts_sk/contracts/index.html.erb
-@@ -30,9 +30,10 @@
-             </span>
-             <div class="card__list-text"><%= contract.reference %></div>
-             <div class="card__list-metadata">
--              <%# Deterministic ISO rendering on purpose: the engine ships no
--                  locale date formats, so I18n.l would depend on host-app data. %>
--              <div><%= contract.published_at&.to_date&.to_fs(:db) %></div>
-+              <%# Locale-aware date rendering (civora-org/civora-platform#81):
-+                  the format string ships with the engine, so no host-app
-+                  locale data is required. %>
-+              <div><%= format_date(contract.published_at) %></div>
-               <%# CRZ-mirror provenance (civora-org/civora-platform#88, ADR-002
-                   rule 1): imported records are labelled externally confirmed,
-                   with the mirror date — never presented as engine-published
-@@ -44,7 +45,7 @@
-                 <div class="text-sm text-gray-2">
-                   <%= t("decidim.contracts_sk.provenance.badge") %>
-                   <% if contract.imported_at.present? %>
--                    · <%= contract.imported_at.to_date.to_fs(:db) %>
-+                    · <%= format_date(contract.imported_at) %>
-                   <% end %>
-                 </div>
-               <% end %>
-diff --git a/app/views/decidim/contracts_sk/contracts/show.html.erb b/app/views/decidim/contracts_sk/contracts/show.html.erb
-index f71cb4d..bb1b708 100644
---- a/app/views/decidim/contracts_sk/contracts/show.html.erb
-+++ b/app/views/decidim/contracts_sk/contracts/show.html.erb
-@@ -7,11 +7,18 @@
-     <h1 class="title-decorator"><%= @contract.title %></h1>
-     <%# Quick-scan metadata line under the title: the record's identity
-         (reference), its publication date and the headline amount. Uses the
--        existing contract vocabulary — no new keys. %>
-+        existing contract vocabulary — no new keys. The optional fields are
-+        guarded like the dl grid below (civora-org/civora-platform#80): a
-+        sparse record renders no dangling date span and no "EUR" with a
-+        blank amount. %>
-     <div class="text-sm text-gray-2 flex gap-x-4">
-       <span><%= t("decidim.contracts_sk.contract.reference_number") %>: <%= @contract.reference %></span>
--      <span><%= t("decidim.contracts_sk.contract.published_on") %>: <%= @contract.published_at&.to_date&.to_fs(:db) %></span>
--      <span><%= t("decidim.contracts_sk.contract.amount") %>: <%= @contract.amount %> <%= @contract.currency %></span>
-+      <% if @contract.published_at.present? %>
-+        <span><%= t("decidim.contracts_sk.contract.published_on") %>: <%= format_date(@contract.published_at) %></span>
-+      <% end %>
-+      <% if @contract.amount.present? %>
-+        <span><%= t("decidim.contracts_sk.contract.amount") %>: <%= format_amount(@contract.amount, @contract.currency) %></span>
-+      <% end %>
-     </div>
-   </section>
- 
-@@ -32,9 +39,9 @@
-     <section class="mt-8 border-t border-gray-3 pt-4">
-       <div class="font-semibold"><%= t("decidim.contracts_sk.provenance.badge") %></div>
-       <% if @contract.imported_at.present? %>
--        <%# Deterministic ISO rendering, same rule as the metadata line above. %>
-+        <%# Same localized date rule as the metadata line above. %>
-         <div class="text-sm text-gray-2">
--          <%= t("decidim.contracts_sk.provenance.imported_on") %> <%= @contract.imported_at.to_date.to_fs(:db) %>
-+          <%= t("decidim.contracts_sk.provenance.imported_on") %> <%= format_date(@contract.imported_at) %>
-         </div>
-       <% end %>
-       <% if mirror_stale?(@contract) %>
-@@ -56,24 +63,39 @@
-       <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.reference_number") %></dt>
-       <dd class="text-md text-black mt-0"><%= @contract.reference %></dd>
- 
--      <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.published_on") %></dt>
--      <%# Deterministic ISO rendering on purpose: the engine ships no locale
--          date formats, so I18n.l would depend on host-app data. %>
--      <dd class="text-md text-black mt-0"><%= @contract.published_at&.to_date&.to_fs(:db) %></dd>
-+      <%# The optional pairs are rendered only when the value is present
-+          (civora-org/civora-platform#80) — the frozen-snapshot section and
-+          the PDF export already drop blank rows, so the live grid must not
-+          render empty dds and dangling currency labels for sparse records.
-+          The reference stays unconditional: identity is NOT NULL. Dates and
-+          amounts render through the shared locale-aware helpers
-+          (civora-org/civora-platform#81). %>
-+      <% if @contract.published_at.present? %>
-+        <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.published_on") %></dt>
-+        <dd class="text-md text-black mt-0"><%= format_date(@contract.published_at) %></dd>
-+      <% end %>
- 
--      <dt class="text-sm text-gray-2 md:col-span-2"><%= t("decidim.contracts_sk.contract.subject_matter") %></dt>
--      <dd class="text-md text-black mt-0 md:col-span-2"><%= @contract.subject_matter %></dd>
-+      <% if @contract.subject_matter.present? %>
-+        <dt class="text-sm text-gray-2 md:col-span-2"><%= t("decidim.contracts_sk.contract.subject_matter") %></dt>
-+        <dd class="text-md text-black mt-0 md:col-span-2"><%= @contract.subject_matter %></dd>
-+      <% end %>
- 
--      <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.amount") %></dt>
--      <dd class="text-md text-black mt-0"><%= @contract.amount %> <%= @contract.currency %></dd>
-+      <% if @contract.amount.present? %>
-+        <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.amount") %></dt>
-+        <dd class="text-md text-black mt-0"><%= format_amount(@contract.amount, @contract.currency) %></dd>
-+      <% end %>
- 
--      <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.signed_on") %></dt>
--      <dd class="text-md text-black mt-0"><%= @contract.signed_on&.to_fs(:db) %></dd>
-+      <% if @contract.signed_on.present? %>
-+        <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.signed_on") %></dt>
-+        <dd class="text-md text-black mt-0"><%= format_date(@contract.signed_on) %></dd>
-+      <% end %>
- 
--      <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.effective_from") %></dt>
--      <dd class="text-md text-black mt-0"><%= @contract.effective_from&.to_fs(:db) %></dd>
-+      <% if @contract.effective_from.present? %>
-+        <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.effective_from") %></dt>
-+        <dd class="text-md text-black mt-0"><%= format_date(@contract.effective_from) %></dd>
-+      <% end %>
- 
--      <%# The only guarded field: a link to a blank URL would render href="". %>
-+      <%# The originally guarded field: a link to a blank URL would render href="". %>
-       <% if @contract.crz_url.present? %>
-         <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.crz_url") %></dt>
-         <dd class="text-md text-black mt-0"><%= link_to @contract.crz_url, @contract.crz_url %></dd>
-@@ -202,23 +224,33 @@
-           <div class="font-semibold">
-             <%= t("decidim.contracts_sk.contracts.show.version_label", version: amendment.version) %>
-             <% if amendment.published_at.present? %>
--              · <%= amendment.published_at.to_date.to_fs(:db) %>
-+              · <%= format_date(amendment.published_at) %>
-             <% end %>
-           </div>
-           <%# Same dl treatment as the current version's fields above — one
--              consistent key/value grid for both snapshot and live data. %>
-+              consistent key/value grid for both snapshot and live data,
-+              including the blank-value guards (#80) and the locale-aware
-+              date/amount helpers (#81). %>
-           <dl class="grid grid-cols-1 gap-x-8 gap-y-3 md:grid-cols-2">
-             <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.summary") %></dt>
-             <dd class="text-md text-black mt-0"><%= amendment.summary %></dd>
+diff --git a/.agent-review/change-package.json b/.agent-review/change-package.json
+index 75b47a1..eefb3ab 100644
+--- a/.agent-review/change-package.json
++++ b/.agent-review/change-package.json
+@@ -1,409 +1,305 @@
+ {
+   "schemaVersion": "agent-review/v1",
+   "session": {
+-    "id": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
+-    "startedAt": "2026-09-28T15:48:32.593Z",
+-    "endedAt": "2026-09-28T16:25:37.886Z",
++    "id": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
++    "startedAt": "2026-10-02T22:26:31.118Z",
++    "endedAt": "2026-10-02T22:27:52.305Z",
+     "status": "ended"
+   },
+-  "task": "Pilot demo UX polish: guard blank live fields on public detail (#80), admin form a11y (#78), input hints + currency select (#79), localized money/date rendering + PDF timestamp UTC label (#81)",
+-  "branch": "polish/pilot-demo-ux",
+-  "commits": [],
++  "task": "Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code",
++  "branch": "chore/claude-code-config",
++  "commits": [
++    {
++      "hash": "5a3f5102c111c56ea154eb5878727e15e45169e1",
++      "subject": "chore: mirror OpenCode agent setup for Claude Code",
++      "author": "Denys Kozlov",
++      "date": "2026-10-03T00:27:48+02:00"
++    }
++  ],
+   "changedFiles": [
+     {
+-      "path": ".opencode/commands/agent-review-github-status.md",
+-      "kind": "added",
+-      "language": "markdown",
+-      "insertions": 16,
+-      "deletions": 0
+-    },
+-    {
+-      "path": ".opencode/commands/agent-review-prepare-pr.md",
+-      "kind": "added",
+-      "language": "markdown",
+-      "insertions": 19,
+-      "deletions": 0
+-    },
+-    {
+-      "path": ".opencode/commands/agent-review-publish-pr.md",
+-      "kind": "added",
+-      "language": "markdown",
+-      "insertions": 19,
+-      "deletions": 0
+-    },
+-    {
+-      "path": ".opencode/commands/agent-review-update-review.md",
+-      "kind": "added",
+-      "language": "markdown",
+-      "insertions": 16,
+-      "deletions": 0
+-    },
+-    {
+-      "path": ".opencode/plugins/agent-review.ts",
+-      "kind": "added",
+-      "language": "typescript",
+-      "insertions": 357,
+-      "deletions": 0,
+-      "symbols": [
+-        "serialize",
+-        "errorMessage",
+-        "recordIfActive"
+-      ]
+-    },
+-    {
+-      "path": ".opencode/skills/agent-review",
+-      "kind": "added",
+-      "language": "unknown",
+-      "insertions": 0,
+-      "deletions": 0
+-    },
+-    {
+-      "path": "AGENTS.md",
++      "path": ".agent-review/change-package.json",
+       "kind": "modified",
+-      "language": "markdown",
+-      "insertions": 2,
+-      "deletions": 0
++      "language": "json",
++      "insertions": 551,
++      "deletions": 290
+     },
+     {
+-      "path": "app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb",
++      "path": ".agent-review/github/inline-comments.preview.json",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 1,
+-      "deletions": 7,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk",
+-        "Admin",
+-        "AuditEventsController",
+-        "index",
+-        "filtered_events",
+-        "audit_events_scope",
+-        "filtered_contract",
+-        "contracts_scope",
+-        "audit_action_label"
+-      ]
++      "language": "json",
++      "insertions": 18,
++      "deletions": 5
+     },
+     {
+-      "path": "app/helpers/decidim/contracts_sk/application_helper.rb",
++      "path": ".agent-review/github/pr-body.md",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 67,
+-      "deletions": 0,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk",
+-        "ApplicationHelper",
+-        "imported_contract?",
+-        "format_amount",
+-        "format_date",
+-        "format_timestamp",
+-        "mirror_stale?",
+-        "localized_amount"
+-      ]
++      "language": "markdown",
++      "insertions": 16,
++      "deletions": 9
+     },
+     {
+-      "path": "app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb",
++      "path": ".agent-review/github/pr-preview.json",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 28,
+-      "deletions": 9,
+-      "symbols": [
+-        "Decidim",
+-        "ContractsSk",
+-        "CrzHandoffPdf",
+-        "initialize",
+-        "render",
+-        "document",
+-        "render_header",
+-        "render_field_rows",
+-        "render_parties",
+-        "render_footer"
+-      ]
++      "language": "json",
++      "insertions": 23,
++      "deletions": 10
+     },
+     {
+-      "path": "app/views/decidim/contracts_sk/admin/amendments/_form.html.erb",
++      "path": ".agent-review/github/publish-plan.md",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 6,
++      "language": "markdown",
++      "insertions": 5,
+       "deletions": 4
+     },
+     {
+-      "path": "app/views/decidim/contracts_sk/admin/audit_events/index.html.erb",
++      "path": ".agent-review/review.md",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 4,
+-      "deletions": 1
++      "language": "markdown",
++      "insertions": 4434,
++      "deletions": 1002
+     },
+     {
+-      "path": "app/views/decidim/contracts_sk/admin/contracts/_form.html.erb",
++      "path": ".claude/agents/architect.md",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 25,
+-      "deletions": 7
++      "language": "markdown",
++      "insertions": 39,
++      "deletions": 0
+     },
+     {
+-      "path": "app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb",
++      "path": ".claude/agents/integration.md",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 1,
+-      "deletions": 1
++      "language": "markdown",
++      "insertions": 34,
++      "deletions": 0
+     },
+     {
+-      "path": "app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb",
++      "path": ".claude/agents/rails.md",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 1,
+-      "deletions": 1
++      "language": "markdown",
++      "insertions": 27,
++      "deletions": 0
+     },
+     {
+-      "path": "app/views/decidim/contracts_sk/admin/documents/_form.html.erb",
++      "path": ".claude/agents/retro.md",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 6,
+-      "deletions": 3
++      "language": "markdown",
++      "insertions": 24,
++      "deletions": 0
+     },
+     {
+-      "path": "app/views/decidim/contracts_sk/admin/parties/_form.html.erb",
++      "path": ".claude/agents/reviewer.md",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 8,
+-      "deletions": 5
++      "language": "markdown",
++      "insertions": 35,
++      "deletions": 0
+     },
+     {
+-      "path": "app/views/decidim/contracts_sk/contracts/index.html.erb",
++      "path": ".claude/agents/tester.md",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 5,
+-      "deletions": 4
++      "language": "markdown",
++      "insertions": 36,
++      "deletions": 0
+     },
+     {
+-      "path": "app/views/decidim/contracts_sk/contracts/show.html.erb",
++      "path": ".claude/settings.json",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 54,
+-      "deletions": 22
++      "language": "json",
++      "insertions": 56,
++      "deletions": 0
+     },
+     {
+-      "path": "config/locales/en.yml",
++      "path": ".claude/skills/agent-review",
+       "kind": "modified",
+-      "language": "yaml",
+-      "insertions": 4,
++      "language": "unknown",
++      "insertions": 1,
+       "deletions": 0
+     },
+     {
+-      "path": "config/locales/sk.yml",
++      "path": ".claude/skills/agent-review-github-status/SKILL.md",
+       "kind": "modified",
+-      "language": "yaml",
+-      "insertions": 4,
++      "language": "markdown",
++      "insertions": 21,
+       "deletions": 0
+     },
+     {
+-      "path": "docs/crz-import.md",
++      "path": ".claude/skills/agent-review-prepare-pr/SKILL.md",
+       "kind": "modified",
+       "language": "markdown",
+-      "insertions": 1,
+-      "deletions": 1
++      "insertions": 25,
++      "deletions": 0
+     },
+     {
+-      "path": "docs/qa-checklist.md",
++      "path": ".claude/skills/agent-review-publish-pr/SKILL.md",
+       "kind": "modified",
+       "language": "markdown",
+-      "insertions": 7,
+-      "deletions": 6
++      "insertions": 26,
++      "deletions": 0
+     },
+     {
+-      "path": "opencode.jsonc",
++      "path": ".claude/skills/agent-review-update-review/SKILL.md",
+       "kind": "modified",
+-      "language": "unknown",
+-      "insertions": 6,
++      "language": "markdown",
++      "insertions": 23,
+       "deletions": 0
+     },
+     {
+-      "path": "spec/decidim/contracts_sk_locales_spec.rb",
++      "path": ".claude/skills/feature/SKILL.md",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 30,
+-      "deletions": 0,
+-      "symbols": [
+-        "LocaleContract",
+-        "locale_file",
+-        "translations",
+-        "module_tree",
+-        "leaf_paths",
+-        "leaf_values",
+-        "fresh_backend",
+-        "PublicCatalogueLabels"
+-      ]
++      "language": "markdown",
++      "insertions": 22,
++      "deletions": 0
+     },
+     {
+-      "path": "spec/decidim/contracts_sk/application_helper_spec.rb",
+-      "kind": "added",
+-      "language": "ruby",
+-      "insertions": 116,
+-      "deletions": 0,
+-      "symbols": [
+-        "with_locale"
+-      ]
++      "path": ".claude/skills/issue/SKILL.md",
++      "kind": "modified",
++      "language": "markdown",
++      "insertions": 23,
++      "deletions": 0
+     },
+     {
+-      "path": "spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb",
++      "path": ".claude/skills/retro/SKILL.md",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 9,
+-      "deletions": 0,
+-      "symbols": [
+-        "blank_optional_fields"
+-      ]
++      "language": "markdown",
++      "insertions": 21,
++      "deletions": 0
+     },
+     {
+-      "path": "spec/requests/admin/amendments_spec.rb",
++      "path": ".claude/skills/review/SKILL.md",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 8,
+-      "deletions": 0,
+-      "symbols": [
+-        "sign_in",
+-        "stub_record_lookups",
+-        "create_contract!"
+-      ]
++      "language": "markdown",
++      "insertions": 19,
++      "deletions": 0
+     },
+     {
+-      "path": "spec/requests/admin/contracts_spec.rb",
++      "path": ".claude/skills/verify/SKILL.md",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 34,
+-      "deletions": 0,
+-      "symbols": [
+-        "RecordingIndexScope",
+-        "initialize",
+-        "where",
+-        "not",
+-        "order",
+-        "group",
+-        "count",
+-        "page",
+-        "per",
+-        "prev_page"
+-      ]
++      "language": "markdown",
++      "insertions": 20,
++      "deletions": 0
+     },
+     {
+-      "path": "spec/requests/admin/documents_spec.rb",
++      "path": ".mcp.json",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 8,
+-      "deletions": 0,
+-      "symbols": [
+-        "sign_in",
+-        "stub_record_lookups",
+-        "sample_fixture",
+-        "upload",
+-        "hostile_upload"
+-      ]
++      "language": "json",
++      "insertions": 16,
++      "deletions": 0
+     },
+     {
+-      "path": "spec/requests/admin/parties_spec.rb",
++      "path": "AGENTS.md",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 10,
+-      "deletions": 0,
+-      "symbols": [
+-        "sign_in",
+-        "stub_record_lookups"
+-      ]
++      "language": "markdown",
++      "insertions": 1,
++      "deletions": 0
+     },
+     {
+-      "path": "spec/requests/contracts_spec.rb",
++      "path": "CLAUDE.md",
+       "kind": "modified",
+-      "language": "ruby",
+-      "insertions": 31,
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
+-      ]
++      "language": "markdown",
++      "insertions": 25,
++      "deletions": 0
+     }
+   ],
+   "logicalChanges": [
+     {
+-      "id": "1ceab998-6ab9-4d37-9100-567c6777205d",
+-      "sessionId": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
+-      "recordedAt": "2026-09-28T15:59:51.598Z",
+-      "entity": "Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.html.erb)",
++      "id": "31f58dca-257b-42df-b67e-cf78fb49b15a",
++      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
++      "recordedAt": "2026-10-02T22:26:44.812Z",
++      "entity": "Claude Code subagents",
+       "files": [
+-        "app/views/decidim/contracts_sk/contracts/show.html.erb"
++        ".claude/agents/architect.md",
++        ".claude/agents/reviewer.md",
++        ".claude/agents/rails.md",
++        ".claude/agents/tester.md",
++        ".claude/agents/integration.md",
++        ".claude/agents/retro.md"
+       ],
+-      "changeKind": "modified",
+-      "reason": "civora-org/civora-platform#80: the live dt/dd pairs (and the metadata line's date/amount spans) render unconditionally except crz_url, so a sparse published record shows an empty subject dd and a dangling EUR dd; each optional pair is now guarded on value presence, mirroring the frozen-snapshot section and the PDF export which already drop blank rows; title/reference stay unconditional (NOT NULL)",
+-      "expectedBehavior": "A published record carrying only title+reference renders no empty subject dd, no dangling EUR dd/span, no empty published-on/signed-on/effective-from dds; a full record renders unchanged; the metadata line under the title hides its date/amount spans when blank",
++      "changeKind": "added",
++      "reason": "Port .opencode/agents to Claude Code subagents so both harnesses share the same roles",
++      "expectedBehavior": "architect/reviewer run on opus with read-only tools; rails/tester/integration/retro on sonnet; bodies identical to the OpenCode agents",
+       "risk": "low",
+-      "alternatives": [],
+-      "limitations": []
++      "alternatives": [
++        "Keep GLM-only OpenCode agents"
++      ],
++      "limitations": [
++        "The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md"
++      ]
+     },
+     {
+-      "id": "58841712-37c6-4efb-8864-cf936ce24632",
+-      "sessionId": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
+-      "recordedAt": "2026-09-28T16:00:02.159Z",
+-      "entity": "Admin form partials accessibility (contracts/parties/documents/amendments _form.html.erb)",
++      "id": "52236dd7-6925-41b6-9df3-c8d3c80bd018",
++      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
++      "recordedAt": "2026-10-02T22:26:44.912Z",
++      "entity": "Claude Code slash-command skills",
+       "files": [
+-        "app/views/decidim/contracts_sk/admin/contracts/_form.html.erb",
+-        "app/views/decidim/contracts_sk/admin/parties/_form.html.erb",
+-        "app/views/decidim/contracts_sk/admin/documents/_form.html.erb",
+-        "app/views/decidim/contracts_sk/admin/amendments/_form.html.erb"
++        ".claude/skills/issue/SKILL.md",
++        ".claude/skills/feature/SKILL.md",
++        ".claude/skills/review/SKILL.md",
++        ".claude/skills/verify/SKILL.md",
++        ".claude/skills/retro/SKILL.md",
++        ".claude/skills/agent-review-github-status/SKILL.md",
++        ".claude/skills/agent-review-prepare-pr/SKILL.md",
++        ".claude/skills/agent-review-publish-pr/SKILL.md",
++        ".claude/skills/agent-review-update-review/SKILL.md"
+       ],
+-      "changeKind": "modified",
+-      "reason": "civora-org/civora-platform#78: validation-error summaries render as a bare ul on 422 re-render and presence-validated inputs carry no required attribute; the ul gets role=\"alert\" tabindex=\"-1\" autofocus and required: true lands on contract title/reference, party name, amendment summary, document file — minimal engine-side a11y, matching the Decidim FormBuilder's supported field options",
+-      "expectedBehavior": "On a 422 re-render the error summary ul carries role=\"alert\" tabindex=\"-1\" autofocus; the presence-validated inputs render the required HTML attribute; no field-level aria-invalid/aria-describedby beyond the item-3 hints",
++      "changeKind": "added",
++      "reason": "Port the 9 .opencode/commands to Claude Code skills invoked as /<name>",
++      "expectedBehavior": "/issue reads civora-org/civora-platform issues via gh; publish-pr, update-review and retro are user-invoked only (disable-model-invocation)",
+       "risk": "low",
+       "alternatives": [],
+       "limitations": []
+     },
+     {
+-      "id": "9f6b85e5-7639-4398-a8be-d2c70e33db82",
+-      "sessionId": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
+-      "recordedAt": "2026-09-28T16:00:12.997Z",
+-      "entity": "Admin contract form amount input + IČO hint + currency select",
++      "id": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
++      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
++      "recordedAt": "2026-10-02T22:26:45.009Z",
++      "entity": "agent-review skill, MCP servers and journaling hook",
++      "files": [
++        ".claude/skills/agent-review",
++        ".mcp.json",
++        ".claude/settings.json"
++      ],
++      "changeKind": "added",
++      "reason": "Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers",
++      "expectedBehavior": "Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active",
++      "risk": "medium",
++      "alternatives": [],
++      "limitations": [
++        "Absolute machine paths in .mcp.json (same as opencode.jsonc)",
++        "Hook assumes agent-review is a sibling checkout",
++        "Skill is a symlink into ../agent-review"
++      ],
++      "evidence": "agent-review npm test: 70/70 pass incl. MCP listTools + hook mapping; stdio smoke call agent_review_status returned status inactive"
++    },
++    {
++      "id": "6c1abf82-4513-47c1-a072-4edf4f90e454",
++      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
++      "recordedAt": "2026-10-02T22:26:45.110Z",
++      "entity": "Claude Code permissions",
+       "files": [
+-        "app/views/decidim/contracts_sk/admin/contracts/_form.html.erb",
+-        "app/views/decidim/contracts_sk/admin/parties/_form.html.erb",
+-        "config/locales/en.yml",
+-        "config/locales/sk.yml",
+-        "spec/decidim/contracts_sk_locales_spec.rb"
++        ".claude/settings.json"
+       ],
+-      "changeKind": "modified",
+-      "reason": "civora-org/civora-platform#79: the amount field accepts only dot-decimals (STRICT_AMOUNT_FORMAT on the form) but says nothing about it, the IČO format rule is invisible to editors, and currency is a free-text input over a one-entry allowlist; hints get explicit ids wired with aria-describedby (the pinned Decidim FormBuilder's help_text: option renders neither id nor aria), and the select copies the role/kind select pattern over the frozen vocabulary",
+-      "expectedBehavior": "Amount input carries inputmode=\"decimal\" and aria-describedby pointing at a localized hint that only dot-decimals are accepted; IČO input carries a localized blank-or-8-digits hint wired the same way; currency renders as a select over Contract::SUPPORTED_CURRENCIES (selected preserved) instead of a free-text input; hints shipped in en.yml and sk.yml and registered in the locale key-surface contract",
++      "changeKind": "added",
++      "reason": "Mirror opencode.jsonc permissions",
++      "expectedBehavior": "git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied",
+       "risk": "low",
+       "alternatives": [],
+-      "limitations": []
++      "limitations": [
++        "edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates"
++      ]
+     },
+     {
+-      "id": "51ae51c3-9fe4-47a9-b704-ac08e36decbc",
+-      "sessionId": "6b2892c2-9985-4b7a-9031-fc723f7302c9",
+-      "recordedAt": "2026-09-28T16:00:26.858Z",
+-      "entity": "Localized money/date rendering + CRZ handoff PDF timestamp zone label",
++      "id": "e272f979-badc-4ead-b674-6708421f71f1",
++      "sessionId": "d89b86e3-d25a-4b4e-aa50-1bd7560e389d",
++      "recordedAt": "2026-10-02T22:26:45.213Z",
++      "entity": "CLAUDE.md and AGENTS.md pointer",
+       "files": [
+-        "app/helpers/decidim/contracts_sk/application_helper.rb",
+-        "app/views/decidim/contracts_sk/contracts/show.html.erb",
+-        "app/views/decidim/contracts_sk/contracts/index.html.erb",
+-        "app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb",
+-        "app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb",
+-        "app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb",
+-        "app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb",
+-        "config/locales/en.yml",
+-        "config/locales/sk.yml"
++        "CLAUDE.md",
++        "AGENTS.md"
+       ],
+-      "changeKind": "modified",
+-      "reason": "civora-org/civora-platform#81: \"1250.5 EUR\" renders locale-blind while the audience is Slovak, every date renders naive to_fs(:db), and the PDF footer stamps a naive server-local time with no zone; a small helper in the base ApplicationHelper (number_with_precision with explicit sk separators; I18n.l with an explicit engine-shipped format string — the harness has no rails-i18n sk data, so named formats/day names would not resolve) replaces every to_fs(:db) date render and both amount renders, and the PDF footer converts to UTC explicitly",
+-      "expectedBehavior": "Amounts render locale-aware: sk \"1 250,50 EUR\" (regular-space grouping, comma decimals — documented decision), en keeps the current fixed-point \"1250.5 EUR\"; dates render through a thin format_date helper backed by engine-shipped date_formats.default keys (sk \"%d. %m. %Y\", en \"%Y-%m-%d\" — no host-app locale data dependency); the PDF footer timestamp renders Time.current converted to UTC with an explicit \" UTC\" suffix; helper is PORO-safe (included by the PDF class)",
+-      "risk": "medium",
++      "changeKind": "added",
++      "reason": "Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router",
++      "expectedBehavior": "CLAUDE.md imports @AGENTS.md; AGENTS.md lists the Claude Code mirror to keep in sync",
++      "risk": "low",
+       "alternatives": [],
+       "limitations": []
+     }
+@@ -411,67 +307,37 @@
+   "tests": [
+     {
+       "command": "bundle exec rspec",
+-      "startedAt": "2026-09-28T15:59:13.070Z",
+-      "finishedAt": "2026-09-28T15:59:19.400Z",
+-      "durationMs": 6330,
++      "startedAt": "2026-10-02T22:26:52.256Z",
++      "finishedAt": "2026-10-02T22:26:55.393Z",
++      "durationMs": 3133,
+       "exitCode": 0,
+       "status": "passed",
+       "stdoutSummary": "Run options: exclude {:db=>true}\n\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_redaction_confirmation_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds only the redaction_confirmed_at column, as a plain nullable datetime\n    attaches no default and no backfill (a fabricated stamp would defeat the gate)\n    adds no index (the stamp is read per-record, never queried as a set)\n\ndb/migrate/*_add_review_decision_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the review_reason and reviewed_at columns\n    adds review_reason as a plain nullable string capped at 1000 characters\n    adds reviewed_at as a plain nullable datetime\n    attaches no default and no backfill (a fabricated judgment would defeat the gate)\n    adds no index (the decision is read per-record, never queried as a set)\n\ndb/migrate/*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  index\n    uniquely indexes (organization, source_id) under the explicit unique name\n    keeps the index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_create_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes version a NOT NULL integer\n    makes summary a NOT NULL string\n  indexes\n    uniquely indexes (contract_id, version) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_audit_events.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant reference NOT NULL with a real FK to the organizations table\n    makes the actor reference NOT NULL with a real FK to the users table\n    makes the target a NOT NULL polymorphic reference\n    makes action a NOT NULL string\n  indexes\n    indexes every reference and created_at under explicit names\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contract_links.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes the target a NOT NULL polymorphic reference with no index of its own\n  indexes\n    uniquely indexes (contract_id, target_type, target_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant and author references NOT NULL\n    makes title and reference NOT NULL strings\n    pins state as NOT NULL defaulting to draft\n    pins source as NOT NULL defaulting to editorial\n    keeps the provenance columns nullable\n  indexes\n    indexes the organization reference under an explicit name\n    indexes the author reference\n    uniquely indexes (organization, reference) under an explicit name\n    indexes (organization, state) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_documents.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL with a real FK to the contracts table\n    makes title NOT NULL\n    pins kind as NOT NULL defaulting to contract\n    keeps the file metadata columns nullable\n  indexes\n    indexes the contract reference under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_parties.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes role and name NOT NULL strings\n    keeps ico as a nullable string with the 8-character limit\n    keeps address nullable\n  indexes\n    compositely indexes (contract_id, role) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\nDecidim::ContractsSk::Admin::AmendmentForm\n  accepts a complete amendment form\n  rejects a blank summary\n  rejects a missing summary\n  caps the summary at 255 characters\n\nDecidim::ContractsSk::Admin::AuditEventsController\n  inherits from the engine's admin base controller\n  implements exactly the index action (read-only viewer)\n  does not sit on the engine's public base controller chain\n  pins the audit action vocabulary actually written by the commands\n  derives the six lifecycle-action keys from the transition table, never hand-enumerated\n\nDecidim::ContractsSk::Admin::ContractForm\n  accepts dotted decimal strings\n  accepts proper numerics without the string guard (spec/API compatibility)\n  accepts the decimal(12,2) ceiling itself\n  accepts a nil amount (the value may be unknown while drafting)\n  rejects non-numeric strings instead of letting the cast zero them\n  rejects comma decimals (the Slovak '12,50' habit, caught deliberately)\n  rejects scientific notation (the format guard stays strict)\n  rejects negative amounts\n  rejects amounts beyond the decimal(12,2) column's ceiling\n  rejects over-ceiling strings too (raw input, same cap)\n\nDecidim::ContractsSk::Admin::ContractsController\n  inherits from the engine's admin base controller\n  implements exactly the CRUD + transition + CRZ-handoff + import + redaction actions (no show, no destroy)\n  does not sit on the engine's public base controller chain\n\nDecidim::ContractsSk::Admin::DocumentForm\n  accepts a complete form\n  defaults the kind to the model's column default\n  accepts every kind of the form's editor vocabulary\n  narrows the mod",
+       "stderrSummary": "",
+       "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
+       "commandTruncated": false
+-    },
+-    {
+-      "command": "bundle exec rspec",
+-      "startedAt": "2026-09-28T16:24:19.457Z",
+-      "finishedAt": "2026-09-28T16:24:28.126Z",
+-      "durationMs": 8669,
+-      "exitCode": 0,
+-      "status": "passed",
+-      "stdoutSummary": "Run options: exclude {:db=>true}\n\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_add_redaction_confirmation_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds only the redaction_confirmed_at column, as a plain nullable datetime\n    attaches no default and no backfill (a fabricated stamp would defeat the gate)\n    adds no index (the stamp is read per-record, never queried as a set)\n\ndb/migrate/*_add_review_decision_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the review_reason and reviewed_at columns\n    adds review_reason as a plain nullable string capped at 1000 characters\n    adds reviewed_at as a plain nullable datetime\n    attaches no default and no backfill (a fabricated judgment would defeat the gate)\n    adds no index (the decision is read per-record, never queried as a set)\n\ndb/migrate/*_add_source_id_unique_index_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  index\n    uniquely indexes (organization, source_id) under the explicit unique name\n    keeps the index name within PostgreSQL's 63-byte limit\n\ndb/migrate/*_create_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes version a NOT NULL integer\n    makes summary a NOT NULL string\n  indexes\n    uniquely indexes (contract_id, version) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_audit_events.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant reference NOT NULL with a real FK to the organizations table\n    makes the actor reference NOT NULL with a real FK to the users table\n    makes the target a NOT NULL polymorphic reference\n    makes action a NOT NULL string\n  indexes\n    indexes every reference and created_at under explicit names\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contract_links.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes the target a NOT NULL polymorphic reference with no index of its own\n  indexes\n    uniquely indexes (contract_id, target_type, target_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the tenant and author references NOT NULL\n    makes title and reference NOT NULL strings\n    pins state as NOT NULL defaulting to draft\n    pins source as NOT NULL defaulting to editorial\n    keeps the provenance columns nullable\n  indexes\n    indexes the organization reference under an explicit name\n    indexes the author reference\n    uniquely indexes (organization, reference) under an explicit name\n    indexes (organization, state) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_documents.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL with a real FK to the contracts table\n    makes title NOT NULL\n    pins kind as NOT NULL defaulting to contract\n    keeps the file metadata columns nullable\n  indexes\n    indexes the contract reference under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\ndb/migrate/*_create_decidim_contracts_sk_parties.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    declares the table with all expected columns\n    makes the contract reference NOT NULL and suppresses its single-column index\n    puts a real FK on the contract reference, targeting the contracts table\n    makes role and name NOT NULL strings\n    keeps ico as a nullable string with the 8-character limit\n    keeps address nullable\n  indexes\n    compositely indexes (contract_id, role) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n    relies only on DSL that ActiveRecord can reverse\n\nDecidim::ContractsSk::Admin::AmendmentForm\n  accepts a complete amendment form\n  rejects a blank summary\n  rejects a missing summary\n  caps the summary at 255 characters\n\nDecidim::ContractsSk::Admin::AuditEventsController\n  inherits from the engine's admin base controller\n  implements exactly the index action (read-only viewer)\n  does not sit on the engine's public base controller chain\n  pins the audit action vocabulary actually written by the commands\n  derives the six lifecycle-action keys from the transition table, never hand-enumerated\n\nDecidim::ContractsSk::Admin::ContractForm\n  accepts dotted decimal strings\n  accepts proper numerics without the string guard (spec/API compatibility)\n  accepts the decimal(12,2) ceiling itself\n  accepts a nil amount (the value may be unknown while drafting)\n  rejects non-numeric strings instead of letting the cast zero them\n  rejects comma decimals (the Slovak '12,50' habit, caught deliberately)\n  rejects scientific notation (the format guard stays strict)\n  rejects negative amounts\n  rejects amounts beyond the decimal(12,2) column's ceiling\n  rejects over-ceiling strings too (raw input, same cap)\n\nDecidim::ContractsSk::Admin::ContractsController\n  inherits from the engine's admin base controller\n  implements exactly the CRUD + transition + CRZ-handoff + import + redaction actions (no show, no destroy)\n  does not sit on the engine's public base controller chain\n\nDecidim::ContractsSk::Admin::DocumentForm\n  accepts a complete form\n  defaults the kind to the model's column default\n  accepts every kind of the form's editor vocabulary\n  narrows the mod",
+-      "stderrSummary": "",
+-      "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
+-      "commandTruncated": false
+-    },
+-    {
+-      "command": "CONTRACTS_SK_DB=1 bundle exec rspec",
+-      "startedAt": "2026-09-28T16:24:32.663Z",
+-      "finishedAt": "2026-09-28T16:24:32.672Z",
+-      "durationMs": 8,
+-      "exitCode": null,
+-      "status": "error",
+-      "stdoutSummary": "",
+-      "stderrSummary": "Executable not found in $PATH: \"CONTRACTS_SK_DB=1\"",
+-      "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk"
+-    },
+-    {
+-      "command": "env CONTRACTS_SK_DB=1 bundle exec rspec",
+-      "startedAt": "2026-09-28T16:24:40.755Z",
+-      "finishedAt": "2026-09-28T16:25:31.244Z",
+-      "durationMs": 50489,
+-      "exitCode": 0,
+-      "status": "passed",
+-      "stdoutSummary": "\ndb/migrate/*_add_amendment_lifecycle_to_decidim_contracts_sk_amendments.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the five lifecycle columns\n    pins state as NOT NULL defaulting to draft (the pre-lifecycle semantic)\n    keeps the system, tenancy and snapshot columns nullable\n    puts real FKs on the tenancy and actor references\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  reversibility proxy\n    uses no raw SQL\n  runnable migration\n==  CreateActiveStorageTables: migrating ======================================\n-- create_table(:active_storage_blobs, {:id=>:primary_key})\n   -> 0.0011s\n-- create_table(:active_storage_attachments, {:id=>:primary_key})\n   -> 0.0009s\n-- create_table(:active_storage_variant_records, {:id=>:primary_key})\n   -> 0.0004s\n==  CreateActiveStorageTables: migrated (0.0026s) =============================\n\n==  CreateDecidimContractsSkContracts: migrating ==============================\n-- create_table(:decidim_contracts_sk_contracts)\n   -> 0.0008s\n-- add_index(:decidim_contracts_sk_contracts, [:decidim_organization_id, :reference], {:unique=>true, :name=>\"idx_contracts_sk_contracts_on_organization_id_and_reference\"})\n   -> 0.0002s\n-- add_index(:decidim_contracts_sk_contracts, [:decidim_organization_id, :state], {:name=>\"idx_contracts_sk_contracts_on_organization_id_and_state\"})\n   -> 0.0002s\n==  CreateDecidimContractsSkContracts: migrated (0.0013s) =====================\n\n==  CreateDecidimContractsSkAmendments: migrating =============================\n-- create_table(:decidim_contracts_sk_amendments)\n   -> 0.0004s\n-- add_index(:decidim_contracts_sk_amendments, [:contract_id, :version], {:unique=>true, :name=>\"idx_contracts_sk_amendments_on_contract_id_and_version\"})\n   -> 0.0002s\n==  CreateDecidimContractsSkAmendments: migrated (0.0006s) ====================\n\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: migrating ============\n-- add_column(:decidim_contracts_sk_amendments, :state, :string, {:null=>false, :default=>\"draft\"})\n   -> 0.0006s\n-- add_column(:decidim_contracts_sk_amendments, :published_at, :datetime)\n   -> 0.0005s\n-- add_reference(:decidim_contracts_sk_amendments, :decidim_organization, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_organizations}, :index=>{:name=>\"idx_contracts_sk_amendments_on_organization_id\"}})\n   -> 0.0086s\n-- add_reference(:decidim_contracts_sk_amendments, :decidim_author, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_users}, :index=>true})\n   -> 0.0098s\n-- add_column(:decidim_contracts_sk_amendments, :content_snapshot, :json)\n   -> 0.0004s\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: migrated (0.0202s) ===\n\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: reverting ============\n-- remove_column(:decidim_contracts_sk_amendments, :content_snapshot, :json)\n   -> 0.0116s\n-- remove_reference(:decidim_contracts_sk_amendments, :decidim_author, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_users}, :index=>true})\n   -> 0.0166s\n-- remove_reference(:decidim_contracts_sk_amendments, :decidim_organization, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_organizations}, :index=>{:name=>\"idx_contracts_sk_amendments_on_organization_id\"}})\n   -> 0.0124s\n-- remove_column(:decidim_contracts_sk_amendments, :published_at, :datetime)\n   -> 0.0050s\n-- remove_column(:decidim_contracts_sk_amendments, :state, :string, {:null=>false, :default=>\"draft\"})\n   -> 0.0044s\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: reverted (0.0552s) ===\n\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: migrating ============\n-- add_column(:decidim_contracts_sk_amendments, :state, :string, {:null=>false, :default=>\"draft\"})\n   -> 0.0003s\n-- add_column(:decidim_contracts_sk_amendments, :published_at, :datetime)\n   -> 0.0002s\n-- add_reference(:decidim_contracts_sk_amendments, :decidim_organization, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_organizations}, :index=>{:name=>\"idx_contracts_sk_amendments_on_organization_id\"}})\n   -> 0.0068s\n-- add_reference(:decidim_contracts_sk_amendments, :decidim_author, {:type=>:bigint, :foreign_key=>{:to_table=>:decidim_users}, :index=>true})\n   -> 0.0092s\n-- add_column(:decidim_contracts_sk_amendments, :content_snapshot, :json)\n   -> 0.0006s\n==  AddAmendmentLifecycleToDecidimContractsSkAmendments: migrated (0.0175s) ===\n\n    adds the columns, defaults pre-lifecycle rows to draft, and reverses cleanly\n\ndb/migrate/*_add_content_fields_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds exactly the seven content columns\n    pins the amount as decimal(12,2)\n    pins currency as NOT NULL defaulting to EUR (D1)\n    keeps the remaining content columns nullable\n  published_at backfill (D3)\n    backfills published rows from updated_at inside the up arm of a reversible block\n    guards the backfill against re-stamping (idempotent WHERE clause)\n  runnable migration\n==  CreateActiveStorageTables: migrating ======================================\n-- create_table(:active_storage_blobs, {:id=>:primary_key})\n   -> 0.0005s\n-- create_table(:active_storage_attachments, {:id=>:primary_key})\n   -> 0.0006s\n-- create_table(:active_storage_variant_records, {:id=>:primary_key})\n   -> 0.0004s\n==  CreateActiveStorageTables: migrated (0.0017s) =============================\n\n==  CreateDecidimContractsSkContracts: migrating ==============================\n-- create_table(:decidim_contracts_sk_contracts)\n   -> 0.0011s\n-- add_index(:decidim_contracts_sk_contracts, [:decidim_organization_id, :reference], {:unique=>true, :name=>\"idx_contracts_sk_contracts_on_organization_id_and_reference\"})\n   -> 0.0002s\n-- add_index(:decidim_contracts_sk_contracts, [:decidim_organization_id, :state], {:name=>\"idx_contracts_sk_contracts_on_organization_id_and_state\"})\n   -> 0.0002s\n==  CreateDecidimContractsSkContracts: migrated (0.0015s) =====================\n\n==  AddContentFieldsToDecidimContractsSkContracts: migrating ==================\n-- add_column(:decidim_contracts_sk_contracts, :subject_matter, :text)\n   -> 0.0004s\n-- add_column(:decidim_contracts_sk_contracts, :amount, :decimal, {:precision=>12, :scale=>2})\n   -> 0.0002s\n-- add_column(:decidim_contracts_sk_contracts, :currency, :string, {:limit=>3, :null=>false, :default=>\"EUR\"})\n   -> 0.0003s\n-- add_column(:decidim_contracts_sk_contracts, :signed_on, :date)\n   -> 0.0002s\n-- add_column(:decidim_contracts_sk_contracts, :effective_from, :date)\n   -> 0.0002s\n-- add_column(:decidim_contracts_sk_contracts, :published_at, :datetime)\n   -> 0.0002s\n-- add_column(:decidim_contracts_sk_contracts, :crz_url, :string)\n   -> 0.0004s\n-- execute(\"UPDATE decidim_contracts_sk_contracts\\nSET published_at = updated_at\\nWHERE state = 'published' AND published_at IS NULL\\n\")\n   -> 0.0001s\n==  AddContentFieldsToDecidimContractsSkContracts: migrated (0.0022s) =========\n\n==  AddContentFieldsToDecidimContractsSkContracts: reverting ==================\n-- remove_column(:decidim_contracts_sk_contracts, :crz_url, :string)\n   -> 0.0135s\n-- remove_column(:decidim_contracts_sk_contracts, :published_at, :datetime)\n   -> 0.0119s\n-- remove_column(:decidim_contracts_sk_contracts, :effective_from, :date)\n   -> 0.0107s\n-- remove_column(:decidim_contracts_sk_contracts, :signed_on, :date)\n   -> 0.0129s\n-- remove_column(:decidim_contracts_sk_contracts, :currency, :string, {:limit=>3, :null=>false, :default=>\"EUR\"})\n   -> 0.0218s\n-- remove_column(:decidim_contracts_sk_contracts, :amount, :decimal, {:precision=>12, :scale=>2})\n   -> 0.0114s\n-- remove_column(:decidim_contracts_sk_contracts, :subject_matter, :text)\n   -> 0.0124s\n==  AddContentFieldsToDecidimContractsSkContracts: reverted (0.0957s) =========\n\n==  AddContentFieldsToDecidimContractsSkContracts: migrating ==================\n-- add_column(:decidim_contracts_sk_contracts, :subject_matter, :text)\n   -> 0.0005s\n-- add_column(:decidim_contracts_sk_contracts, :amount, :decimal, {:precision=>12, :scale=>2})\n   -> 0.0004s\n-- add_column(:decidim_contracts_sk_contracts, :currency, :string, {:limit=>3, :null=>false, :default=>\"EUR\"})\n   -> 0.0004s\n-- add_column(:decidim_contracts_sk_contracts, :signed_on, :date)\n   -> 0.0005s\n-- add_column(:decidim_contracts_sk_contracts, :effective_from, :date)\n   -> 0.0004s\n-- add_column(:decidim_contracts_sk_contracts, :published_at, :datetime)\n   -> 0.0003s\n-- add_column(:decidim_contracts_sk_contracts, :crz_url, :string)\n   -> 0.0002s\n-- execute(\"UPDATE decidim_contracts_sk_contracts\\nSET published_at = updated_at\\nWHERE state = 'published' AND published_at IS NULL\\n\")\n   -> 0.0002s\n==  AddContentFieldsToDecidimContractsSkContracts: migrated (0.0032s) =========\n\n    adds the columns, backfills published rows, and reverses cleanly\n\ndb/migrate/*_add_import_provenance_to_decidim_contracts_sk_contracts.rb\n  file surface\n    has exactly one matching migration file\n    keeps the class name in sync with the file name\n  class shape\n    subclasses ActiveRecord::Migration[7.2]\n    defines exactly one `def change` and no up/down split\n  columns\n    adds the checksum column as a nullable string\n  indexes\n    indexes (organization, source, source_id) under an explicit name\n    keeps every explicit index name within PostgreSQL's 63-byte limit\n  runnable migration\n==  CreateActiveStorageTables: migrating ======================================\n-- create_table(:active_storage_blobs, {:id=>:primary_key})\n   -> 0.0006s\n-- create_table(:active_storage_attachments, {:id=>:primary_key})\n   -> 0.0006s\n-- create_table(:active_storage_variant_records, {:id=>:primary_key})\n   -> 0.0004s\n==  CreateActiveStorageTables: migrated (0.0016s) =============================\n\n==  CreateDecidimContractsSkContracts: migrating ==============================\n-- create_table(:decidim_contracts_sk_contracts)\n   -> 0.0006s\n-- add_index(:decidim_contracts_",
+-      "stderrSummary": "",
+-      "workingDirectory": "/Users/denyskozlov/Code/decidim-contracts_sk",
+-      "commandTruncated": false
+     }
+   ],
+   "risks": [
+-    "Working tree was dirty at session start (17 entries) — pre-existing changes may be mixed into the diff.",
+-    "1 test run(s) did not pass (exit codes: signal)."
++    "Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.",
++    "Large diff: 5541 insertions across 26 files."
+   ],
+   "limitations": [
+     "Snapshots cover only files that were changed at checkpoint time.",
+     "Symbol extraction is regex-based, not AST-based.",
+-    "Only observed facts are recorded — private model reasoning is not captured."
++    "Only observed facts are recorded — private model reasoning is not captured.",
++    "The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md",
++    "Absolute machine paths in .mcp.json (same as opencode.jsonc)",
++    "Hook assumes agent-review is a sibling checkout",
++    "Skill is a symlink into ../agent-review",
++    "edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates"
+   ],
+   "agentMetadata": {
+-    "toolCalls": 110,
+-    "commands": 40,
+-    "checkpoints": 3,
+-    "tests": 4,
+-    "events": 3791
++    "toolCalls": 0,
++    "commands": 0,
++    "checkpoints": 1,
++    "tests": 1,
++    "events": 3814
+   },
+-  "generatedAt": "2026-09-28T16:25:37.850Z"
++  "generatedAt": "2026-10-02T22:28:12.473Z"
+ }
+diff --git a/.agent-review/github/inline-comments.preview.json b/.agent-review/github/inline-comments.preview.json
+index fe4f652..7824628 100644
+--- a/.agent-review/github/inline-comments.preview.json
++++ b/.agent-review/github/inline-comments.preview.json
+@@ -1,20 +1,33 @@
+ {
+   "schemaVersion": "agent-review-inline-comments/v1",
+-  "branch": "m03-92-audit-trail-viewer",
++  "branch": "chore/claude-code-config",
+   "baseBranch": "main",
+   "comments": [
+     {
+       "id": "comment_001",
+-      "logicalChangeId": "4fa1dda2-92d7-4b00-b687-9134fa8a2f7c",
+-      "path": "config/routes.rb",
+-      "line": 82,
++      "logicalChangeId": "6c1abf82-4513-47c1-a072-4edf4f90e454",
++      "path": ".claude/settings.json",
++      "line": 1,
+       "side": "RIGHT",
+-      "body": "### Agent context\n\n**What changed:** added — Audit-trail viewer (civora-org/civora-platform#92)\n\n**Why:** The append-only audit trail has no read surface; roles doc promises \"view audit trail\" to every engine role. Gate-1: single GET /admin/audit_events index, contract filter via tenant-scoped contract_id query param, :read :audit_event permission for any engine role, Kaminari 25/page, dangling-target-safe rendering, #90 reason display on live contracts.\n\n**Expected behavior:** Read-only org-scoped audit index (newest first, paged), contract-filtered via tenant-scoped contract_id param, any engine role admitted, dangling targets render gracefully, #90 review reason displayed on live decision-state contracts.\n\n**Evidence:** `bundle exec rspec` executed (recorded test run).\n\n**Risk:** Low\n\n<!-- agent-review:session=54a881af-6d32-4e7c-a6b6-5c9c14c22113;change=4fa1dda2-92d7-4b00-b687-9134fa8a2f7c;version=1 -->",
++      "body": "### Agent context\n\n**What changed:** added — Claude Code permissions\n\n**Why:** Mirror opencode.jsonc permissions\n\n**Expected behavior:** git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied\n\n**Evidence:** `bundle exec rspec` executed (recorded test run).\n\n**Risk:** Low — edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates\n\n<!-- agent-review:session=d89b86e3-d25a-4b4e-aa50-1bd7560e389d;change=6c1abf82-4513-47c1-a072-4edf4f90e454;version=1 -->",
+       "risk": "low",
+       "evidenceRefs": [
+         "test_001"
+       ],
+       "status": "preview"
++    },
++    {
++      "id": "comment_002",
++      "logicalChangeId": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
++      "path": ".claude/skills/agent-review",
++      "line": 1,
++      "side": "RIGHT",
++      "body": "### Agent context\n\n**What changed:** added — agent-review skill, MCP servers and journaling hook\n\n**Why:** Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers\n\n**Expected behavior:** Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active\n\n**Evidence:** `agent-review npm test: 70/70 pass incl. MCP listTools + hook mapping; stdio smoke call agent_review_status returned status inactive` executed.\n\n**Risk:** Medium — Absolute machine paths in .mcp.json (same as opencode.jsonc); Hook assumes agent-review is a sibling checkout; Skill is a symlink into ../agent-review\n\n<!-- agent-review:session=d89b86e3-d25a-4b4e-aa50-1bd7560e389d;change=ac3edcfd-5a8f-4604-aae8-ca1d3c290a57;version=1 -->",
++      "risk": "medium",
++      "evidenceRefs": [
++        "test_001"
++      ],
++      "status": "preview"
+     }
+   ]
+ }
+diff --git a/.agent-review/github/pr-body.md b/.agent-review/github/pr-body.md
+index d8a5596..bc6bef9 100644
+--- a/.agent-review/github/pr-body.md
++++ b/.agent-review/github/pr-body.md
+@@ -1,26 +1,33 @@
+ # Agent Review
  
--            <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.published_on") %></dt>
--            <dd class="text-md text-black mt-0"><%= amendment.published_at&.to_date&.to_fs(:db) %></dd>
-+            <% if amendment.published_at.present? %>
-+              <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.published_on") %></dt>
-+              <dd class="text-md text-black mt-0"><%= format_date(amendment.published_at) %></dd>
-+            <% end %>
+ ## Summary
+-- 1 logical changes / 23 files changed
+-- Tests: 1 passed (2 failed/error)
+-- Risks: 1 low
++- 5 logical changes / 74 files changed
++- Tests: 1 passed
++- Risks: 1 medium, 4 low
  
-             <% amendment.content_snapshot.to_h.each do |field, value| %>
-               <% next if value.blank? %>
-               <% if field == "crz_url" %>
-                 <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.crz_url") %></dt>
-                 <dd class="text-md text-black mt-0"><%= link_to value, value %></dd>
-+              <% elsif field == "amount" %>
-+                <%# The frozen amount renders through the same locale-aware
-+                    helper as the live fields (#81); the currency renders
-+                    under its own row, exactly as stored. %>
-+                <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.amount") %></dt>
-+                <dd class="text-md text-black mt-0"><%= format_amount(value) %></dd>
-               <% else %>
-                 <dt class="text-sm text-gray-2"><%= t("decidim.contracts_sk.contract.#{field}") %></dt>
-                 <dd class="text-md text-black mt-0"><%= value %></dd>
-diff --git a/config/locales/en.yml b/config/locales/en.yml
-index 1b6c4cb..9bcc9a8 100644
---- a/config/locales/en.yml
-+++ b/config/locales/en.yml
-@@ -33,6 +33,8 @@ en:
-         heading: "CRZ handoff aid"
-         disclaimer: "This document is a handoff aid for the CRZ record — not a legal publication."
-         generated_on: "Generated on"
-+      date_formats:
-+        default: "%Y-%m-%d"
-       menu:
-         contracts: "Contracts"
-         admin_contracts: "Contracts"
-@@ -140,6 +142,7 @@ en:
-             reference: "Reference"
-             subject_matter: "Subject matter"
-             amount: "Amount"
-+            amount_hint: "Use a dot as the decimal separator (e.g. 1250.50) — comma decimals are rejected."
-             currency: "Currency"
-             signed_on: "Signed on"
-             effective_from: "Effective from"
-@@ -239,6 +242,7 @@ en:
-             role: "Role"
-             name: "Name"
-             ico: "Company ID (IČO)"
-+            ico_hint: "Leave blank or enter exactly 8 digits."
-             address: "Address"
-         documents:
-           index:
-diff --git a/config/locales/sk.yml b/config/locales/sk.yml
-index 12d393e..b9ddf77 100644
---- a/config/locales/sk.yml
-+++ b/config/locales/sk.yml
-@@ -33,6 +33,8 @@ sk:
-         heading: "Pomôcka na odovzdanie do CRZ"
-         disclaimer: "Tento dokument je pomôcka na odovzdanie do CRZ — nie právna publikácia."
-         generated_on: "Vygenerované"
-+      date_formats:
-+        default: "%d. %m. %Y"
-       menu:
-         contracts: "Zmluvy"
-         admin_contracts: "Zmluvy"
-@@ -140,6 +142,7 @@ sk:
-             reference: "Číslo zmluvy"
-             subject_matter: "Predmet zmluvy"
-             amount: "Hodnota"
-+            amount_hint: "Použite bodku ako oddeľovač desatinných miest (napr. 1250.50) — desatinná čiarka nie je prijateľná."
-             currency: "Mena"
-             signed_on: "Dátum podpisu"
-             effective_from: "Dátum účinnosti"
-@@ -239,6 +242,7 @@ sk:
-             role: "Rola"
-             name: "Názov"
-             ico: "IČO"
-+            ico_hint: "Nechajte prázdne alebo zadajte presne 8 číslic."
-             address: "Adresa"
-         documents:
-           index:
-diff --git a/docs/crz-import.md b/docs/crz-import.md
-index bd2ea19..3e9ad7f 100644
---- a/docs/crz-import.md
-+++ b/docs/crz-import.md
-@@ -146,7 +146,7 @@ import writes — mirrors are labelled, never implied to be real-time
- (ADR-002 rule 1, ADR-008 decisions 4/6):
+ ## What changed
+-1. **Audit-trail viewer (civora-org/civora-platform#92)** — The append-only audit trail has no read surface; roles doc promises "view audit trail" to every engine role. Gate-1: single GET /admin/audit_events index, contract filter via tenant-scoped contract_id query param, :read :audit_event permission for any engine role, Kaminari 25/page, dangling-target-safe rendering, #90 reason display on live contracts.
++1. **Claude Code subagents** — Port .opencode/agents to Claude Code subagents so both harnesses share the same roles
++2. **Claude Code slash-command skills** — Port the 9 .opencode/commands to Claude Code skills invoked as /<name>
++3. **agent-review skill, MCP servers and journaling hook** — Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers
++4. **Claude Code permissions** — Mirror opencode.jsonc permissions
++5. **CLAUDE.md and AGENTS.md pointer** — Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router
  
- - **Index card:** the "Externally confirmed" badge plus the mirror date
--  (`imported_at`, rendered as an ISO date). No stale indicator — cards
-+  (`imported_at`, rendered as a localized date). No stale indicator — cards
-   stay lean.
- - **Detail page:** a provenance block with the badge, the mirror date and
-   the preserved attribution note (data via ekosystem.slovensko.digital;
-diff --git a/docs/qa-checklist.md b/docs/qa-checklist.md
-index 891b1c3..b0a4b62 100644
---- a/docs/qa-checklist.md
-+++ b/docs/qa-checklist.md
-@@ -69,7 +69,7 @@ ideally in both `en` and `sk` where noted.
+ ## Evidence
+-- `bundle exec rspec`: FAILED (exit 1)
+-- `env CONTRACTS_SK_DB=1 bundle exec rspec`: FAILED (exit 1)
+ - `bundle exec rspec`: passed
  
- - [ ] The contract edit page links to the audit trail pre-filtered to that record; the link renders for every engine role.
- - [ ] The viewer lists the organization's events newest-first; a contract-filtered view shows the naming banner and the back-to-all link.
--- [ ] Rows show the localized action (lifecycle verbs, redaction confirmation, amendment publish, CRZ import), the target record, the acting user and the ISO date.
-+- [ ] Rows show the localized action (lifecycle verbs, redaction confirmation, amendment publish, CRZ import), the target record, the acting user and the localized date.
- - [ ] A target whose record was deleted renders the localized "record no longer exists" label — no error, no internals (en + sk).
- - [ ] The decision-reason column fills only for records sitting in a decision state (returned/rejected) carrying a reason; everything else stays blank.
- - [ ] Localized empty state when the organization has no events (en + sk); pagination carries the contract filter across pages.
-@@ -80,7 +80,7 @@ ideally in both `en` and `sk` where noted.
- - [ ] Every input labeled, ids unique per page (en + sk).
- - [ ] Confirm dialogs on ALL destroys, amendment publish and contract transitions; keyboard-operable.
- - [ ] Writes are POST/redirect/flash (no re-render on success); 422 re-renders keep values and show errors near the form top.
--- [ ] Money and dates render per convention — **DECISION RECORD**: ISO dates, fixed-point EUR amounts, no locale-dependent grouping (deterministic across hosts).
-+- [ ] Money and dates render per convention — **DECISION RECORD** (civora-org/civora-platform#81): locale-aware rendering — under :sk amounts group thousands with a regular space and use comma decimals ("1 250,50 EUR") and dates render "01. 09. 2026"; under :en the historical ISO dates and fixed-point amounts ("1250.5 EUR") are kept. The date format strings and the sk separators ship with the engine (no host locale data), and the PDF footer stamp is UTC-converted and explicitly labelled "UTC".
- - [ ] Loading states: N/A (no async UI in the engine).
- - [ ] Mixed en/sk content: page `lang` is host-owned; spot-check that engine strings match the active locale even when record content is in the other language.
- - [ ] Keyboard-only full workflow pass: create → edit → parties → documents → redaction confirmation → submit → return → approve → publish → amendment → archive.
-@@ -88,8 +88,9 @@ ideally in both `en` and `sk` where noted.
+ ## Risks and limitations
+-- Working tree was dirty at session start (17 entries) — pre-existing changes may be mixed into the diff.
+-- 2 test run(s) did not pass (exit codes: 1, 1).
++- Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.
++- Large diff: 10373 insertions across 74 files.
+ - Limitation: Snapshots cover only files that were changed at checkpoint time.
+ - Limitation: Symbol extraction is regex-based, not AST-based.
+ - Limitation: Only observed facts are recorded — private model reasoning is not captured.
++- Limitation: The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md
++- Limitation: Absolute machine paths in .mcp.json (same as opencode.jsonc)
++- Limitation: Hook assumes agent-review is a sibling checkout
++- Limitation: Skill is a symlink into ../agent-review
++- Limitation: edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates
  
- ## Known gaps and follow-ups
+ ## Review guidance
+-Start with the inline comments marked `Agent context` (1 comment on the current diff).
++Start with the inline comments marked `Agent context` (2 comments on the current diff).
  
--- Validation errors are visible but not announced to assistive tech; no required-field markers on forms — civora-org/civora-platform#78.
--- Hints for constrained inputs (dot-decimal amount, 8-digit IČO) and currency as a select — civora-org/civora-platform#79.
--- Sparse published records (nil amount / subject matter) render bare labels on the public detail page — civora-org/civora-platform#80.
- - CRZ handoff section disappears on a failed contract update re-render — civora-org/civora-platform#77.
--- Formatting conventions (ISO dates, ungrouped fixed-point money, PDF timestamp without zone) are deliberate V0.1 determinism pending a product decision — civora-org/civora-platform#81.
-+
-+<!-- Resolved by the pilot-demo-ux arc (civora-org/civora-platform#78, #79, #80, #81):
-+     announced/focused 422 error summaries + required markers; amount/IČO hints and
-+     the currency select; guarded blank live fields on the public detail page;
-+     locale-aware money/date rendering and the UTC-labelled PDF stamp. -->
-diff --git a/opencode.jsonc b/opencode.jsonc
-index 79182e2..1feac13 100644
---- a/opencode.jsonc
-+++ b/opencode.jsonc
-@@ -39,6 +39,12 @@
-     }
+ _This summary and the inline comments are review CONTEXT, not guarantees of correctness._
+diff --git a/.agent-review/github/pr-preview.json b/.agent-review/github/pr-preview.json
+index 36a8325..3142db8 100644
+--- a/.agent-review/github/pr-preview.json
++++ b/.agent-review/github/pr-preview.json
+@@ -2,31 +2,44 @@
+   "schemaVersion": "agent-review-pr-preview/v1",
+   "repository": null,
+   "baseBranch": "main",
+-  "headBranch": "m03-92-audit-trail-viewer",
+-  "title": "Admin audit-trail viewer (civora-org/civora-platform#92): read-only org-level + contract-filtered index",
++  "headBranch": "chore/claude-code-config",
++  "title": "Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code",
+   "draft": true,
+   "summary": {
+-    "logicalChanges": 1,
+-    "filesChanged": 23,
++    "logicalChanges": 5,
++    "filesChanged": 74,
+     "testsPassed": 1,
+     "risks": [
+-      "Working tree was dirty at session start (17 entries) — pre-existing changes may be mixed into the diff.",
+-      "2 test run(s) did not pass (exit codes: 1, 1)."
++      "Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.",
++      "Large diff: 10373 insertions across 74 files."
+     ]
    },
-   "mcp": {
-+    "slov-lex": {
-+      "type": "local",
-+      "command": ["node", "/Users/denyskozlov/.local/share/slov-lex-mcp/dist/index.js"],
-+      "enabled": true,
-+      "environment": {}
+   "inlineComments": [
+     {
+       "id": "comment_001",
+-      "logicalChangeId": "4fa1dda2-92d7-4b00-b687-9134fa8a2f7c",
+-      "path": "config/routes.rb",
+-      "line": 82,
++      "logicalChangeId": "6c1abf82-4513-47c1-a072-4edf4f90e454",
++      "path": ".claude/settings.json",
++      "line": 1,
+       "side": "RIGHT",
+-      "body": "### Agent context\n\n**What changed:** added — Audit-trail viewer (civora-org/civora-platform#92)\n\n**Why:** The append-only audit trail has no read surface; roles doc promises \"view audit trail\" to every engine role. Gate-1: single GET /admin/audit_events index, contract filter via tenant-scoped contract_id query param, :read :audit_event permission for any engine role, Kaminari 25/page, dangling-target-safe rendering, #90 reason display on live contracts.\n\n**Expected behavior:** Read-only org-scoped audit index (newest first, paged), contract-filtered via tenant-scoped contract_id param, any engine role admitted, dangling targets render gracefully, #90 review reason displayed on live decision-state contracts.\n\n**Evidence:** `bundle exec rspec` executed (recorded test run).\n\n**Risk:** Low\n\n<!-- agent-review:session=54a881af-6d32-4e7c-a6b6-5c9c14c22113;change=4fa1dda2-92d7-4b00-b687-9134fa8a2f7c;version=1 -->",
++      "body": "### Agent context\n\n**What changed:** added — Claude Code permissions\n\n**Why:** Mirror opencode.jsonc permissions\n\n**Expected behavior:** git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied\n\n**Evidence:** `bundle exec rspec` executed (recorded test run).\n\n**Risk:** Low — edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates\n\n<!-- agent-review:session=d89b86e3-d25a-4b4e-aa50-1bd7560e389d;change=6c1abf82-4513-47c1-a072-4edf4f90e454;version=1 -->",
+       "risk": "low",
+       "evidenceRefs": [
+         "test_001"
+       ],
+       "status": "preview"
 +    },
-     "playwright": {
-       "type": "local",
-       "command": ["npx", "-y", "@playwright/mcp@latest"],
-diff --git a/spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb b/spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb
-index d6549ce..828a097 100644
---- a/spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb
-+++ b/spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb
-@@ -90,4 +90,13 @@ RSpec.describe Decidim::ContractsSk::CrzHandoffPdf do
++    {
++      "id": "comment_002",
++      "logicalChangeId": "ac3edcfd-5a8f-4604-aae8-ca1d3c290a57",
++      "path": ".claude/skills/agent-review",
++      "line": 1,
++      "side": "RIGHT",
++      "body": "### Agent context\n\n**What changed:** added — agent-review skill, MCP servers and journaling hook\n\n**Why:** Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers\n\n**Expected behavior:** Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active\n\n**Evidence:** `agent-review npm test: 70/70 pass incl. MCP listTools + hook mapping; stdio smoke call agent_review_status returned status inactive` executed.\n\n**Risk:** Medium — Absolute machine paths in .mcp.json (same as opencode.jsonc); Hook assumes agent-review is a sibling checkout; Skill is a symlink into ../agent-review\n\n<!-- agent-review:session=d89b86e3-d25a-4b4e-aa50-1bd7560e389d;change=ac3edcfd-5a8f-4604-aae8-ca1d3c290a57;version=1 -->",
++      "risk": "medium",
++      "evidenceRefs": [
++        "test_001"
++      ],
++      "status": "preview"
+     }
+   ],
+   "fileLevelNotes": [],
+diff --git a/.agent-review/github/publish-plan.md b/.agent-review/github/publish-plan.md
+index 34b0c19..3b03510 100644
+--- a/.agent-review/github/publish-plan.md
++++ b/.agent-review/github/publish-plan.md
+@@ -1,9 +1,10 @@
+ # Publish plan
  
-     expect { pdf_bytes }.not_to raise_error
-   end
-+
-+  it "labels the footer generation stamp with an explicit UTC zone (civora-org/civora-platform#81)" do
-+    # Byte-level content assertions are impossible (font-subset encoding —
-+    # see the header), so the stamp is asserted through the method the
-+    # footer draws: UTC-converted digits plus the zone label.
-+    stamp = described_class.new(contract).send(:generated_stamp)
-+
-+    expect(stamp).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC\z/)
-+  end
- end
-diff --git a/spec/decidim/contracts_sk_locales_spec.rb b/spec/decidim/contracts_sk_locales_spec.rb
-index cae4d40..202b223 100644
---- a/spec/decidim/contracts_sk_locales_spec.rb
-+++ b/spec/decidim/contracts_sk_locales_spec.rb
-@@ -448,6 +448,25 @@ module LocaleContract
-   }.freeze
-   # rubocop:enable Style/FormatStringToken
+-- Draft PR: `m03-92-audit-trail-viewer` → `main`
+-- Title: Admin audit-trail viewer (civora-org/civora-platform#92): read-only org-level + contract-filtered index
+-- Inline comments: 1
+-  - `config/routes.rb`:82
++- Draft PR: `chore/claude-code-config` → `main`
++- Title: Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code
++- Inline comments: 2
++  - `.claude/settings.json`:1
++  - `.claude/skills/agent-review`:1
+ - Skipped: 0
  
-+  # The admin form hints and the engine-shipped date format per locale
-+  # (civora-org/civora-platform#79, #81). The date format is a strftime
-+  # STRING resolved by the engine's format_date helper — never a named I18n
-+  # format, so no host-app or rails-i18n locale data is ever required.
-+  FORM_HINT_AND_DATE_FORMAT_LABELS = {
-+    en: {
-+      "admin.contracts.form.amount_hint" =>
-+        "Use a dot as the decimal separator (e.g. 1250.50) — comma decimals are rejected.",
-+      "admin.parties.form.ico_hint" => "Leave blank or enter exactly 8 digits.",
-+      "date_formats.default" => "%Y-%m-%d"
-+    },
-+    sk: {
-+      "admin.contracts.form.amount_hint" =>
-+        "Použite bodku ako oddeľovač desatinných miest (napr. 1250.50) — desatinná čiarka nie je prijateľná.",
-+      "admin.parties.form.ico_hint" => "Nechajte prázdne alebo zadajte presne 8 číslic.",
-+      "date_formats.default" => "%d. %m. %Y"
-+    }
-+  }.freeze
-+
-   # The exact expected leaf-key surface under decidim.contracts_sk, including
-   # the public catalogue keys (plan Option B of #39), the admin CRUD keys
-   # (civora-org/civora-platform#58), the admin content-field form keys
-@@ -514,6 +533,7 @@ module LocaleContract
-     "admin.contracts.create.success",
-     "admin.contracts.edit.title",
-     "admin.contracts.form.amount",
-+    "admin.contracts.form.amount_hint",
-     "admin.contracts.form.crz_url",
-     "admin.contracts.form.currency",
-     "admin.contracts.form.effective_from",
-@@ -628,6 +648,7 @@ module LocaleContract
-     "admin.parties.edit.title",
-     "admin.parties.form.address",
-     "admin.parties.form.ico",
-+    "admin.parties.form.ico_hint",
-     "admin.parties.form.name",
-     "admin.parties.form.role",
-     "admin.parties.index.empty",
-@@ -678,6 +699,7 @@ module LocaleContract
-     "crz_handoff_pdf.disclaimer",
-     "crz_handoff_pdf.generated_on",
-     "crz_handoff_pdf.heading",
-+    "date_formats.default",
-     "menu.admin_contracts",
-     "menu.contracts",
-     "pagination.aria_label",
-@@ -1035,6 +1057,14 @@ RSpec.describe Decidim::ContractsSk do
-       end
-     end
+ Nothing has been pushed or published. Publishing requires explicit user confirmation.
+diff --git a/.agent-review/review.md b/.agent-review/review.md
+index 7e84630..9f72e43 100644
+--- a/.agent-review/review.md
++++ b/.agent-review/review.md
+@@ -1,38 +1,47 @@
+ # Agent Review
  
-+    it "translates the admin form hints and the engine date format in both locales (#79, #81)" do
-+      LocaleContract::FORM_HINT_AND_DATE_FORMAT_LABELS.each do |locale, labels|
-+        labels.each do |key, value|
-+          expect(backend.translate(locale, "decidim.contracts_sk.#{key}")).to eq(value)
-+        end
-+      end
-+    end
-+
-     it "keeps the established Slovak party terminology on the public detail page (civora-org/civora-platform#63)" do
-       PublicCatalogueLabels::PARTY_ROLE_LABELS.each do |locale, labels|
-         labels.each do |role, value|
-diff --git a/spec/requests/admin/amendments_spec.rb b/spec/requests/admin/amendments_spec.rb
-index e93822c..c314b75 100644
---- a/spec/requests/admin/amendments_spec.rb
-+++ b/spec/requests/admin/amendments_spec.rb
-@@ -346,6 +346,14 @@ RSpec.describe "admin amendment management", type: :request do
-       expect(response).to have_http_status(:unprocessable_entity)
-       expect(flash[:alert]).to be_present
-       expect(Decidim::ContractsSk::Amendment.count).to eq(0)
-+      # The re-rendered form (civora-org/civora-platform#78): the announced,
-+      # focused error summary and the required attribute on the
-+      # presence-validated summary input.
-+      aggregate_failures do
-+        expect(response.body).to include('role="alert"')
-+        expect(response.body).to include("autofocus")
-+        expect(response.body).to include('required="required"')
-+      end
-     end
+ ## Task
+-Pilot demo UX polish: guard blank live fields on public detail (#80), admin form a11y (#78), input hints + currency select (#79), localized money/date rendering + PDF timestamp UTC label (#81)
++Migrate OpenCode agents, commands, agent-review skill, MCP servers and permissions to Claude Code
  
-     it "denies a reviewer-only user on create" do
-diff --git a/spec/requests/admin/contracts_spec.rb b/spec/requests/admin/contracts_spec.rb
-index afa7649..e1b3935 100644
---- a/spec/requests/admin/contracts_spec.rb
-+++ b/spec/requests/admin/contracts_spec.rb
-@@ -409,6 +409,33 @@ RSpec.describe "admin contracts CRUD", type: :request do
-     end
-   end
+ ## Session
+-- Session ID: 6b2892c2-9985-4b7a-9031-fc723f7302c9
+-- Branch: polish/pilot-demo-ux
+-- Started: 2026-09-28T15:48:32.593Z
+-- Finished: 2026-09-28T16:25:37.886Z
++- Session ID: d89b86e3-d25a-4b4e-aa50-1bd7560e389d
++- Branch: chore/claude-code-config
++- Started: 2026-10-02T22:26:31.118Z
++- Finished: 2026-10-02T22:27:52.305Z
  
-+  describe "contract form rendering (offline, DB-free, civora-org/civora-platform#78, #79)" do
-+    it "renders the accessible amount hint, the decimal input mode and the currency select" do
-+      sign_in(roles: %i[editor])
-+
-+      get "/admin/contracts/new"
-+
-+      expect(response).to have_http_status(:ok)
-+      aggregate_failures do
-+        # Amount input (#79): decimal keyboard hint plus the localized
-+        # dot-decimal hint, wired through aria-describedby to the hint's id.
-+        expect(response.body).to include('inputmode="decimal"')
-+        expect(response.body).to include('aria-describedby="contract_amount_hint"')
-+        expect(response.body).to include('id="contract_amount_hint"')
-+        expect(response.body).to include("Use a dot as the decimal separator")
-+        # Currency (#79): a select over the allowlist with the default
-+        # selected — never the free-text input again.
-+        expect(response.body).to include(">EUR</option>")
-+        expect(response.body).to include("selected=")
-+        expect(response.body).not_to match(/<input[^>]*name="contract\[currency\]"/)
-+        # Presence-validated identity inputs carry the required attribute
-+        # (#78) — exactly two: title and reference.
-+        expect(response.body.scan('required="required"').size).to eq(2)
-+        expect(response.body).to include("label-required")
-+      end
-+    end
-+  end
-+
-   describe "allowed and validation paths", :db do
-     # The current_user belongs to the stubbed organization, like a real
-     # signed-in editor — CreateContract's tenancy guard reads
-@@ -587,6 +614,13 @@ RSpec.describe "admin contracts CRUD", type: :request do
+ ## Summary
+-Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.html.erb): civora-org/civora-platform#80: the live dt/dd pairs (and the metadata line's date/amount spans) render unconditionally except crz_url, so a sparse published record shows an empty subject dd and a dangling EUR dd; each optional pair is now guarded on value presence, mirroring the frozen-snapshot section and the PDF export which already drop blank rows; title/reference stay unconditional (NOT NULL) Admin form partials accessibility (contracts/parties/documents/amendments _form.html.erb): civora-org/civora-platform#78: validation-error summaries render as a bare ul on 422 re-render and presence-validated inputs carry no required attribute; the ul gets role="alert" tabindex="-1" autofocus and required: true lands on contract title/reference, party name, amendment summary, document file — minimal engine-side a11y, matching the Decidim FormBuilder's supported field options Admin contract form amount input + IČO hint + currency select: civora-org/civora-platform#79: the amount field accepts only dot-decimals (STRICT_AMOUNT_FORMAT on the form) but says nothing about it, the IČO format rule is invisible to editors, and currency is a free-text input over a one-entry allowlist; hints get explicit ids wired with aria-describedby (the pinned Decidim FormBuilder's help_text: option renders neither id nor aria), and the select copies the role/kind select pattern over the frozen vocabulary Localized money/date rendering + CRZ handoff PDF timestamp zone label: civora-org/civora-platform#81: "1250.5 EUR" renders locale-blind while the audience is Slovak, every date renders naive to_fs(:db), and the PDF footer stamps a naive server-local time with no zone; a small helper in the base ApplicationHelper (number_with_precision with explicit sk separators; I18n.l with an explicit engine-shipped format string — the harness has no rails-i18n sk data, so named formats/day names would not resolve) replaces every to_fs(:db) date render and both amount renders, and the PDF footer converts to UTC explicitly
++Claude Code subagents: Port .opencode/agents to Claude Code subagents so both harnesses share the same roles Claude Code slash-command skills: Port the 9 .opencode/commands to Claude Code skills invoked as /<name> agent-review skill, MCP servers and journaling hook: Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers Claude Code permissions: Mirror opencode.jsonc permissions CLAUDE.md and AGENTS.md pointer: Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router
  
-       expect(response).to have_http_status(:unprocessable_entity)
-       expect(Decidim::ContractsSk::Contract.count).to eq(0)
-+      # The re-rendered form's error summary is announced and focused
-+      # (civora-org/civora-platform#78) — a bare ul is an a11y regression.
-+      aggregate_failures do
-+        expect(response.body).to include('role="alert"')
-+        expect(response.body).to include('tabindex="-1"')
-+        expect(response.body).to include("autofocus")
-+      end
-     end
+ ## Logical Changes
  
-     it "answers 422 and persists nothing on a duplicate (organization, reference)" do
-diff --git a/spec/requests/admin/documents_spec.rb b/spec/requests/admin/documents_spec.rb
-index 41022a2..36def87 100644
---- a/spec/requests/admin/documents_spec.rb
-+++ b/spec/requests/admin/documents_spec.rb
-@@ -386,6 +386,14 @@ RSpec.describe "admin document management", type: :request do
+-### 1. Localized money/date rendering + CRZ handoff PDF timestamp zone label
+-- What changed: modified in `app/helpers/decidim/contracts_sk/application_helper.rb`, `app/views/decidim/contracts_sk/contracts/show.html.erb`, `app/views/decidim/contracts_sk/contracts/index.html.erb`, `app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb`, `app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb`, `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb`, `app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb`, `config/locales/en.yml`, `config/locales/sk.yml`
+-- Why: civora-org/civora-platform#81: "1250.5 EUR" renders locale-blind while the audience is Slovak, every date renders naive to_fs(:db), and the PDF footer stamps a naive server-local time with no zone; a small helper in the base ApplicationHelper (number_with_precision with explicit sk separators; I18n.l with an explicit engine-shipped format string — the harness has no rails-i18n sk data, so named formats/day names would not resolve) replaces every to_fs(:db) date render and both amount renders, and the PDF footer converts to UTC explicitly
+-- Expected behavior: Amounts render locale-aware: sk "1 250,50 EUR" (regular-space grouping, comma decimals — documented decision), en keeps the current fixed-point "1250.5 EUR"; dates render through a thin format_date helper backed by engine-shipped date_formats.default keys (sk "%d. %m. %Y", en "%Y-%m-%d" — no host-app locale data dependency); the PDF footer timestamp renders Time.current converted to UTC with an explicit " UTC" suffix; helper is PORO-safe (included by the PDF class)
++### 1. agent-review skill, MCP servers and journaling hook
++- What changed: added in `.claude/skills/agent-review`, `.mcp.json`, `.claude/settings.json`
++- Why: Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers
++- Expected behavior: Tools appear as mcp__agent-review__agent_review_*; Edit/Write/Bash calls are journaled to .agent-review/events.jsonl only while a session is active
+ - Risk: medium
+-### 2. Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.html.erb)
+-- What changed: modified in `app/views/decidim/contracts_sk/contracts/show.html.erb`
+-- Why: civora-org/civora-platform#80: the live dt/dd pairs (and the metadata line's date/amount spans) render unconditionally except crz_url, so a sparse published record shows an empty subject dd and a dangling EUR dd; each optional pair is now guarded on value presence, mirroring the frozen-snapshot section and the PDF export which already drop blank rows; title/reference stay unconditional (NOT NULL)
+-- Expected behavior: A published record carrying only title+reference renders no empty subject dd, no dangling EUR dd/span, no empty published-on/signed-on/effective-from dds; a full record renders unchanged; the metadata line under the title hides its date/amount spans when blank
++- Limitations: Absolute machine paths in .mcp.json (same as opencode.jsonc); Hook assumes agent-review is a sibling checkout; Skill is a symlink into ../agent-review
++### 2. Claude Code subagents
++- What changed: added in `.claude/agents/architect.md`, `.claude/agents/reviewer.md`, `.claude/agents/rails.md`, `.claude/agents/tester.md`, `.claude/agents/integration.md`, `.claude/agents/retro.md`
++- Why: Port .opencode/agents to Claude Code subagents so both harnesses share the same roles
++- Expected behavior: architect/reviewer run on opus with read-only tools; rails/tester/integration/retro on sonnet; bodies identical to the OpenCode agents
+ - Risk: low
+-### 3. Admin form partials accessibility (contracts/parties/documents/amendments _form.html.erb)
+-- What changed: modified in `app/views/decidim/contracts_sk/admin/contracts/_form.html.erb`, `app/views/decidim/contracts_sk/admin/parties/_form.html.erb`, `app/views/decidim/contracts_sk/admin/documents/_form.html.erb`, `app/views/decidim/contracts_sk/admin/amendments/_form.html.erb`
+-- Why: civora-org/civora-platform#78: validation-error summaries render as a bare ul on 422 re-render and presence-validated inputs carry no required attribute; the ul gets role="alert" tabindex="-1" autofocus and required: true lands on contract title/reference, party name, amendment summary, document file — minimal engine-side a11y, matching the Decidim FormBuilder's supported field options
+-- Expected behavior: On a 422 re-render the error summary ul carries role="alert" tabindex="-1" autofocus; the presence-validated inputs render the required HTML attribute; no field-level aria-invalid/aria-describedby beyond the item-3 hints
++- Alternatives considered: Keep GLM-only OpenCode agents
++- Limitations: The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md
++### 3. Claude Code slash-command skills
++- What changed: added in `.claude/skills/issue/SKILL.md`, `.claude/skills/feature/SKILL.md`, `.claude/skills/review/SKILL.md`, `.claude/skills/verify/SKILL.md`, `.claude/skills/retro/SKILL.md`, `.claude/skills/agent-review-github-status/SKILL.md`, `.claude/skills/agent-review-prepare-pr/SKILL.md`, `.claude/skills/agent-review-publish-pr/SKILL.md`, `.claude/skills/agent-review-update-review/SKILL.md`
++- Why: Port the 9 .opencode/commands to Claude Code skills invoked as /<name>
++- Expected behavior: /issue reads civora-org/civora-platform issues via gh; publish-pr, update-review and retro are user-invoked only (disable-model-invocation)
+ - Risk: low
+-### 4. Admin contract form amount input + IČO hint + currency select
+-- What changed: modified in `app/views/decidim/contracts_sk/admin/contracts/_form.html.erb`, `app/views/decidim/contracts_sk/admin/parties/_form.html.erb`, `config/locales/en.yml`, `config/locales/sk.yml`, `spec/decidim/contracts_sk_locales_spec.rb`
+-- Why: civora-org/civora-platform#79: the amount field accepts only dot-decimals (STRICT_AMOUNT_FORMAT on the form) but says nothing about it, the IČO format rule is invisible to editors, and currency is a free-text input over a one-entry allowlist; hints get explicit ids wired with aria-describedby (the pinned Decidim FormBuilder's help_text: option renders neither id nor aria), and the select copies the role/kind select pattern over the frozen vocabulary
+-- Expected behavior: Amount input carries inputmode="decimal" and aria-describedby pointing at a localized hint that only dot-decimals are accepted; IČO input carries a localized blank-or-8-digits hint wired the same way; currency renders as a select over Contract::SUPPORTED_CURRENCIES (selected preserved) instead of a free-text input; hints shipped in en.yml and sk.yml and registered in the locale key-surface contract
++### 4. Claude Code permissions
++- What changed: added in `.claude/settings.json`
++- Why: Mirror opencode.jsonc permissions
++- Expected behavior: git status/diff/log allowed; branch/commit/push/pull/docker compose/web ask; git reset/clean, rm, docker system prune, db drop/reset denied
++- Risk: low
++- Limitations: edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates
++### 5. CLAUDE.md and AGENTS.md pointer
++- What changed: added in `CLAUDE.md`, `AGENTS.md`
++- Why: Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router
++- Expected behavior: CLAUDE.md imports @AGENTS.md; AGENTS.md lists the Claude Code mirror to keep in sync
+ - Risk: low
  
-       expect(response).to have_http_status(:unprocessable_entity)
-       expect(Decidim::ContractsSk::Document.count).to eq(0)
-+      # The re-rendered form (civora-org/civora-platform#78): the announced
-+      # error summary and the required attribute on the presence-validated
-+      # file input.
-+      aggregate_failures do
-+        expect(response.body).to include('role="alert"')
-+        expect(response.body).to include("autofocus")
-+        expect(response.body).to include('required="required"')
-+      end
-     end
+ ## Test Evidence
+@@ -40,1016 +49,4439 @@ Public contract detail rendering (app/views/decidim/contracts_sk/contracts/show.
+ ### Run 1
+ - Command: `bundle exec rspec`
+ - Result: **passed** (exit code: 0)
+-- Duration: 6330 ms
+-- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
+-### Run 2
+-- Command: `bundle exec rspec`
+-- Result: **passed** (exit code: 0)
+-- Duration: 8669 ms
+-- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
+-### Run 3
+-- Command: `CONTRACTS_SK_DB=1 bundle exec rspec`
+-- Result: **error** (exit code: signal)
+-- Duration: 8 ms
+-- Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
+-- Notes: stderr captured (1 lines, redacted and truncated)
+-### Run 4
+-- Command: `env CONTRACTS_SK_DB=1 bundle exec rspec`
+-- Result: **passed** (exit code: 0)
+-- Duration: 50489 ms
++- Duration: 3133 ms
+ - Working directory: `/Users/denyskozlov/Code/decidim-contracts_sk`
  
-     it "answers 422 with the alert and persists nothing when the kind is outside the vocabulary" do
-diff --git a/spec/requests/admin/parties_spec.rb b/spec/requests/admin/parties_spec.rb
-index b2eb2b6..4c81cdd 100644
---- a/spec/requests/admin/parties_spec.rb
-+++ b/spec/requests/admin/parties_spec.rb
-@@ -290,6 +290,16 @@ RSpec.describe "admin party management", type: :request do
-       expect(response).to have_http_status(:unprocessable_entity)
-       expect(flash[:alert]).to be_present
-       expect(Decidim::ContractsSk::Party.count).to eq(0)
-+      # The re-rendered form (civora-org/civora-platform#78, #79): the
-+      # error summary is announced/focused, the required name input carries
-+      # the attribute, and the IČO hint is wired through aria-describedby.
-+      aggregate_failures do
-+        expect(response.body).to include('role="alert"')
-+        expect(response.body).to include("autofocus")
-+        expect(response.body).to include('aria-describedby="party_ico_hint"')
-+        expect(response.body).to include("Leave blank or enter exactly 8 digits.")
-+        expect(response.body).to include('required="required"')
-+      end
-     end
+ ## Risks
+-- Working tree was dirty at session start (17 entries) — pre-existing changes may be mixed into the diff.
+-- 1 test run(s) did not pass (exit codes: signal).
++- Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.
++- Large diff: 10373 insertions across 74 files.
  
-     it "answers 422 with the alert and persists nothing when the role is outside the vocabulary" do
-diff --git a/spec/requests/contracts_spec.rb b/spec/requests/contracts_spec.rb
-index 8ca259f..639a844 100644
---- a/spec/requests/contracts_spec.rb
-+++ b/spec/requests/contracts_spec.rb
-@@ -402,6 +402,37 @@ RSpec.describe "public contracts catalogue", type: :request do
-       end
-     end
+ ## Limitations
+ - Snapshots cover only files that were changed at checkpoint time.
+ - Symbol extraction is regex-based, not AST-based.
+ - Only observed facts are recorded — private model reasoning is not captured.
++- The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md
++- Absolute machine paths in .mcp.json (same as opencode.jsonc)
++- Hook assumes agent-review is a sibling checkout
++- Skill is a symlink into ../agent-review
++- edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates
  
-+    it "renders no blank field rows for a sparse published record (civora-org/civora-platform#80)" do
-+      # Only the identity is filled: every optional live field is blank —
-+      # the exact shape that used to render an empty subject dd and a
-+      # dangling "EUR" dd (and metadata spans).
-+      sparse = detail_contract_double(
-+        published_at: Time.new(2026, 9, 1, 12, 0, 0),
-+        subject_matter: nil,
-+        amount: nil,
-+        signed_on: nil,
-+        effective_from: nil,
-+        crz_url: nil
-+      )
-+      stub_published_contracts(double(find: sparse))
+ ## Changed Files
+-- `.opencode/commands/agent-review-github-status.md` — added (markdown, +16/−0)
+-- `.opencode/commands/agent-review-prepare-pr.md` — added (markdown, +19/−0)
+-- `.opencode/commands/agent-review-publish-pr.md` — added (markdown, +19/−0)
+-- `.opencode/commands/agent-review-update-review.md` — added (markdown, +16/−0)
+-- `.opencode/plugins/agent-review.ts` — added (typescript, +357/−0)
+-- `.opencode/skills/agent-review` — added (unknown, +0/−0)
+-- `AGENTS.md` — modified (markdown, +2/−0)
+-- `app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb` — modified (ruby, +1/−7)
+-- `app/helpers/decidim/contracts_sk/application_helper.rb` — modified (ruby, +67/−0)
+-- `app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb` — modified (ruby, +28/−9)
+-- `app/views/decidim/contracts_sk/admin/amendments/_form.html.erb` — modified (unknown, +6/−4)
+-- `app/views/decidim/contracts_sk/admin/audit_events/index.html.erb` — modified (unknown, +4/−1)
+-- `app/views/decidim/contracts_sk/admin/contracts/_form.html.erb` — modified (unknown, +25/−7)
+-- `app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb` — modified (unknown, +1/−1)
+-- `app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb` — modified (unknown, +1/−1)
+-- `app/views/decidim/contracts_sk/admin/documents/_form.html.erb` — modified (unknown, +6/−3)
+-- `app/views/decidim/contracts_sk/admin/parties/_form.html.erb` — modified (unknown, +8/−5)
+-- `app/views/decidim/contracts_sk/contracts/index.html.erb` — modified (unknown, +5/−4)
+-- `app/views/decidim/contracts_sk/contracts/show.html.erb` — modified (unknown, +54/−22)
++- `.agent-review/change-package.json` — modified (json, +512/−290)
++- `.agent-review/review.md` — modified (markdown, +2619/−935)
++- `.claude/agents/architect.md` — modified (markdown, +39/−0)
++- `.claude/agents/integration.md` — modified (markdown, +34/−0)
++- `.claude/agents/rails.md` — modified (markdown, +27/−0)
++- `.claude/agents/retro.md` — modified (markdown, +24/−0)
++- `.claude/agents/reviewer.md` — modified (markdown, +35/−0)
++- `.claude/agents/tester.md` — modified (markdown, +36/−0)
++- `.claude/settings.json` — modified (json, +56/−0)
++- `.claude/skills/agent-review` — modified (unknown, +1/−0)
++- `.claude/skills/agent-review-github-status/SKILL.md` — modified (markdown, +21/−0)
++- `.claude/skills/agent-review-prepare-pr/SKILL.md` — modified (markdown, +25/−0)
++- `.claude/skills/agent-review-publish-pr/SKILL.md` — modified (markdown, +26/−0)
++- `.claude/skills/agent-review-update-review/SKILL.md` — modified (markdown, +23/−0)
++- `.claude/skills/feature/SKILL.md` — modified (markdown, +22/−0)
++- `.claude/skills/issue/SKILL.md` — modified (markdown, +23/−0)
++- `.claude/skills/retro/SKILL.md` — modified (markdown, +21/−0)
++- `.claude/skills/review/SKILL.md` — modified (markdown, +19/−0)
++- `.claude/skills/verify/SKILL.md` — modified (markdown, +20/−0)
++- `.impeccable/surfaces/site-index-html.md` — added (markdown, +17/−0)
++- `.mcp.json` — modified (json, +16/−0)
++- `.playwright-mcp/console-2026-09-29T20-39-02-278Z.log` — added (unknown, +71/−0)
++- `.playwright-mcp/console-2026-09-29T20-40-14-925Z.log` — added (unknown, +163/−0)
++- `.playwright-mcp/console-2026-09-29T20-51-39-769Z.log` — added (unknown, +23/−0)
++- `.playwright-mcp/console-2026-09-29T20-54-04-239Z.log` — added (unknown, +25/−0)
++- `.playwright-mcp/console-2026-09-29T20-58-03-864Z.log` — added (unknown, +23/−0)
++- `.playwright-mcp/console-2026-09-29T20-59-13-047Z.log` — added (unknown, +69/−0)
++- `.playwright-mcp/console-2026-09-29T21-00-11-311Z.log` — added (unknown, +172/−0)
++- `.playwright-mcp/console-2026-09-29T21-18-30-180Z.log` — added (unknown, +344/−0)
++- `.playwright-mcp/page-2026-09-29T20-39-03-419Z.yml` — added (yaml, +129/−0)
++- `.playwright-mcp/page-2026-09-29T20-39-28-693Z.yml` — added (yaml, +133/−0)
++- `.playwright-mcp/page-2026-09-29T20-40-15-321Z.yml` — added (yaml, +129/−0)
++- `.playwright-mcp/page-2026-09-29T20-51-40-347Z.yml` — added (yaml, +110/−0)
++- `.playwright-mcp/page-2026-09-29T20-54-04-656Z.yml` — added (yaml, +295/−0)
++- `.playwright-mcp/page-2026-09-29T20-58-04-515Z.yml` — added (yaml, +113/−0)
++- `.playwright-mcp/page-2026-09-29T20-59-13-652Z.yml` — added (yaml, +107/−0)
++- `.playwright-mcp/page-2026-09-29T21-00-11-526Z.yml` — added (yaml, +111/−0)
++- `.playwright-mcp/page-2026-09-29T21-18-30-824Z.yml` — added (yaml, +285/−0)
++- `AGENTS.md` — modified (markdown, +1/−0)
++- `app/helpers/decidim/contracts_sk/application_helper.rb` — modified (ruby, +38/−0)
++- `app/views/decidim/contracts_sk/admin/audit_events/index.html.erb` — modified (unknown, +19/−6)
++- `app/views/decidim/contracts_sk/contracts/index.html.erb` — modified (unknown, +87/−64)
++- `app/views/decidim/contracts_sk/contracts/show.html.erb` — modified (unknown, +278/−249)
++- `app/views/decidim/contracts_sk/shared/_public_styles.html.erb` — added (unknown, +108/−0)
++- `CLAUDE.md` — modified (markdown, +25/−0)
+ - `config/locales/en.yml` — modified (yaml, +4/−0)
+ - `config/locales/sk.yml` — modified (yaml, +4/−0)
+-- `docs/crz-import.md` — modified (markdown, +1/−1)
+-- `docs/qa-checklist.md` — modified (markdown, +7/−6)
+-- `opencode.jsonc` — modified (unknown, +6/−0)
+-- `spec/decidim/contracts_sk_locales_spec.rb` — modified (ruby, +30/−0)
+-- `spec/decidim/contracts_sk/application_helper_spec.rb` — added (ruby, +116/−0)
+-- `spec/decidim/contracts_sk/crz_handoff_pdf_spec.rb` — modified (ruby, +9/−0)
+-- `spec/requests/admin/amendments_spec.rb` — modified (ruby, +8/−0)
+-- `spec/requests/admin/contracts_spec.rb` — modified (ruby, +34/−0)
+-- `spec/requests/admin/documents_spec.rb` — modified (ruby, +8/−0)
+-- `spec/requests/admin/parties_spec.rb` — modified (ruby, +10/−0)
+-- `spec/requests/contracts_spec.rb` — modified (ruby, +31/−0)
++- `demo-catalogue.png` — added (unknown, +151/−0)
++- `docs/sales/cold-email-templates.sk.md` — added (markdown, +70/−0)
++- `docs/sales/demo-script.sk.md` — added (markdown, +72/−0)
++- `docs/sales/dpa-lawyer-checklist.md` — added (markdown, +27/−0)
++- `docs/sales/dpa-zoou-template.sk.md` — added (markdown, +117/−0)
++- `docs/sales/offer-template.sk.md` — added (markdown, +79/−0)
++- `docs/sales/one-pager.sk.md` — added (markdown, +54/−0)
++- `docs/sales/README.md` — added (markdown, +36/−0)
++- `docs/sales/screenshots/audit-trail.png` — added (unknown, +577/−0)
++- `docs/sales/screenshots/catalogue-sk.png` — added (unknown, +213/−0)
++- `docs/sales/screenshots/detail-crz-sk.png` — added (unknown, +326/−0)
++- `docs/sales/target-list.sk.md` — added (markdown, +47/−0)
++- `PRODUCT.md` — added (markdown, +57/−0)
++- `site/favicon.svg` — added (unknown, +1/−0)
++- `site/fonts/source-sans-3-latin-400.woff2` — added (unknown, +52/−0)
++- `site/fonts/source-sans-3-latin-600.woff2` — added (unknown, +76/−0)
++- `site/fonts/source-sans-3-latin-700.woff2` — added (unknown, +78/−0)
++- `site/fonts/source-sans-3-latin-ext-400.woff2` — added (unknown, +117/−0)
++- `site/fonts/source-sans-3-latin-ext-600.woff2` — added (unknown, +135/−0)
++- `site/fonts/source-sans-3-latin-ext-700.woff2` — added (unknown, +156/−0)
++- `site/img/audit-trail.png` — added (unknown, +577/−0)
++- `site/img/catalogue-sk.png` — added (unknown, +213/−0)
++- `site/img/detail-crz-sk.png` — added (unknown, +326/−0)
++- `site/index.html` — added (html, +154/−0)
++- `site/style.css` — added (css, +149/−0)
++- `spec/decidim/contracts_sk_locales_spec.rb` — modified (ruby, +11/−2)
++- `spec/requests/contracts_spec.rb` — modified (ruby, +20/−2)
 +
-+      get "/7"
-+
-+      expect(response).to have_http_status(:ok)
-+      aggregate_failures do
-+        # The identity pair stays unconditional — title/reference are NOT NULL.
-+        expect(response.body).to include("Road reconstruction")
-+        expect(response.body).to include("ZP-2026-001")
-+        # The guarded optional pairs disappear entirely: no blank dd
-+        # placeholders, no dangling currency label next to a nil amount.
-+        expect(response.body).not_to include("Subject matter")
-+        expect(response.body).not_to include("EUR")
-+        expect(response.body).not_to include("Signed on")
-+        expect(response.body).not_to include("Effective from")
-+        expect(response.body).not_to include('<dd class="text-md text-black mt-0"></dd>')
-+      end
-+    end
-+
-     it "renders the empty-party state gracefully" do
-       stub_published_contracts(double(find: contract))
++## Commits
++- `5a3f5102c1` chore: mirror OpenCode agent setup for Claude Code (Denys Kozlov, 2026-10-03T00:27:48+02:00)
  
-
+ ## Diff
+ ```diff
+-diff --git a/AGENTS.md b/AGENTS.md
+-index d07b8da..1c4ccc3 100644
+---- a/AGENTS.md
+-+++ b/AGENTS.md
+-@@ -133,6 +133,8 @@ Current lessons:
+- 
+- - **The `with_lock` + in-lock re-check discipline applies to every command that writes state another request can change — not just lifecycle transitions.** Any guard (`draft?`, `published?`, `editable?`) evaluated on a request-loaded object is TOCTOU-bypassable: two concurrent publishes both pass the stale re-check and double-write. Wrap the write in `with_lock` (which reloads under lock) and re-check inside; read attributes the write depends on (snapshots, sequence numbers) from the post-lock instance. Test it deterministically with a stale pre-loaded object, no threads (proven in the #65 arc: reviewer H-1 on the amendment commands; `TransitionContract` was already the precedent).
+- 
+-+- **Close the previous agent-review session before starting a new arc, and expect `confirm:true` not to pass through.** A stale active session (e.g. a dry-run left over from a prior arc) blocks `agent_review_start` until the old session is finalized with `agent_review_build_package`; and the plugin's branch-creation confirmation can loop on `confirm:true`, in which case create the approved branch with plain `git checkout -b` and start the session on it (proven in the #87 arc).
+-+
+- *Archived lessons (tracker & issue hygiene; engine mount-design; tooling & verification hygiene; host-app & ops; engine implementation mechanics; release-please; Decidim view & asset mechanics; live-source operations; issue & planning hygiene clusters) live in [`docs/retro-lessons.md`](docs/retro-lessons.md).*
+- 
+- ## Testing Expectations
+-diff --git a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
+-index 6db8a76..1f56f5f 100644
+---- a/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
+-+++ b/app/controllers/decidim/contracts_sk/admin/audit_events_controller.rb
+-@@ -26,7 +26,7 @@ module Decidim
+-       # admin contracts index (:read :contract): any engine role.
+-       class AuditEventsController < Admin::ApplicationController
+-         helper_method :audit_action_label, :audit_actor_name, :audit_target_info,
+--                      :audit_reason_for, :audit_recorded_on
+-+                      :audit_reason_for
+- 
+-         # Deterministic index ordering: newest events first, id as the
+-         # tiebreaker (same doctrine as the contracts index — a total order,
+-@@ -183,12 +183,6 @@ module Decidim
+-         rescue StandardError
+-           nil
+-         end
+--
+--        # The event's timestamp, ISO date like the decision banner's
+--        # decided-on line (nil-guarded the same way).
+--        def audit_recorded_on(event)
+--          event.created_at&.to_date&.to_fs(:db)
+--        end
+-       end
+-     end
+-   end
+-diff --git a/app/helpers/decidim/contracts_sk/application_helper.rb b/app/helpers/decidim/contracts_sk/application_helper.rb
+-index 37d94a3..f55f5c2 100644
+---- a/app/helpers/decidim/contracts_sk/application_helper.rb
+-+++ b/app/helpers/decidim/contracts_sk/application_helper.rb
+-@@ -9,7 +9,15 @@ module Decidim
+-     # imported records "externally confirmed" data — never a legal
+-     # publication — and ADR-008 decisions 4/6 require a freshness signal
+-     # that never implies real-time accuracy.
+-+    #
+-+    # Also carries the engine's locale-aware money/date/timestamp rendering
+-+    # (civora-org/civora-platform#81). The three formatters are deliberately
+-+    # PORO-safe — no view-context dependencies, I18n only — so the CRZ
+-+    # handoff PDF (a plain object) can include this module and share one
+-+    # formatting vocabulary with the views, never a second one.
+-     module ApplicationHelper
+-+      include ActionView::Helpers::NumberHelper
+-+
+-       # True when the record is a CRZ metadata mirror created by the import
+-       # ETL (ADR-008) rather than an editorial record. Drives every
+-       # provenance-labelled render in the catalogue; editorial records are
+-@@ -18,6 +26,47 @@ module Decidim
+-         contract.source == "crz"
+-       end
+- 
+-+      # Locale-aware amount rendering (civora-org/civora-platform#81).
+-+      # Under :sk the value is grouped and comma-decimalized — "1 250,50" —
+-+      # through number_with_precision with EXPLICIT separators: regular
+-+      # spaces (not non-breaking ones) were chosen on purpose, so the
+-+      # engine ships no glyph-dependent markup and the same string renders
+-+      # identically in HTML and in the PDF. Under every other locale the
+-+      # historical fixed-point form is kept verbatim (BigDecimal#to_s("F"),
+-+      # which also guards huge amounts against scientific notation). A
+-+      # blank amount renders empty; a blank currency renders the bare
+-+      # number — the PDF's drop-the-row semantics rely on both.
+-+      def format_amount(amount, currency = nil)
+-+        return "" if amount.blank?
+-+
+-+        formatted = localized_amount(amount)
+-+        return formatted if currency.blank?
+-+
+-+        "#{formatted} #{currency}"
+-+      end
+-+
+-+      # Locale-aware date rendering (civora-org/civora-platform#81): the
+-+      # format STRING is resolved from the engine's own
+-+      # decidim.contracts_sk.date_formats vocabulary and handed to I18n.l
+-+      # explicitly — never a named format, so no host-app or rails-i18n
+-+      # locale data can ever be required for the render to resolve. Blank
+-+      # renders empty, so guarded views may call it unconditionally.
+-+      def format_date(date)
+-+        return "" if date.blank?
+-+
+-+        I18n.l(date, format: I18n.t("decidim.contracts_sk.date_formats.default"))
+-+      end
+-+
+-+      # The PDF footer's generation stamp (civora-org/civora-platform#81):
+-+      # the timestamp is converted to UTC BEFORE formatting, so the naive
+-+      # to_fs(:db) digits can never silently carry the server's local zone
+-+      # — the label is explicit and true.
+-+      def format_timestamp(time)
+-+        return "" if time.blank?
+-+
+-+        "#{time.utc.to_fs(:db)} UTC"
+-+      end
+-+
+-       # True when a mirrored record must carry the stale notice (ADR-008
+-       # decision 4): the last import was stamped "failed" (the engine-side
+-       # stale-fallback signal — the record kept its last-good mirror data
+-@@ -38,6 +87,24 @@ module Decidim
+- 
+-         contract.imported_at < Decidim::ContractsSk.stale_after.to_i.seconds.ago
+-       end
+-+
+-+      private
+-+
+-+      # The locale branch of format_amount. Under :sk the value is grouped
+-+      # and comma-decimalized through number_with_precision; under every
+-+      # other locale the historical fixed-point form is kept verbatim —
+-+      # "F" on BigDecimal keeps extreme magnitudes out of scientific
+-+      # notation (plain BigDecimal#to_s goes scientific), while the frozen
+-+      # content snapshots' plain Strings render as stored.
+-+      def localized_amount(amount)
+-+        if I18n.locale == :sk
+-+          number_with_precision(amount, precision: 2, delimiter: " ", separator: ",")
+-+        elsif amount.is_a?(BigDecimal)
+-+          amount.to_s("F")
+-+        else
+-+          amount.to_s
+-+        end
+-+      end
+-     end
+-   end
+- end
+-diff --git a/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb b/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb
+-index c714c2f..9e28f62 100644
+---- a/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb
+-+++ b/app/pdfs/decidim/contracts_sk/crz_handoff_pdf.rb
+-@@ -31,7 +31,17 @@ module Decidim
+-     # The contract is duck-typed (title, reference, state, subject_matter,
+-     # amount, currency, signed_on, effective_from, crz_url, parties), so the
+-     # renderer is testable without ActiveRecord.
+-+    #
+-+    # Money, dates and the footer stamp render through the engine's shared
+-+    # ApplicationHelper formatters (civora-org/civora-platform#81) — the
+-+    # PDF runs under I18n.with_locale(:sk), so they come out locale-aware
+-+    # ("1 250,50 EUR", "31. 01. 2026") — one formatting vocabulary with the
+-+    # views, never a second one. The footer stamp additionally converts the
+-+    # generation time to UTC explicitly and labels it, so the printed
+-+    # moment is never naive server-local time.
+-     class CrzHandoffPdf
+-+      include Decidim::ContractsSk::ApplicationHelper
+-+
+-       def initialize(contract)
+-         super()
+-         @contract = contract
+-@@ -82,7 +92,15 @@ module Decidim
+- 
+-       def render_footer(pdf)
+-         pdf.move_down 12
+--        pdf.text "#{t("decidim.contracts_sk.crz_handoff_pdf.generated_on")} #{Time.current.to_fs(:db)}", size: 9
+-+        pdf.text "#{t("decidim.contracts_sk.crz_handoff_pdf.generated_on")} #{generated_stamp}", size: 9
+-+      end
+-+
+-+      # The footer's generation stamp (civora-org/civora-platform#81): the
+-+      # moment is converted to UTC BEFORE formatting and carries an explicit
+-+      # zone label, so a naive server-local "2026-09-27 09:53:07" can never
+-+      # be misread as registry time.
+-+      def generated_stamp
+-+        format_timestamp(Time.current)
+-       end
+- 
+-       # The identity + content field rows, in the data dictionary's order,
+-@@ -103,8 +121,8 @@ module Decidim
+-           [t("decidim.contracts_sk.contract.status"), state_label],
+-           [t("decidim.contracts_sk.contract.subject_matter"), contract.subject_matter],
+-           [t("decidim.contracts_sk.contract.amount"), amount_value],
+--          [t("decidim.contracts_sk.contract.signed_on"), contract.signed_on&.to_fs(:db)],
+--          [t("decidim.contracts_sk.contract.effective_from"), contract.effective_from&.to_fs(:db)],
+-+          [t("decidim.contracts_sk.contract.signed_on"), format_date(contract.signed_on)],
+-+          [t("decidim.contracts_sk.contract.effective_from"), format_date(contract.effective_from)],
+-           [t("decidim.contracts_sk.contract.crz_url"), contract.crz_url]
+-         ].select { |_, value| value.present? }
+-       end
+-@@ -119,15 +137,16 @@ module Decidim
+-         I18n.t("decidim.contracts_sk.contract_states.#{contract.state}", default: contract.state.to_s)
+-       end
+- 
+--      # Fixed-point rendering on purpose: BigDecimal#to_s alone is
+--      # scientific ("0.125e4"); the public catalogue's ERB interpolation
+--      # hides that, a plain text draw would not. Nil when the amount is
+--      # blank, so the row drops out of the field list.
+-+      # Locale-aware rendering on purpose (civora-org/civora-platform#81):
+-+      # under the PDF's forced :sk locale the shared formatter groups the
+-+      # thousands with regular spaces and comma-decimalizes ("12 345,67"),
+-+      # which also keeps BigDecimal's scientific to_s ("0.125e4") out of a
+-+      # plain text draw. Nil when the amount is blank, so the row drops out
+-+      # of the field list; a blank currency renders the bare number.
+-       def amount_value
+-         return nil if contract.amount.blank?
+--        return contract.amount.to_s("F") if contract.currency.blank?
+- 
+--        "#{contract.amount.to_s("F")} #{contract.currency}"
+-+        format_amount(contract.amount, contract.currency)
+-       end
+- 
+-       def t(key)
+-diff --git a/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb b/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb
+-index 46afb5d..39a41bf 100644
+---- a/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb
+-+++ b/app/views/decidim/contracts_sk/admin/amendments/_form.html.erb
+-@@ -2,14 +2,16 @@
+-     the summary is rendered — a draft amendment carries nothing else
+-     content-wise: the version is sequenced by the command and the content
+-     snapshot is taken at publish time from the contract's live fields
+--    (civora-org/civora-platform#65, ADR-006). %>
+--<%= form_with url: url, method: method, html: { class: "form form-defaults" } do |form| %>
+-+    (civora-org/civora-platform#65, ADR-006). The summary is the only
+-+    presence-validated input, so it alone carries the required attribute
+-+    (civora-org/civora-platform#78). %>
+-+<%= form_with model: @form, url: url, method: method, html: { class: "form form-defaults" } do |form| %>
+-   <div class="card">
+-     <div class="card-section">
+-       <div class="form__wrapper">
+-         <% if @form.errors.any? %>
+-           <div class="flash alert">
+--            <ul>
+-+            <ul role="alert" tabindex="-1" autofocus>
+-               <% @form.errors.full_messages.each do |message| %>
+-                 <li><%= message %></li>
+-               <% end %>
+-@@ -18,7 +20,7 @@
+-         <% end %>
+- 
+-         <div class="row column">
+--          <%= form.text_field :summary, label: t("decidim.contracts_sk.admin.amendments.form.summary"), label_options: { for: "amendment_summary" }, id: "amendment_summary", name: "amendment[summary]", value: @form.summary %>
+-+          <%= form.text_field :summary, label: t("decidim.contracts_sk.admin.amendments.form.summary"), label_options: { for: "amendment_summary" }, id: "amendment_summary", name: "amendment[summary]", value: @form.summary, required: true %>
+-         </div>
+-       </div>
+-     </div>
+-diff --git a/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb b/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
+-index b93dc6e..1918976 100644
+---- a/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
+-+++ b/app/views/decidim/contracts_sk/admin/audit_events/index.html.erb
+-@@ -51,7 +51,10 @@
+-                 <% end %>
+-               </td>
+-               <td><%= audit_actor_name(event) %></td>
+--              <td><%= audit_recorded_on(event) %></td>
+-+              <%# The row date renders through the shared locale-aware helper
+-+                  (civora-org/civora-platform#81) directly in the view — the
+-+                  helper chain is the view's, not the controller's. %>
+-+              <td><%= format_date(event.created_at) %></td>
+-               <td><%= reason %></td>
+-             </tr>
+-           <% end %>
+-diff --git a/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb b/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb
+-index e52fb35..cdcee94 100644
+---- a/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb
+-+++ b/app/views/decidim/contracts_sk/admin/contracts/_form.html.erb
+-@@ -2,14 +2,23 @@
+-     the editorial identity fields and the contract content fields
+-     (civora-org/civora-platform#75) are rendered — the lifecycle state and
+-     the system-stamped published_at are intentionally absent from every
+--    admin form. %>
+--<%= form_with url: url, method: method, html: { class: "form form-defaults" } do |form| %>
+-+    admin form.
+-+    Accessibility surface (civora-org/civora-platform#78/#79): the error
+-+    summary is announced as a live alert and focused on the 422 re-render;
+-+    the presence-validated identity inputs carry the required attribute
+-+    (the builder is bound to @form — the Decidim builder's required path
+-+    needs the object, and the explicit name/id options keep every field
+-+    name stable); the amount input declares its decimal keyboard and its
+-+    dot-decimal hint through aria-describedby (the Decidim builder's
+-+    help_text option wires neither an id nor the aria relation, so the
+-+    hint element is explicit). %>
+-+<%= form_with model: @form, url: url, method: method, html: { class: "form form-defaults" } do |form| %>
+-   <div class="card">
+-     <div class="card-section">
+-       <div class="form__wrapper">
+-         <% if @form.errors.any? %>
+-           <div class="flash alert">
+--            <ul>
+-+            <ul role="alert" tabindex="-1" autofocus>
+-               <% @form.errors.full_messages.each do |message| %>
+-                 <li><%= message %></li>
+-               <% end %>
+-@@ -18,11 +27,11 @@
+-         <% end %>
+- 
+-         <div class="row column">
+--          <%= form.text_field :title, label: t("decidim.contracts_sk.admin.contracts.form.title"), label_options: { for: "contract_title" }, id: "contract_title", name: "contract[title]", value: @form.title %>
+-+          <%= form.text_field :title, label: t("decidim.contracts_sk.admin.contracts.form.title"), label_options: { for: "contract_title" }, id: "contract_title", name: "contract[title]", value: @form.title, required: true %>
+-         </div>
+- 
+-         <div class="row column">
+--          <%= form.text_field :reference, label: t("decidim.contracts_sk.admin.contracts.form.reference"), label_options: { for: "contract_reference" }, id: "contract_reference", name: "contract[reference]", value: @form.reference %>
+-+          <%= form.text_field :reference, label: t("decidim.contracts_sk.admin.contracts.form.reference"), label_options: { for: "contract_reference" }, id: "contract_reference", name: "contract[reference]", value: @form.reference, required: true %>
+-         </div>
+- 
+-         <div class="row column">
+-@@ -30,11 +39,20 @@
+-         </div>
+- 
+-         <div class="row column">
+--          <%= form.text_field :amount, label: t("decidim.contracts_sk.admin.contracts.form.amount"), label_options: { for: "contract_amount" }, id: "contract_amount", name: "contract[amount]", value: @form.amount %>
+-+          <%= form.text_field :amount, label: t("decidim.contracts_sk.admin.contracts.form.amount"), label_options: { for: "contract_amount" }, id: "contract_amount", name: "contract[amount]", value: @form.amount, inputmode: "decimal", aria: { describedby: "contract_amount_hint" } %>
+-+          <span class="help-text" id="contract_amount_hint"><%= t("decidim.contracts_sk.admin.contracts.form.amount_hint") %></span>
+-         </div>
+- 
+-         <div class="row column">
+--          <%= form.text_field :currency, label: t("decidim.contracts_sk.admin.contracts.form.currency"), label_options: { for: "contract_currency" }, id: "contract_currency", name: "contract[currency]", value: @form.currency %>
+-+          <%# The options come from the model's frozen SUPPORTED_CURRENCIES
+-+              vocabulary (D1 of #75), never hand-enumerated. Currency ISO
+-+              codes are locale-neutral, so each option labels itself —
+-+              unlike the role/kind selects, no second localized vocabulary
+-+              is invented. %>
+-+          <% currency_options = Decidim::ContractsSk::Contract::SUPPORTED_CURRENCIES.map do |currency|
+-+               [currency, currency]
+-+             end %>
+-+          <%= form.select :currency, currency_options, { selected: @form.currency, label: t("decidim.contracts_sk.admin.contracts.form.currency"), label_options: { for: "contract_currency" } }, id: "contract_currency", name: "contract[currency]" %>
+-         </div>
+- 
+-         <div class="row column">
+-diff --git a/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb b/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb
+-index ff35bd4..122e891 100644
+---- a/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb
+-+++ b/app/views/decidim/contracts_sk/admin/contracts/_redaction_confirmation_body.html.erb
+-@@ -12,7 +12,7 @@
+-                  (the index can show several confirmable rows on one page),
+-                  while the name stays the server-side contract. %>
+- <% if contract.redaction_confirmed_at.present? %>
+--  <p><%= t("decidim.contracts_sk.admin.contracts.confirm_redaction.confirmed_on", confirmed_at: contract.redaction_confirmed_at.to_date.to_fs(:db)) %></p>
+-+  <p><%= t("decidim.contracts_sk.admin.contracts.confirm_redaction.confirmed_on", confirmed_at: format_date(contract.redaction_confirmed_at)) %></p>
+- <% else %>
+-   <p><%= t("decidim.contracts_sk.admin.contracts.confirm_redaction.description") %></p>
+-   <ul>
+-diff --git a/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb b/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb
+-index 328b99c..33e2cb1 100644
+---- a/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb
+-+++ b/app/views/decidim/contracts_sk/admin/contracts/_review_decision_body.html.erb
+-@@ -9,6 +9,6 @@
+- <p>
+-   <strong><%= t(contract.state, scope: "decidim.contracts_sk.contract_states") %></strong>
+-   — <%= t("decidim.contracts_sk.admin.contracts.review_decision.decided_on",
+--          reviewed_at: contract.reviewed_at&.to_date&.to_fs(:db)) %>
+-+          reviewed_at: format_date(contract.reviewed_at)) %>
+- </p>
+- <p><%= contract.review_reason %></p>
+-diff --git a/app/views/decidim/contracts_sk/admin/documents/_form.html.erb b/app/views/decidim/contracts_sk/admin/documents/_form.html.erb
+-index d68b2df..a0a5efb 100644
+---- a/app/views/decidim/contracts_sk/admin/documents/_form.html.erb
+-+++ b/app/views/decidim/contracts_sk/admin/documents/_form.html.erb
+-@@ -5,13 +5,13 @@
+-     civora-org/civora-platform#73). The kind options are derived from the
+-     form's EDITOR_KINDS vocabulary, never hand-enumerated, with localized
+-     labels. The form is multipart: the file travels with the request. %>
+--<%= form_with url: url, method: method, html: { multipart: true, class: "form form-defaults" } do |form| %>
+-+<%= form_with model: @form, url: url, method: method, html: { multipart: true, class: "form form-defaults" } do |form| %>
+-   <div class="card">
+-     <div class="card-section">
+-       <div class="form__wrapper">
+-         <% if @form.errors.any? %>
+-           <div class="flash alert">
+--            <ul>
+-+            <ul role="alert" tabindex="-1" autofocus>
+-               <% @form.errors.full_messages.each do |message| %>
+-                 <li><%= message %></li>
+-               <% end %>
+-@@ -38,7 +38,10 @@
+-         <% end %>
+- 
+-         <div class="row column">
+--          <%= form.file_field :file, label: t("decidim.contracts_sk.admin.documents.form.file"), label_options: { for: "document_file" }, id: "document_file", name: "document[file]" %>
+-+          <%# The file is presence-validated on the form, so it carries the
+-+              required attribute on both the attach and the replace page
+-+              (civora-org/civora-platform#78). %>
+-+          <%= form.file_field :file, label: t("decidim.contracts_sk.admin.documents.form.file"), label_options: { for: "document_file" }, id: "document_file", name: "document[file]", required: true %>
+-         </div>
+-       </div>
+-     </div>
+-diff --git a/app/views/decidim/contracts_sk/admin/parties/_form.html.erb b/app/views/decidim/contracts_sk/admin/parties/_form.html.erb
+-index 8da1183..6f7a9c2 100644
+---- a/app/views/decidim/contracts_sk/admin/parties/_form.html.erb
+-+++ b/app/views/decidim/contracts_sk/admin/parties/_form.html.erb
+-@@ -2,14 +2,16 @@
+-     the party's content fields are rendered — the parent contract is never
+-     form-writable (civora-org/civora-platform#76). The role options are
+-     derived from the model's frozen ROLES vocabulary, never hand-enumerated,
+--    with localized labels. %>
+--<%= form_with url: url, method: method, html: { class: "form form-defaults" } do |form| %>
+-+    with localized labels. The IČO hint (civora-org/civora-platform#79)
+-+    states the blank-or-8-digits rule the form validates, wired to the
+-+    input through aria-describedby. %>
+-+<%= form_with model: @form, url: url, method: method, html: { class: "form form-defaults" } do |form| %>
+-   <div class="card">
+-     <div class="card-section">
+-       <div class="form__wrapper">
+-         <% if @form.errors.any? %>
+-           <div class="flash alert">
+--            <ul>
+-+            <ul role="alert" tabindex="-1" autofocus>
+-               <% @form.errors.full_messages.each do |message| %>
+-                 <li><%= message %></li>
+-               <% end %>
+-@@ -26,11 +28,12 @@
+-         </div>
+- 
+-         <div class="row column">
+--          <%= form.text_field :name, label: t("decidim.contracts_sk.admin.parties.form.name"), label_options: { for: "party_name" }, id: "party_name", name: "party[name]", value: @form.name %>
+-+          <%= form.text_field :name, label: t("decidim.contracts_sk.admin.parties.form.name"), label_options: { for: "party_name" }, id: "party_name", name: "party[name]", value: @form.name, required: true %>
+-         </div>
+- 
+-         <div class="row column">
+--          <%= form.text_field :ico, label: t("decidim.contracts_sk.admin.parties.form.ico"), label_options: { for: "party_ico" }, id: "party_ico", name: "party[ico]", value: @form.ico %>
+-+          <%= form.text_field :ico, label: t("decidim.contracts_sk.admin.parties.form.ico"), label_options: { for: "party_ico" }, id: "party_ico", name: "party[ico]", value: @form.ico, aria: { describedby: "party_ico_hint" } %>
+-+          <span class="help-text" id="party_ico_hint"><%= t("decidim.contracts_sk.admin.parties.form.ico_hint") %></span>
+-         </div>
+- 
+-         <div class="row column">
+-diff --git a/app/views/decidim/contracts_sk/contracts/index.html.erb b/app/views/decidim/contracts_sk/contracts/index.html.erb
+-index c8f9e43..653d6e7 100644
+---- a/app/views/decidim/contracts_sk/contracts/index.html.erb
+-+++ b/app/views/decidim/contracts_sk/contracts/index.html.erb
+-@@ -30,9 +30,10 @@
+-             </span>
+-             <div class="card__list-text"><%= contract.reference %></div>
+-             <div class="card__list-metadata">
+--              <%# Deterministic ISO rendering on purpose: the engine ships no
+--                  locale date formats, so I18n.l would depend on host-app data. %>
+--              <div><%= contract.published_at&.to_date&.to_fs(:db) %></div>
+-+              <%# Locale-aware date rendering (civora-org/civora-platform#81):
+-+                  the format string ships with the engine, so no host-app
+-+                  locale data is required. %>
+-+              <div><%= format_date(contract.published_at) %></div>
+-               <%# CRZ-mirror provenance (civora-org/civora-platform#88, ADR-002
+-                   rule 1): imported records are labelled externally confirmed,
+-                   with the mirror date — never presented as engine-published
+-@@ -44,7 +45,7 @@
+-                 <div class="text-sm text-gray-2">
+-                   <%= t("decidim.contracts_sk.provenance.badge") %>
+-                   <% if contract.imported_at.present? %>
+--                    · <%= contract.imported_at.to_date.to_fs(:db) %>
+-+                    · <%= format_date(contract.imported_at) %>
+-                   <% end %>
+-                 </div>
+-               <% end %>
+-diff --git a/app/views/decidim/contracts_sk/contracts/show.html.erb b/app/views/decidim/contracts_sk/contracts/show.html.erb
+-index f71cb4d..bb1b708 100644
+---- a/app/views/decidim/contracts_sk/contracts/show.html.erb
+-+++ b/app/views/decidim/contracts_sk/contracts/show.html.erb
+-@@ -7,11 +7,18 @@
+-     <h1 class="title-decorator"><%= @contract.title %></h1>
+-     <%# Quick-scan metadata line under the title: the record's identity
+-         (reference), its publication date and the headline amount. Uses the
+--        existing contract vocabulary — no new keys. %>
+-+        existing contract vocabulary — no new keys. The optional fields are
+-+        guarded like the dl grid below (civora-org/civora-platform#80): a
+-+        sparse record renders no dangling date span and no "EUR" with a
+-+        blank amount. %>
+-     <div class="text-sm text-gray-2 flex gap-x-4">
+-       <span><%= t("decidim.contracts_sk.contract.reference_number") %>: <%= @contract.reference %></span>
+--      <span><%= t("decidim.contracts_sk.contract.published_on") %>: <%= @contract.published_at&.to_date&.to_fs(:db) %></span>
+--      <span><%= t("decidim.contracts_sk.contract.amount") %>: <%= @contract.amount %> <%= @contract.currency %></span>
+-+      <% if @contract.published_at.present? %>
+-+        <span><%= t("decidim.contracts_sk.contract.published_on") %>: <%= format_date(@contract.published_at) %></span>
+-+      <% end %>
+-+      <% if @contract.amount.present? %>
+-+        <span><%= t("decidim.contracts_sk.contract.amount") %>: <%= format_amount(@contract.amount, @contract.currency) %></span>
+-+      <% end %>
+-     </div>
+-   </section>
+- 
+-@@ -32,9 +39,9 @@
+-     <section class="mt-8 border-t border-gray-3 pt-4">
+-       <div class="font-semibold"><%= t("decidim.contracts_sk.provenance.badge") %></div>
+-       <% if @contract.imported_at.present? %>
+--        <%# Deterministic ISO rendering, same rule as the metadata line above. %>
+-+        <%# Same localized date rule as the metadata line above. %>
+-         <div class="text-sm text-gray-2">
+--          <%= t("decidim.contracts_sk.provenance.imported_on") %> <%= @contract.imported_at.to_date.to_fs(:db) %>
+-+          <%= t("decidim.contracts_sk.provenance.imported_on") %> <%= format_date(@contract.imported_at) %>
+-         </div>
+-       <% end %>
+-       <% if mirror_stale?(@contract) %>
+-@@ -56,24 +63,39 @
```

## Agent Activity
- Tool calls: 0
- Commands: 0
- Checkpoints: 1
- Test runs: 1
- Journal events: 3816

_Generated: 2026-10-02T22:28:12.683Z · schema agent-review/v1_
