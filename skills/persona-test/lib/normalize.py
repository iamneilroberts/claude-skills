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
