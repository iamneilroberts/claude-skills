---
name: persona-test
description: |
  Run persona-based subagent tests against a target app through an app-specific adapter.
  Dispatches multiple parallel persona subagents — each role-playing a distinct user type
  (budget-conscious, power user, frustrated first-timer, skeptic, accessibility-first, or
  generated ones) — through the app, judges every resulting run record against a rubric,
  aggregates the results, and always writes a local Markdown report, optionally posting to an
  adapter-declared sink. Triggers on `/persona-test`, `/persona-test changes`, `/persona-test
  issue <N>`, `/persona-test scenario <name>`, "run a persona test", "test this with
  personas", "persona-test this change", "how would different users experience this".
user_invocable: true
args: "[changes|issue|scenario] [--issue N] [--name NAME] [--n K] [--target T] [--adapter A]"
---

# /persona-test — persona-driven subagent testing

Tests an app the way a human QA pass would, but through several distinct simulated users at
once, each following its own persona's goals, temperament, and quit conditions rather than a
scripted test case. Every run produces evidence-scored judged results and a local report;
nothing here depends on any one target app — what's app-specific lives entirely in the
adapter directory the run selects (`adapters/<name>/`, contract documented in
`adapters/example-http/adapter.md`).

## Procedure

### 1. Parse launch intent

Run `persona-test.sh` with the invocation's arguments (mode positional, `--issue`, `--name`,
`--n`, `--target`, `--adapter`, `--min-model`, `--max-model`). It validates and prints the
resolved plan line
(`mode=... n=... adapter=... target=... issue=... name=... min_model=... max_model=...`); exit
0 on success, exit 3 on any malformed input (bad mode, bad flag, `--n` out of 1–10, a
model outside `haiku|sonnet|opus`, `min_model` above `max_model`, a value-taking flag with no
value), exit 0 with usage text for `--help`. Read MODE, N, ADAPTER, TARGET, ISSUE, NAME,
MIN_MODEL, MAX_MODEL off that line — these values drive every following step (MIN_MODEL /
MAX_MODEL are `none` when unset; they bound step 4's per-subagent model choice).

### 2. Load adapter + personas

Read `adapters/<ADAPTER>/adapter.md` for its three required hooks (`reach/interact`, `done`,
`context`) and any declared optional overrides (judge dimensions, pass threshold, sink). Load
the starter persona library at `personas/*.md`.

If N is greater than the starter library's count, generate the shortfall: follow
`lib/generate-personas.md`, giving it the adapter's `context` hook text and
`M = N - <starter count>`. It returns exactly `M` blocks, each delimited by a line
`### FILE: personas/generated/<slug>.md` followed by that persona's four-field body — write
each block's content to that exact path before use. If N is at or below the starter count,
use the first N starter personas as-is and skip generation entirely.

### 3. Build the test plan

Per MODE:

- **`changes`** — inspect `git diff` (or the current branch's PR diff, if one exists against
  its base) to see what actually changed, and derive one or more scenario names from the
  touched surfaces — the plan is "exercise what changed", not a fixed script.
- **`issue`** — fetch issue `ISSUE`'s body and acceptance criteria (e.g. `gh issue view
  <ISSUE>`); the plan is those criteria, one scenario per distinct criterion when there are
  several.
- **`scenario`** — a single named scenario, `NAME`, exactly as given — no inference, the user
  supplied the path to test.

Each (persona × scenario) pair the plan yields becomes one dispatched run.

### 4. Fan out persona subagents

Dispatch one subagent per (persona, scenario) pair per `superpowers:dispatching-parallel-agents`.
Each subagent gets: its persona file's four fields (Goal, Temperament, Constraints,
Interaction tendencies), the adapter's `reach/interact` and `done` hooks, and the scenario. It
role-plays that persona through the app via the reach hook, stopping per the done hook, and
returns one JSON run record. Validate every returned record immediately against
`lib/schema.py`'s `validate_run_record` — a record that fails validation is **dropped** from
the run (never retried, never patched to fit) and counted separately in the final summary.

**Pick each subagent's model by how hard its (persona, scenario) is to role-play, then clamp
to `[MIN_MODEL, MAX_MODEL]`.** Default judgment (both `none`): a happy-path persona whose job
is to walk the obvious flow runs on a cheaper tier (haiku/sonnet); an adversarial or
detail-sensitive persona — the skeptic probing consequences, the power-user hunting silently
dropped params, the accessibility-first reader judging whether output survives being read
aloud — warrants a stronger tier (sonnet/opus) because the finding quality depends on it
noticing subtle failures. Then apply the bounds: `MIN_MODEL` is a floor (never dispatch below
it), `MAX_MODEL` a ceiling (never above it); when they are equal, every subagent runs that one
tier; when a set bound clamps a choice, use the bound. Pin the resolved model explicitly on
every dispatch — never let a subagent inherit the caller's model. The external `codex` driver
(below) is a fixed second-model perspective and is **not** subject to these bounds.

**Hard cap: never dispatch more than 10 persona subagents in one run**, regardless of how
large N × scenario-count computes to — `persona-test.sh` already rejects `--n` above 10, but
this cap also bounds the (persona × scenario) fan-out from step 3, which can multiply past 10
even when N alone is small.

If an external driver (`codex`) is installed — check once, e.g. `command -v codex` —
additionally dispatch **at most one** such driver, running the same role-play against one
representative (persona, scenario) pair, for a second-model perspective. If it is not
installed, drop this step entirely: no error, no placeholder record, and it doesn't count
against the 10-subagent cap.

### 5. Judge each run

For every run record that passed validation, dispatch a subagent following `lib/judge.md`'s
instructions, bundling `rubric.md` verbatim unless the adapter declares a judge-dimensions
and/or pass-threshold override, in which case bundle that override instead. Take the judge
subagent's raw JSON and run it through `lib/normalize.py`'s `normalize_judged` before using it
anywhere downstream — never consume a judge's raw output directly, always through the
normalizer, so a malformed or partial judge response still yields a well-shaped result.

If the loaded adapter declares a judge-dimensions override, call `normalize_judged(raw,
dimensions=<the adapter's dimensions>)` — passing the adapter's own dimension tuple, not the
normalizer's default — so the adapter's scores survive normalization instead of being zeroed
out under dimension keys the judge never populated. If the adapter also declares extra
judged-result fields beyond `normalize_judged`'s fixed output shape (`personaId, scenario,
scores, verdict, severity, rationale, suspectedIssues`), merge those extra fields from the raw
judge JSON back onto the normalized result before step 6, so nothing the adapter needs
downstream gets dropped by normalization.

### 6. Aggregate and report

Feed every normalized judged result through `lib/aggregate.py`'s `summarize`. **Always** write
the local report via `sinks/local_report.py`'s `write(results, runs_dir, run_id)` — this
happens unconditionally, before any adapter sink is attempted, and is never rolled back by
anything that follows. Then, only if the loaded adapter declares a sink, run it: map the
results from step 5 — carrying both the adapter's own-dimension scores and any adapter-declared
extra fields — through the adapter's own mapper if it has one, then post with
`sinks/http_post.py`. A sink failure (network error, missing route, bad auth) does not
invalidate or roll back the already-written local report — surface the failure alongside the
summary, do not fail the whole `/persona-test` run over it.

### 7. Report to the user

Summarize, in the final reply: total / passed / failed / worst_severity (straight from
`aggregate.summarize`'s output), how many records were dropped for failing schema validation,
the local report's path, and the sink's outcome if one ran (posted / no sink declared /
failed, with reason).

## Graceful degradation rules

- **External driver absent** — no `codex` on `PATH` → drop that one dispatch; the run proceeds
  on the subscription persona subagents alone. Never fabricate its result.
- **A run record fails schema validation** — drop that run, count it, keep going; one bad
  record never blocks the rest of the batch.
- **Sink not declared, or declared but fails** — the local report from step 6 stands either
  way; only the reported sink-outcome line changes.
- **Fan-out cap** — 10 persona subagents, hard, independent of how N and scenario-count
  combine.
