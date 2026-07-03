---
name: claude-code-best-practices
description: Use when asked about Claude Code workflow, prompt caching cost,
  session economics, CLAUDE.md hygiene, context-window management, plan mode,
  permission modes, hooks, skills, subagents, checkpointing/rewind, parallel
  sessions, worktrees, headless/CI usage, the Agent SDK, slash commands, MCP
  configuration, or "what's the right way to use Claude Code for X". Also use
  proactively BEFORE suggesting /model, /compact, fast-mode toggle, or editing
  CLAUDE.md mid-session, since those bust the system cache.
---

# Claude Code best practices reference

Routes to a local mirror of the official docs at `~/.claude/anthropic-docs/` (refreshed weekly
from https://code.claude.com/docs/llms.txt) — canonical Markdown; cite the source path when you
reference a fact. Read the file for the topic at hand instead of guessing.

## How to look something up

- **Know the topic?** Read `~/.claude/anthropic-docs/en__<slug>.md` (route table below).
- **Don't know it?** `cat ~/.claude/anthropic-docs/_llms.txt | grep -i <keyword>`
- **API/SDK topic** (not the CLI)? Check `en__agent-sdk__*.md`.

## Route table — topic → local file

| Topic | Local file |
|---|---|
| **Best practices overview** (workflow patterns, common failures) | `en__best-practices.md` |
| **CLAUDE.md** (format, placement, what to include/exclude) | `en__memory.md` |
| **Context window** (how it fills, what loads at startup) | `en__context-window.md` |
| **Cost / reduce token usage** | `en__costs.md` |
| **Prompt caching** (also see platform.claude.com docs) | `en__costs.md` (CC-specific) |
| **Checkpointing / /rewind** | `en__checkpointing.md` |
| **Sessions** (continue, resume, fork, naming) | `en__sessions.md` |
| **Interactive mode** (/clear, /compact, /btw, key bindings) | `en__interactive-mode.md` |
| **Slash commands / built-in commands** | `en__commands.md` |
| **Hooks** (events, JSON shape, examples) | `en__hooks-guide.md` + `en__hooks.md` |
| **Skills** (SKILL.md format, when to use) | `en__skills.md` |
| **Subagents** (.claude/agents/*) | `en__sub-agents.md` |
| **Permission modes** (auto, plan, sandbox) | `en__permission-modes.md` |
| **Permissions** (allowlists, /permissions) | `en__permissions.md` |
| **Sandboxing** | `en__sandboxing.md` |
| **MCP** (configuration, claude mcp add) | `en__mcp.md` |
| **Worktrees / parallel sessions** | `en__worktrees.md` |
| **Agent teams** | `en__agent-teams.md` |
| **Headless / CI** (claude -p, --output-format) | `en__headless.md` |
| **Chrome extension** (UI verification) | `en__chrome.md` |
| **Claude Code on the web** | `en__claude-code-on-the-web.md` |
| **Plugins** | `en__plugins.md` + `en__discover-plugins.md` |
| **Settings.json reference** | `en__settings.md` |
| **CLI reference** | `en__cli-reference.md` |
| **Status line** | `en__statusline.md` |
| **Channels** (push events into a session) | `en__channels.md` + `en__channels-reference.md` |
| **Auto mode config** (classifier rules) | `en__auto-mode-config.md` |
| **How Claude Code works** (agentic loop internals) | `en__how-claude-code-works.md` |
| **Agent SDK** (build agents programmatically) | `en__agent-sdk__overview.md` and siblings |

For anything not listed, grep `_llms.txt`.

## Load-bearing principles (nuance in `en__best-practices.md`)

### Workflow
- **Verify before claiming done**: include tests, screenshots, or expected outputs so Claude
  can self-check — the highest-leverage single habit.
- **Explore → plan → implement → commit**; skip planning only when the diff fits in one
  sentence (Ctrl+G opens plan mode in a text editor).
- **Specific prompts beat vague ones**: name files, point to existing patterns, describe
  symptoms + likely location + what "fixed" looks like.

### Context hygiene
- **One concern per session** — don't mix research/write/review in one context.
- **`/clear` liberally**: after two failed correction attempts (a fresh session with a
  sharper prompt beats a corrected long one), between unrelated tasks, or before an unscoped
  "investigate X" (scope narrowly or delegate to a subagent instead).
- **Subagents for investigation** — their reads don't pollute your context.
- **`/btw` for side-questions** — answers land in an overlay, never in history.

### Cache hygiene (invalidation order: tools → system → messages; a change at level N
invalidates N and everything after)
- **Don't, mid-session**: edit CLAUDE.md (system block — edit between sessions or `/clear`
  right after), switch models, toggle Shift+Tab fast mode, or enable/disable MCP servers.
- **`/compact`** rewrites the prefix — use at deliberate breakpoints, not reflexively.
- Safe mid-session: pasted images, skill invocations, tool calls.

### CLAUDE.md content discipline
- Loaded every session — per line, ask *"would removing this cause mistakes?"*; if no, cut.
  Bloat makes Claude ignore rules.
- Include bash commands Claude can't guess, non-default code style, test preferences, repo
  etiquette, env quirks. Exclude anything readable from code, standard conventions, tutorials,
  and frequently-changing info.

### Parallel work
- **Writer/reviewer**: one session implements, a fresh one reviews (less bias toward
  just-written code).
- **Worktrees** for parallel edits that mustn't collide; **`claude -p`** for fan-out over
  files, scoped with `--allowedTools`.

## Refreshing the mirror

Auto-refreshes weekly via cron; manual: `~/.claude/scripts/refresh-anthropic-docs.sh`.
Source: `https://code.claude.com/docs/llms.txt`. Manifest with per-page SHA-256 + timestamps:
`~/.claude/anthropic-docs/_manifest.json`.
