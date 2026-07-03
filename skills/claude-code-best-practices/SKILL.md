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

This skill routes to a local mirror of the official docs at `~/.claude/anthropic-docs/`
(refreshed weekly from https://code.claude.com/docs/llms.txt). Read the specific
file for the topic at hand instead of guessing.

## How to look something up

1. **If you know the topic**, read directly:
   `~/.claude/anthropic-docs/en__<slug>.md` — see route table below.
2. **If you don't**, scan the index:
   `cat ~/.claude/anthropic-docs/_llms.txt | grep -i <keyword>`
3. **If the topic is API/SDK** (not Claude Code CLI), check the
   `en__agent-sdk__*.md` files — they cover the programmatic surface.

Each file is the canonical Anthropic documentation in Markdown form. Cite the
source path when you reference a fact so the user can verify.

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

## Load-bearing principles — act on these without re-reading

These are the rules that should change your behavior in real time. The full
nuance is in `en__best-practices.md`, but these are the ones that bite hard:

### Workflow
- **Verification before completion**: include tests, screenshots, or expected
  outputs so Claude can self-check. Highest-leverage single change.
- **Explore → plan → implement → commit**. Skip planning only when the diff
  fits in one sentence. Use plan mode (Ctrl+G to open the plan in a text
  editor).
- **Specific prompts beat vague ones**: name files, point to existing
  patterns, describe symptoms + likely location + what "fixed" looks like.
- **After two failed corrections, /clear** and re-prompt with what you
  learned. Long sessions with accumulated corrections almost always lose to a
  fresh session with a sharper prompt.

### Context hygiene
- **One concern per session**. Switching from research → writing → review
  inside one session bloats context. Split.
- **Subagents for investigation**, not main-context exploration. Their reads
  don't pollute your conversation.
- **`/clear` between unrelated tasks** is cheap; running long is expensive.
- **`/btw` for quick side-questions** — answer appears in an overlay, never
  enters conversation history.

### Cache hygiene (per Anthropic's invalidation table)
Order: tools → system → messages. A change at level N invalidates N and
everything after.
- **Don't edit CLAUDE.md mid-session** — it sits in the system block. Save
  edits between sessions, or `/clear` immediately after editing.
- **Don't switch models mid-session** — caches are per-model.
- **Don't toggle Shift+Tab (fast mode) mid-session** — listed as a
  system-cache invalidator.
- **Don't enable/disable MCP servers mid-session** — changes tool definitions.
- **`/compact` rewrites the prefix** — use deliberately at logical
  breakpoints, not reflexively.
- Safe mid-session: pasting images (messages-tail only), invoking skills,
  running tool calls.

### CLAUDE.md content discipline
- Loaded every session. For each line ask: *"would removing this cause
  mistakes?"* If no, cut.
- Include: bash commands Claude can't guess, code style that differs from
  defaults, test preferences, repo etiquette, env quirks.
- Exclude: anything Claude can read from code, standard language conventions,
  long tutorials, file-by-file descriptions, frequently-changing info.
- Bloated CLAUDE.md causes Claude to ignore rules. If a rule isn't landing,
  the file is probably too long.

### Parallel work
- **Writer / Reviewer pattern**: one session implements, a fresh session
  reviews. Fresh context = less bias toward just-written code.
- **Worktrees** for parallel edits that mustn't collide.
- **`claude -p` for fan-out**: loop over files, scope with `--allowedTools`.

## Refreshing the mirror

The mirror auto-refreshes weekly via cron. To refresh manually:

```bash
~/.claude/scripts/refresh-anthropic-docs.sh
```

Source: `https://code.claude.com/docs/llms.txt` (canonical Mintlify index).
Manifest at `~/.claude/anthropic-docs/_manifest.json` with per-page SHA-256
and timestamps.

## Common failure patterns (from `en__best-practices.md`)

- **Kitchen sink session** — unrelated tasks share one context → `/clear`
- **Correcting over and over** — two failed corrections → `/clear` + better
  prompt
- **Over-specified CLAUDE.md** — rules lost in noise → prune
- **Trust-then-verify gap** — plausible code missing edge cases → always
  verify
- **Infinite exploration** — unscoped "investigate X" → scope narrowly OR
  use subagents
