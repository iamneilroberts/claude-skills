---
name: session-pause
description: Manually generate a rich session handoff file for clean context transition. Use when context is getting large, switching phases, or before a break.
user_invocable: true
---

# Session Pause

Generate a detailed handoff file so a fresh session can pick up seamlessly.

## Steps

1. **Gather git state** by running these commands:
   - `git rev-parse --show-toplevel` (repo root — used for repo tagging)
   - `git branch --show-current`
   - `git status --short`
   - `git diff --stat`
   - `git log --oneline -5`

2. **Summarize from session memory** — write these sections from what you know:
   - **What Was Accomplished**: list of completed tasks with file paths
   - **Decisions Made**: key decisions with rationale
   - **Files Created or Modified**: table with file path, action, and description
   - **Remaining Work**: actionable next steps with specific file paths
   - **Open Questions**: anything that needs user input

3. **Determine output path**:
   - Use the repo root from `git rev-parse --show-toplevel` as the base directory (this automatically resolves to the worktree root when inside a worktree)
   - If `docs/summaries/` exists under that base, write there
   - Otherwise create `.claude-sessions/` under that base
   - Filename: `pause-{YYYY-MM-DD}-{topic-slug}.md` where topic-slug is a 2-3 word summary of the work

4. **Write the handoff file** using atomic write (write to `.tmp` then rename):

```markdown
# Session Pause: {Topic}
**Date:** {YYYY-MM-DD} at {HH:MM}
**Repo:** {output of `git rev-parse --show-toplevel`}
**Branch:** {branch}
**Uncommitted changes:** {yes/no}

## What Was Accomplished
1. {task} -> output at `{file path}`

## Decisions Made
- {decision}: {what} BECAUSE {why}

## Files Created or Modified
| File Path | Action | Description |
|-----------|--------|-------------|
| `{path}` | Created/Modified | {what changed} |

## Git State
```
{git status --short}
```

## Recent Changes
```
{git diff --stat}
```

## Recent Commits
```
{git log --oneline -5}
```

## Remaining Work
1. **Next**: {specific action with file paths}
2. **Then**: {specific action}

## Open Questions
- [ ] {question} — impacts {what}

## Instructions
Continue the work from this session. Start with the Remaining Work section.
Review git state to confirm nothing has changed since the handoff.
```

4.5. **Curate the handoff** — if a `curator` agent is available (check by attempting the dispatch; skip silently if not — it ships in this collection as `agents/curator.md`). Dispatch the `curator` subagent (Agent tool, `subagent_type: curator`) with the handoff file path you just wrote. It verifies the handoff's factual claims against git/files/read-only environment checks and against the repo's invariants doc, if any. Append the returned report to the handoff file under a `## Curator Verification` heading (atomic write). This makes the *next* session pick up a handoff whose claims have already been checked — the point is to catch confabulation at the moment it's recorded, not after it's trusted.

5. **Warn about uncommitted changes** if `git status --short` shows any output. **If the curator returned any CONTRADICTED claim, say so prominently here** — those are handoff statements that did not survive verification and must not be trusted by the next session as-is.

6. **Tell the user**: "Handoff saved to `{path}`. Type `/clear` to continue — if the `auto-resume.sh` hook is installed it loads automatically, otherwise run `/session-resume`."
   - If inside a worktree, also mention: "Note: this handoff is in the worktree. `/session-resume` will find it and switch back into the worktree automatically."
