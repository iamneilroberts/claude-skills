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

The cross-model review you already run on every lane ("Codex-reviewed (N findings fixed)"),
hardened in the four places the ad-hoc script was soft. **Codex is the judge; the diff is the
defendant; this session does not get to overrule a CRITICAL/IMPORTANT verdict.**

## The four disciplines (why this exists)

1. **Structured verdict** — Codex emits JSON against `sev.schema.json`, not prose. The gate is
   computed from `priority`, not eyeballed.
2. **Don't re-judge the verdict** — the script (`codex-review.sh`) decides pass/fail via exit
   code. When it returns BLOCK items, you **fix or escalate** them; you do **not** argue Codex out
   of a CRITICAL/IMPORTANT. Re-judging Codex with the model that wrote the code is the exact
   independence leak this skill removes.
3. **Infra ≠ clean** — a rate-limit / model-reject / empty-output run exits `2` (INFRA), never `0`.
   Never treat it as a pass and never feed it into a fix loop.
4. **Judge immutability** — `codex-review.sh` + `sev.schema.json` are committed and **must not be
   edited during a review cycle**. You edit source; you never edit the gate that judges it.

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

Run this as a capped loop, not a one-shot — but let the script, not your judgment, decide each gate:

1. **Review.** Run the script for the right target (`--plan` before execution; `--base`/`--staged`
   after TDD, before deploy/merge).
2. **Branch on the exit code:**
   - **0 CLEAN** → done. Note "Codex-reviewed: clean" in the lane summary and proceed to the
     existing gates (`npm run typecheck`, `npm run test`, deploy.sh).
   - **1 FINDINGS** → read `/tmp/codex-review.json`. For each **BLOCK** item (priority ≤ block_at):
     - **CRITICAL (0) / IMPORTANT (1):** fix it. Do not write a rebuttal. If you genuinely believe
       Codex is wrong about a CRITICAL/IMPORTANT, that is a human call — escalate with
       `AskUserQuestion` (quote the finding + your reasoning), do not silently override.
     - **MINOR (2) / NIT (3)** (advisory at the default threshold): use judgment — fix, or note as
       a deliberate skip in the lane summary.
     Then **re-review** (back to step 1).
   - **2 INFRA** → do not proceed and do not loop on it. Retry once; if it persists, surface the
     tail (rate limit? `codex login` expired? model gone?) and stop. An unrun review is not a pass.
3. **Cap the rounds at 3.** If round 3 still returns blocking CRITICAL/IMPORTANT items, stop looping
   and escalate the residual list to the human — burning more Opus rounds past the cap degrades more
   than it fixes.

## Notes

- **Read-only.** Codex runs `-s read-only`; it inspects, it does not edit. All fixes are yours.
- Model fallback (`default → gpt-5.1-codex → gpt-5-codex`) and the read-only sandbox match the prior
  `scripts/codex-review-b-inline.sh`; that one-off can now be replaced by
  `--plan docs/superpowers/plans/2026-06-01-folio-board-vnext-phaseB-inline.md --focus "<its 8 questions>"`.
- Keep this skill's files out of the diff you're reviewing — if a change needs to touch the gate,
  do it in a separate, self-reviewed commit, never mid-cycle.
- Pairs with, does not replace, the deterministic gates: Codex review is the *correctness/security*
  check; `typecheck` + `test` + `test:security` + `deploy.sh` remain the last word.
