# Command: /issue <number>

Read-only analysis and auto-router plan for an existing GitHub Issue.

## Workflow

1. Read Issue `#<number>`.
2. Determine task type.
3. Call `architect` for scope if needed.
4. Propose subagents.
5. Prepare plan and approval gates.

## Output

- Issue summary;
- scope/non-scope;
- proposed subagents;
- plan;
- approval gates.
