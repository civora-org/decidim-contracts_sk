# Command: /agent-review-update-review

Update the Agent Review on an existing PR after a new commit/push. Replaces only the plugin's own comments — never human or other-bot comments.

## Workflow

1. Call `agent_review_update_github_review` WITHOUT `confirmed` first: it returns the update preview (would-publish count, replace mode, skipped).
2. Show the preview to the user and ask for explicit confirmation.
3. Only after the user agrees, re-invoke with `confirmed: true` (optionally `pullRequestNumber`).
4. The plugin identifies its own comments via a hidden marker and replaces only those (`updateMode: replace-agent-comments`).

## Output

- head moved: yes/no;
- own comments replaced / new comments published;
- skipped entries and reasons.
