# Command: /agent-review-github-status

Read-only GitHub readiness check for the Agent Review plugin. No external state change.

## Workflow

1. Call `agent_review_github_status` (optionally `baseBranch`).
2. Report to the user: gh availability + auth, repository (owner/repo), current branch, base branch, and any existing open PR for the branch.
3. If gh is missing or unauthenticated, tell the user: «Для публикации PR выполните: gh auth login». Keep all local artifacts; never work around it.

## Output

- `available` / `authenticated`;
- repository, remote, current/base branch;
- existing pull request (number, url, isDraft) or null;
- human-readable problem list (if any).
