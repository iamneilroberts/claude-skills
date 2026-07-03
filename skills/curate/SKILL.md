---
name: curate
description: Verify a session's or handoff's factual claims against ground truth before trusting them. Dispatches the read-only `curator` subagent to check claims against git, files, and read-only environment checks, plus the repo's invariants doc if any, and returns a confabulation report for human spot-check. Use at pass boundaries — resuming from a handoff, before a deploy, or whenever a prior session's summary looks suspiciously clean. Triggers on `/curate`, "curate this", "verify these claims", "check the handoff for confabulation", "is this actually done".
user_invocable: true
---

# /curate — confabulation check before you trust a claim

Runs the `curator` subagent (read-only) over a set of claims and returns a verdict report. This is
the in-loop guard against claims that sound done but aren't — fabricated tool results, "prod-ready"
work that only passed local smoke, stale audit claims treated as current.

> Requires the `curator` agent (`agents/curator.md` in this collection) installed to
> `~/.claude/agents/`. The out-of-tree journal lookup in step 1 is optional — it only applies if you
> also use the `branch` skill; otherwise that bullet is skipped.

## Steps

1. **Determine the target** (in priority order):
   - An explicit argument — a file path, or a claim/list of claims the user pasted → use it.
   - Else the newest `docs/summaries/pause-*.md` under the repo root (`git rev-parse --show-toplevel`).
   - Else the `## Active` entry for this session in the shared out-of-tree journal at
     `$(bash ~/.claude/coordination/resolve-coord-dir.sh)/journal.md` (the in-tree
     `docs/worktree-journal.md` is a tombstone — do not read it).
   - Else this session's own stated accomplishments since the last checkpoint.
   If you can't find a target, ask the user what to curate — don't curate nothing.

2. **Dispatch the curator.** Call the Agent tool with `subagent_type: curator`, passing the target
   (the file path, or the extracted claims verbatim). The curator reads the repo's invariants doc
   (e.g. `LAWS.md`) itself, if one exists. For a deeper-reasoning pass on a high-stakes deploy, you
   may override its model to `opus`.

3. **Surface the report.** Print the curator's report as-is. **Lead with CONTRADICTED items** —
   those are the lies. Then the high-impact UNVERIFIED items. Do not bury them under VERIFIED rows.

4. **Never auto-fix.** The curator is a guard, not a fixer. Present findings; let the human decide
   what to re-check, correct, or override. If they confirm a recurring confabulation pattern (e.g.
   "handoffs keep claiming prod-ready off local smoke"), offer to append a one-line OPEN observation
   to `~/.claude/skill-observations/log.md` tagged to the relevant skill, so the pattern accumulates.

## Notes
- Read-only by contract: the curator never edits, deploys, or mutates any store. If you find
  yourself wanting it to "just fix" something, stop — that's a separate, explicit action the human
  approves.
- This skill is also invoked automatically by `/session-pause` (step 4.5) and `/session-end`
  (Phase 1.5) so handoffs and session logs are curated before they're trusted.
