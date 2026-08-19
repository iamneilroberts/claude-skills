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
