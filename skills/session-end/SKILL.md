---
name: session-end
description: Wrap up a coding session — run a right-sized end-of-session self-critique, optionally curator-verify the claims, prepend a SESSION_LOG.md entry, and print a rename + counter summary. Use before you /clear or stop for the day. Triggers on `/session-end`, "end this session", "wrap up and log what we did".
user_invocable: true
---

# End Coding Session

I'll wrap up this session: persist what we did, prepend a SESSION_LOG entry, and surface a session-rename suggestion.

## Phase 1 — Take stock

Analyze what we accomplished:
1. Files created/modified
2. Git changes made during the session
3. Tasks completed vs left open

While doing this, **count three things** (I'll print them in Phase 3):
- `MEMORY_WRITES` — auto-memory file edits (`~/.claude/projects/*/memory/*.md`) + vestige `*_ingest`/`remember_*`/`set_intention` tool calls made this session
- `COMMIT_COUNT` — number of `git commit` invocations this session
- `SESSION_LOG_UPDATED` — true/false depending on whether Phase 2 actually wrote an entry

```bash
# Append session marker to the legacy per-session log if one exists
SESSION_FILE=$(ls -t .claude-sessions/session_*.log 2>/dev/null | head -1)
if [ -f "$SESSION_FILE" ]; then
  printf '\n=== Session Summary ===\nEnded: %s\n\n' "$(date)" >> "$SESSION_FILE"
fi

# Capture git context for Phase 2
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
git diff --stat $(git rev-parse HEAD~1 2>/dev/null || echo HEAD) 2>/dev/null || echo "(no git changes this session)"
```

## Phase 1.4 — Session-close self-critique (surface gaps before you log)

**Right-size this to the session — don't manufacture concerns.** For a long-but-simple session
(few files, nothing risky or irreversible, nothing shipped), a single honest line — "nothing
shaky; only X was deferred" — is the whole phase. Scale up only when the work was genuinely
complex, touched risky surfaces (auth / payments / prod / data / deletion), or shipped. The point
is to catch what got silently skipped or assumed, not to perform diligence.
(Adapted from the r/ClaudeAI "I end every AI session with two questions" thread.)

When it's worth the deeper pass, answer as many of these as the session warrants:

1. **What are you least confident about right now?** List every shaky spot — not one.
2. **What's the biggest thing being missed about this situation — what might I not realize?**
3. **If this ships and breaks in 3 months, what's the most likely reason?** (future fragility,
   distinct from present-state gaps.)
4. **What did you NOT do?** Everything skipped, deferred, stubbed, or assumed — even things that
   felt out of scope.
5. For each item surfaced in 1 and 4: **name the exact test or command that would confirm or kill
   it.** An uncertainty with no verification step is filler; a real gap comes with a way to check.

**Capture, don't chase.** This is a wrap-up inventory, not a fix-it session — do NOT start fixing
what it surfaces (that's the rabbit trail to avoid). Route findings instead:
- Items with a concrete check (from 5) → hand to Phase 1.5 Curate to verify where cheap.
- Everything else → **offer the user two capture routes** and do the chosen one: (a) fold it into
  the Phase 2 **Pending** / **Handoff Notes** as an instruction for the next session, or (b) file
  the notable / standalone ones via `/idea`. Never let a finding evaporate — but never let it
  derail the current task either.

Skip this phase entirely if Phase 1 found nothing meaningful (no files changed, no decisions, no
commits) — silence is a valid result, not a gap.

## Phase 1.5 — Curate (verify before you log)

If a `curator` agent is available (attempt the dispatch; skip silently if not), dispatch it
(Agent tool, `subagent_type: curator`) with this session's accomplishments from Phase 1. It checks
those claims against git/files/live production and against the repo's `LAWS.md`, read-only.

Apply the result before writing anything in Phase 2:
- Only log a claim as done if it came back **VERIFIED**.
- A claim that came back **UNVERIFIED** may still be logged, but mark it as unverified in the entry
  (e.g. "deployed (unverified)") — never launder it into a flat assertion.
- A claim that came back **CONTRADICTED** must NOT be logged as done. Surface it in the
  in-conversation summary's **Handoff Notes** as something the next session must fix or re-check.

Skip this phase only if Phase 1 found nothing meaningful (no files changed, no decisions, no commits).

## Phase 2 — Prepend a SESSION_LOG.md entry

Determine the log path:
- Git repo: `$GIT_ROOT/SESSION_LOG.md`
- Otherwise: `~/SESSION_LOG.md`

Draft a one-block entry — date, short title, 1–2 sentence summary, and a pointer to the main artifact (file path, commit SHA, PR URL, or issue ID — whichever best identifies "where does this session live"). Format (newest at top):

```markdown
## YYYY-MM-DD — <Short title>

<1–2 sentence summary of what we did and why.>

Main artifact: <file path / commit SHA / issue ID / URL>
```

Skip the entry if nothing meaningful happened (no files changed, no decisions, no commits) — set `SESSION_LOG_UPDATED=false` and move on.

Prepend atomically (newest at top):

```bash
LOG_PATH="${GIT_ROOT:-$HOME}/SESSION_LOG.md"
ENTRY=$(mktemp)
# Write the drafted entry to $ENTRY (Claude writes it via Write/Edit, not via this script)

if [ -s "$ENTRY" ]; then
  if [ -f "$LOG_PATH" ]; then
    { cat "$ENTRY"; printf '\n'; cat "$LOG_PATH"; } > "${LOG_PATH}.tmp" && mv "${LOG_PATH}.tmp" "$LOG_PATH"
  else
    cp "$ENTRY" "$LOG_PATH"
  fi
  echo "SESSION_LOG: $LOG_PATH"
fi
rm -f "$ENTRY"
```

## Phase 3 — Print the close

Two lines exactly, for at-a-glance review and paste:

1. **Session rename suggestion** (the user pastes this as the session name):
   ```
   Rename: [YYYY-MM-DD] <project-or-topic> - <what-was-done>
   ```
   Topic = the project / repo / domain we worked in. "What was done" = the verb-phrase summary, ≤8 words.

2. **Counter summary**:
   ```
   <N> memory updates · <N> commits · SESSION_LOG <updated|skipped>
   ```

If SESSION_LOG was skipped, say `SESSION_LOG skipped (no meaningful changes)` so it's clear that was a deliberate decision, not a bug.

## Session Summary (in-conversation, before the close lines):

### Accomplished
- Completed tasks
- Files created/modified
- Problems solved

### Pending
- Tasks started but not completed
- Known issues to address
- Next steps recommended

### Handoff Notes
- Key decisions made
- Important context for next session
- Any blockers or dependencies
