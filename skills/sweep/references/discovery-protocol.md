# /sweep discovery protocol (Phase 1 — subagent brief)

You sweep ONE repo (+ its worktrees). Policy `normal` or `report_only` is given.
You are READ-ONLY except: `git fetch` once, and ONLY if policy is `normal`.
Never checkout, pull, stash, stage, or touch any working tree. Findings are raw
observations — triage happens later; report, don't judge, and NEVER guess: a source
that errors is reported as `DATA GAP: <source> — <error>`.

## A. Git surface

1. `git fetch` (normal policy only; report_only → note fetch age: `stat -c %y .git/FETCH_HEAD`).
2. Baseline: `git rev-parse origin/main` (or upstream default branch: `git symbolic-ref refs/remotes/origin/HEAD`).
3. Worktrees: `git worktree list --porcelain`. For EACH worktree:
   - `git -C <wt> status -sb --untracked-files=all` (ahead/behind + dirt)
   - `git -C <wt> rev-list --count @{u}..HEAD` and inverse (skip if no upstream — that IS a finding: unpushed branch)
   - dirty/untracked files: `stat -c "%y %n" <files>` for staleness evidence
4. Branches — local AND remote heads:
   - `git for-each-ref --format='%(refname:short) %(upstream:trackshort)' refs/heads`
   - `git for-each-ref --format='%(refname:short)' refs/remotes/origin | grep -v HEAD`
   - for each branch not merged: `git rev-list --left-right --count origin/main...<branch>` + `git merge-base --fork-point origin/main <branch> || git merge-base origin/main <branch>` → date it (`git show -s --format=%ci <mb>`). Two-sided nonzero = divergence; note merge-base age so stale forks rank lower.
5. Stashes ONCE per repo (worktrees share the stash ref): `git stash list --format='%gd %ci %s'`.
6. Dangling: `git fsck --unreachable --no-reflogs 2>/dev/null | grep 'unreachable commit' | head -20` — count + `git show -s --format='%h %ci %s'` each. NEVER `--lost-found` (it writes).

## B. Deploy surface

1. Discover targets from the repo: wrangler config (`wrangler.toml`/`wrangler.jsonc` routes), `scripts/deploy*.sh`, CLAUDE.md deploy sections, plus the Config hints passed in the dispatch.
2. Read live provenance per environment (BUILD_SHA `/version` endpoints; bundle hash mapped to commit; `wrangler deployments list` as arbiter when HTTP is ambiguous).
3. Compare vs origin/main and branch tips: live SHA not an ancestor of origin/main → name the branch that contains it (`git branch -a --contains <sha>`). origin/main ahead of live SHA → pending-deploy backlog (`git rev-list --count <live>..origin/main`).
4. **Edge-cache rule:** a stale bundle read with `cf-cache-status: HIT` is NOT a failed deploy. Verify via a never-cached path or `wrangler deployments list`; retry the cached path after ~60s before concluding.
5. **Redaction:** if a probe needs a bearer, reference it by env-var name (e.g. `$STAGING_AUTH_KEYS_BEARER` from `.env`) — never paste the value into your finding.

## C. Intent surface

1. `docs/summaries/pause-*.md`, `docs/summaries/handoff-*.md`: pending sections, `## Instructions`, unchecked `- [ ]` boxes. Newest-first; note file dates.
2. `docs/summaries/CHECKLIST.md`, `docs/superpowers/plans/*.md`: unchecked tasks (count "N of M unchecked").
3. Specs/ADRs (`docs/superpowers/specs/`, `docs/adr/`) with no implementation reachable from origin/main (grep main's tree for the feature's identifiers). NO time window — stranded work older than any window is precisely the target.
4. Journals — in-repo `docs/worktree-journal.md` AND your external coordination journal + `handoffs/`. If the in-repo file is a tombstone/pointer, follow it. Scan for: PENDING, HELD, "NOT deployed", "deploy pending", "rides the next prod go", "will run", unchecked merge/deploy boxes. For each marker, check whether any LATER entry resolves the same subject — only unresolved markers are findings.

## D. Cross-session artifact seams

Binary assets (images/fonts/media) added ACROSS ALL REFS
(`git log --all --since="90 days ago" --diff-filter=A --name-only -- '*.jpg' '*.png' '*.webp' '*.gif' '*.svg'`
— without `--all` you only see the checked-out branch and miss assets landed on
other branches). The 90-day window is a PERFORMANCE bound only and MUST be stated in
your CHECKED list ("assets checked: last 90 days") — a windowed scan never produces
an unqualified "none found". Flag any asset whose path is consumed by code from a
DIFFERENT branch/session. Consumer search must cover every worktree of the repo, not just the
current checkout: `git worktree list --porcelain | awk '/^worktree /{print $2}'`
then `grep -rl "<basename>" <each-worktree>/ --include='*.css' --include='*.html' --include='*.ts' --include='*.tsx' --include='*.js'`
(consumers often live on an unmerged feature worktree). Cross-session = the asset
commit and the consuming code come from different branches/sessions → mark
`vision-check` for triage.

## Return format

One line per finding, with a sequential per-repo id:
`<id D-1,D-2,…>|<class>|<repo>|<subject>|<evidence cmd>|<evidence output, redacted, ≤200 chars>`
plus a `DATA GAPS:` section (or `DATA GAPS: none`) and a `CHECKED:` list of every
source class you completed, so zero-findings classes are provably checked.
