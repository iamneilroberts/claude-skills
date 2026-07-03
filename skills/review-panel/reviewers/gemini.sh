#!/usr/bin/env bash
# gemini adapter — wraps the Gemini CLI. Same uniform contract as claude.sh.
# Invocation matches the canonical /gemini-review command
# (~/.claude/commands/gemini-review.md): `gemini --approval-mode plan -o text -p`.
# --approval-mode plan = read-only (a reviewer must never get edit/tool rights,
# same principle as dropping --permission-mode from the claude adapter);
# -o text = plain output the JSON extractor below scans. Verified live 2026-07-01.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$DIR/../../codex-review/sev.schema.json"
TARGET=""; OUT=""; FOCUS_FILE=""; TIMEOUT=300
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="$2"; shift 2;; --out) OUT="$2"; shift 2;;
  --focus-file) FOCUS_FILE="$2"; shift 2;; --timeout) TIMEOUT="$2"; shift 2;; *) shift;; esac; done
command -v gemini >/dev/null 2>&1 || { echo "gemini CLI absent" >&2; exit 2; }
FOCUS=""; [ -n "$FOCUS_FILE" ] && FOCUS="$(cat "$FOCUS_FILE")"
PROMPT="You are an independent code reviewer. Review the diff for correctness, security, and requirement gaps. ${FOCUS}
Your FINAL output MUST be a single JSON object conforming to this schema:
$(cat "$SCHEMA")

DIFF:
$(cat "$TARGET")"
raw="$(timeout "$TIMEOUT" gemini --approval-mode plan -o text -p "$PROMPT" 2>/dev/null)" || { echo "gemini call failed" >&2; exit 2; }
RAW="$raw" python3 - "$OUT" <<'PY' || { echo "no JSON from gemini" >&2; exit 2; }
import json,os,sys
raw=os.environ["RAW"]
depth=0; start=None; last=None
for i,c in enumerate(raw):
    if c=='{':
        if depth==0: start=i
        depth+=1
    elif c=='}':
        depth-=1
        if depth==0 and start is not None: last=raw[start:i+1]
if last is None: sys.exit(1)
d=json.loads(last); d['_model']='gemini'
json.dump(d, open(sys.argv[1],'w'))
PY
exit 0
