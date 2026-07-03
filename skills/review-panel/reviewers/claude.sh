#!/usr/bin/env bash
# claude adapter — fresh `claude -p` process, independent of the author session.
# Uniform contract: --target <file> [--focus-file <f>] --out <file> [--timeout <s>].
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$DIR/../../codex-review/sev.schema.json"
TARGET=""; OUT=""; FOCUS_FILE=""; TIMEOUT=300
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="$2"; shift 2;; --out) OUT="$2"; shift 2;;
  --focus-file) FOCUS_FILE="$2"; shift 2;; --timeout) TIMEOUT="$2"; shift 2;; *) shift;; esac; done
command -v claude >/dev/null 2>&1 || { echo "claude CLI absent" >&2; exit 2; }
FOCUS=""; [ -n "$FOCUS_FILE" ] && FOCUS="$(cat "$FOCUS_FILE")"
PROMPT="You are an independent code reviewer. Review the diff below for correctness, security, and requirement gaps. ${FOCUS}
Your FINAL message MUST be a single JSON object and nothing else, conforming to this schema:
$(cat "$SCHEMA")

DIFF:
$(cat "$TARGET")"
# Headless `-p` is non-interactive (tool calls needing permission are denied, not
# prompted), so we pass no write-granting permission mode — a reviewer must never
# edit the repo. The diff is inline in the prompt; the reviewer needs no tools.
raw="$(timeout "$TIMEOUT" claude -p "$PROMPT" --model sonnet 2>/dev/null)" || { echo "claude call failed" >&2; exit 2; }
RAW="$raw" python3 - "$OUT" <<'PY' || { echo "no JSON from claude" >&2; exit 2; }
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
d=json.loads(last); d['_model']='claude'
json.dump(d, open(sys.argv[1],'w'))
PY
exit 0
