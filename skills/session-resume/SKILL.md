---
name: session-resume
description: Manually load a session handoff file to resume previous work. Fallback when auto-resume doesn't apply (new terminal, older handoffs).
user_invocable: true
args: "[date or topic filter]"
---

# Session Resume

Find and load a session handoff file to resume previous work.

## Steps

1. **Search for handoff files.** Look in these directories (the first is the optional shared
   out-of-tree coordination home used by the `branch` skill; the rest are in-tree):
   - `$(bash ~/.claude/coordination/resolve-coord-dir.sh)/handoffs/` — only if you installed
     `scripts/resolve-coord-dir.sh` to `~/.claude/coordination/`; skip this line if the script
     isn't present.
   - `docs/summaries/`
   - `.claude-sessions/`
   - `.worktrees/*/docs/summaries/` (worktree handoffs)

   **Handoff precedence (important — avoids loading a thin auto-pause over a real one):**
   - `pause-*.md` = **intentional** handoffs (model-written via `/handoff`, `/session-pause`).
   - `auto-*.md` = **mechanical** thin auto-pauses (written by hooks at ~75% context or
     on `/clear`). A legacy `pause-*.md` whose first line is `# Auto Session Pause` is
     also mechanical.
   - `handoff-*.md` = long-lived multi-session coordination docs.
   - **Prefer the newest intentional `pause-*.md`. Only fall back to the newest
     `auto-*.md` when no intentional handoff exists.** Mention if you fell back to a
     mechanical one (its detail is thin — verify against git).

2. **Filter by current repo** (default behavior):
   - Run `git rev-parse --show-toplevel` to get the current repo root
   - For each found file, read the first 10 lines and check for a `**Repo:**` line
   - **Keep** files where the `Repo:` value matches the current repo root
   - **Keep** files where the `Repo:` value is a subdirectory of the repo root (e.g., worktree paths like `/repo/.worktrees/mvp`)
   - **Keep** files with no `Repo:` line (legacy files — these predate repo tagging)
   - **Exclude** files where the `Repo:` value is a different repo entirely
   - If the user passes `--all` or says "all repos/projects", skip this filter and show everything

3. **If an argument was provided** (other than `--all`), filter results by date (YYYY-MM-DD) or topic slug substring match.

4. **If multiple files found**, list the 5 most recent with dates and any topic info from the filename:
   ```
   Found 3 handoff files (filtered to current repo):
   1. docs/summaries/pause-2026-02-26-context-hooks.md (2 hours ago)
   2. docs/summaries/pause-2026-02-25-auth-refactor.md (1 day ago)
   3. docs/summaries/handoff-2026-02-24-api-redesign.md (2 days ago)

   Which one should I load? (Use `--all` to see handoffs from all repos)
   ```
   Ask the user to pick one.

5. **If exactly one file found**, load it directly.

6. **If no files found**, tell the user:
   > No handoff files found for this repo. This session appears to be a fresh start. What would you like to work on?
   > (Use `/session-resume --all` to search across all repos)

7. **After loading the handoff file**, do the following:
   - Present a brief summary of what's in the handoff (accomplished, remaining work, branch)
   - **If the handoff came from a worktree** (path contains `.worktrees/`):
     - Extract the worktree directory from the file path (e.g., `.worktrees/mvp/docs/summaries/pause-*.md` → `.worktrees/mvp/`)
     - Check if that worktree directory still exists
     - If it exists, `cd` into the worktree directory and tell the user: "Switched into worktree at `[path]` on branch `[branch]`." Verify git state from there.
     - If the worktree no longer exists, warn the user and suggest checking if the branch was merged
   - Run `git status --short` and `git branch --show-current` (from the correct directory) to verify current git state matches the handoff
   - If there's a mismatch (different branch, unexpected changes), warn the user
   - If the handoff has a **Remaining Work** section, present it and ask: "Should I continue with the remaining work, or do you have something else in mind?"
