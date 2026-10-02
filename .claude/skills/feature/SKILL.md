---
name: feature
description: Read-only plan for a new feature in this engine. Use when the user runs /feature <description>.
argument-hint: "<description>"
---

Read-only plan for a new feature.

## Workflow

1. Read the feature description: $ARGUMENTS
2. Delegate to the `architect` subagent (Agent tool) for scope.
3. Propose subagents.
4. Prepare plan and approval gates.

## Output

- feature summary;
- scope/non-scope;
- proposed subagents;
- plan;
- approval gates.
