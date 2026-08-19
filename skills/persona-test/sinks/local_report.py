"""Default sink: render judged results to a Markdown report under a runs dir."""
import json, os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))

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
