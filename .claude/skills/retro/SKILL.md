---
name: retro
description: Router self-review of a finished arc; distills lessons into AGENTS.md Process Lessons (pre-approved by the Retro Policy).
argument-hint: "<issue-number>"
disable-model-invocation: true
---

Router self-review of an arc tied to Issue `#<number>`.

## Workflow

1. Read Issue `civora-org/civora-platform#$ARGUMENTS` (`gh issue view $ARGUMENTS --repo civora-org/civora-platform --comments`) and the arc's outcomes.
2. Self-review the arc (optionally ask the `retro` subagent for a second opinion).
3. Distill durable lessons into `AGENTS.md` *Process Lessons* directly — pre-approved by the Retro Policy; commits still pass the normal git gate.
4. When *Process Lessons* hits its growth trigger, execute the migration policy.

## Output

- arc summary;
- lessons added or updated in `AGENTS.md`;
- proposed follow-up improvements.
