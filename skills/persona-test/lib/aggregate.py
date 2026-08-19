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
