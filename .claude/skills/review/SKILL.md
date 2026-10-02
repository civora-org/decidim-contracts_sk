---
name: review
description: Read-only severity-graded review of the current diff, optionally tied to a civora-org/civora-platform Issue.
argument-hint: "[issue-number]"
---

Read-only current-diff review tied to an Issue or active diff.

## Workflow

1. Read Issue `civora-org/civora-platform#$ARGUMENTS` (`gh issue view $ARGUMENTS --repo civora-org/civora-platform --comments`) if available, otherwise inspect current diff.
2. Delegate to the `reviewer` subagent (Agent tool).
3. Summarize findings and recommendation.

## Output

- findings by severity;
- final recommendation;
- follow-up list.
