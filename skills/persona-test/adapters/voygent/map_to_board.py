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
