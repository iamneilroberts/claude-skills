#!/usr/bin/env python3
"""review-panel merge engine. Pure: reads verdict files, never spawns processes.
Phases: classify (which lone blocks to challenge) and finalize (apply the gate)."""
import argparse, json, re, sys

def _extract_last_json(text):
    """Return the last top-level JSON object in text, or None (mirrors codex-review)."""
    depth, start, last = 0, None, None
    for i, c in enumerate(text):
        if c == "{":
            if depth == 0: start = i
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start is not None:
                last = text[start:i + 1]
    if last is None: return None
    try: return json.loads(last)
    except json.JSONDecodeError: return None

def load_verdict(path):
    """Load a reviewer verdict file; return dict or None if unparseable/missing."""
    try:
        with open(path) as fh: raw = fh.read()
    except OSError:
        return None
    v = _extract_last_json(raw)
    if not isinstance(v, dict) or "findings" not in v: return None
    v.setdefault("_model", path)
    return v

def _norm(s): return re.sub(r"\s+", " ", (s or "").strip().lower())

def _parse_loc(s):
    """Parse a code_location into (file, lo, hi). lo/hi are None when no line
    number is present. Handles `file:12`, `file:12-20`, and `file line 12`."""
    s = (s or "").strip()
    if not s: return ("", None, None)
    m = re.match(r"\s*(.+?):(\d+)(?:\s*-\s*(\d+))?", s)
    if m:
        lo = int(m.group(2)); hi = int(m.group(3)) if m.group(3) else lo
        if hi < lo: lo, hi = hi, lo
        return (_norm(m.group(1)), lo, hi)
    m = re.match(r"\s*(.+?)\bline\s+(\d+)", s, re.I)
    if m:
        return (_norm(m.group(1)), int(m.group(2)), int(m.group(2)))
    return (_norm(s), None, None)

def _same_file(a, b):
    """Same file, tolerant of path depth: exact, or matching basename."""
    if a == b and a != "": return True
    ba, bb = a.rsplit("/", 1)[-1], b.rsplit("/", 1)[-1]
    return ba == bb and ba != ""

def _title_sim(a, b):
    """Token Jaccard over normalized titles (0..1)."""
    ta, tb = set(_norm(a).split()), set(_norm(b).split())
    if not ta or not tb: return 0.0
    return len(ta & tb) / len(ta | tb)

def _same_bug(f1, f2):
    """Whether two findings (from different models) describe the same defect.
    Conservative and structural: same file is required (models rarely agree on
    exact line, but almost always on file). With line numbers, ranges must
    OVERLAP; without them, fall back to strong title similarity. Line-only,
    no ±window expansion — so two distinct-but-nearby bugs don't false-merge
    (a false merge HIDES a real finding, worse than a false split here)."""
    fa, alo, ahi = _parse_loc(f1.get("code_location"))
    fb, blo, bhi = _parse_loc(f2.get("code_location"))
    if not _same_file(fa, fb): return False
    if alo is not None and blo is not None:
        return alo <= bhi and blo <= ahi
    return _title_sim(f1.get("title"), f2.get("title")) >= 0.6

def finding_key(f):
    """Stable output/challenge-matching key: priority|location|title. Computed on
    the MERGED finding, whose identity (priority/title/body) is chosen
    deterministically in dedup() so the key is identical across the classify and
    finalize invocations — otherwise challenge matching would silently break."""
    return f"{f.get('priority', 3)}|{_norm(f.get('code_location'))}|{_norm(f.get('title'))}"

def dedup(verdicts):
    """Merge same-bug findings across verdicts (see _same_bug); annotate agreement
    + models. Grouping is the connected components of the symmetric same-bug
    relation (union-find), so the PARTITION is independent of input order. Merged
    identity is the most-severe contributor (lowest priority, tie-broken by
    normalized title), keeping finding_key stable between the classify and
    finalize phases."""
    items = []  # [(finding, model)]
    for v in verdicts:
        model = v.get("_model", "?")
        for f in v.get("findings", []):
            items.append((f, model))
    n = len(items)
    parent = list(range(n))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    def union(x, y):
        rx, ry = find(x), find(y)
        if rx != ry: parent[max(rx, ry)] = min(rx, ry)  # min-root → deterministic
    for i in range(n):
        for j in range(i + 1, n):
            if _same_bug(items[i][0], items[j][0]):
                union(i, j)
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    merged = []
    for idxs in groups.values():
        contribs = [items[i][0] for i in idxs]
        models = []
        for i in idxs:
            m = items[i][1]
            if m not in models: models.append(m)
        lead = min(contribs, key=lambda f: (f.get("priority", 3), _norm(f.get("title"))))
        merged.append({**lead,
                       "priority": min(f.get("priority", 3) for f in contribs),
                       "agreement": len(models),
                       "models": sorted(models)})
    return merged

def classify(verdicts, block_at, strict):
    ok = [v for v in verdicts if v is not None]
    infra = len(ok) < 2
    merged = dedup(ok)
    lone = []
    if not strict and not infra:
        lone = [finding_key(f) for f in merged
                if f["priority"] <= block_at and f["agreement"] == 1]
    return {"reviewers_ok": len(ok), "lone_blocking": lone, "infra": infra}

def _demote_to(block_at):
    """Priority a refuted lone finding is demoted to. Must land STRICTLY above
    the gate, so it is block_at+1 (capped at 3=NIT) — a hardcoded 2 would still
    block under `--block-at 2`, silently defeating the challenge demotion."""
    return min(block_at + 1, 3)

def _load_challenges(paths):
    """key -> list of 'confirmed'/'refuted' verdicts from other models."""
    out = {}
    for p in paths:
        v = load_verdict(p) or {}
        k = v.get("_challenge_of"); verdict = v.get("_verdict")
        if k and verdict in ("confirmed", "refuted"):
            out.setdefault(k, []).append(verdict)
    return out

def finalize(verdicts, challenges, block_at, strict):
    ok = [v for v in verdicts if v is not None]
    unavailable = sum(1 for v in verdicts if v is None)
    merged = dedup(ok)
    disagreements = []
    demote_to = _demote_to(block_at)
    for f in merged:
        k = finding_key(f)
        f["challenge"] = "n/a"
        if f["priority"] <= block_at and f["agreement"] == 1 and not strict:
            verdicts_for = challenges.get(k, [])
            if any(x == "confirmed" for x in verdicts_for):
                # Any confirmation wins over a refutation (conservative): stays blocking.
                f["challenge"] = "confirmed"
            elif verdicts_for and all(x == "refuted" for x in verdicts_for):
                f["challenge"] = "refuted"
                disagreements.append({"finding": k, "resolution": "refuted", "was_priority": f["priority"]})
                f["priority"] = demote_to  # demote strictly above the gate
            # no challenge result → stays blocking (conservative), challenge left "n/a"
    infra = len(ok) < 2
    blocking = [f for f in merged if f["priority"] <= block_at]
    clean = (not infra) and len(blocking) == 0
    result = {
        "overall_correctness": "incorrect" if blocking else ("cannot_determine" if infra else "correct"),
        "findings": sorted(merged, key=lambda f: f["priority"]),
        "_gate": {"block_at": block_at, "blocking_count": len(blocking), "clean": clean},
        "_panel": {"reviewers": [v.get("_model") for v in ok],
                   "unavailable": unavailable, "disagreements": disagreements},
    }
    print(json.dumps(result, indent=2))
    if infra: return 2
    return 1 if blocking else 0

def _load_all(paths): return [load_verdict(p) for p in paths]

def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", required=True, choices=["classify", "finalize"])
    ap.add_argument("verdicts", nargs="+")
    ap.add_argument("--challenge", nargs="*", default=[])
    ap.add_argument("--block-at", type=int, default=1)
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args(argv)
    verdicts = _load_all(args.verdicts)
    if args.phase == "classify":
        print(json.dumps(classify(verdicts, args.block_at, args.strict)))
        return 0
    challenges = _load_challenges(args.challenge)
    return finalize(verdicts, challenges, args.block_at, args.strict)

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
