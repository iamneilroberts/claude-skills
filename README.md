# claude-skills

A curated set of the custom skills, slash commands, hooks, and agents I actually use to run
[Claude Code](https://claude.ai/code) day to day. The through-line is **session and context
management**: starting clean, wrapping up honestly, handing off across `/clear`, isolating parallel
work in worktrees, and verifying that "done" is actually done — plus a few general-purpose helpers
(multi-model review, product teardowns, anti-slop UI).

Everything here is plain Markdown + a little Bash/Python. No framework, nothing to build. Copy the
pieces you want into `~/.claude/` and go. Most skills degrade gracefully when an optional
integration is missing, so you can adopt one without adopting all of them.

---

## The end-of-session self-critique (start here)

This is the piece that prompted me to clean the rest up and publish it. It came out of a
[r/ClaudeAI thread — "I end every AI session with two questions"](https://www.reddit.com/r/ClaudeAI/comments/1ulti1r/i_end_every_ai_session_with_two_questions/).
The idea: before you close a session, make the model turn on its own work and say what it's unsure
about. I wired a right-sized version into my wrap-up flow so I don't have to remember to ask.

At the end of a session (`/session-end`) or when writing a handoff (`/handoff`), the model answers,
as deeply as the session warrants:

1. **What are you least confident about right now?** (all of them, not one)
2. **What's the biggest thing being missed about this situation?**
3. **If this ships and breaks in 3 months, what's the most likely reason?** (future fragility — the
   best variant, contributed by a commenter in that thread)
4. **What did you NOT do?** — skipped, deferred, stubbed, or assumed
5. For each item in 1 and 4: **name the exact test or command that would confirm or kill it.** No
   verification step → it was filler.

Two rules keep it from becoming noise:

- **Right-sized.** A long-but-simple session gets one line, or gets skipped. The full list only fires
  when the work was complex or touched something risky. Run it every time regardless and you just
  train yourself to ignore it.
- **Capture, don't chase.** It writes findings into the handoff or files them as a separate idea — it
  does **not** start fixing them. Otherwise a two-minute wrap-up turns into another hour and you stop
  running it.

It lives in three places that reinforce each other:

- [`skills/session-end/`](skills/session-end/) — Phase 1.4, the wrap-up self-critique.
- [`skills/handoff/`](skills/handoff/) — the `Self-Critique` section of the handoff doc.
- [`skills/curate/`](skills/curate/) — the mechanized version of the thread's "paste it into a fresh
  chat and ask what it missed" trick: a read-only `curator` subagent checks the session's claims
  against git, files, and the environment before you trust them.

---

## What's inside

### Skills (`~/.claude/skills/`)
| Skill | What it does |
|---|---|
| [`session-start`](skills/session-start/SKILL.md) | Begin a session; set up the per-session log. |
| [`session-end`](skills/session-end/SKILL.md) | Wrap up: **self-critique**, optional curator verification, prepend a `SESSION_LOG.md` entry. |
| [`handoff`](skills/handoff/SKILL.md) | Write a rich `pause-*.md` handoff (checklist, decisions, self-critique, verbatim-id "coordinate closet") that a fresh session can resume from. |
| [`session-pause`](skills/session-pause/SKILL.md) | Manually generate a handoff (the lightweight sibling of `/handoff`). |
| [`session-resume`](skills/session-resume/SKILL.md) | Find and load the newest handoff to resume work in place. |
| [`pickup`](skills/pickup/SKILL.md) | Resume the newest handoff **in an isolated worktree** (orchestrates `branch` + `session-resume`). |
| [`branch`](skills/branch/SKILL.md) | Create an isolated git worktree + a shared out-of-tree work journal, so parallel Claude sessions don't clobber each other's HEAD or WIP. |
| [`curate`](skills/curate/SKILL.md) | Dispatch the read-only `curator` to verify a handoff/session's claims (confabulation check). |
| [`sitrep`](skills/sitrep/SKILL.md) | Occasional "state of the union" sweep: what actually shipped vs what handoffs/specs claim, plus loose ends and loss-risk. |
| [`crisp`](skills/crisp/SKILL.md) | Shorter, denser responses on demand. |
| [`idea`](skills/idea/SKILL.md) | Capture a fix/feature/research idea fast → a labelled GitHub Issue + a planning doc under `docs/ideas/`. |
| [`fix-issue`](skills/fix-issue/SKILL.md) | Resolve a GitHub issue end to end: read it, reproduce, fix in an isolated branch with a test, verify, open a PR that closes it. The counterpart to `idea`. |
| [`brag`](skills/brag/SKILL.md) | Memorialize something you just built as a persuasive "showcase" page (sales/hype leaning) with a screenshot and links to related pages. Fast, like `/idea`. |
| [`write-post`](skills/write-post/SKILL.md) | Draft a neutral, no-BS technical deep-dive post to `docs/posts/` (rich outline by default, `--draft` for prose). The technical counterpart to `brag`. |
| [`get-reddit`](skills/get-reddit/SKILL.md) | Fetch one public Reddit post + its top comments as clean markdown, by driving a real browser (see note below). |
| [`claude-code-best-practices`](skills/claude-code-best-practices/SKILL.md) | Routes questions to a local mirror of the Claude Code docs. |
| [`evaluate`](skills/evaluate/SKILL.md) | Teardown a third-party product/repo from a URL; fan out read-only subagents; decide ADOPT / LIFT / SKIP. |
| [`frontier-spend`](skills/frontier-spend/README.md) | Spend scarce/expiring premium-model access on durable judgment artifacts: adjudicate-don't-author, rationed audits, effort tuning, review-the-premium-output. Full write-up + A/B test in its README. |
| [`llm-tools`](skills/llm-tools/SKILL.md) | Cheap-worker delegation: `llm-ask`/`llm-write`/`llm-extract` CLIs route bulk reads, boilerplate, and transcript compression to a cheap OpenAI-compatible model (Kimi/DeepSeek/OpenRouter/Ollama). Ships the full package. |
| [`review-panel`](skills/review-panel/SKILL.md) | Multi-model code review (Codex + Gemini + a fresh Claude), merged with a consensus-gated challenge round and a pass/fail exit code. |
| [`codex-review`](skills/codex-review/SKILL.md) | Single-reviewer external pass (Codex) with a structured JSON verdict and mechanical gate. |
| [`gemini-review`](skills/gemini-review/SKILL.md) | Single-reviewer external pass using the Gemini CLI, presented alongside your own analysis. |
| [`unslop-ui`](skills/unslop-ui/SKILL.md) | Detect and remove the visual tells that make a UI look AI-generated. |
| [`mock`](skills/mock/SKILL.md) | Build a few UI design variations as one self-contained HTML file behind a view-switcher, passed through the `unslop-ui` gate; deliver by download, email draft, or a URL if you wire your own host. |
| [`my-voice`](skills/my-voice/SKILL.md) | Rewrite text to sound like a specific person: distill a checkable voice profile from a writing sample + a short interview, then de-slop the AI tells and verify the output against it. The prose counterpart to `unslop-ui`. |
| [`task-observer`](skills/task-observer/SKILL.md) | Capture observations during work and turn them into skill improvements. *(third-party — see Attribution)* |

### Agents (`~/.claude/agents/`)
| Agent | What it does |
|---|---|
| [`curator`](agents/curator.md) | Read-only verification subagent. Takes claims (or a handoff) and returns VERIFIED / UNVERIFIED / CONTRADICTED per claim, each backed by a real command + output. Never edits or deploys. |

### Scripts (`~/.claude/`) and Hooks (optional)
| File | What it does |
|---|---|
| [`scripts/resolve-coord-dir.sh`](scripts/resolve-coord-dir.sh) | Resolves the shared out-of-tree coordination dir for a repo (used by `branch`, `pickup`, `session-resume`, `curate`, `sitrep`). Install to `~/.claude/coordination/`. |
| [`scripts/refresh-anthropic-docs.sh`](scripts/refresh-anthropic-docs.sh) | Mirror the public Claude Code docs locally for `claude-code-best-practices`. |
| [`hooks/auto-resume.sh`](hooks/auto-resume.sh) | On `/clear`, auto-load the newest `pause-*.md` handoff. |
| [`hooks/session-end-nudge.sh`](hooks/session-end-nudge.sh) | After N commits, nudge you to run `/session-end` (or `/handoff`) before `/clear`. |
| [`hooks/session-end-handoff.sh`](hooks/session-end-handoff.sh) | Write a mechanical handoff on `/clear` so early clears still leave a resume point. |

---

### A note on `get-reddit` (why a browser, not the API)

Reddit is worth calling out because the obvious approaches don't work anymore:

- **The API path is closed.** Reddit's Responsible Builder Policy (2025) disabled self-serve
  API-app creation — the "create app" button is zombie functionality, and new apps need a
  manual pre-approval that's effectively unavailable to solo devs. So the OAuth route is out.
- **Plain fetch gets a 403.** Reddit returns an anti-bot page to any non-browser client —
  `.json` endpoints, `old.reddit.com`, UA spoofing, and reader proxies all fail, from both
  datacenter and residential IPs.

The one path left is a **real browser session**: `get-reddit` launches Chromium (via Playwright),
parks on the post to warm the session, then does an in-page same-origin fetch of the post JSON —
the browser carries the cookies and headers Node's fetch can't replicate. No Reddit login or API
key needed. Playwright and its Chromium binary auto-install on first run; `node_modules/` and the
browser profile are gitignored, so only the small source (`get-reddit.sh`, `get-reddit.mjs`,
`package.json`) is tracked here.

## Install

Everything maps onto Claude Code's standard directories. Copy what you want:

```
cp -r skills/*    ~/.claude/skills/
cp    agents/*    ~/.claude/agents/
cp    scripts/resolve-coord-dir.sh  ~/.claude/coordination/    # if you use branch/pickup/sitrep
```

Every skill here is `user_invocable`, so each is both a `/slash-command` you can type and a skill
Claude can auto-invoke when your request matches its description.

Hooks are opt-in — wire the ones you want into `~/.claude/settings.json` under the matching event
(`SessionStart` for `auto-resume.sh`, `Stop` for `session-end-nudge.sh`, `SessionEnd` for
`session-end-handoff.sh`). See the comment header in each hook for the exact event and payload.

---

## Optional integrations

Nothing here hard-requires these; each skill skips the relevant step (and says so) when a dependency
is absent.

- **`curator` agent** — `session-end`, `session-pause`, `sitrep`, and `curate` use it for
  verification. Ship `agents/curator.md` to enable. It's written generically; point it at your own
  deploy/DB read commands and your project's invariants doc (e.g. a `LAWS.md`) if you keep one.
- **External review CLIs** — `review-panel`, `codex-review`, and `gemini-review` shell out to the
  `codex`, `gemini`, and/or `claude` CLIs. An absent CLI is a clean skip, never a failure.
- **Memory / session-history MCP servers** — `sitrep`'s historical lane and `session-end`'s counters
  can use a long-term memory MCP and a session-history MCP if you run them; otherwise those lanes are
  skipped.
- **A roadmap file** (`docs/roadmap/MILESTONES.md`) — `sitrep` anchors "what's next" to it if
  present; otherwise it falls back to recent handoffs/journal.
- **Companion skills** — `pickup` needs `branch`; several skills mention `/pm` and `/focus` as
  optional daily drivers (not included here).
- **A publish target for `brag`** — `brag` writes showcase pages to a local `showcase/` dir by
  default; it only deploys if you've wired up a publish command, and never automatically.

---

## Attribution

- **`skills/task-observer/`** — third-party, redistributed unmodified under **CC BY 4.0**,
  © Eoghan Henn (rebelytics.com). Source:
  <https://github.com/rebelytics/one-skill-to-rule-them-all>. See its `LICENSE.txt` and `SOURCE.md`.
- **`skills/unslop-ui/`** — derives from an upstream analysis of "AI slop" UI tells; see
  `skills/unslop-ui/LICENSE.upstream`.
- The handoff "coordinate closet" idea mirrors a small verbatim-identifier algorithm from
  **context-warp-drive** (MIT).
- The end-of-session self-critique is adapted from a
  [r/ClaudeAI thread](https://www.reddit.com/r/ClaudeAI/comments/1ulti1r/i_end_every_ai_session_with_two_questions/).

## License

MIT for my own work (everything outside `skills/task-observer/`). See [LICENSE](LICENSE).
Third-party components retain their own licenses as noted above.
