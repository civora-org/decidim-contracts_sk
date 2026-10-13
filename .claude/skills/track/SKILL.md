---
name: track
description: Show where the Civora project stands (current stage, what is left, what is in flight) and fix tracking drift in civora-org/civora-platform — issues without a stage milestone, merged-but-open issues, epics whose children are all closed, stale epic checklists. Use when the user runs /track, asks "where are we", "what stage", "what's left", or after merging PRs.
---

Keeps the roadmap legible. Issues live in `civora-org/civora-platform`; the code lives in `civora-org/decidim-contracts_sk` (engine), `civora-org/civora-host` (host) and `civora-org/civora-site` (site).

## The model (since 2026-10-11)

Milestones are **stages**, not themes. Exactly one stage is current, marked `(NOW)` in its title.

| Milestone | Meaning |
|---|---|
| `Stage 1 — Pilot launch (NOW)` | Everything needed before the first municipality goes live. Epic #15 is its checklist. |
| `Stage 2 — Multi-city scale (after the first pilot)` | Running several towns. Epic #16. |
| `Candidates — validate with towns` | Prototyped feature ideas (spec + clickable prototype). Epic #206. An idea leaves this milestone when it is decided: built → moved to a stage, or killed with the reason. |
| `Later — future modules (blocked)` | Discovery-only ideas, blocked until a paying pilot asks. |
| `00`–`10` (closed) | History of the theme milestones that are finished. |

Each stage has one epic. The epic's body is a checklist of every issue in that stage, grouped by kind (business/legal, upgrade, hosting, quality). **An epic closes when its checklist is fully ticked, and its milestone closes with it.** When Stage 1 closes, rename Stage 2 to `(NOW)`.

## Workflow

Read-only by default. Report first, then fix drift only where the fix is mechanical (see Rules); anything else is a proposal for the user.

1. **Snapshot** (one call each):
   ```bash
   gh api "repos/civora-org/civora-platform/milestones?state=open" --jq '.[]|"\(.number)\t\(.title)\topen=\(.open_issues) closed=\(.closed_issues)"'
   gh issue list --repo civora-org/civora-platform --state open --limit 100 --json number,title,milestone,labels,assignees
   gh pr list --repo civora-org/decidim-contracts_sk --state open --json number,title,url
   gh pr list --repo civora-org/civora-host --state open --json number,title,url
   gh pr list --repo civora-org/civora-platform --state open --json number,title,url
   ```
2. **Drift checks**:
   - Open issues with **no milestone** → assign the stage they belong to (an upgrade/hosting/legal blocker of go-live is Stage 1; multi-city is Stage 2; a prototyped idea awaiting town validation is Candidates; discovery is Later).
   - Open issues whose fix is **already merged** (search merged PRs in the three code repos for `civora-platform#<n>`) → close with a comment naming the PR.
   - **Epics** whose children are all closed → close, then close the milestone if it is empty.
   - **Epic checklists** where a box is unticked but the issue is closed (or the reverse) → re-tick the body.
   - Issues closed since the last run that are missing from their epic's checklist → add them under "Already done".
3. **Report** to the user in this shape, short:
   - **Stage:** the `(NOW)` milestone, `x of y` done, with a one-line meaning ("first pilot can go live when this is empty").
   - **Blocking go-live**, grouped: founder (business/legal), engineering, hosting. Each line: issue number, title, owner (founder or agent), and whether it can start now or waits for something (e.g. "waits for pilot signature").
   - **In flight:** open PRs and running agents.
   - **Drift fixed:** what this run closed, moved or re-ticked.
   - **Next:** the 2–3 items to start now.

## Rules (also in AGENTS.md → Tracking)

- Every new issue gets a stage milestone at creation. No milestone = drift.
- After a PR merges: close its issue (cross-repo closing keywords don't work), tick it in the epic checklist.
- New follow-up issues found during work go into the epic checklist of their stage the same day.
- Never invent progress: tick a box only when the issue is closed and the work is merged.
- The status board (`civora-status-board.md` in civora-platform) is the narrative view; epics are the checklist view. When a stage closes, update the board in the same session.
- Founder-only work (legal entity, lawyer, signatures, manual screen-reader pass) is tracked as issues too, labelled with the real owner, so the stage count is honest.
