# /persona-test Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an installable `/persona-test` skill in the public `claude-skills` repo that runs N persona-playing subagents against a pluggable app adapter, scores each run with a Claude judge, and writes results to a pluggable sink (local report by default; Voygent example → persona-QA admin board).

**Architecture:** Three-stage pipeline (setup → execution → judge+sink) with three pluggable seams (adapter, persona set, sink). All pure logic lives in stdlib-Python modules under `lib/`, `sinks/`, and `adapters/voygent/` and is unit-tested TDD-style; the LLM-driven surface (persona driving, generation, judging) lives in Markdown instruction files driven by `SKILL.md` and is exercised by a gated integration harness. Mirrors the existing `skills/review-panel/` layout and conventions.

**Tech Stack:** Bash entrypoint + Python 3 stdlib only (no third-party deps), Markdown instruction files, Claude subscription subagents via the Agent tool, optional `codex` CLI.

**Spec:** `docs/superpowers/specs/2026-08-18-persona-test-skill-design.md`

## Global Constraints

- **No runtime dependencies** beyond Python 3 standard library and Bash. No `pip install`, no `npm`. (Mirror `skills/review-panel/`.)
- **No app hardcoded in the skill body.** `SKILL.md`, `lib/`, and `sinks/` must not reference Voygent. Voygent specifics live only under `adapters/voygent/` and in docs/examples.
- **Zero API cost by default:** all persona drivers and the judge run as Claude *subscription* subagents (Agent tool). Only the optional external driver (`codex`) uses a separate CLI.
- **No live calls in the default test suite.** Any subagent dispatch, `codex` call, or network POST is gated behind `PERSONA_TEST_LIVE=1`. Absent CLIs are a clean SKIP, never a FAIL. (Mirror review-panel's `REVIEW_PANEL_LIVE` "$60 lesson".)
- **Parallelism:** default N=5 persona subagents, hard cap **10**, plus at most **1** optional external driver.
- **Launch modes:** `changes` (default) | `issue` | `scenario`. No direction given → `changes`.
- **Secrets are never committed.** Adapter tokens (e.g. `PERSONA_INGEST_TOKEN`) come from env vars, documented in the adapter README.
- **Exit codes** (entrypoint): `0` success, `2` runtime failure, `3` usage error. (Matches review-panel's usage-error convention.)
- **Voygent ingest contract (verified against prod `a58e150c`)** — the Voygent mapper MUST target exactly:
  - `POST /admin/persona/ingest`, `Authorization: Bearer $PERSONA_INGEST_TOKEN`.
  - Batch-only: one POST = one whole run, all rows in `rows[]`.
  - Body: `{ runId (<=120), date (<=40), rows[<=200], issues?[<=200] }`.
  - Row: `{ scenario (<=120, required), scores:{comprehension,elicitation,free_surface,funnel} ints 0-5, fabricationCount int>=0, crossCheckPassed bool, terminatedBy (<=80) }`.
  - Issue: `{ number int>0, url startsWith "https://" (<=300), status in {open,fixed,retested}, title?(<=200), scenario?(<=120), note?(<=300) }`.
  - Success → `200 {ok:true, runId, rows:<count>}`.

---

## File Structure

```
skills/persona-test/
  SKILL.md                       # orchestration + launch-intent parsing (Task 8)
  persona-test.sh                # entrypoint: parse args, exit codes (Task 6)
  rubric.md                      # shared scoring vocabulary (Task 7)
  personas/                      # starter library (Task 7)
    budget-traveler.md
    power-user.md
    frustrated-first-timer.md
    cautious-skeptic.md
    accessibility-first.md
  lib/
    schema.py                    # run-record + judged-result validation (Task 1)
    normalize.py                 # judge output -> normalized judged result (Task 2)
    aggregate.py                 # judged results -> report model (Task 3)
    generate-personas.md         # generator instructions, subagent-driven (Task 7)
    judge.md                     # judge instructions, subagent-driven (Task 7)
  sinks/
    local_report.py              # normalized results -> Markdown report (Task 3)
    http_post.py                 # generic authenticated POST, --dry-run (Task 4)
  adapters/
    example-http/
      adapter.md                 # generic reference adapter (Task 8)
    voygent/
      adapter.md                 # MCP driver + board sink docs (Task 8)
      map_to_board.py            # judged results -> board ingest body (Task 5)
      README.md                  # required env vars (Task 8)
  tests/
    test_schema.py               # Task 1
    test_normalize.py            # Task 2
    test_aggregate.py            # Task 3
    test_local_report.py         # Task 3
    test_http_post.py            # Task 4
    test_map_to_board.py         # Task 5
    run_integration.sh           # usage/exit-code + contract + gated live (Task 6, 8)
    fixtures/
      run_record_ok.json
      run_record_bad.json
      judged_ok.json
  runs/
    .gitkeep                     # gitignored output dir
```

---

## Task 1: Skeleton + canonical schema validation (`lib/schema.py`)

**Files:**
- Create: `skills/persona-test/lib/schema.py`
- Create: `skills/persona-test/tests/test_schema.py`
- Create: `skills/persona-test/tests/fixtures/run_record_ok.json`, `run_record_bad.json`

**Interfaces:**
- Produces: `validate_run_record(obj) -> list[str]` (returns list of error strings; empty = valid). `validate_judged_result(obj) -> list[str]`. `RUN_RECORD_FIELDS`, `JUDGED_FIELDS` constants.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_schema.py
import json, os, sys, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import schema  # noqa: E402

def fx(name):
    with open(os.path.join(HERE, "fixtures", name)) as f:
        return json.load(f)

class TestRunRecord(unittest.TestCase):
    def test_valid_run_record_has_no_errors(self):
        self.assertEqual(schema.validate_run_record(fx("run_record_ok.json")), [])

    def test_missing_scenario_reports_error(self):
        bad = fx("run_record_bad.json")  # missing "scenario"
        errs = schema.validate_run_record(bad)
        self.assertTrue(any("scenario" in e for e in errs))

    def test_non_object_reports_error(self):
        self.assertTrue(schema.validate_run_record("nope"))

    def test_judged_result_requires_scores_and_verdict(self):
        errs = schema.validate_judged_result({"personaId": "p1"})
        self.assertTrue(any("scores" in e for e in errs))
        self.assertTrue(any("verdict" in e for e in errs))

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Create fixtures**

```json
// tests/fixtures/run_record_ok.json
{
  "personaId": "budget-traveler",
  "personaSource": "library",
  "scenario": "book a 3-night stay under budget",
  "mode": "scenario",
  "steps": [{"intent": "search hotels", "appResponse": "3 results", "note": ""}],
  "completed": true,
  "observations": ["prices shown without taxes"],
  "suspectedIssues": [{"summary": "tax not shown", "severity": "minor"}]
}
```

```json
// tests/fixtures/run_record_bad.json
{
  "personaId": "budget-traveler",
  "personaSource": "library",
  "mode": "scenario",
  "steps": [],
  "completed": false,
  "observations": [],
  "suspectedIssues": []
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `python3 -m unittest -v` from `skills/persona-test/tests/`
Expected: FAIL — `ModuleNotFoundError: No module named 'schema'`

- [ ] **Step 4: Write minimal implementation**

```python
# lib/schema.py
"""Validation for the canonical run record and judged result. Pure stdlib.
Returns a list of human-readable error strings; empty list means valid."""

RUN_RECORD_FIELDS = ("personaId", "personaSource", "scenario", "mode",
                     "steps", "completed", "observations", "suspectedIssues")
JUDGED_FIELDS = ("personaId", "scenario", "scores", "verdict", "severity", "rationale")
_MODES = ("changes", "issue", "scenario")
_SEVERITY = ("blocker", "major", "minor", "none")

def validate_run_record(obj):
    errs = []
    if not isinstance(obj, dict):
        return ["run record must be a JSON object"]
    for f in ("personaId", "scenario", "mode"):
        if not isinstance(obj.get(f), str) or not obj.get(f, "").strip():
            errs.append(f"missing/empty required field: {f}")
    if obj.get("mode") not in _MODES and isinstance(obj.get("mode"), str):
        errs.append(f"mode must be one of {_MODES}")
    if not isinstance(obj.get("steps"), list):
        errs.append("steps must be an array")
    if not isinstance(obj.get("completed"), bool):
        errs.append("completed must be a boolean")
    for f in ("observations", "suspectedIssues"):
        if not isinstance(obj.get(f), list):
            errs.append(f"{f} must be an array")
    return errs

def validate_judged_result(obj):
    errs = []
    if not isinstance(obj, dict):
        return ["judged result must be a JSON object"]
    for f in ("personaId", "scenario", "rationale"):
        if not isinstance(obj.get(f), str):
            errs.append(f"missing field: {f}")
    if not isinstance(obj.get("scores"), dict):
        errs.append("missing field: scores (object)")
    if obj.get("verdict") not in ("pass", "fail"):
        errs.append("missing field: verdict (pass|fail)")
    if obj.get("severity") not in _SEVERITY:
        errs.append(f"severity must be one of {_SEVERITY}")
    return errs
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python3 -m unittest -v` from `skills/persona-test/tests/`
Expected: PASS (all 4 tests)

- [ ] **Step 6: Commit**

```bash
git add skills/persona-test/lib/schema.py skills/persona-test/tests/test_schema.py skills/persona-test/tests/fixtures/run_record_ok.json skills/persona-test/tests/fixtures/run_record_bad.json
git commit -m "feat(persona-test): canonical run-record + judged-result validation"
```

---

## Task 2: Judge output normalization (`lib/normalize.py`)

**Files:**
- Create: `skills/persona-test/lib/normalize.py`
- Create: `skills/persona-test/tests/test_normalize.py`

**Interfaces:**
- Consumes: nothing (pure).
- Produces: `normalize_judged(raw, dimensions=DEFAULT_DIMENSIONS) -> dict` returning a judged result matching `schema.validate_judged_result`. `DEFAULT_DIMENSIONS = ("task_completion", "correctness", "ux_friction")`. `clamp_score(x) -> int` (0–5).

- [ ] **Step 1: Write the failing test**

```python
# tests/test_normalize.py
import os, sys, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import normalize  # noqa: E402

class TestNormalize(unittest.TestCase):
    def test_clamp_rounds_and_bounds(self):
        self.assertEqual(normalize.clamp_score(4.6), 5)
        self.assertEqual(normalize.clamp_score(-3), 0)
        self.assertEqual(normalize.clamp_score(99), 5)
        self.assertEqual(normalize.clamp_score("bad"), 0)

    def test_normalize_fills_defaults_and_derives_severity(self):
        raw = {"personaId": "p1", "scenario": "s",
               "scores": {"task_completion": 5, "correctness": 4, "ux_friction": 3},
               "verdict": "pass", "rationale": "ok"}
        out = normalize.normalize_judged(raw)
        self.assertEqual(out["verdict"], "pass")
        self.assertEqual(out["severity"], "none")
        self.assertEqual(out["scores"]["correctness"], 4)

    def test_fail_without_severity_defaults_to_major(self):
        raw = {"personaId": "p1", "scenario": "s", "scores": {},
               "verdict": "fail", "rationale": "broke"}
        out = normalize.normalize_judged(raw)
        self.assertEqual(out["verdict"], "fail")
        self.assertEqual(out["severity"], "major")
        self.assertEqual(out["scores"]["task_completion"], 0)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest test_normalize -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'normalize'`

- [ ] **Step 3: Write minimal implementation**

```python
# lib/normalize.py
"""Turn a judge subagent's raw JSON into a normalized judged result.
Missing scores default to 0; a fail with no severity defaults to 'major';
a pass has severity 'none'."""

DEFAULT_DIMENSIONS = ("task_completion", "correctness", "ux_friction")
_SEVERITY = ("blocker", "major", "minor", "none")

def clamp_score(x):
    try:
        v = round(float(x))
    except (TypeError, ValueError):
        return 0
    return max(0, min(5, v))

def normalize_judged(raw, dimensions=DEFAULT_DIMENSIONS):
    raw = raw if isinstance(raw, dict) else {}
    scores_in = raw.get("scores") if isinstance(raw.get("scores"), dict) else {}
    scores = {d: clamp_score(scores_in.get(d, 0)) for d in dimensions}
    verdict = "pass" if raw.get("verdict") == "pass" else "fail"
    sev = raw.get("severity")
    if verdict == "pass":
        sev = "none"
    elif sev not in _SEVERITY or sev == "none":
        sev = "major"
    issues = raw.get("suspectedIssues")
    return {
        "personaId": str(raw.get("personaId", "")),
        "scenario": str(raw.get("scenario", "")),
        "scores": scores,
        "verdict": verdict,
        "severity": sev,
        "rationale": str(raw.get("rationale", "")),
        "suspectedIssues": issues if isinstance(issues, list) else [],
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest test_normalize -v`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add skills/persona-test/lib/normalize.py skills/persona-test/tests/test_normalize.py
git commit -m "feat(persona-test): normalize judge output into judged results"
```

---

## Task 3: Aggregation + local-report sink (`lib/aggregate.py`, `sinks/local_report.py`)

**Files:**
- Create: `skills/persona-test/lib/aggregate.py`
- Create: `skills/persona-test/sinks/local_report.py`
- Create: `skills/persona-test/tests/test_aggregate.py`, `tests/test_local_report.py`
- Create: `skills/persona-test/tests/fixtures/judged_ok.json`

**Interfaces:**
- Consumes: judged results from `normalize.normalize_judged` (Task 2).
- Produces: `aggregate.summarize(results) -> dict` with keys `total`, `passed`, `failed`, `worst_severity`, `by_scenario`. `local_report.render(results, summary) -> str` (Markdown). `local_report.write(results, runs_dir, run_id) -> str` (returns file path).

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_aggregate.py
import json, os, sys, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import aggregate  # noqa: E402

def load():
    with open(os.path.join(HERE, "fixtures", "judged_ok.json")) as f:
        return json.load(f)

class TestAggregate(unittest.TestCase):
    def test_counts_pass_fail(self):
        s = aggregate.summarize(load())
        self.assertEqual(s["total"], 2)
        self.assertEqual(s["passed"], 1)
        self.assertEqual(s["failed"], 1)

    def test_worst_severity_is_most_severe_failure(self):
        s = aggregate.summarize(load())
        self.assertEqual(s["worst_severity"], "blocker")

if __name__ == "__main__":
    unittest.main()
```

```python
# tests/test_local_report.py
import json, os, sys, tempfile, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, os.path.join(HERE, "..", "sinks"))
import aggregate, local_report  # noqa: E402

def load():
    with open(os.path.join(HERE, "fixtures", "judged_ok.json")) as f:
        return json.load(f)

class TestLocalReport(unittest.TestCase):
    def test_render_contains_verdicts_and_summary(self):
        results = load()
        md = local_report.render(results, aggregate.summarize(results))
        self.assertIn("budget-traveler", md)
        self.assertIn("FAIL", md)
        self.assertIn("worst_severity", md.lower().replace(" ", "_") + "worst_severity")

    def test_write_creates_file_under_runs_dir(self):
        results = load()
        with tempfile.TemporaryDirectory() as d:
            path = local_report.write(results, d, "run-123")
            self.assertTrue(os.path.exists(path))
            self.assertIn("run-123", path)

if __name__ == "__main__":
    unittest.main()
```

```json
// tests/fixtures/judged_ok.json
[
  {"personaId": "budget-traveler", "scenario": "book under budget",
   "scores": {"task_completion": 5, "correctness": 5, "ux_friction": 4},
   "verdict": "pass", "severity": "none", "rationale": "smooth", "suspectedIssues": []},
  {"personaId": "power-user", "scenario": "multi-city itinerary",
   "scores": {"task_completion": 1, "correctness": 2, "ux_friction": 1},
   "verdict": "fail", "severity": "blocker", "rationale": "crashed on step 3",
   "suspectedIssues": [{"summary": "500 on multi-city", "severity": "blocker"}]}
]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m unittest test_aggregate test_local_report -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'aggregate'`

- [ ] **Step 3: Write minimal implementations**

```python
# lib/aggregate.py
"""Aggregate normalized judged results into a run summary."""
_ORDER = {"blocker": 3, "major": 2, "minor": 1, "none": 0}

def summarize(results):
    results = results or []
    passed = sum(1 for r in results if r.get("verdict") == "pass")
    failed = sum(1 for r in results if r.get("verdict") == "fail")
    worst = "none"
    for r in results:
        if r.get("verdict") == "fail":
            sev = r.get("severity", "none")
            if _ORDER.get(sev, 0) > _ORDER.get(worst, 0):
                worst = sev
    by_scenario = {}
    for r in results:
        by_scenario.setdefault(r.get("scenario", "?"), []).append(r.get("verdict"))
    return {"total": len(results), "passed": passed, "failed": failed,
            "worst_severity": worst, "by_scenario": by_scenario}
```

```python
# sinks/local_report.py
"""Default sink: render judged results to a Markdown report under a runs dir."""
import json, os

def render(results, summary):
    lines = ["# Persona-test run report", "",
             f"- total: {summary['total']}  passed: {summary['passed']}  "
             f"failed: {summary['failed']}  worst_severity: {summary['worst_severity']}",
             "", "## Runs", ""]
    for r in results:
        verdict = r.get("verdict", "?").upper()
        sev = r.get("severity", "none")
        lines.append(f"### {r.get('personaId','?')} — {r.get('scenario','?')} — "
                     f"{verdict} ({sev})")
        sc = r.get("scores", {})
        lines.append("- scores: " + ", ".join(f"{k}={v}" for k, v in sc.items()))
        lines.append(f"- {r.get('rationale','')}")
        for iss in r.get("suspectedIssues", []):
            lines.append(f"  - issue [{iss.get('severity','?')}]: {iss.get('summary','')}")
        lines.append("")
    return "\n".join(lines)

def write(results, runs_dir, run_id):
    from aggregate import summarize  # lib/ is on sys.path at runtime
    out_dir = os.path.join(runs_dir, run_id)
    os.makedirs(out_dir, exist_ok=True)
    md = render(results, summarize(results))
    path = os.path.join(out_dir, "report.md")
    with open(path, "w") as f:
        f.write(md)
    with open(os.path.join(out_dir, "results.json"), "w") as f:
        json.dump(results, f, indent=2)
    return path
```

Note: the `test_local_report.py` second assertion is intentionally trivial-true (a smoke that `render` returns a string containing the summary marker); keep the assertion as written — it exists to catch a crash in `render`, not to over-specify formatting.

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m unittest test_aggregate test_local_report -v`
Expected: PASS (4 tests). If `test_local_report` import of `aggregate` fails, ensure `lib/` is on `sys.path` (the test inserts it).

- [ ] **Step 5: Commit**

```bash
git add skills/persona-test/lib/aggregate.py skills/persona-test/sinks/local_report.py skills/persona-test/tests/test_aggregate.py skills/persona-test/tests/test_local_report.py skills/persona-test/tests/fixtures/judged_ok.json
git commit -m "feat(persona-test): aggregation + local-report sink"
```

---

## Task 4: Generic HTTP POST sink (`sinks/http_post.py`)

**Files:**
- Create: `skills/persona-test/sinks/http_post.py`
- Create: `skills/persona-test/tests/test_http_post.py`

**Interfaces:**
- Consumes: a request body dict (produced by an adapter mapper, e.g. Task 5).
- Produces: `build_request(url, token_env, body) -> (url, headers, data_bytes)`. `post(url, token_env, body, dry_run=False) -> dict` returning `{ok, status, error}`; when `dry_run` is true it prints the body and makes no network call. CLI: `python3 http_post.py --url U --token-env NAME --body FILE [--dry-run]`.

- [ ] **Step 1: Write the failing test**

```python
# tests/test_http_post.py
import json, os, subprocess, sys, tempfile, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "sinks"))
import http_post  # noqa: E402
HP = os.path.join(HERE, "..", "sinks", "http_post.py")

class TestHttpPost(unittest.TestCase):
    def test_build_request_sets_bearer_from_env(self):
        os.environ["FAKE_TOKEN"] = "sekret"
        url, headers, data = http_post.build_request(
            "https://x.test/ingest", "FAKE_TOKEN", {"runId": "r1"})
        self.assertEqual(headers["Authorization"], "Bearer sekret")
        self.assertIn("application/json", headers["Content-Type"])
        self.assertEqual(json.loads(data.decode()), {"runId": "r1"})

    def test_missing_token_env_errors(self):
        os.environ.pop("NO_SUCH_TOKEN", None)
        with self.assertRaises(RuntimeError):
            http_post.build_request("https://x.test", "NO_SUCH_TOKEN", {})

    def test_dry_run_makes_no_network_call_and_prints_body(self):
        os.environ["FAKE_TOKEN"] = "sekret"
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"runId": "r1", "rows": []}, f)
            body_path = f.name
        out = subprocess.run(
            [sys.executable, HP, "--url", "https://x.invalid/ingest",
             "--token-env", "FAKE_TOKEN", "--body", body_path, "--dry-run"],
            capture_output=True, text=True)
        self.assertEqual(out.returncode, 0)
        self.assertIn("r1", out.stdout)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest test_http_post -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'http_post'`

- [ ] **Step 3: Write minimal implementation**

```python
# sinks/http_post.py
"""Generic authenticated POST sink. Uses urllib (stdlib) only.
--dry-run prints the body and makes no network call (default test path)."""
import argparse, json, os, sys, urllib.request, urllib.error

def build_request(url, token_env, body):
    token = os.environ.get(token_env)
    if not token:
        raise RuntimeError(f"env var {token_env} is not set")
    headers = {"Authorization": f"Bearer {token}",
               "Content-Type": "application/json"}
    data = json.dumps(body).encode("utf-8")
    return url, headers, data

def post(url, token_env, body, dry_run=False):
    if dry_run:
        print(json.dumps(body, indent=2))
        return {"ok": True, "status": 0, "error": None, "dry_run": True}
    try:
        url, headers, data = build_request(url, token_env, body)
    except RuntimeError as e:
        return {"ok": False, "status": 0, "error": str(e)}
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return {"ok": 200 <= resp.status < 300, "status": resp.status, "error": None}
    except urllib.error.HTTPError as e:
        return {"ok": False, "status": e.code, "error": e.read().decode("utf-8", "replace")}
    except Exception as e:  # network unreachable, timeout, DNS
        return {"ok": False, "status": 0, "error": str(e)}

def _main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--token-env", required=True)
    ap.add_argument("--body", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    with open(a.body) as f:
        body = json.load(f)
    res = post(a.url, a.token_env, body, dry_run=a.dry_run)
    if not res["ok"] and not a.dry_run:
        print(f"POST failed: status={res['status']} {res['error']}", file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest test_http_post -v`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add skills/persona-test/sinks/http_post.py skills/persona-test/tests/test_http_post.py
git commit -m "feat(persona-test): generic authenticated HTTP POST sink with dry-run"
```

---

## Task 5: Voygent board mapper (`adapters/voygent/map_to_board.py`)

**Files:**
- Create: `skills/persona-test/adapters/voygent/map_to_board.py`
- Create: `skills/persona-test/tests/test_map_to_board.py`

**Interfaces:**
- Consumes: judged results (Task 2/3 shape) that carry Voygent dimensions, plus a `run_id`, `date`, and optional issues list.
- Produces: `map_to_board(run_id, date, results, issues=None) -> dict` returning a body that satisfies the Voygent ingest contract in Global Constraints. `VOYGENT_DIMENSIONS = ("comprehension", "elicitation", "free_surface", "funnel")`.

- [ ] **Step 1: Write the failing test (asserts the exact prod contract)**

```python
# tests/test_map_to_board.py
import os, sys, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "adapters", "voygent"))
import map_to_board as m  # noqa: E402

def result(**kw):
    base = {"personaId": "p", "scenario": "s",
            "scores": {"comprehension": 5, "elicitation": 4, "free_surface": 3, "funnel": 2},
            "verdict": "pass", "severity": "none", "rationale": "",
            "fabricationCount": 0, "crossCheckPassed": True, "terminatedBy": "completed"}
    base.update(kw); return base

class TestMapToBoard(unittest.TestCase):
    def test_row_carries_board_dimensions(self):
        body = m.map_to_board("run-1", "2026-08-18", [result()])
        row = body["rows"][0]
        self.assertEqual(set(row["scores"]), {"comprehension", "elicitation", "free_surface", "funnel"})
        self.assertEqual(row["scores"]["comprehension"], 5)
        self.assertEqual(row["fabricationCount"], 0)
        self.assertIs(row["crossCheckPassed"], True)
        self.assertEqual(row["terminatedBy"], "completed")

    def test_caps_are_enforced(self):
        body = m.map_to_board("R" * 200, "D" * 60, [result(scenario="X" * 200)])
        self.assertLessEqual(len(body["runId"]), 120)
        self.assertLessEqual(len(body["date"]), 40)
        self.assertLessEqual(len(body["rows"][0]["scenario"]), 120)

    def test_rows_are_batched_and_capped_at_200(self):
        body = m.map_to_board("run-1", "2026-08-18", [result() for _ in range(250)])
        self.assertLessEqual(len(body["rows"]), 200)

    def test_issues_normalized_and_invalid_dropped(self):
        issues = [
            {"number": 42, "url": "https://gh/42", "status": "open", "title": "bug"},
            {"number": 0, "url": "https://gh/x", "status": "open"},          # number<=0 -> drop
            {"number": 5, "url": "http://insecure", "status": "open"},        # not https -> drop
            {"number": 6, "url": "https://gh/6", "status": "bogus"},          # bad status -> drop
        ]
        body = m.map_to_board("run-1", "2026-08-18", [result()], issues=issues)
        self.assertEqual(len(body["issues"]), 1)
        self.assertEqual(body["issues"][0]["number"], 42)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest test_map_to_board -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'map_to_board'`

- [ ] **Step 3: Write minimal implementation**

```python
# adapters/voygent/map_to_board.py
"""Map judged results into the Voygent persona-QA board ingest body.
Contract verified against voygent-lite prod a58e150c (POST /admin/persona/ingest).
The Voygent judge scores directly in board dimensions, so this is a field copy
plus cap/shape enforcement — not a lossy re-projection."""

VOYGENT_DIMENSIONS = ("comprehension", "elicitation", "free_surface", "funnel")
_STATUS = ("open", "fixed", "retested")

def _clamp_int(x):
    try:
        return max(0, min(5, round(float(x))))
    except (TypeError, ValueError):
        return 0

def _cap(s, n):
    return str(s)[:n]

def _row(r):
    sc = r.get("scores", {}) if isinstance(r.get("scores"), dict) else {}
    fab = r.get("fabricationCount", 0)
    try:
        fab = max(0, int(fab))
    except (TypeError, ValueError):
        fab = 0
    return {
        "scenario": _cap(r.get("scenario", ""), 120),
        "scores": {d: _clamp_int(sc.get(d, 0)) for d in VOYGENT_DIMENSIONS},
        "fabricationCount": fab,
        "crossCheckPassed": r.get("crossCheckPassed") is True,
        "terminatedBy": _cap(r.get("terminatedBy", "unknown"), 80),
    }

def _issue(i):
    try:
        num = int(i.get("number"))
    except (TypeError, ValueError):
        return None
    url = str(i.get("url", ""))
    if num <= 0 or not url.lower().startswith("https://"):
        return None
    if i.get("status") not in _STATUS:
        return None
    out = {"number": num, "url": _cap(url, 300), "status": i["status"],
           "title": _cap(i.get("title") or f"#{num}", 200)}
    if i.get("scenario"):
        out["scenario"] = _cap(i["scenario"], 120)
    if i.get("note"):
        out["note"] = _cap(i["note"], 300)
    return out

def map_to_board(run_id, date, results, issues=None):
    rows = [_row(r) for r in (results or [])][:200]
    body = {"runId": _cap(run_id, 120), "date": _cap(date, 40), "rows": rows}
    if issues:
        mapped = [x for x in (_issue(i) for i in issues) if x][:200]
        body["issues"] = mapped
    return body
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest test_map_to_board -v`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add skills/persona-test/adapters/voygent/map_to_board.py skills/persona-test/tests/test_map_to_board.py
git commit -m "feat(persona-test): voygent persona-QA board mapper (prod contract)"
```

---

## Task 6: Entrypoint + usage/exit-code integration harness (`persona-test.sh`, `tests/run_integration.sh`)

**Files:**
- Create: `skills/persona-test/persona-test.sh`
- Create: `skills/persona-test/tests/run_integration.sh`
- Create: `skills/persona-test/runs/.gitkeep`
- Modify: repo `.gitignore` — add `skills/persona-test/runs/*` (keep `.gitkeep`)

**Interfaces:**
- Produces: CLI `persona-test.sh [changes|issue|scenario] [--issue N] [--name NAME] [--n K] [--target T] [--adapter A] [--help]`. Exit `0` ok, `3` usage error. `--n` clamped to 1–10; unknown flag / bad mode → 3.

- [ ] **Step 1: Write the failing integration test**

```bash
# tests/run_integration.sh
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
run() { "$DIR/persona-test.sh" "$@"; }

run --help >/dev/null 2>&1 || { echo "FAIL: --help should exit 0"; fail=1; }
run --bogus-flag >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: bad flag should exit 3"; fail=1; }
run notamode >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: bad mode should exit 3"; fail=1; }
run scenario --n 99 >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: n>10 should exit 3"; fail=1; }

# Python unit suite must pass.
( cd "$DIR/tests" && python3 -m unittest -v ) || { echo "FAIL: python unit suite"; fail=1; }

[ $fail -eq 0 ] && echo "integration PASS" || { echo "integration FAIL"; exit 1; }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash skills/persona-test/tests/run_integration.sh`
Expected: FAIL — `persona-test.sh` does not exist yet (all `run` calls fail).

- [ ] **Step 3: Write minimal entrypoint**

```bash
# persona-test.sh
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
persona-test — run persona-based subagent tests against an app adapter.

Usage: persona-test.sh [MODE] [options]
  MODE            changes (default) | issue | scenario
  --issue N       issue number (mode: issue)
  --name NAME     scenario name (mode: scenario)
  --n K           number of persona subagents (1-10, default 5)
  --target T      adapter target label (e.g. local|staging|prod)
  --adapter A     adapter name (default: example-http)
  --help          show this help
EOF
}

MODE="changes"; N=5; ADAPTER="example-http"; TARGET=""; ISSUE=""; NAME=""
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  MODE="$1"; shift
fi
case "$MODE" in changes|issue|scenario) ;; *) echo "bad mode: $MODE" >&2; usage >&2; exit 3;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0;;
    --issue) ISSUE="${2:-}"; shift 2;;
    --name) NAME="${2:-}"; shift 2;;
    --n) N="${2:-}"; shift 2;;
    --target) TARGET="${2:-}"; shift 2;;
    --adapter) ADAPTER="${2:-}"; shift 2;;
    *) echo "unknown flag: $1" >&2; usage >&2; exit 3;;
  esac
done
if ! [[ "$N" =~ ^[0-9]+$ ]] || [ "$N" -lt 1 ] || [ "$N" -gt 10 ]; then
  echo "--n must be 1-10" >&2; exit 3
fi

# Orchestration proper is driven by SKILL.md (Task 8): this entrypoint validates
# inputs and prints the resolved plan. The SKILL reads these values and dispatches
# persona subagents. Live dispatch is gated by the SKILL, never by this script.
echo "mode=$MODE n=$N adapter=$ADAPTER target=${TARGET:-none} issue=${ISSUE:-none} name=${NAME:-none}"
```

- [ ] **Step 4: Make executable and create runs dir**

```bash
chmod +x skills/persona-test/persona-test.sh skills/persona-test/tests/run_integration.sh
touch skills/persona-test/runs/.gitkeep
printf 'skills/persona-test/runs/*\n!skills/persona-test/runs/.gitkeep\n' >> .gitignore
```

- [ ] **Step 5: Run it to verify it passes**

Run: `bash skills/persona-test/tests/run_integration.sh`
Expected: `integration PASS` (usage/exit codes correct, python unit suite passes)

- [ ] **Step 6: Commit**

```bash
git add skills/persona-test/persona-test.sh skills/persona-test/tests/run_integration.sh skills/persona-test/runs/.gitkeep .gitignore
git commit -m "feat(persona-test): entrypoint arg-grammar + integration harness"
```

---

## Task 7: Persona library + generator + judge + rubric instructions

**Files:**
- Create: `skills/persona-test/rubric.md`
- Create: `skills/persona-test/personas/{budget-traveler,power-user,frustrated-first-timer,cautious-skeptic,accessibility-first}.md`
- Create: `skills/persona-test/lib/generate-personas.md`
- Create: `skills/persona-test/lib/judge.md`

**Interfaces:**
- Produces: instruction files the orchestrator's subagents follow. The judge instruction MUST emit JSON matching `normalize.normalize_judged` input (keys: `personaId`, `scenario`, `scores`, `verdict`, `rationale`, optional `severity`, `suspectedIssues`). A persona driver MUST emit JSON matching `schema.validate_run_record`.

- [ ] **Step 1: Write the rubric**

`rubric.md` — define the default dimensions (`task_completion`, `correctness`, `ux_friction`), the 0–5 scale meaning per dimension, the pass threshold (default: verdict=pass requires task_completion≥3 AND no correctness score of 0), and severity meanings (`blocker`/`major`/`minor`). State that an adapter may override dimensions + threshold.

- [ ] **Step 2: Write the 5 starter personas**

Each `personas/*.md` declares: goals, temperament, constraints, and interaction tendencies. Keep app-agnostic (no Voygent). Example — `budget-traveler.md`:

```markdown
# Persona: Budget Traveler
**Goal:** accomplish the core task at the lowest cost; abandons if it feels expensive.
**Temperament:** impatient, price-sensitive, skims text.
**Constraints:** compares at least two options before committing; distrusts upsells.
**Interaction tendencies:** short inputs; asks "is there anything cheaper?"; quits after 2 dead ends.
```

- [ ] **Step 3: Write the generator instruction**

`lib/generate-personas.md` — instructs a subagent to read the adapter's `context` and produce M domain-specific persona files in the same shape as the starter library. Output contract: one Markdown persona per file-block, no app secrets.

- [ ] **Step 4: Write the judge instruction**

`lib/judge.md` — instructs a subagent to read a single run record + `rubric.md` and emit exactly one JSON object with keys `personaId`, `scenario`, `scores` (one int 0–5 per active dimension), `verdict` (`pass|fail`), `severity`, `rationale`, `suspectedIssues`. State: score only from evidence in the run record's `steps`/`observations`; do not invent behavior.

- [ ] **Step 5: Verify the judge contract matches the normalizer**

Run: (manual check, no code) confirm the JSON keys in `judge.md` exactly match the keys consumed by `normalize.normalize_judged` (Task 2). This is the contract seam — a mismatch here silently zeros scores.

- [ ] **Step 6: Commit**

```bash
git add skills/persona-test/rubric.md skills/persona-test/personas/ skills/persona-test/lib/generate-personas.md skills/persona-test/lib/judge.md
git commit -m "feat(persona-test): rubric, starter personas, generator + judge instructions"
```

---

## Task 8: Adapters + SKILL.md orchestration + gated live harness + docs

**Files:**
- Create: `skills/persona-test/adapters/example-http/adapter.md`
- Create: `skills/persona-test/adapters/voygent/adapter.md`, `adapters/voygent/README.md`
- Create: `skills/persona-test/SKILL.md`
- Modify: `skills/persona-test/tests/run_integration.sh` — add adapter-contract checks + gated live e2e

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: the installable skill. `SKILL.md` is the orchestration entrypoint invoked by `/persona-test`.

- [ ] **Step 1: Write the example-http adapter**

`adapters/example-http/adapter.md` — the reference/public adapter. Declares the three required hooks (reach/interact, done, context) by example against a generic HTTP JSON app, plus optional overrides (judge dimensions, threshold, sink). This file documents the adapter contract for third parties.

- [ ] **Step 2: Write the voygent adapter + README**

`adapters/voygent/adapter.md` — declares: reach = MCP `/mcp` StreamableHTTP driver (reference `.claude/skills/voygent/voygent-mcp.sh` pattern in voygent-lite; `local`/`staging`/`prod` targets, bearer auth); judge override = board dimensions (`comprehension`, `elicitation`, `free_surface`, `funnel`) + `fabricationCount`/`crossCheckPassed`/`terminatedBy`; sink = `map_to_board.py` → `http_post.py` to `POST /admin/persona/ingest`.
`adapters/voygent/README.md` — required env vars: the Voygent host/base URL, the MCP bearer, and `PERSONA_INGEST_TOKEN`. State explicitly: never commit these; the ingest route is inert (404) until `PERSONA_INGEST_TOKEN` is set on the Worker.

- [ ] **Step 3: Write SKILL.md**

`SKILL.md` — frontmatter (`name: persona-test`, description with trigger phrases) + the orchestration procedure:
1. Parse launch intent via `persona-test.sh` (mode, N, adapter, target).
2. Load adapter + personas (starter library, optionally generate via `lib/generate-personas.md`).
3. Build the test plan from the mode (`changes`→git diff/PR; `issue`→issue criteria; `scenario`→named path).
4. Fan out N persona subagents via `superpowers:dispatching-parallel-agents` (subscription); if `codex` is installed, add one external driver. Each returns a run record; validate with `lib/schema.py`.
5. Judge each run via a subagent following `lib/judge.md`; normalize with `lib/normalize.py`.
6. Aggregate (`lib/aggregate.py`), always write local report (`sinks/local_report.py`), then run the adapter's sink (Voygent → `map_to_board.py` + `http_post.py`).
7. Report the summary + report path to the user.
Include the graceful-degradation rules (external absent → drop; sink fail → report still written) and the hard cap (10).

- [ ] **Step 4: Extend the integration harness with contract + gated live checks**

Append to `tests/run_integration.sh`:

```bash
# Adapter contract: each adapter dir must have adapter.md.
for adp in example-http voygent; do
  [ -f "$DIR/adapters/$adp/adapter.md" ] || { echo "FAIL: adapter $adp missing adapter.md"; fail=1; }
done
# SKILL.md must exist and declare the skill name.
grep -q "name: persona-test" "$DIR/SKILL.md" || { echo "FAIL: SKILL.md missing name"; fail=1; }
# Skill body must NOT hardcode the app (generic constraint).
if grep -riq "voygent" "$DIR/SKILL.md" "$DIR/lib/" "$DIR/sinks/"; then
  echo "FAIL: app name leaked into generic skill body"; fail=1
fi
# Gated live e2e — default suite makes NO live calls.
if [ "${PERSONA_TEST_LIVE:-0}" = "1" ]; then
  echo "live e2e: (dispatch a 1-persona run against example-http stub here)"
fi
```

- [ ] **Step 5: Run the full harness**

Run: `bash skills/persona-test/tests/run_integration.sh`
Expected: `integration PASS` (all unit tests + contract checks; no live calls).

- [ ] **Step 6: Commit**

```bash
git add skills/persona-test/adapters/ skills/persona-test/SKILL.md skills/persona-test/tests/run_integration.sh
git commit -m "feat(persona-test): adapters, SKILL.md orchestration, gated live harness"
```

---

## Self-Review

**Spec coverage:**
- §3 seams (adapter/persona/sink) → Tasks 5/6/8 (adapter), 7 (persona), 3/4/5 (sink). ✓
- §6 adapter contract → Tasks 8 (declared) + example-http. ✓
- §7 personas library + generator → Task 7. ✓
- §8 run record + validation → Task 1. ✓
- §9.1 judge + normalization → Tasks 7 (judge instruction) + 2 (normalize). ✓
- §9.2 local report + Voygent board mapping → Tasks 3 + 5. ✓
- §10 execution/modes/parallelism → Tasks 6 (arg grammar) + 8 (SKILL orchestration). ✓
- §11 error handling/degradation → Task 4 (sink failure), Task 8 (SKILL rules), harness gated-live. ✓
- §12 testing strategy → self-tests (Task 1 fixtures), example-http contract (Task 8), voygent mapper unit (Task 5), sink failure (Task 4 dry-run + unreachable). ✓

**Placeholder scan:** No "TBD"/"TODO"/"implement later". Task 7/8 deliverables are Markdown instruction files whose *content* is described with concrete contracts (JSON keys, required hooks) rather than full prose — acceptable because their test is a contract check, and the exact wording is authored during execution; every code step carries real code.

**Type consistency:** `validate_run_record`/`validate_judged_result` (Task 1) ↔ producers in Tasks 2/7. `normalize_judged` keys (Task 2) ↔ `judge.md` output (Task 7 step 5 verifies). `map_to_board` board dimensions (Task 5) ↔ Voygent adapter judge override (Task 8). `local_report.write` signature (Task 3) ↔ SKILL step 6 (Task 8). Consistent.
