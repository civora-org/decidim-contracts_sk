---
name: verify
description: Run only safe, applicable local tests and lints (rspec, rubocop) and report results.
---

Runs only safe, applicable local tests and lints.

## Workflow

1. Detect applicable verification commands for the current repo.
2. Prefer targeted checks before broad suites.
3. Do not run destructive or irrelevant commands.
4. Report results, failures, and next fixes.

## Output

- executed checks;
- pass/fail summary;
- failing areas;
- suggested next action.
