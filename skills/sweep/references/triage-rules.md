# /sweep triage rules (Phase 2 — the comparison engine)

Answer "did this land?" MECHANICALLY for every discovery finding. Truth baseline is
fetched `origin/main` (never local main — a stale local main is itself a finding).

## Checks, per finding type

**Merged?** Two independent signals, NEITHER sufficient alone:
(a) `git cherry origin/main <branch>` — `-` = equivalent upstream, `+` = not.
Catches rebases/cherry-picks; does NOT catch multi-commit squash-merges (the squash
commit's combined diff matches no single commit's patch-id).
(b) `gh pr list --head "${branch#origin/}" --state merged --json number,mergeCommit`
(strip the remote prefix — GitHub matches the PR head branch name, never the
remote-tracking refname) — catches squash-merges.
A branch is "unmerged" only when BOTH say so. If `gh` errors (auth, rate limit),
that signal is a DATA GAP: report the item as MERGE-STATUS UNCERTAIN — never file
NEEDS MERGE on cherry evidence alone.

**Partially merged?** Count `git cherry` `+` vs `-`: "N of M commits have main
equivalents" — the `+` delta is the loose end. List the delta subjects.

**Deployed?** Is the content reachable from each environment's live SHA?
First confirm the live SHA exists locally: `git cat-file -e <live-sha>^{commit} || echo "DATA GAP: live SHA not in local objects — fetch or wrangler-verify"`.
Then distinguish all three outcomes — exit 1 (not ancestor) is evidence, exit 128
(bad object) is a DATA GAP, never "absent":
`git merge-base --is-ancestor <commit> <live-sha>; case $? in 0) echo deployed;; 1) echo absent;; *) echo "DATA GAP: is-ancestor errored";; esac`.
Both directions: merged-but-not-deployed = NEEDS DEPLOY (carry any "HELD"/"rides next
go" context found in journals); deployed-from-unmerged-branch = NEEDS MERGE (name the
branch: `git branch -a --contains <live-sha>`).

**Ride-along constraints:** before proposing ANY merge, grep the ACTIVE journal +
handoffs for the branch name. Documented couplings ("must merge WITH X in one PR")
are quoted verbatim in the finding and the proposed action honors them.

**Superseded?** Files the stranded work touches, reworked on main after its
merge-base — use the exact topological range, never a date filter (commit dates lie:
an old branch merged yesterday carries old dates):
`git diff --name-only <merge-base> <branch> | while read f; do hits=$(git log --oneline <merge-base>..origin/main -- "$f"); [ -n "$hits" ] && echo "OVERLAP $f:"; echo "$hits"; done`.
Overlap = flag `discard-superseded?` — ALWAYS a proposal for human judgment
(if genuinely ambiguous, this is the one triage call that may use an opus subagent).

**Active?** Staleness test before anything is touchable: newest dirty-file mtime,
ACTIVE journal heartbeats for that worktree/branch (per SKILL.md Config journal
resolution), running sessions. Anything arguably active → `leave-active`, category
listed but DO-NOT-TOUCH.

**Suspect artifact?** For `vision-check` findings: Read the image; does it depict
what the consuming code's comment/filename says? Verdict + one-line description into
the ledger.

**Unresolved intent markers:** verify the marker's subject against ground truth
(the Merged?/Deployed? checks above) before reporting — a PENDING line whose subject
actually shipped is reported as a stale-claim NEEDS RECONCILE (fix: append the
resolution line), not as pending work.

## Category assignment (rank order)

1. LOSS-RISK — uncommitted diffs, unpushed commits/branches, stashes, dangling commits
2. NEEDS MERGE — unmerged/diverged/partially-merged branches; deployed-from-unmerged
3. NEEDS DEPLOY — merged, live-verified absent; include the exact gated command (e.g. `npm run deploy:prod -- --yes`) — command is GIVEN, never run
4. NEEDS RECONCILE — behind/diverged local mains (ff-only vs rebase-then-STOP), stale journal claims, orphaned PENDING/HELD markers
5. SUSPECT ARTIFACTS — vision-check mismatches
6. UNFINISHED INTENT — plans/handoffs/specs with unchecked work and no artifact
7. HYGIENE — shipped-but-unpruned worktrees (squash-aware via `gh pr list --head <branch> --state merged`; STRIP the remote prefix first — GitHub matches the head branch name, so `origin/claude/foo` must be queried as `claude/foo`: `gh pr list --head "${branch#origin/}" --state merged`), aged parked WIP

## Evidence & redaction (every ledger item)

- evidence command + its actual output (trimmed to the decisive lines)
- **REDACT:** no credential values, ever — env-var names only; scrub `Authorization:` header values and `?token=` query values from captured output
- the claim it contradicts (file:line of the journal/handoff line), if any
- one-line fix
- proposed disposition: `recover-via-<playbook>` / `discard-superseded` / `park` / `leave-active` / `report-only` / `port-out` (`report_only` repos: last two only)
