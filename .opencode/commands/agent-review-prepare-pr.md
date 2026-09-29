# Command: /agent-review-prepare-pr

LOCAL ONLY preparation of a Draft PR preview. Never pushes, never creates PRs.

## Workflow

1. Require a built Change Package (`agent_review_build_package` first if missing).
2. Call `agent_review_prepare_pr` (optional `baseBranch`, `maxInlineComments`).
3. Show the user:
   - branch and proposed PR title;
   - summary counts (logical changes / files / tests passed / risks);
   - inline-comment list (path:line, risk);
   - risks and limitations (including skipped comments and why).
4. Point the user at the artifacts under `.agent-review/github/` (`pr-preview.json`, `pr-body.md`, `inline-comments.preview.json`, `publish-plan.md`).

## Output

- preview summary as above;
- nothing external happened — say so explicitly.
