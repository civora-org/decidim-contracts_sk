---
name: issue
description: Read-only analysis and router plan for a civora-org/civora-platform Issue. Use when the user runs /issue <number> or asks to plan an issue.
argument-hint: "<number>"
---

Read-only analysis and auto-router plan for an existing GitHub Issue.

## Workflow

1. Read Issue `civora-org/civora-platform#$ARGUMENTS` (`gh issue view $ARGUMENTS --repo civora-org/civora-platform --comments`).
2. Determine task type.
3. Delegate to the `architect` subagent (Agent tool) for scope if needed.
4. Propose subagents.
5. Prepare plan and approval gates.

## Output

- Issue summary;
- scope/non-scope;
- proposed subagents;
- plan;
- approval gates.
