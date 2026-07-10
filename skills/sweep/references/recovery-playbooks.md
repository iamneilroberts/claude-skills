# /sweep recovery playbooks (Phase 4 — only after batch approval)

Execute in ledger category order, ONE item at a time. After EVERY item append to the
ledger's Recovery log: `- [x] SW-<n>: <outcome>` (or `- [ ] SW-<n>: BLOCKED — <why>`).
A second crash mid-recovery must itself be sweepable.

Universal re-asks (even inside the approved batch): prod/staging deploys · ANY push
to a shared/protected branch, fast-forward included · merges to main ·
`--force-with-lease` · branch/worktree deletion · discarding any diff.
`report_only` repos: NO in-repo mutation — `port-out` only.

## Stray uncommitted diff (proven stale)

Follow the `orphaned-wip-adopter` skill if you have it, with ONE override: staleness
reads the ACTIVE journal from /sweep's Config (follow the in-repo tombstone pointer),
not `docs/worktree-journal.md` literally. Adopt or rebuild per its decision table.
If you don't have that skill, apply the staleness test inline — file mtimes + journal
heartbeats + live sessions — then decide by hand: adopt (commit the WIP, note
provenance) or rebuild (discard and redo). Discards re-ask either way.

## Documented handoff

`/pickup`-style resume: worktree + context load ONLY. Batch approval authorizes the
RESUME, not the work — stop where pickup's own gate sits (first concrete next step
presented, confirmation asked). The handoff work itself is a new lane, not part of
the sweep.

## Unpushed / unmerged branch

1. `git fetch`
2. **Materialize the branch in its own worktree — never operate on the current
   checkout.** Local branch already in a worktree: work there. Local branch with no
   worktree: `git worktree add <repo>-sweep-<branch-slug> <branch>`. REMOTE-ONLY
   branch (exists only as `origin/<name>`):
   `git worktree add <repo>-sweep-<branch-slug> --track -b <name> origin/<name>`.
   The playbook's input interface is the ledger item's branch name WITH its
   remote-prefix status, so the executor knows which form applies.
3. Rebase onto origin/main INSIDE that worktree (rebase-then-push, never push-then-rebase —
   publishing stale history forces a rewrite). If the branch already exists on the
   remote and the rebase makes the push non-fast-forward, `--force-with-lease`
   re-asks explicitly.
4. Repo's own gates: typecheck + tests (e.g. `npx tsc --noEmit && npm run test`).
5. Push the feature branch (feature branches under the batch approval; SHARED branches re-ask).
6. Open the PR (repo's review convention; note ride-along constraints from the ledger
   in the PR body). RECOVERY STOPS HERE — merge is the user's.

## Merged-not-deployed

Recommendation only. Ledger line already carries the exact gated command
(e.g. `npm run deploy:prod -- --yes`). Do NOT run it — surface it in the final
summary under "awaiting your deploy".

## Behind / diverged local main

**`git status` FIRST, always** — uncommitted edits you didn't make in that clone
belong to another session: surface and STOP, never pull or rebase under them (the
worktree-awareness rule; this is the one Phase 4 step that touches a working tree
another session may be using). Clean tree + behind only: `git pull --ff-only` (no
re-ask). Diverged: rebase the local commits onto origin/main locally, then STOP —
the push to main re-asks individually. NEVER force-push over origin/main; if the
rebase conflicts with another session's pushed work, surface and stop.

## Suspect artifact

Present the vision verdict + the concrete correction (regenerate asset per the
consuming code's expectation, or fix the consumer). The fix commit always follows
the unpushed-branch playbook (its own branch + PR) — no direct-to-main shortcut.

## Prunable worktree

`gh pr list --head <branch> --state merged` re-verified live, then `/branch done
<slug>` + `git branch -D <branch>` — deletion, so it re-asks. Parked WIP: offer park
(push, remove worktree, keep branch, journal `## Parked` entry) instead of delete.
