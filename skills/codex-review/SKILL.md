---
name: codex-review
description: |
  Get a second opinion on the current change or a plan from a different model (Codex), and
  enforce its verdict mechanically. Codex returns a structured JSON verdict — findings
  scored by priority (0 critical, 1 important, 2 minor, 3 nit) against sev.schema.json — and
  a gate script turns that into a pass/fail exit code, so a critical or important finding
  gets fixed or escalated rather than re-argued by the model that wrote the code. Infra
  failures (rate limit, model reject, empty output) are their own outcome and never count as
  a clean pass. Use after writing tests, before a deploy or merge, or to review a plan before
  execution. Triggers on `/codex-review`, `/codex-review --plan <file>`,
  `/codex-review --base <ref>`, "run a codex review", "get an external review of this diff",
  "codex-review this before I ship".
user_invocable: true
---

# /codex-review — cross-model external review, mechanically gated

Codex is the judge; the diff is the defendant. This session does not get to overrule a
CRITICAL/IMPORTANT verdict.

## Before you run: should you, and how hard?

This tool assumes the review is *warranted now*. If that isn't obvious, run **`/review`** first —
the orchestrator decides whether to review at all, at which gate, and sets the round budget, then
dispatches here. Quick self-gate if you skip it:

- **Plan/spec exists but little/no code** → review the plan (`--plan`), defer the diff review until
  after build. Don't diff-review an empty tree.
- **Trivial / docs-only / tests-only / mechanical rename** → don't review. Reviewing noise erodes
  the signal of a real finding.
- **Just applied a trivial/mechanical fix** → don't re-review; re-review only substantive change.

Before reading any findings, **pre-commit the fix bar**: you will fix CRITICAL/IMPORTANT (a
core-user-journey break, data loss, security, a privacy/cost leak) and **file** MINOR/NIT as issues
rather than fixing them in-loop. Deciding the bar up front is what stops "one more round" creep.

## The five disciplines

1. **Structured verdict** — Codex emits JSON against `sev.schema.json`, not prose. The gate is
   computed from `priority`, never eyeballed.
2. **Don't re-judge the verdict** — `codex-review.sh` decides pass/fail via exit code. For BLOCK
   items you **fix or escalate**; you do **not** argue Codex out of a CRITICAL/IMPORTANT. That
   would forfeit the cross-vendor independence this skill exists for.
3. **Infra ≠ clean** — a rate-limit / model-reject / empty-output run exits `2` (INFRA), never `0`.
   Never treat it as a pass or feed it into a fix loop.
4. **Judge immutability** — `codex-review.sh` + `sev.schema.json` are committed and **must not be
   edited during a review cycle**. Edit source; never edit the gate that judges it. The reverse is
   enforced too: the gate fingerprints the working tree + HEAD before and after, so a reviewer that
   edited your code is INFRA (exit 2), never a verdict.
5. **Verification must be executed, not asserted** — the reviewer runs `workspace-write` so it can
   actually run your typechecker and tests, and is told to prove findings by running them and never
   to restate test counts from commit messages. Read its `notes`: if it claims a pass without naming
   a command it ran, distrust it. See "Why #5 exists" below — this was learned the hard way.

## Usage

```bash
# review the branch diff vs origin/main (default), block on CRITICAL+IMPORTANT:
.claude/skills/codex-review/codex-review.sh

.claude/skills/codex-review/codex-review.sh --base origin/main          # explicit base
.claude/skills/codex-review/codex-review.sh --staged                    # staged diff (pre-commit)
.claude/skills/codex-review/codex-review.sh --worktree                  # unstaged WIP
.claude/skills/codex-review/codex-review.sh --plan docs/superpowers/plans/<f>.md \
    --focus "auth clone forge risk; persist-tail drift; array-index targeting"
.claude/skills/codex-review/codex-review.sh --base origin/main --block-at 2   # also block MINOR
```

Exit codes: **0** CLEAN (pass) · **1** FINDINGS (blocking items exist) · **2** INFRA (did not run
cleanly) · **3** USAGE. Raw verdict JSON is written to `--out` (default `/tmp/codex-review.json`).

## How to drive it (the bounded loop)

Run as a capped loop; the script decides each gate, not your judgment.

1. **Review.** Run the script for the right target (`--plan` before execution; `--base`/`--staged`
   after TDD, before deploy/merge).
2. **Branch on the exit code:**
   - **0 CLEAN** → done. Note "Codex-reviewed: clean" in the lane summary and proceed to the
     existing gates (`npm run typecheck`, `npm run test`, deploy.sh).
   - **1 FINDINGS** → read `/tmp/codex-review.json`. For each **BLOCK** item (priority ≤ block_at):
     - **CRITICAL (0) / IMPORTANT (1):** fix it. Do not write a rebuttal. If you genuinely believe
       Codex is wrong, that's a human call — escalate with `AskUserQuestion` (quote the finding +
       your reasoning), don't silently override.
     - **MINOR (2) / NIT (3)** (advisory at the default threshold): use judgment — fix, or note as
       a deliberate skip in the lane summary.
     Then **re-review** (back to step 1).
   - **2 INFRA** → do not proceed and do not loop on it. Retry once; if it persists, surface the
     tail (rate limit? `codex login` expired? model gone?) and stop. An unrun review is not a pass.
3. **Round budget: set it from risk, extend only on convergence, backstop at 6.**
   Don't default to "loop until clean." Set an initial budget (via `/review`, or: standard diff
   **1**, elevated/multi-file **2**, high-risk auth/privacy/cost/data-loss **2–3**).
   - **Converging** (round N's findings are the same blocking items, fewer/less severe) → you may
     extend by **+1** with a one-line justification in the lane summary.
   - **DEEPENING** (round 2+ surfaces *new, lower-severity* findings rather than confirming the
     round-1 fixes) → **stop. Do not open another round.** New lower-severity findings each round is
     a scope call for the human, not a convergence problem — escalate the residual.
   - **Hard backstop 6, absolute.** If round 6 still returns blocking CRITICAL/IMPORTANT, stop and
     escalate — more rounds past the cap degrade more than they fix.
   Don't re-run on an unchanged diff. If the only remaining findings are ones the human has already
   reviewed and accepted as residuals, that's the terminal state — record them as human-accepted
   and proceed.

## Notes

- **workspace-write, not read-only.** Codex runs `-s workspace-write` so it can execute your
  typechecker and test suite; it is told not to edit, and the gate *enforces* that with a
  before/after tree+HEAD fingerprint (a mutation ⇒ INFRA exit 2). All fixes are still yours.
  Override with `CODEX_REVIEW_SANDBOX=read-only` — but note that mode **cannot run Vitest at all**,
  because Vite must write a temp config file next to `vitest.config.ts` to load a TS config, so the
  reviewer silently drops back to static-only.

### Why #5 exists

This gate ran `-s read-only` until 2026-07-15. Two things were wrong with that, and together they
made the reviewer *look* like it was verifying while it was not:

1. Read-only can't run Vitest (the temp-config write above) — a flaw in the mode choice itself.
2. On Ubuntu 24.04, `kernel.apparmor_restrict_unprivileged_userns=1` blocks unprivileged user
   namespaces. Codex sandboxes with bubblewrap, which needs them, so **every command it tried died**
   (`bwrap: loopback: Failed RTM_NEWADDR`). It could not run *anything*.

It reported verification anyway — "TypeScript type-checking passed" without ever running the
typechecker, and once a precise test count that turned out to be **copied from the diff's own commit
message**. It was reading the author's claims and handing them back as evidence.

The cost, on one real lane: 17 rounds of apparent convergence while a bug that made publishing
permanently impossible sat in the diff untouched. A multi-agent review later found it, plus nine
more, in a single pass — and once the sandbox was fixed, the *same* Codex found six of them in one
round, because it could finally execute.

Two lessons worth keeping:

- **A reviewer that cannot execute is a static reviewer wearing a verification badge**, and its
  reassurance is worse than none, because it reads as evidence. Check the host once:
  `unshare -U -r echo ok` must print `ok` (fix: `kernel.apparmor_restrict_unprivileged_userns=0`).
- **Clean ≠ correct.** A single-reviewer pass reads the diff in isolation and is structurally blind
  to bugs that only appear when you trace call paths across the codebase. Before a non-trivial PR,
  run a multi-reviewer pass as well.
- Keep this skill's files out of the diff you're reviewing — if the gate itself needs to change,
  do it in a separate, self-reviewed commit, never mid-cycle.
- Pairs with, does not replace, the deterministic gates: Codex reviews correctness/security;
  `typecheck` + `test` + `test:security` + `deploy.sh` remain the last word.
