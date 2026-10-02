---
name: agent-review-publish-pr
description: Commit, push, open a Draft PR and publish Agent Review inline comments — only after explicit user confirmation.
argument-hint: "[base-branch]"
disable-model-invocation: true
---

Publish a Draft PR with the Agent Review summary and grouped inline comments.
ALWAYS requires explicit user confirmation before any external action.

In Claude Code the `agent_review_*` tools are `mcp__agent-review__agent_review_*` (MCP server `agent-review`, see `.mcp.json`).

## Workflow

1. Run `/agent-review-prepare-pr` first and show the full preview.
2. Ask the user EXACTLY: «Создать commit, push branch, Draft PR и опубликовать N review comments?»
3. Without an unambiguous yes — stop. Calling `agent_review_publish_pr` without `confirmed: true` performs nothing by design; do not try to bypass it.
4. Only after confirmation call `agent_review_publish_pr` with `allowCommit: true`, `allowPush: true`, `confirmed: true` (adjust only if the user asked otherwise).
5. If gh is missing/unauthenticated, report: «Для публикации PR выполните: gh auth login» and keep local artifacts.

## Output

- PR URL;
- PR created or reused (never duplicated);
- how many inline comments were published;
- which comments were skipped and why.
