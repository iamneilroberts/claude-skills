# /sitrep synthesis rules (main thread)

## 1. Validate digests
Every claim must have all schema fields. A lane that errors, returns nothing, or returns a claim missing fields makes that source a DATA GAP — record it, don't invent its contents.

## 2. Conflict resolution — by claim_type (NOT one global order)
When two claims share a `subject` but disagree, the winner depends on `claim_type`:

| claim_type | authority order (highest first) |
|---|---|
| shipped / code-state | live prod + git > current docs (handoffs/journals) > specs > chat history > memory |
| architecture / intended-design | spec/ADR + vestige decisions > chat history > inferred-from-code |
| priority | MILESTONES.md > everything |
| intention | vestige intentions + specs (always FUTURE; never current state) |
| loose-end | backbone git/filesystem state > everything (direct fact — an unpushed commit / unchecked box / stale worktree either exists or it doesn't) |

FRESHNESS GATE: a `historical`-lane claim never overrides a `backbone`-lane claim whose `source_ts` is newer than the CONTINUITY LAG reported by the historical lane. Historical = signal, never current-state evidence.

## 3. Curator escalation score
For each claim that matters to a verdict or the diff, sum points; escalate to the curator subagent when score >= 3:
- +2 touches prod behavior / data integrity / security / billing
- +2 contradicts the top-tier source for its claim_type
- +1 missing primary evidence pointer (hypothesis)
- +1 stale (source_ts > 14 days) but feeding a proposed next-action
- +1 a user-visible promise in a handoff/spec not found in git or prod

To escalate: `Agent(subagent_type: "curator", prompt: "<the specific claims, verbatim, with their evidence pointers>")`. Fold its CONTRADICTED / UNVERIFIED / VERIFIED verdicts back into the report. Do NOT re-implement verification yourself.

## 4. Failure semantics
- Any DATA GAP is listed in the report's "Sweep completeness" section.
- If a BACKBONE source is a DATA GAP, set the report status to `INCOMPLETE SWEEP` and WITHHOLD sections 3 (Milestone-anchored next steps) and 5 (Proposed MILESTONES.md diff). Report what was gathered; do not reset priorities on partial truth. Section 2 (Loose ends / at-risk) is NEVER withheld — loss-risk items are exactly what a partial sweep still needs to surface.
- Historical-lane gaps degrade gracefully: note them, proceed.
