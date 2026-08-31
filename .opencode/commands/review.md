# Command: /review <number>

Read-only current-diff review tied to an Issue or active diff.

## Workflow

1. Read Issue `#<number>` if available, otherwise inspect current diff.
2. Call `reviewer`.
3. Summarize findings and recommendation.

## Output

- findings by severity;
- final recommendation;
- follow-up list.
