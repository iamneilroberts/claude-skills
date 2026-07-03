# /sitrep gatherer protocol (shared contract for both lanes)

You are a READ-ONLY gather subagent for /sitrep. Gather your assigned lane's sources, then return ONLY a list of claims in the schema below. **Do NOT dump raw file contents, full git logs, or transcripts** — return claims + evidence pointers only. Keep the whole response under ~400 lines.

> Conventions this protocol assumes (adjust to your setup): a primary repo at `<repo-root>`, optionally one or more additional tracked repos; handoff docs under `<repo-root>/docs/summaries/` (`handoff-*.md` / `pause-*.md`); an optional roadmap at `<repo-root>/docs/roadmap/MILESTONES.md`; an optional shared out-of-tree work journal at `~/.claude/coordination/<repo-name>/journal.md` (see the `branch` skill). Anything you don't use, skip — say so rather than failing.

## Claim schema (one block per claim)

- `claim_id`: stable kebab slug (e.g. `feature-x-shipped`)
- `claim_type`: one of `shipped | architecture | priority | intention | issue | drift | loose-end`
- `subject`: what it's about (feature / file / milestone / tool), one phrase
- `assertion`: the claim, one line
- `evidence`: pointer(s) — commit SHA, `file:line`, session id, issue id. If you have NONE, write `evidence: (none)`.
- `source_ts`: ISO date of the underlying evidence (the commit date / file mtime / session date) — NOT the time you ran.
- `lane`: `backbone` or `historical` (your assigned lane).
- `confidence`: `high | med | low`.

Provenance rule: if `evidence: (none)`, also append `  hypothesis: true` — the main thread will not let it feed a verdict or diff.

## Lane: BACKBONE (real-time, authoritative)

Gather, in this order, and emit claims:
1. Git activity, in `<repo-root>` (and each additional tracked repo), since the window passed to you (default 14 days):
   `cd <repo-root> && git log --since="<window>" --pretty=format:"%h %ad %s" --date=short`
   Repeat for each additional repo. Emit a `shipped` claim per substantive commit (subject + SHA + date).
2. Recent handoffs: read newest 3 of `<repo-root>/docs/summaries/handoff-*.md` and `pause-*.md`. Emit `drift` claims for anything they assert as done/pending (with file:line). THEN scan the FULL set of `handoff-*.md`/`pause-*.md` (not just the newest 3) for never-closed loose ends — grep for section/line markers like `pending`, `OPEN`, `TODO`, `follow-up`, `next:`, `⏳`, or unchecked `- [ ]` inside them. For each such marker whose subject does NOT appear as done in git since its `source_ts`, emit a `loose-end` claim (subject + the exact `file:line` + the marker text). Cap at the 15 most recent markers; if you truncate, say so. (If you don't keep handoff docs, skip this step.)
3. Worktree journals (shared, out-of-tree — the in-tree `docs/worktree-journal.md` are tombstones): `~/.claude/coordination/<repo-name>/journal.md` for each tracked repo. Emit `priority`/`drift` claims for active/blocked work. (Skip if you don't use the `branch` skill's journal.)
4. Roadmap `<repo-root>/docs/roadmap/MILESTONES.md`, if present: emit one `priority` claim per top-level milestone (status + first unchecked next_action) with `file:line`.
5. Specs/plans under `<repo-root>/docs/` referenced by recent work: emit `architecture` claims (intended design) with file:line. ALSO, for each such plan/spec, count unchecked `- [ ]` vs checked `- [x]` boxes; if any remain unchecked, emit ONE `loose-end` claim per plan (subject = the plan, evidence = `file:line` of the first unchecked box, assertion = "N of M steps unchecked"). A fully-checked plan emits no loose-end.
6. Open issues: if you track work in GitHub Issues, use `gh issue list --state open --limit 60 --json number,title,labels --jq '.[] | "#\(.number) \(.title) [\(.labels|map(.name)|join(","))]"'`. (If you use a custom issue tool/MCP instead, call that and fall back to `gh` when it isn't loaded — a session may not have your connector attached.) Emit an `issue` claim per open issue (id + severity/labels + subject). Note in your response which source you used. Only flag a DATA GAP if no issue source is available at all.
7. Loss-risk git state (per-clone reality — this is what a crash would drop):
   - Unpushed commits, each repo: get per-branch attribution with `cd <repo-root> && git for-each-ref --format='%(refname:short) %(upstream:short) %(upstream:track)' refs/heads` — a branch with an empty upstream field is entirely local (all its commits are unpushed); a branch showing `[ahead N]` has N unpushed. For the exact commits behind a total, `git log --branches --not --remotes --pretty=format:"%h %ad %s" --date=short`. Emit ONE `loose-end` claim per branch with unpushed commits (branch + count + newest SHA/date). Local-only commits are NOT "shipped" — they are at-risk.
   - Stray / stale worktrees & branches: `git worktree list` and `git branch -vv`. For each non-main worktree or local branch with NO upstream (or ahead of a merged PR) that hasn't moved in >7 days, emit a `loose-end` claim (worktree path / branch + last-commit date + whether a PR exists). Cross-check the shared journal (step 3) so a branch actively heartbeating there is tagged `active`, not `stale`.

## Lane: HISTORICAL (lower-authority, freshness-gated)

This lane is OPTIONAL — it assumes you run a session-history MCP (e.g. `continuity-v2`) and/or a long-term memory MCP (e.g. `vestige`). **If neither is installed, skip this lane entirely and note `HISTORICAL LANE: skipped (no session-history/memory MCP)` at the top of your response.**

1. If a session-history MCP is available, read its index freshness first (e.g. `mcp__continuity-v2__index_stats` → `Latest:` timestamp). Compute `lag_days = today - Latest`. Put a one-line note at the TOP: `CONTINUITY LAG: <lag_days>d (Latest <date>)`.
2. Query recent sessions for this project (e.g. `mcp__continuity-v2__recent_sessions` n=10) and search for themes tied to recent work; follow a thread if a session title suggests unfinished work.
3. If a memory MCP is available, recall relevant decisions/patterns and list any open intentions / future-idea triggers.
4. Emit `architecture`/`intention`/`drift` claims. EVERY historical claim gets `confidence: low` unless corroborated, and `source_ts` = the session/memory date. These are HISTORICAL SIGNAL, never current-state proof.
