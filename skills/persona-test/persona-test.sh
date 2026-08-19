#!/usr/bin/env bash
set -euo pipefail

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
    --issue) [ $# -lt 2 ] && { echo "missing value for $1" >&2; usage >&2; exit 3; }; ISSUE="$2"; shift 2;;
    --name) [ $# -lt 2 ] && { echo "missing value for $1" >&2; usage >&2; exit 3; }; NAME="$2"; shift 2;;
    --n) [ $# -lt 2 ] && { echo "missing value for $1" >&2; usage >&2; exit 3; }; N="$2"; shift 2;;
    --target) [ $# -lt 2 ] && { echo "missing value for $1" >&2; usage >&2; exit 3; }; TARGET="$2"; shift 2;;
    --adapter) [ $# -lt 2 ] && { echo "missing value for $1" >&2; usage >&2; exit 3; }; ADAPTER="$2"; shift 2;;
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
