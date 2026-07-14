#!/usr/bin/env bash
# /codex — run the OpenAI Codex CLI on a prompt in this repo and print its final answer.
#
# Codex is invoked as a delegate: READ-ONLY by default; --write lets it edit the tree.
# The prompt comes from args or stdin. Only Codex's final message is printed (via -o),
# so banner/progress noise is skipped. Model falls back on failure.
#
# Usage:
#   codex.sh "explain the auth flow in src/worker.ts"
#   codex.sh --write "add a null-check to resolveFieldAnchor and a test"
#   printf '%s' "long prompt with \"quotes\"" | codex.sh -
# Flags:
#   --write        workspace-write sandbox (Codex may edit files)   [default: read-only]
#   -m|--model M   pin a Codex model
#   --dir D        working root                                       [default: git root or cwd]
set -euo pipefail

command -v codex >/dev/null 2>&1 || { echo "codex.sh: codex CLI not found on PATH" >&2; exit 2; }

SANDBOX="read-only"
MODEL=""
DIR=""
PROMPT=""
GOT_PROMPT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write)     SANDBOX="workspace-write"; shift ;;
    -m|--model)  MODEL="${2:-}"; shift 2 ;;
    --dir)       DIR="${2:-}"; shift 2 ;;
    -)           PROMPT="$(cat)"; GOT_PROMPT=1; shift ;;   # explicit stdin
    *)           PROMPT="$1"; GOT_PROMPT=1; shift ;;
  esac
done

# No prompt arg → read stdin.
if [[ "$GOT_PROMPT" -eq 0 ]]; then PROMPT="$(cat)"; fi
[[ -n "$PROMPT" ]] || { echo "codex.sh: empty prompt" >&2; exit 2; }

# Working root: explicit --dir, else git root, else cwd.
if [[ -z "$DIR" ]]; then
  DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

LAST="$(mktemp)"
trap 'rm -f "$LAST"' EXIT

# Prompt travels on stdin ('-' positional); codex-cli reads it reliably there. -o writes
# only the final agent message so we skip banners/progress. stdout → /dev/null (we cat -o).
run() {
  printf '%s' "$PROMPT" | codex exec -s "$SANDBOX" -C "$DIR" "$@" -o "$LAST" - >/dev/null 2>&1
}

if [[ -n "$MODEL" ]]; then
  # User pinned a model — respect it, no fallback.
  run -m "$MODEL" || { echo "codex.sh: codex exec failed with -m $MODEL (rate limit / reject / auth)." >&2; exit 1; }
else
  # Default model, then a codex-tuned fallback.
  run || run -m gpt-5.1-codex || { echo "codex.sh: codex exec failed (rate limit / auth / no model). Retry or pass -m <model>." >&2; exit 1; }
fi

cat "$LAST"
