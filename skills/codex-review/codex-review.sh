#!/usr/bin/env bash
# /codex-review gate — cross-model (Codex) external review with a STRUCTURED verdict.
#
# This is the JUDGE. It is committed and must NOT be edited mid-review by the session
# whose code it is reviewing (pattern #4, "judge immutability"): the implementer edits
# source, never this gate. It runs `codex exec` READ-ONLY, forces a JSON verdict against
# sev.schema.json (pattern #1), and converts that verdict into a gate exit code so the
# result is enforced MECHANICALLY — the authoring model does not get to re-litigate a
# CRITICAL/IMPORTANT finding (pattern #2). An infra failure (rate-limit / model reject /
# empty output) is its own exit code so a transient error is never mistaken for "clean"
# and never feeds a fix loop (pattern #3, infra-vs-findings guard).
#
# Exit codes:
#   0  CLEAN     — no findings at/under the blocking threshold. Gate PASS.
#   1  FINDINGS  — one or more blocking findings. Gate FAIL; fix or escalate.
#   2  INFRA     — Codex failed / no parseable verdict. NOT clean. Do not fix-loop; retry/escalate.
#   3  USAGE     — bad arguments.
#
# Usage:
#   codex-review.sh --base <ref>      review `git diff <ref>...HEAD`   (default base: origin/main)
#   codex-review.sh --staged          review the staged diff
#   codex-review.sh --worktree        review the unstaged working-tree diff
#   codex-review.sh --plan <file>     review an implementation PLAN file (codex also reads referenced files)
# Options:
#   --focus "<text>" | --focus-file <f>   extra reviewer instructions (per-task hints)
#   --block-at <0..3>   block on priority<=N. default 1 (CRITICAL+IMPORTANT block; MINOR/NIT advisory)
#   --out <path>        raw JSON verdict output. default /tmp/codex-review.json
#   --dry-run           assemble diff+prompt, print sizes, skip codex (gate self-test)
set -uo pipefail

usage() { sed -n '2,30p' "$0" >&2; exit 3; }
command -v codex >/dev/null 2>&1 || { echo "codex CLI not found on PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found on PATH" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 3; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$HERE/sev.schema.json"

MODE="" PLAN="" BASE="origin/main" FOCUS="" BLOCK_AT=1 OUT="/tmp/codex-review.json" DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) MODE="diff"; BASE="${2:?}"; shift 2 ;;
    --staged) MODE="staged"; shift ;;
    --worktree) MODE="worktree"; shift ;;
    --plan) MODE="plan"; PLAN="${2:?}"; shift 2 ;;
    --focus) FOCUS="${2:-}"; shift 2 ;;
    --focus-file) FOCUS="$(cat "${2:?}")"; shift 2 ;;
    --block-at) BLOCK_AT="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done
[[ -z "$MODE" ]] && MODE="diff"   # default: diff origin/main...HEAD

# ---- assemble the TARGET section ---------------------------------------------
# Generated bundles (multi-MB single-line base64/minified builds) are excluded from the
# reviewed diff by DEFAULT (#329): they are unreviewable, their sources are in the diff,
# and a single-line multi-MB string both spun the old emptiness probe for 54+ min and
# overflowed argv (E2BIG). Extra patterns: one per line in <repo>/.codexreviewignore.
EXCLUDES=(
  ":(glob,exclude)src/**/*-html.ts"
  ":(glob,exclude)prototypes/board/board.html"
  ":(glob,exclude)prototypes/folio-board/folio-board-widget.html"
  ":(glob,exclude)**/*.compiled.js"
)
if [[ -f "$ROOT/.codexreviewignore" ]]; then
  while IFS= read -r pat; do
    [[ -z "$pat" || "$pat" == \#* ]] && continue
    EXCLUDES+=(":(glob,exclude)$pat")
  done < "$ROOT/.codexreviewignore"
fi

TARGET_DESC="" DIFF=""
case "$MODE" in
  diff)     TARGET_DESC="the code change in: git diff ${BASE}...HEAD"; DIFF="$(git -C "$ROOT" diff "${BASE}...HEAD" -- . "${EXCLUDES[@]}" 2>/dev/null)" ;;
  staged)   TARGET_DESC="the STAGED code change"; DIFF="$(git -C "$ROOT" diff --cached -- . "${EXCLUDES[@]}")" ;;
  worktree) TARGET_DESC="the UNSTAGED working-tree change"; DIFF="$(git -C "$ROOT" diff -- . "${EXCLUDES[@]}")" ;;
  plan)     TARGET_DESC="the IMPLEMENTATION PLAN at ${PLAN} (read it AND the files it references)" ;;
esac
# Write the diff to a FILE first (#329: it must travel to codex as a file anyway — a
# multi-hundred-KB prompt as one exec argument hits the kernel per-arg limit, E2BIG),
# then probe THE FILE for emptiness: grep on a file exits at the first non-space byte.
# Never probe via a pipe — under \`set -o pipefail\`, grep -q's early exit SIGPIPEs the
# writer (exit 141) and a LARGE diff reads as "empty". And never bash
# pattern-substitution over the whole diff (the old \${DIFF// } spun 54+ min on a
# multi-MB single-line bundle).
DIFF_FILE=""
if [[ "$MODE" != "plan" ]]; then
  # Unique per invocation (mktemp) — two concurrent gate runs against the same
  # worktree must not race on one fixed path. Must live under $ROOT so the
  # read-only codex sandbox can read it; pattern is gitignored.
  DIFF_FILE="$(mktemp "$ROOT/.codex-review-diff.XXXXXX.patch")"
  printf '%s\n' "$DIFF" > "$DIFF_FILE"
  if ! grep -q '[^[:space:]]' "$DIFF_FILE"; then
    rm -f "$DIFF_FILE"
    echo "no reviewable diff for mode=$MODE (base=$BASE; generated bundles are excluded) — nothing to review" >&2; exit 3
  fi
fi
DIFF_BYTES=${#DIFF}
[[ $DIFF_BYTES -gt 400000 ]] && echo "WARN: diff is ${DIFF_BYTES}B — large; consider narrowing --base" >&2

# ---- build the prompt --------------------------------------------------------
read -r -d '' PROMPT <<EOF || true
You are a senior staff engineer doing an INDEPENDENT cross-model review. You are the
external check on another model's work — be skeptical, do not rubber-stamp. Review
${TARGET_DESC}. You may read any file in this repo for context. Verify claims against the
ACTUAL code; cite file:line for anything you assert is wrong.

Flag CORRECTNESS and SECURITY problems first, then sequencing/contract bugs, then real
maintainability issues. Do not invent work; if it is correct, say so.

${FOCUS:+REVIEWER FOCUS (the author asked you to weigh these specifically):
${FOCUS}
}
OUTPUT CONTRACT — your FINAL message MUST be a single JSON object and nothing else,
conforming to this schema (priority: 0=CRITICAL correctness/security, 1=IMPORTANT real
bug/risk, 2=MINOR should-fix, 3=NIT advisory):
{"overall_correctness":"correct|minor_issues|incorrect|cannot_determine",
 "findings":[{"priority":0,"title":"...","code_location":"file:line","body":"what is wrong + concrete failure"}],
 "notes":"optional"}
Empty findings array means nothing found. Do not wrap the JSON in prose or code fences.
EOF
# The diff already sits in DIFF_FILE (written above); point codex at it instead of
# inlining it in argv. Codex reads repo files natively; the file is untracked, never
# part of the reviewed diff, removed on exit.
if [[ "$MODE" != "plan" ]]; then
  PROMPT="${PROMPT}

DIFF UNDER REVIEW: read the unified diff in the file \`$(basename "$DIFF_FILE")\` at the
repo root (it is the ONLY content under review; it is untracked tooling output, not part
of the change itself)."
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "DRY RUN: mode=$MODE diff_bytes=$DIFF_BYTES prompt_bytes=${#PROMPT} diff_file=${DIFF_FILE:-'(none)'}" >&2
  [[ -n "$DIFF_FILE" ]] && rm -f "$DIFF_FILE"
  exit 0
fi

# ---- run codex (read-only) with model fallback -------------------------------
RAW="$(mktemp)"; trap 'rm -f "$RAW" ${DIFF_FILE:+"$DIFF_FILE"}' EXIT
got=""
for M in "" "-m gpt-5.1-codex" "-m gpt-5-codex"; do
  echo ">>> codex exec ${M:-(default model)} [read-only]" >&2
  # --output-schema is best-effort; the prompt also pins the JSON contract as a fallback.
  codex exec -s read-only $M --output-schema "$SCHEMA" -C "$ROOT" "$PROMPT" >"$RAW" 2>>"$RAW" \
    || codex exec -s read-only $M -C "$ROOT" "$PROMPT" >"$RAW" 2>>"$RAW" || true
  if grep -q "is not supported when using Codex" "$RAW"; then
    echo "(model rejected, trying next...)" >&2; continue
  fi
  got="yes"; break
done
[[ -z "$got" ]] && { echo "INFRA: every model was rejected by the account" >&2; exit 2; }

# ---- parse + recompute the gate MECHANICALLY (script is authoritative, not the model) --
python3 - "$RAW" "$OUT" "$BLOCK_AT" <<'PY'
import json, re, sys
raw_path, out_path, block_at = sys.argv[1], sys.argv[2], int(sys.argv[3])
text = open(raw_path, encoding="utf-8", errors="replace").read()
# Extract the LAST verdict object. The old naive brace-walker desynced on any
# unbalanced brace earlier in the raw stream (codex banners/progress lines), after
# which depth never returned to 0 and a PERFECTLY VALID verdict was reported as
# INFRA (observed live 2026-07-02: findings visible in the dump, gate said INFRA).
# Anchor on the schema's required key and walk STRING-AWARE from the nearest '{'.
def parse_from(anchor_pos):
    start = text.rfind('{', 0, anchor_pos + 1)
    while start >= 0:
        depth, in_str, esc = 0, False, False
        for i in range(start, len(text)):
            ch = text[i]
            if in_str:
                if esc: esc = False
                elif ch == '\\': esc = True
                elif ch == '"': in_str = False
            elif ch == '"': in_str = True
            elif ch == '{': depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    try: return json.loads(text[start:i+1])
                    except Exception: return None
        start = text.rfind('{', 0, start)
    return None
obj = None
pos = len(text)
while obj is None:
    pos = text.rfind('"overall_correctness"', 0, pos)
    if pos < 0: break
    obj = parse_from(pos)
if not isinstance(obj, dict) or "findings" not in obj:
    sys.stderr.write("INFRA: no parseable JSON verdict in codex output (rate limit / wrong format?)\n")
    sys.stderr.write(text[-1500:] + "\n")
    sys.exit(2)
findings = obj.get("findings") or []
LABEL = {0: "CRITICAL", 1: "IMPORTANT", 2: "MINOR", 3: "NIT"}
findings.sort(key=lambda f: f.get("priority", 3))
blocking = [f for f in findings if int(f.get("priority", 3)) <= block_at]
obj["_gate"] = {"block_at": block_at, "blocking_count": len(blocking), "clean": not blocking}
json.dump(obj, open(out_path, "w"), indent=2)

print(f"=== codex-review verdict ===  overall: {obj.get('overall_correctness','?')}")
for f in findings:
    p = int(f.get("priority", 3))
    mark = "■ BLOCK" if p <= block_at else "·"
    loc = f.get("code_location") or ""
    print(f"  {mark} [{LABEL.get(p,'?')}] {f.get('title','')}" + (f"  ({loc})" if loc else ""))
    if f.get("body"): print(f"        {f['body']}")
if obj.get("notes"): print(f"  notes: {obj['notes']}")
print(f"--- block_at=priority<={block_at}; {len(blocking)} blocking / {len(findings)} total; verdict JSON -> {out_path}")
sys.exit(1 if blocking else 0)
PY
RC=$?
case $RC in
  0) echo "GATE: CLEAN — pass" >&2 ;;
  1) echo "GATE: FINDINGS — fix the BLOCK items or escalate (do not re-judge a CRITICAL/IMPORTANT)" >&2 ;;
  2) echo "GATE: INFRA — review did not run cleanly; retry or escalate, do NOT treat as clean" >&2 ;;
esac
exit $RC
