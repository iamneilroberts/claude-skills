# Design Spec — `/persona-test` skill

_Date: 2026-08-18 · Repo: `claude-skills` (public) · Path: `skills/persona-test/`_
_Status: design approved in chat (2026-08-18); awaiting spec-review gate before writing-plans._

## 1. Purpose

A distributable Claude Code skill that runs **persona-based subagent tests** against an
app-under-test. On launch it spins up N persona-playing subagents (default 5) that each drive the
app end-to-end through a pluggable adapter, an LLM judge scores each run against a rubric, and
normalized results are written to a pluggable sink (default a local report; example Voygent adapter
POSTs to the shipped persona-QA admin board).

Design goals: **public-installable and generic** (no app hardcoded in the skill body), **zero API
cost** (all personas + judge run as Claude *subscription* subagents via the Agent tool), and
**graceful degradation** (optional external agent / optional POST sink drop out cleanly when absent).

## 2. Scope (v1) and non-goals

**In scope (v1):**
- Interactive invocation only (`/persona-test [args]`).
- Three pluggable seams: **adapter**, **persona set**, **sink**.
- Starter persona library + a per-run persona generator.
- One Claude judge subagent scoring on named dimensions.
- Local-report sink (always) + generic HTTP POST sink.
- Two shipped adapters: `example-http` (generic reference) and `voygent` (example → persona-QA board).
- Optional one external persona-driver (codex) when the CLI is installed.

**Non-goals (v1):** CI/headless mode; a formal plugin registry or config-schema validator; a judge
panel; persistent cross-run trend storage inside the skill (the sink owns persistence). These are
deferred, not designed-in.

## 3. Locked decisions (from brainstorming)

| # | Decision |
|---|----------|
| Q1 System-under-test | Generic, **adapter-driven**. Voygent is the first configured adapter, not the target. |
| Q2 Interaction channel | **Adapter decides** per app (HTTP/MCP, CLI, or conversational). |
| Q3 Personas | **Starter library (`personas/*.md`) + generator** for domain-specific ones. |
| Q4 Judging | **Single judge subagent, scored dimensions** (0–5) + pass/fail + severity. Threshold = skill default, adapter-overridable. |
| Q5 External agent | **Extra persona-driver** (e.g. codex), same run-record schema; **silent degrade** to all-Claude if absent. |
| Q6 Sink | **Local report (default, always) + pluggable HTTP POST sink.** Voygent example POSTs to persona-QA board. |
| Launch modes | **`changes` (default) / `issue` / `scenario`.** Default when no direction given = `changes`. |
| Parallelism | Default **N=5**, hard cap **10**, all subscription subagents, +1 optional external. |

## 4. Architecture — three-stage pipeline

```
launch intent ──► SETUP ──► EXECUTION ──► JUDGE + SINK
                   │            │              │
        adapter + persona set   fan-out        judge scores each run
        + test plan (mode)      N subagents    ──► normalized results
                                +1 external?    ──► sink(s)
```

Three pluggable seams isolate everything app-specific:

- **Adapter** — how to reach the app, how a persona interacts, what "done" means, and app context
  for the generator/judge. The make-or-break contract (§6).
- **Persona set** — starter library files + optional generated personas (§7).
- **Sink** — where normalized results go (§9).

The skill body orchestrates; it never references a specific app.

## 5. Package layout

```
skills/persona-test/
  SKILL.md                     # orchestration + launch-intent parsing
  rubric.md                    # shared scoring vocabulary (dimensions + severity)
  personas/                    # starter library (generic personas)
    budget-traveler.md
    power-user.md
    frustrated-first-timer.md
    cautious-skeptic.md
    accessibility-first.md
  lib/
    run.sh                     # entrypoint helper (parse args, orchestrate)
    generate-personas.md       # generator prompt/instructions (subagent-driven)
    judge.md                   # judge prompt/rubric binding (subagent-driven)
    run-record.schema.json     # canonical run-record shape (§8)
    sinks/
      local-report.md          # renders results -> Markdown/HTML under runs dir
      http-post.md             # generic authenticated POST sink
  adapters/
    example-http/
      adapter.md               # generic reference adapter
    voygent/
      adapter.md               # MCP driver + persona-QA board mapping/sink
  runs/                        # gitignored; local-report output lands here
```

Skill logic is expressed as Markdown instruction files the orchestrator + subagents follow (the
repo convention), with light Bash glue in `lib/run.sh`. No compiled deps.

## 6. Adapter contract (the critical seam)

An adapter is a Markdown declaration + a small set of hooks answering three questions:

- **reach / interact** — `invoke(personaTurn) -> appResponse`. The adapter owns the channel: an
  HTTP/MCP call, a CLI invocation, or a conversational turn. The skill only passes the persona's
  next intended action and receives the app's response.
- **done** — a predicate describing task completion for a scenario, so a persona subagent knows when
  to stop.
- **context** — app facts (domain, key flows, "what good looks like", known constraints) consumed by
  the persona generator and the judge.

Optional adapter overrides: judge dimensions + pass threshold, a result **mapper** (transform the
canonical run record into a sink-specific shape), and a sink binding.

**`example-http` adapter** — drives a generic HTTP JSON app; documents the contract by example for
public users.

**`voygent` adapter** — reaches the app via the MCP `/mcp` StreamableHTTP endpoint (reusing the
existing `voygent-mcp.sh` driver pattern: `local`/`staging`/`prod` targets, bearer auth). Declares a
mapper + POST sink targeting the persona-QA board (§9.2).

## 7. Personas

- **Starter library** (`personas/*.md`): reusable, app-agnostic personas. Each file declares a
  persona's goals, temperament, constraints, and how it tends to interact.
- **Generator** (`lib/generate-personas.md`): a subagent reads the adapter's `context` and
  synthesizes M domain-specific personas for the target app, in the same file shape.
- Default run = starter library personas, optionally topped up / replaced by generated ones when the
  launch mode or adapter asks for domain specificity.

## 8. Run record (canonical schema)

Every persona driver (Claude subagents and the external agent alike) returns the **same** structured
run record:

```json
{
  "personaId": "string",
  "personaSource": "library | generated | external",
  "scenario": "string",
  "mode": "changes | issue | scenario",
  "steps": [{ "intent": "string", "appResponse": "string", "note": "string" }],
  "completed": true,
  "observations": ["string"],
  "suspectedIssues": [{ "summary": "string", "severity": "blocker|major|minor" }]
}
```

The judge consumes run records; sinks consume the judge's normalized results. `run-record.schema.json`
is the source of truth and is validated before judging.

## 9. Judge and sinks

### 9.1 Judge
One judge subagent scores each run against `rubric.md`:
- Dimensions (0–5, adapter-overridable): **task-completion**, **correctness**, **ux-friction**.
- **verdict**: `pass | fail`; **severity** (`blocker|major|minor`) on fails; short rationale.
- Pass threshold: skill default (documented in `rubric.md`), overridable per adapter.

Normalized judged result per run:
```json
{
  "personaId": "string", "scenario": "string",
  "scores": { "task_completion": 0, "correctness": 0, "ux_friction": 0 },
  "verdict": "pass|fail", "severity": "blocker|major|minor|none",
  "rationale": "string",
  "suspectedIssues": [{ "summary": "string", "severity": "..." }]
}
```

### 9.2 Sinks
- **`local-report` (default, always runs):** writes a Markdown/HTML report of all judged runs under
  `skills/persona-test/runs/<timestamp>/` — per-persona verdicts, scores, and an aggregate summary.
- **`http-post` (generic):** POSTs normalized results to a configured URL with a bearer token from a
  named env var. Adapter supplies URL, token env var name, and an optional mapper.

**Voygent sink mapping — matches the shipped persona-QA board contract (voygent-lite prod `a58e150c`):**

- Endpoint: `POST /admin/persona/ingest` on the Voygent host.
- Auth: `Authorization: Bearer $PERSONA_INGEST_TOKEN` (constant-time SHA-256 compare server-side;
  route is inert/404 until the secret is set). `401` on bad/missing bearer, `405` on wrong method.
- **Batch-only:** one POST = one whole run; all persona rows go in a single `rows[]` array.
- Request body the Voygent mapper must produce:
  ```json
  {
    "runId": "string (<=120)",
    "date": "string (<=40)",
    "rows": [{
      "scenario": "string (<=120, required)",
      "scores": {
        "comprehension": 0, "elicitation": 0,
        "free_surface": 0, "funnel": 0
      },
      "fabricationCount": 0,
      "crossCheckPassed": true,
      "terminatedBy": "string (<=80)"
    }],
    "issues": [{
      "number": 1, "url": "https://...",
      "status": "open|fixed|retested",
      "title": "string", "scenario": "string", "note": "string"
    }]
  }
  ```
  Server stores latest full snapshot at KV `_health/persona-runs` and prepends a summary to the
  bounded history ring `_health/persona-runs/history` (max 30). Success → `200 {ok:true, runId, rows}`.
- **Mapping note:** the board's dimensions are Voygent-specific and differ from the generic judge
  dimensions. The Voygent adapter's judge override scores directly in the board's vocabulary
  (`comprehension/elicitation/free_surface/funnel`, `fabricationCount`, `crossCheckPassed`,
  `terminatedBy`) so the mapper is a straight field copy, not a lossy re-projection. Generic adapters
  keep the default `task_completion/correctness/ux_friction` dimensions.

## 10. Execution & orchestration

- Fan out N persona subagents via `superpowers:dispatching-parallel-agents` (Agent tool =
  subscription, no API cost). Default N=5, hard cap 10.
- Optional **external driver**: if a supported external CLI (codex) is installed, launch one extra
  driver that runs a scenario and returns the same run record. Absent → silently all-Claude.
- Launch-intent parsing selects the **test plan**:
  - `changes` (default): derive scenarios from the git diff / latest PR since last deploy.
  - `issue`: derive scenarios from a named issue's acceptance criteria.
  - `scenario`: run a named trip-type / persona end-to-end path.
  - No direction given → `changes`.
- Missing details → the skill asks at most a couple of clarifying questions, else picks documented
  defaults ("just decide" branch).

## 11. Error handling & degradation

- External CLI absent → drop the external driver, log one line, continue.
- POST sink unreachable / 401 / route 404 (token unset) → local report still written; sink failure
  reported, run not lost.
- A persona subagent that errors → its run recorded as `completed:false` with the error; judging and
  the report proceed for the rest.
- Adapter `invoke` failure → surfaced in that run's steps; does not abort the batch.

## 12. Testing strategy

- **Harness self-tests:** a known-good run record and a known-bad one exercise schema validation and
  the judge rubric wiring without a live app.
- **`example-http` smoke:** run the pipeline against a tiny local stub HTTP app; assert a report is
  produced and verdicts are shaped correctly.
- **Voygent mapper unit check:** feed a judged-result fixture through the Voygent mapper and assert
  the produced body matches the ingest contract in §9.2 (field names, caps, batch shape).
- **Sink failure path:** point `http-post` at an unreachable URL; assert local report still lands and
  failure is reported.

## 13. Open items to resolve during writing-plans

- Exact `lib/run.sh` argument grammar (`/persona-test changes`, `... issue #N`, `... scenario <name>
  --n 5 --target staging`).
- Where the Voygent adapter reads its target/token (env vars vs a local config file) — must not
  commit secrets; document the required env vars in the adapter's README.
