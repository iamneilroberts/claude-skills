---
name: sweep
description: Use when work may have been dropped between sessions — after a crash, a lockup, parallel-session churn, or on a "did we drop anything?" hunch. Crawls worktrees, local AND remote branches, stashes, deploy targets, and intent docs (handoffs, checklists, plans, coordination journals); triages every item against ground truth (patch-id merge equivalence vs fetched origin/main, live BUILD_SHA/bundle provenance, PR state); presents a ranked loose-end ledger for ONE batch approval; then methodically recovers approved items via playbooks (adopt stray WIP, resume handoffs, rebase→test→push→PR). Never deploys, merges to main, force-pushes, or prunes autonomously. Complements /sitrep (read-only state-of-union) and a live project-board skill if you have one (e.g. /pm); triggers on /sweep, "sweep for dropped work", "what did we lose in the crash", "find stranded work", "recover dropped work", "loose ends sweep".
user_invocable: true
---

# /sweep — dropped-work sweep & recovery

Find work stranded between "exists on disk" and "merged + deployed"; recover it
methodically after one batch approval. Born from a real multi-session crash recovery
(2026-07-09) — every detection below corresponds to a failure mode that actually
happened.

## Invocation & scope

- `/sweep` — current repo + every `git worktree list` entry of it (default).
- `/sweep all` — every repo in the Config table below.
- `/sweep <path>` — a named repo (+ its worktrees).

## Config (edit this table for your repos — this is a template)

| Repo | Policy | Deploy provenance |
|---|---|---|
| `~/dev/my-app` | normal | BUILD_SHA via `/version` endpoint (see Provenance notes) |
| `~/dev/my-app-web` | normal | web bundle hash → commit mapping (see Provenance notes) |
| `~/dev/my-app-legacy` | report_only | deprecated; findings report-only / port-out |

**Provenance notes** (exact commands live here, NOT in the table — markdown tables
mangle pipes):

```bash
# my-app: prod + staging stamp BUILD_SHA
curl -s https://<your-worker>/version   # {"sha":...,"env":"production"}
curl -s https://<your-staging-host>/version               # {"sha":...,"env":"staging"}
# arbiter when HTTP is ambiguous: npx wrangler deployments list (or your platform's equivalent)

# my-app-web: bundle hash, mapped to a commit READ-ONLY
curl -s https://<your-app>/ | grep -o 'index-[^"]*\.js'
# map via `git log --oneline -- web/` history + your deploy tool's release list.
# NEVER run a local build during discovery/triage (a local build writes build
# artifacts — violates the non-destructive rule). Unmappable read-only →
# report "DATA GAP: bundle-hash unmapped".

# a repo with no SHA endpoint: /health proves liveness only — there is NO deployed-SHA source.
curl -s https://<your-app>/health
# Deploy-surface comparison for this repo is BY DESIGN a stated limitation, not an
# error: record "deploy provenance: liveness-only (no SHA endpoint)" in the ledger's
# completeness section. Do not hunt for a SHA; do not mark it DATA GAP.
```

Coordination journals: your coordination/worktree journal (plus any `handoffs/`
directory it references). In-repo `docs/worktree-journal.md` may be a tombstone
pointing elsewhere — ALWAYS follow the pointer (the active journal is the one that
counts for staleness/heartbeats).

**Policy semantics:** in a `report_only` repo the only dispositions allowed are
`report-only` and `port-out` (recover content INTO a `normal` repo); Phase 4 refuses to
execute any mutation inside the repo — enforced at execution time, not just proposal
time. Discovery skips `git fetch` there (use existing refs; note their fetch age).

## Ground rules (non-negotiable)

1. **Machinery state is not ground truth.** Journal/handoff/memory lines saying
   "SHIPPED" or "PENDING" are claims. Verify every claim against the real artifact:
   git containment, live BUILD_SHA/bundle hash, an HTTP read, `gh pr list`.
2. **Discovery/triage are non-destructive.** Exactly three writes are permitted in
   Phases 1–3: (a) `git fetch` in `normal` repos (remote-tracking refs only — never
   checkout/pull/working-tree); (b) the ledger file; (c) nothing else. Use
   `git fsck --unreachable --no-reflogs`, NEVER `--lost-found` (it writes).
3. **One batch gate; individual re-asks on top.** Recovery runs only after the user
   approves the ledger. Even inside an approved batch, ALWAYS re-ask individually:
   prod/staging deploys, ANY push to a shared/protected branch (fast-forward
   included), merges to main, `--force-with-lease`, branch/worktree deletion,
   discarding any diff. Recovery stops at PR-opened; deploys are recommendations
   with the exact gated command, never executed.
4. **Respect other sessions.** Uncommitted WIP you didn't create belongs to someone
   else until proven stale (file mtimes + ACTIVE journal heartbeats + live sessions —
   the `orphaned-wip-adopter` staleness test if you have it — otherwise apply the
   staleness test inline: file mtimes + journal heartbeats + live sessions — but read
   the ACTIVE journal per Config, overriding that skill's own
   `docs/worktree-journal.md` reference). Active work is `leave-active` / DO-NOT-TOUCH:
   never staged, stashed, or built on.
5. **Zero findings in a category is stated explicitly** (silence reads as "not
   checked"). A source that errors is a DATA GAP — report it, never invent.

## Phase 1 — Discover (read-only)

Dispatch one subagent per repo (Agent tool, `model: sonnet` pinned), each prompted:
"Read `~/.claude/skills/sweep/references/discovery-protocol.md`. Sweep <repo-path>
(policy: <policy>). Deploy-provenance hints: <the repo's full Config-table row +
Provenance notes>. Coordination journal: <resolved journal path for this repo>.
Return the finding list only." The dispatcher COPIES the config context into the
prompt — the subagent cannot see this SKILL.md. Dispatch all repos in one message
for `/sweep all`.

## Phase 2 — Triage

For each finding, run the checks in
`~/.claude/skills/sweep/references/triage-rules.md` (main session, or one sonnet
subagent per repo for large sweeps — a triage subagent's prompt must ALSO carry the
repo's Config row and resolved journal path, since it cannot see this SKILL.md;
supersession judgment calls may use `model: opus`).
Every surviving item carries: evidence command + output (REDACTED per triage-rules),
the claim it contradicts (if any), one-line proposed fix, proposed disposition.

## Phase 3 — Ledger + the single gate

Write the ledger (template below) to `docs/digests/YYYY-MM-DD-sweep.md` in the repo
/sweep was invoked from — never into a `report_only` repo; if the invoking directory
is `report_only` or not a repo, write
`~/.claude/coordination/sweep/YYYY-MM-DD-<repo>-sweep.md` instead.
**No-clobber:** if the filename already exists (same-day re-sweep), NEVER overwrite
— the existing Recovery log is the checkpoint record of what already executed. Write
`YYYY-MM-DD-sweep-2.md` (`-3`, …), link the prior ledger at the top, and carry its
executed/blocked items forward so nothing re-runs. Present the
compact table in-chat and ask the user to approve/edit/veto the batch — ONE question,
listing each item's id, category, one-liner, and proposed disposition.

### Ledger template

```markdown
# /sweep — YYYY-MM-DD (<scope>)

**Status:** COMPLETE | DATA GAPS: <list>
**Baseline:** origin/main = <sha> · prod = <sha/provenance> · staging = <sha> (per repo)

## 1. LOSS-RISK (would vanish on disk death)
- [ ] SW-1 <worktree/branch> — <uncommitted diff / unpushed commits / stash> ·
      evidence: `<cmd>` → `<output>` · fix: <one-liner> · proposed: <disposition>
## 2. NEEDS MERGE
## 3. NEEDS DEPLOY (commands given, never run)
## 4. NEEDS RECONCILE
## 5. SUSPECT ARTIFACTS
## 6. UNFINISHED INTENT
## 7. HYGIENE

(each category: items as above, or "None found — checked.")

## Recovery log   <!-- Phase 4 appends here; checkpoint after EVERY item -->
- [ ] SW-<n>: <outcome line>
```

## Phase 4 — Recover (only after approval)

Execute approved items in category order, one at a time, via the matching playbook in
`~/.claude/skills/sweep/references/recovery-playbooks.md`. After EVERY item update
the ledger's Recovery log (`- [x]` + outcome) — a second crash mid-sweep must itself
be sweepable. Re-ask individually per ground rule 3. `report_only` repos: refuse
in-repo mutation; `port-out` only.

## Non-goals

Not a daily-driver digest skill (if you have one), not a live project board (if you
have one, e.g. /pm), no issue-tracker sweep (if you have one), no memory/chat-history
mining lane (/sitrep's historical lane covers that here, if present). Never
merges to main, deploys, force-pushes, or prunes autonomously.
