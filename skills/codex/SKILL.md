---
name: codex
description: Delegate a task or question to the OpenAI Codex CLI running as an isolated subagent, then relay its answer. Use when the user invokes /codex <prompt>, says "ask codex", "have codex look at / do X", or wants a second independent model to investigate a question or make a self-contained edit. Read-only by default; /codex --write lets Codex edit the working tree. Distinct from /codex-review, which is the structured JSON review gate — /codex is a general-purpose Codex delegate.
---

# /codex — delegate to the Codex CLI via a subagent

Runs the OpenAI Codex CLI (`codex exec`) on the user's prompt inside a **dispatched
subagent**, so Codex's (possibly large) output stays out of the main context and you relay
only its answer. Codex is a genuinely independent model — good for a second opinion, an
adversarial read, or offloading a self-contained investigation or edit.

Helper: `codex.sh` (this skill's dir) runs `codex exec`, captures only Codex's final
message (`-o`), and falls back across models on failure.

## When to use
- `/codex <prompt>` — hand any question or task to Codex against this repo.
- "ask codex to …", "have codex look at …", "get codex to write / refactor …".
- NOT the structured review gate — that's `/codex-review`.

## How to run

1. **Parse the invocation.** Everything after `/codex` is the PROMPT. Flags:
   - `--write` → Codex may edit the working tree (workspace-write sandbox). Default is read-only.
   - `-m <model>` → pin a Codex model. `--dir <path>` → working root (default: repo root).

2. **Dispatch ONE subagent** (Agent tool, `subagent_type: general-purpose`). Pin the model
   explicitly: `haiku` for a plain ask/relay; `sonnet` if Codex is making edits and you want
   the result sanity-checked. Give it this task (substitute `<SKILL_DIR>` = this skill's base
   directory, and `<PROMPT>`):

   > Run the Codex CLI and return its final answer VERBATIM — trim only banner/progress
   > noise, do not summarize or editorialize. Run:
   > `printf %s '<PROMPT>' | bash <SKILL_DIR>/codex.sh [--write] [--stats] [-m MODEL] -`
   > (stdin form avoids quoting problems for long or quote-heavy prompts). If the script
   > exits non-zero, report its stderr line so the caller can retry. If `--write` was used,
   > also run `git status --short` and `git --no-pager diff` afterward and include a short
   > list of what Codex changed.

   **Only pass `--stats`** when the user asked for Codex's token usage or API cost (e.g. a
   model comparison / cost accounting). It appends a token-usage + estimated-cost block after
   the answer; relay that block verbatim. Omit `--stats` for normal delegation so output stays
   clean. Cost is an estimate — override the rates with `CODEX_PRICE_INPUT_PER_M` /
   `CODEX_PRICE_CACHED_PER_M` / `CODEX_PRICE_OUTPUT_PER_M` if the model's real pricing differs.

3. **Relay Codex's answer** to the user, attributed ("Codex says:") so it's clear this is the
   second model, not you. If `--write` was used, review the diff the subagent returned and
   summarize what Codex changed **before trusting it** — never present Codex's edits as
   verified without looking at the diff.

## Notes
- Read-only is the safe default; pass `--write` only when the user clearly wants Codex to
  edit files.
- Codex's output is not ground truth. Verify anything that matters — especially `--write`
  edits — against the actual code and the test suite.
- If `codex.sh` reports rate-limit / auth failure, tell the user and offer to retry (or try a
  different `-m` model). If it exits 3 (`CODEX-INFRA: empty final message`), the run is an
  infra failure — never interpret it as a completed task; any `--write` diff is unreviewed
  salvage.

## Constraint design (MANDATORY for --write dispatches)

Never issue a constraint set whose only nominal success path is gaming. In particular, never
combine "change behavior" with "all existing tests must stay green" — that exact combination
has produced a manufactured green in practice (dozens of suites pinned to legacy exports via
`vi.mock`/import aliases so the new behavior was never exercised). Reformulate: "expected
failures are FINDINGS — list them; do not make them pass." Every implementation prompt MUST
include:

1. The escape hatch, verbatim or equivalent: "If any existing test fails and the fix is not a
   straightforwardly legitimate assertion update, or any two instructions here conflict: STOP,
   report, and change nothing to work around it. A stopped run with a clear report is a
   SUCCESS; a green suite obtained by mocks, aliases, wrapper exports, fixture reshaping, or
   snapshot regeneration is a FAILURE."
2. A disclosure ledger requirement: counts of test files changed, assertions changed
   (before/after), mocks/aliases added (must be 0), snapshots touched (must be 0 or itemized).
3. Scope fences (CREATE-ONLY / READ-ONLY file lists — these have a clean track record).
4. Your repo's fixture rules restated whenever tests will be written (Codex never sees your
   CLAUDE.md): fixtures derive from the REAL writer; relative dates only; assert independently
   enumerated values, never the code-under-test's own output.

## Verification (before trusting any --write result — applies to EVERY worker, not just Codex)

- Tier 0 (always): independently re-run every claimed command; run the mechanical mock sweep
  `git diff -U0 -- '*.test.*' | grep -nE '^\+.*(vi\.(do)?mock|Legacy)'` — any hit is an
  automatic stop; an empty final message is INFRA (codex.sh exits 3), never a result; record
  the model id + token count into your run log.
- Tier 1 (new tests/fixtures): tautology + reader-shaped-fixture spot-check; a couple of
  targeted mutants on the claimed-critical logic.
- Tier 2 (live behavior / "behavior-preserving"): a behavioral old-vs-new capture diff is the
  non-negotiable gate; the instrument must not be solely authored by the same worker; use a
  top-tier model for the verification wrapper, doing an adversarial code READ, not a suite
  re-run.
- Wrapper protocol: after launching a background codex job, arm a monitor on the process;
  the driver arms a backstop. Silence long past job completion is a defect, not a signal to
  assume success.

## Retirement rule

One manufactured-green incident (mocked/aliased/tautologized tests presented as passing
verification) retires Codex from that lane immediately. Re-entry, if any: greenfield-only,
Tier-2 verification, several consecutive clean packages, never sole author of a verification
instrument.
