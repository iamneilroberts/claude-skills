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
  --min-model M   floor for per-subagent model tier (haiku|sonnet|opus)
  --max-model M   ceiling for per-subagent model tier (haiku|sonnet|opus)
  --help          show this help

Model tiers: the SKILL right-sizes each persona subagent's model by how hard
its (persona, scenario) is to role-play, then clamps that choice to
[min-model, max-model]. Set only one to pin a floor or a ceiling; set both
equal to force one tier for every subagent; leave both unset for default
judgment. The external codex driver is unaffected.
EOF
}

MODE="changes"; N=5; ADAPTER="example-http"; TARGET=""; ISSUE=""; NAME=""; MIN_MODEL=""; MAX_MODEL=""
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
    --min-model) [ $# -lt 2 ] && { echo "missing value for $1" >&2; usage >&2; exit 3; }; MIN_MODEL="$2"; shift 2;;
    --max-model) [ $# -lt 2 ] && { echo "missing value for $1" >&2; usage >&2; exit 3; }; MAX_MODEL="$2"; shift 2;;
    *) echo "unknown flag: $1" >&2; usage >&2; exit 3;;
  esac
done
if ! [[ "$N" =~ ^[0-9]+$ ]] || [ "$N" -lt 1 ] || [ "$N" -gt 10 ]; then
  echo "--n must be 1-10" >&2; exit 3
fi
model_rank() { case "$1" in haiku) echo 1;; sonnet) echo 2;; opus) echo 3;; *) echo 0;; esac; }
for pair in "min:${MIN_MODEL}" "max:${MAX_MODEL}"; do
  name="${pair%%:*}"; val="${pair#*:}"
  [ -z "$val" ] && continue
  if [ "$(model_rank "$val")" = 0 ]; then
    echo "--${name}-model must be one of haiku|sonnet|opus" >&2; exit 3
  fi
done
if [ -n "$MIN_MODEL" ] && [ -n "$MAX_MODEL" ] && [ "$(model_rank "$MIN_MODEL")" -gt "$(model_rank "$MAX_MODEL")" ]; then
  echo "--min-model ($MIN_MODEL) must not exceed --max-model ($MAX_MODEL)" >&2; exit 3
fi

# Orchestration proper is driven by SKILL.md (Task 8): this entrypoint validates
# inputs and prints the resolved plan. The SKILL reads these values and dispatches
# persona subagents. Live dispatch is gated by the SKILL, never by this script.
echo "mode=$MODE n=$N adapter=$ADAPTER target=${TARGET:-none} issue=${ISSUE:-none} name=${NAME:-none} min_model=${MIN_MODEL:-none} max_model=${MAX_MODEL:-none}"
