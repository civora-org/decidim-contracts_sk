---
name: agent-review-prepare-pr
description: LOCAL ONLY Draft PR preview from the Agent Review Change Package. Never pushes or creates PRs.
argument-hint: "[base-branch]"
---

LOCAL ONLY preparation of a Draft PR preview. Never pushes, never creates PRs.

In Claude Code the `agent_review_*` tools are `mcp__agent-review__agent_review_*` (MCP server `agent-review`, see `.mcp.json`).

## Workflow

1. Require a built Change Package (`agent_review_build_package` first if missing).
2. Call `agent_review_prepare_pr` (optional `baseBranch`, `maxInlineComments`).
3. Show the user:
   - branch and proposed PR title;
   - summary counts (logical changes / files / tests passed / risks);
   - inline-comment list (path:line, risk);
   - risks and limitations (including skipped comments and why).
4. Point the user at the artifacts under `.agent-review/github/` (`pr-preview.json`, `pr-body.md`, `inline-comments.preview.json`, `publish-plan.md`).

## Output

- preview summary as above;
- nothing external happened — say so explicitly.
