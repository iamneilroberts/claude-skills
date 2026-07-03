---
name: sitrep
description: Use when the user invokes /sitrep — an occasional "state of the union" re-orientation sweep. Verifies what has actually shipped versus what handoffs, specs, memory, and chat history claim shipped (across git in one or more repos, handoff docs, specs, optional chat-history/memory MCPs, and open issues), surfaces loose ends and loss-risk (unpushed commits, stale/stray worktrees & branches, unchecked plan boxes, never-closed handoff pending sections), then resets what matters next as a milestone-anchored list plus a bounded off-roadmap-drift section. Writes a report to docs/digests/ and proposes (never applies) a roadmap diff. Triggers on /sitrep, "state of play", "what's actually shipped", "what did I leave hanging", "re-orient me on this project".
user_invocable: true
---

# /sitrep — state of the union re-orientation

> **Optional integrations** (all degrade gracefully — the sweep still runs without them): a `curator` verification subagent (see `agents/curator.md` in this collection) for escalated claims; a session-history MCP and a memory MCP for the historical lane; a `docs/roadmap/MILESTONES.md` for milestone anchoring; sibling skills `/pm` and `/focus`. If you don't have one, that step is skipped and noted as a DATA GAP rather than failing.

Occasional deep sweep. Three jobs: verify shipped-vs-claimed, surface loose ends / loss-risk (unpushed commits, stale worktrees, unchecked plans, unclosed handoffs), and reset what's next. Read-only except for the report file it writes; the MILESTONES.md change is PROPOSED, never applied.

Boundary vs `/pm`: `/pm` is the live at-a-glance in-progress board (daily); `/sitrep` is periodic truth-reconciliation. The loose-ends/at-risk section here is loss-risk & staleness reconciliation, not the live board.

## Step 1 — Args + window
`/sitrep` takes no required args. Determine the git/since window: read the newest prior `docs/digests/*-sitrep.md`; if found, window = its date → today; else default 14 days. Pass the window string (e.g. `14 days ago` or `2026-05-14`) to the backbone lane.

## Step 2 — Dispatch both lanes IN PARALLEL
In a single message, dispatch two general-purpose subagents (Agent tool, no subagent_type):
- BACKBONE: "Read `~/.claude/skills/sitrep/references/gatherer-protocol.md`. Act as the BACKBONE lane, window=<window>. Return only the claim list."
- HISTORICAL: "Read `~/.claude/skills/sitrep/references/gatherer-protocol.md`. Act as the HISTORICAL lane. Return only the claim list with the CONTINUITY LAG note at top."

## Step 3 — Validate digests
Read `~/.claude/skills/sitrep/references/synthesis-rules.md` §1. For each lane: confirm schema completeness; mark missing/errored sources as DATA GAPs.

## Step 4 — Synthesize
Per synthesis-rules.md §2–§4: group claims by subject, resolve conflicts by claim_type + freshness gate, compute the escalation score, dispatch the `curator` subagent for claims scoring ≥3, fold verdicts back. Route `loose-end` claims into section 2 (rank Loss-risk → Stale → Unfinished); a `loose-end` is a direct git/fs fact so it rarely escalates, but DO curator-check any loose-end that contradicts a `shipped` claim (e.g. a handoff says "shipped" but the commits are unpushed). Determine INCOMPLETE SWEEP if any backbone source is a gap.

## Step 5 — Write report + terminal summary
Write `docs/digests/YYYY-MM-DD-sitrep.md` (overwrite if it exists) using the template below. Then print a terminal summary: status (OK / INCOMPLETE SWEEP), CONTRADICTED count, loss-risk count (loose-ends in the Loss-risk bucket), the single top next-action, and the report path. Do not paste the full report into chat.

### Report template
````
# /sitrep — YYYY-MM-DD

**Status:** OK | INCOMPLETE SWEEP
**Window:** <since> → today · **Continuity lag:** <N>d

## 1. Shipped vs claimed
### CONTRADICTED (look here first)
- <claim> — <curator verdict / evidence> · confidence <h/m/l> · freshness <date>
### Unverified
- <claim> — why unconfirmed
### Verified shipped
- <claim> — <SHA/date>

## 2. Loose ends / at-risk   <!-- always shown, even on INCOMPLETE SWEEP -->
From `loose-end` claims, ranked most-at-risk first. Omit a bucket if empty; if all three are empty, write "None — tree, plans, and handoffs are clean."
### Loss-risk (would vanish on a crash)
- <unpushed-commit / uncommitted-nothing> — <branch/repo · count · newest SHA/date>
### Stale (in-flight but untouched >7d)
- <stale worktree / branch> — <path/branch · last-commit date · PR? · `active` if heartbeating the journal>
### Unfinished (committed but not closed out)
- <plan with unchecked boxes / handoff pending section> — <file:line · "N of M unchecked" or marker text>

## 3. Milestone-anchored next steps   <!-- WITHHELD if INCOMPLETE SWEEP -->
Iterate milestones top-to-bottom, first unchecked next_action; anything explicitly parked "below the line" is NEVER suggested. If you keep a roadmap (`docs/roadmap/MILESTONES.md`) consume it; otherwise anchor to the most recent priorities from the handoffs/journal. (If you have a `/focus`-style daily driver, consume today's digest instead of recomputing.)
- **Primary — M<n>:** <next_action>
- **Backfill — M<m>:** <next_action>

## 4. Off-roadmap drift (max 3, propose-only)
- <item> — impact: <…> — tag: `roadmap-it` | `consciously-defer-until-<date>`

## 5. Proposed MILESTONES.md diff   <!-- WITHHELD if INCOMPLETE SWEEP -->
Bounded to `status:` + `- [ ]/[x]` next_action lines ONLY. Never add/remove milestones; never touch below-the-line. Per-hunk rationale. PROPOSED — apply only on user approval.
```diff
<hunks>
```

## 6. Sweep completeness
- Loaded: <sources>
- DATA GAPS: <sources that failed, or "none">
````

## Behavior rules
- No fabrication; DATA GAP over invention.
- Read-only: never apply the diff; never edit specs/memory/prod. Writing the report file is the only write.
- Idempotent same-day overwrite.
- Off-roadmap section: hard cap 3, mandatory tag, propose-only.
