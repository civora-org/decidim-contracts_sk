# Agent Review

## Summary
- 5 logical changes / 26 files changed
- Tests: 1 passed
- Risks: 1 medium, 4 low

## What changed
1. **Claude Code subagents** — Port .opencode/agents to Claude Code subagents so both harnesses share the same roles
2. **Claude Code slash-command skills** — Port the 9 .opencode/commands to Claude Code skills invoked as /<name>
3. **agent-review skill, MCP servers and journaling hook** — Expose the agent_review_* tools to Claude Code via the agent-review MCP server and replace the OpenCode plugin hooks with a PostToolUse hook; carry over slov-lex and playwright MCP servers
4. **Claude Code permissions** — Mirror opencode.jsonc permissions
5. **CLAUDE.md and AGENTS.md pointer** — Load AGENTS.md as shared source of truth in Claude Code and define the main session as the contracts router

## Evidence
- `bundle exec rspec`: passed

## Risks and limitations
- Working tree was dirty at session start (72 entries) — pre-existing changes may be mixed into the diff.
- Large diff: 4919 insertions across 26 files.
- Limitation: Snapshots cover only files that were changed at checkpoint time.
- Limitation: Symbol extraction is regex-based, not AST-based.
- Limitation: Only observed facts are recorded — private model reasoning is not captured.
- Limitation: The contracts router is not a subagent: Claude subagents cannot spawn subagents, so the role lives in CLAUDE.md
- Limitation: Absolute machine paths in .mcp.json (same as opencode.jsonc)
- Limitation: Hook assumes agent-review is a sibling checkout
- Limitation: Skill is a symlink into ../agent-review
- Limitation: edit:ask not mirrored as a hard rule; governed by permission mode plus AGENTS.md approval gates

## Review guidance
Start with the inline comments marked `Agent context` (2 comments on the current diff).

_This summary and the inline comments are review CONTEXT, not guarantees of correctness._
