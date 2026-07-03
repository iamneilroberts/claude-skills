---
name: handoff
description: Write a rich session handoff to a pause-*.md file — checklist, decisions, files changed, self-critique, and a verbatim-id "coordinate closet" — so a fresh session can resume the work after /clear (via the auto-resume hook, or /session-resume). Use before you /clear with work still in flight. Triggers on `/handoff`, "write a handoff", "snapshot this session so I can resume later".
user_invocable: true
---

# Write Handoff (auto-loaded on next /clear)

I'll write a rich session handoff to the **`pause-*.md` namespace**. If you run the optional
`hooks/auto-resume.sh` (bundled in this collection), it loads the newest such file automatically on
your next `/clear`, so the fresh session picks it up with zero effort. Without the hook, resume it
manually with `/session-resume`.

> Why `pause-` and not `handoff-`: the `auto-resume.sh` hook globs `pause-*.md` only. The
> `handoff-*.md` prefix is reserved for long-lived multi-session coordination docs and is
> intentionally NOT auto-loaded. So this command writes `pause-<date>-<topic>.md` even though it's a
> "handoff" — that prefix is what guarantees pickup.

## Steps

1. **Gather git state** (run these):
   - `git rev-parse --show-toplevel` (repo/worktree root — resolves correctly inside a worktree)
   - `git branch --show-current`
   - `git status --short`
   - `git diff --stat`
   - `git log --oneline -8`

2. **Summarize from this session's memory** — write these sections:
   - **What Was Accomplished** — completed work with file paths / commit SHAs
   - **Decisions Made** — key choices + rationale
   - **Files Created or Modified** — table: path · action · why
   - **Checklist** — snapshot your **current TodoWrite list** as GitHub-style
     boxes: `- [x]` for completed/`- [ ]` for pending/in-progress. This is the
     part that vanishes on `/clear` unless you write it down. If you have no
     active TodoWrite list, derive the checklist from Remaining Work. **Carry
     forward** any unchecked items from the prior handoff's checklist that
     aren't done yet, so todos survive across multiple `/clear`s.
   - **Self-Critique** — before writing Remaining Work, answer five questions honestly about
     this session (adapted from the r/ClaudeAI "I end every AI session with two questions" thread):
     (1) what you're **least confident about** (list all, not one); (2) the **biggest thing being
     missed** about the situation; (3) if this **breaks in 3 months, the likely reason** (future
     fragility, not present state); (4) **what you did NOT do** — skipped/deferred/stubbed/assumed;
     (5) for each item in (1) and (4), the **exact test or command** that would confirm or kill it.
     **Right-size it** — a long-but-simple session may need only one honest line; scale up for
     complex / risky / shipped work. **Capture, don't chase:** fold findings into Remaining Work /
     Open Questions, or offer to `/idea` the standalone ones — do NOT stop to fix them here.
   - **Remaining Work** — actionable next steps with specific paths
   - **Open Questions** — anything needing the user's input
   - **Coordinate Closet** — see the trailing-block rule below. This is the
     lossless safety net: prose summaries drop exact identifiers, the closet
     does not.

   Also **mirror the checklist to the durable file** `<base>/docs/summaries/CHECKLIST.md`
   (overwrite it with the same `## Checklist` block + a `_Updated: {date} — {branch}_`
   line). That file is the stable, single-path source of truth that survives even an
   abrupt `/clear` where only a mechanical hook fires.

3. **Resolve output path** (worktree-aware):
   - Base = `git rev-parse --show-toplevel`
   - If `<base>/docs/summaries/` exists, write there; else create `<base>/.claude-sessions/`
   - Filename: `pause-{YYYY-MM-DD}-{topic-slug}.md` (topic-slug = 2–3 word kebab summary). **The `pause-` prefix is mandatory** — it's what `auto-resume.sh` matches.

4. **Write the file** (atomic: write `.tmp`, then `mv`). It MUST contain, in this order:

```markdown
# Session Handoff: {Topic}
**Date:** {YYYY-MM-DD} at {HH:MM}
**Repo:** {output of git rev-parse --show-toplevel}
**Branch:** {branch}
**Uncommitted changes:** {yes/no}
**Transcript:** {transcript_path if known, else "(current session)"}

## What Was Accomplished
...
## Decisions Made
...
## Files Created or Modified
| File | Action | Why |
|------|--------|-----|
...
## Git State
```
{git status --short}
```
## Checklist
<!-- snapshot of the TodoWrite list — resume rebuilds TodoWrite from these boxes -->
- [x] {completed item}
- [ ] {pending item}
- [ ] {in-progress item} (in progress)

## Self-Critique
<!-- Honest end-of-session gaps — least-confident, missing, fragile, not-done, + how to check each. -->
- **Least confident:** {shaky spots — all of them}
- **Biggest thing being missed:** {framing blind spot}
- **If it breaks in 3 months:** {most likely reason — future fragility}
- **Did NOT do:** {skipped / deferred / stubbed / assumed}
- **How to check:** {for each uncertainty/gap above, the exact test or command that confirms or kills it}

## Remaining Work
...
## Open Questions
...
## Coordinate Closet
<!-- Exact ids/paths/SHAs/PR-refs/key=value pairs scraped VERBATIM from this
     session — use these as exact ids/paths/values when the narrative above
     omits or summarizes detail. Newest-first, deduped. Each opaque id (bare
     UUID / hex) is labeled with its nearest key (`7fd5835b (changelog_id)`). -->
- `{verbatim id/path/sha/ref}` ({nearest-key label, if the value is opaque})
- ...

## Instructions
Resume this work. **First, re-create the TodoWrite list** from the `## Checklist`
section above (one TodoWrite entry per `- [ ]` unchecked item; mark `- [x]` items
done or omit them) — if `docs/summaries/CHECKLIST.md` exists and is newer, prefer
it. Then summarize the above for the user and run `git status` /
`git branch --show-current` to confirm state matches this handoff (warn on any
mismatch — different branch, unexpected changes). Present the rebuilt checklist +
Remaining Work and ask whether to continue or do something else.
```

   The `## Instructions` section is **required** — the `auto-resume.sh` hook rejects any handoff without it as "incomplete."

5. **Offer to commit it** (don't force): handoffs read from disk, so an uncommitted one auto-loads fine within the same worktree — but committing it (`git add <file> && git commit -m "docs(handoff): <topic>"`) makes it durable and visible to other worktrees. Ask: "Commit the handoff, or leave it uncommitted?"

6. **Confirm to the user**, exactly:
   ```
   Handoff written: <path>
   → if the auto-resume.sh hook is installed, this loads on your next /clear; otherwise run
     /session-resume. Safe to /clear now.
   ```

---

## Coordinate Closet — the trailing-block rule

Prose is lossy: when a section gets summarized, exact identifiers (SHAs, KV
ids, ports, absolute paths, PR/issue refs) are the first thing to evaporate —
and they're exactly what the resuming session needs to act without re-deriving.
The Coordinate Closet is a deterministic safety net that conserves them verbatim
regardless of how the narrative compresses.

Build it by scraping THIS session's transcript (your own tool results +
assistant text, plus operator-pasted values) for carry-worthy literals:

- **What to nominate**, in priority order (id-shaped wins under any cap):
  UUIDs → hex ids ≥12 → short mixed-hex 8–11 (`b602c1e8`, `rail-1f6be5b4`:
  must hold ≥1 letter AND ≥1 digit, so dates like `20260610` and hex-words like
  `deadbeef` are skipped) → absolute paths → `key=value`/`key: value` pairs
  whose value bears a digit/`/`/`@` (`port=3002`, drop prose like
  `mode=continuous`) → issue refs `#1234`.
- **Newest-first, deduped** (boundary-aware: `6787` is NOT covered by `67870`).
- **Label opaque ids** (bare UUID/hex) with their nearest preceding key or
  prose subject — `"changelog_id":"7fd5835b"` → `7fd5835b (changelog_id)`,
  `commit b602c1e8` → `b602c1e8 (commit)`. Self-describing values (paths, KV
  pairs, `#refs`) need no label. Never let one hash label another.

This mirrors a small verbatim-identifier-scraping algorithm from context-warp-drive (MIT); here
it's applied by hand to the session trace rather than in code.

## Length budget (optional — only when a hard size cap is set)

If a handoff must fit a byte/char cap, don't truncate top-to-bottom (that
starves whatever's last). Instead split **fill order** from **display order**:

- **Fill** sections in IMPORTANCE order — Coordinate Closet and Checklist
  first (never drop the lossless data), then Remaining Work, Decisions, the
  rest — each section capped at its own share of the budget.
- **Display** them in READING order (the template order above), so the doc
  still reads top-to-bottom.
- When a section overflows its cap, **truncate the middle**, not the tail:
  keep ~58% head + ~42% tail joined by a `…[N chars omitted]…` marker, so both
  the opening context and the closing state survive.

Without a cap, skip this entirely — write every section in full.
