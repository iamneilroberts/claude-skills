---
name: review
description: |
  The top-level review verb — decide WHETHER, WHEN, WHICH, and HOW HARD to review a change
  before reaching for a review tool. Assesses the situation (a plan vs a diff, the risk surface,
  what changed since the last review, rounds already spent), picks the lightest review shape the
  risk justifies (in-session self-review → cross-model → multi-model panel), sets an initial
  round budget it will extend only on convergence, and dispatches. Exists to stop review spirals:
  reviewing before the plan is formed, reviewing after every trivial edit, or looping a reviewer
  past the point of convergence. Triggers on `/review`, "should I review this", "what review does
  this need", "is this worth a codex-review / panel".
user_invocable: true
---

# /review — the review orchestrator (whether / when / which / how hard)

`/review` does not blindly review — it **assesses the situation, picks the right review shape, sets
a round budget, and then runs it** (either an in-session self-review, or by dispatching to a
cross-model gate). Reviewing badly is worse than not reviewing: reviewing before the plan is formed
wastes a pass, reviewing after every trivial edit trains you to ignore findings, and looping a
reviewer past convergence *degrades* the change.

## The ladder (lightest → heaviest)

Escalate for **independence and thoroughness**, not out of habit. Start at the lightest tier the
risk justifies:

1. **light — in-session self-review (Phase 3B).** *I* review the diff. Fastest and cheapest (no
   external model, no process spawn). Its weakness is exactly its cost: it's the author grading its
   own work — **least independent** — so it's for **low-risk** diffs and as a first pass before
   escalating.
2. **cross-model — `/codex-review`** (if present). One independent external model (different
   vendor), mechanically gated. Reach here when the diff is non-trivial or self-review's
   independence isn't enough.
3. **panel — `/review-panel`** (if present). Multiple independent reviewers, pre-merge. For complex
   or elevated-risk (privacy/cost/data-loss/money) diffs where a mistake is asymmetric.

## Phase 1 — Assess (read, don't guess)

- **Artifact state:** a *plan/spec* with little/no code, a *diff* (`git diff --stat <base>` — size,
  file count), or both?
- **Risk surface** (the multiplier): elevated when the change touches auth/tokens, permissions/
  access control, **private data**, **per-user cost / metered spend**, data deletion/migration,
  persistent-store writes, money, or a shared wire contract. Low when it's docs, tests, copy, a
  mechanical rename, or a localized pure-function tweak with tests.
- **Blast radius:** flag-gated & dark vs live-to-users vs shipped-on-merge.
- **Review history this lane:** rounds run, and is the trend *converging* (fewer/less severe) or
  *DEEPENING* (new lower-severity findings each round)?

## Phase 2 — Choose a shape and set a round budget

| Situation | Shape |
|---|---|
| Plan/spec exists, little/no code | **Defer the diff review.** Review the *plan* now. Catching an architecture gap here is ~free; after N tasks it's a rebuild. |
| Trivial / docs-only / tests-only / mechanical rename | **No review.** Say why in one line. |
| Normal feature diff, low risk | **light** (Phase 3B) or a single **cross-model** pass — one gate, not both. |
| Complex OR elevated-risk diff, pre-merge | **panel**, `--focus`-flagged at the exact risk. |
| Multi-task lane | Budget the lane: plan review now → one review per *substantive* task → **one** panel pre-merge. Don't panel every task. |
| Already reviewed, only trivial edits since | **Don't re-review.** |

**Round budget — set from risk, extend only on convergence:**
- Skip **0** (trivial) · Standard **1** · Elevated/multi-file **2** · High-risk (auth/privacy/cost/data-loss) **2–3**.
- **Converging** → may extend **+1** with a one-line justification in the lane summary.
- **DEEPENING** (round 2+ surfaces *new, lower-severity* findings instead of confirming the round-1
  fixes) → **stop. Escalate the residual to the human.** It's a scope call, not a convergence
  problem — do not open another round.
- **Hard backstop 6, absolute.** Reaching it means escalate, never a 7th.

**Conditional dispatch:** use `/codex-review` for the cross-model shape and `/review-panel` for the
panel shape *if they exist in this project*; otherwise fall back to the **light** self-review at the
chosen budget, and say so.

## Phase 3A — Dispatch (cross-model / panel)

Invoke `/codex-review` (single) or `/review-panel` (panel) for the target (`--plan <file>` before
build; `--base`/`--staged` after). Carry the anti-spiral rules (below). Those skills own their exit
codes — don't re-run the deterministic gates by hand.

## Phase 3B — Light in-session self-review

The cheap mode: **I** review the diff for real problems and grade every finding by evidence.

**Evidence ladder** — each finding gets one tag; nothing is a confirmed bug unless provable:
- **CONFIRMED** — traced the full path (file:line → file:line, 3+ steps) or a concrete triggering
  input. Only CONFIRMED is blocking.
- **LIKELY** — strong reasoning, one inferred link. **POSSIBLE** — an untraced smell, informational.
  **UNFOUNDED** — considered and ruled out.

Rule: if I can't trace it to lines or produce a triggering input, it's at most POSSIBLE. Keeps the
blocking list short and trustworthy.

**Assumption-verification (run first).** For each changed file: *"what must be true elsewhere for
this to actually run?"* — then verify instead of trusting. Generic categories:
- **Wiring** — a new/edited unit is actually registered/imported where the system loads it
  (coded-but-not-wired ships silently).
- **Config/env** — new settings/secrets are declared where the code reads them, gated, and
  documented; deploy/CI config agrees (no sibling-file drift).
- **Contract stability** — public names, response keys, routes, and stored-data keys are unchanged
  unless changing them is the point.
- **Every mutation site** — a new field on a stored shape is set at *all* write paths, not just the
  new one.

**Domain checks:** schema/API consistency across consumers; concurrency correctness (unguarded
read-modify-write on eventually-consistent stores); auth on every new entrypoint; security
(secrets, input validation, injection, output encoding); common bugs (null/undefined, swallowed
errors, off-by-one, missing `await`); quality (dead code, needless complexity).

**Output:** per finding **[TAG]** `file:line` — what it is, why it bites, the fix; trace or
triggering input for CONFIRMED. Lead with CONFIRMED/LIKELY, then POSSIBLE as a short list.

## Anti-spiral rules (apply in every mode)

1. **Pre-commit the fix bar BEFORE reading findings.** Fix CRITICAL/IMPORTANT (core journey, data
   loss, security, privacy/cost leak). MINOR/NIT → **file as issues, don't fix in-loop**.
2. **DEEPENING = terminal** (Phase 2). Stop and escalate; don't open another round.
3. **Don't re-review after a trivial/mechanical fix** — only after substantive change.
4. **The author never overrules a cross-model CRITICAL/IMPORTANT by re-arguing** — that forfeits the
   independence. Genuine disagreement is a human escalation, not a silent override.
