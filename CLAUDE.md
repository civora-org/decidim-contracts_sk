@AGENTS.md

## Claude Code setup

`AGENTS.md` above is the shared source of truth for OpenCode and Claude Code. The Claude Code mirror of `opencode.jsonc` / `.opencode/` lives in:

- **Subagents:** `.claude/agents/`: `architect`, `reviewer` (opus); `rails`, `tester`, `integration`, `retro` (sonnet). These replace the `zai-coding-plan/glm-*` models in the agents table.
- **Commands:** `.claude/skills/`: `/issue`, `/feature`, `/review`, `/verify`, `/retro`, `/agent-review-*`.
- **Agent Review:** `.claude/skills/agent-review` is symlinked to `../agent-review/skills/agent-review`. Its tools come from the `agent-review` MCP server (`.mcp.json`) as `mcp__agent-review__agent_review_*`. A `PostToolUse` hook in `.claude/settings.json` journals edits and shell commands while a session is active.
- **MCP servers:** `agent-review`, `slov-lex`, `playwright` (`.mcp.json`).
- **Permissions:** `.claude/settings.json` mirrors the `opencode.jsonc` permissions.

When you change an agent, command, or permission, update both `.opencode/` and `.claude/`.

## Router role (main session)

The main Claude Code session plays the `contracts` router: Claude Code subagents cannot spawn other subagents, so the router is not a subagent here.

1. Read `AGENTS.md`, `README.md`, `CHANGELOG.md`, local code, and the Issue (in `civora-org/civora-platform`) or the feature request.
2. Determine the task type: feature, bug, refactor, docs, or future integration.
3. For non-trivial tasks, delegate scoping to the `architect` subagent.
4. Choose subagents (`architect`, `rails`, `tester`, `reviewer`, optional `integration`, `retro`).
5. Prepare a plan with approval gates, then stop for human approval (see *Approval Gates* in `AGENTS.md`).
6. After approval, delegate implementation to `rails` and verification to `tester`/`reviewer`.
7. After meaningful completion, run the retro (`/retro`).
