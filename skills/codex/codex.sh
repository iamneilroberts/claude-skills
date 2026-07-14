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
#   --stats        append a TOKEN USAGE + estimated API COST block after the answer
#                  (opt-in; default output is unchanged). Prices are estimates and
#                  env-overridable: CODEX_PRICE_INPUT_PER_M / CODEX_PRICE_CACHED_PER_M /
#                  CODEX_PRICE_OUTPUT_PER_M (USD per 1M tokens).
set -euo pipefail

command -v codex >/dev/null 2>&1 || { echo "codex.sh: codex CLI not found on PATH" >&2; exit 2; }

SANDBOX="read-only"
MODEL=""
DIR=""
PROMPT=""
GOT_PROMPT=0
STATS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write)     SANDBOX="workspace-write"; shift ;;
    --stats)     STATS=1; shift ;;
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
JSONL="$(mktemp)"
trap 'rm -f "$LAST" "$JSONL"' EXIT

# Prompt travels on stdin ('-' positional); codex-cli reads it reliably there. -o writes
# only the final agent message so we skip banners/progress. In --stats mode we also emit
# JSONL events to a file (to read the turn.completed usage); otherwise stdout → /dev/null.
run() {
  if [[ "$STATS" -eq 1 ]]; then
    printf '%s' "$PROMPT" | codex exec -s "$SANDBOX" -C "$DIR" "$@" --json -o "$LAST" - >"$JSONL" 2>/dev/null
  else
    printf '%s' "$PROMPT" | codex exec -s "$SANDBOX" -C "$DIR" "$@" -o "$LAST" - >/dev/null 2>&1
  fi
}

if [[ -n "$MODEL" ]]; then
  # User pinned a model — respect it, no fallback.
  run -m "$MODEL" || { echo "codex.sh: codex exec failed with -m $MODEL (rate limit / reject / auth)." >&2; exit 1; }
else
  # Default model, then a codex-tuned fallback.
  run || run -m gpt-5.1-codex || { echo "codex.sh: codex exec failed (rate limit / auth / no model). Retry or pass -m <model>." >&2; exit 1; }
fi

cat "$LAST"

# --stats: append token usage + an estimated API cost from the last turn.completed event.
if [[ "$STATS" -eq 1 ]]; then
  # Prices (USD per 1M tokens) — estimates, env-overridable. Defaults track the GPT-5.x
  # codex tier (uncached input / cached input / output; reasoning billed as output).
  P_IN="${CODEX_PRICE_INPUT_PER_M:-1.25}"
  P_CACHED="${CODEX_PRICE_CACHED_PER_M:-0.125}"
  P_OUT="${CODEX_PRICE_OUTPUT_PER_M:-10.00}"
  # Last usage object in the stream (final turn.completed).
  USAGE="$(grep -oE '"usage":\{[^}]*\}' "$JSONL" | tail -1)"
  if [[ -n "$USAGE" ]]; then
    field() { echo "$USAGE" | grep -oE "\"$1\":[0-9]+" | grep -oE '[0-9]+$' | tail -1; }
    IN="$(field input_tokens)";       IN="${IN:-0}"
    CACHED="$(field cached_input_tokens)"; CACHED="${CACHED:-0}"
    OUT="$(field output_tokens)";     OUT="${OUT:-0}"
    REASON="$(field reasoning_output_tokens)"; REASON="${REASON:-0}"
    printf '\n---\n**Codex stats** (estimate)\n'
    awk -v in_t="$IN" -v cached="$CACHED" -v out="$OUT" -v reason="$REASON" \
        -v pin="$P_IN" -v pc="$P_CACHED" -v po="$P_OUT" 'BEGIN {
      uncached = in_t - cached; if (uncached < 0) uncached = 0;
      billed_out = out + reason;
      cost = uncached*pin/1e6 + cached*pc/1e6 + billed_out*po/1e6;
      printf "- Tokens: input %d (cached %d, uncached %d) · output %d (reasoning %d) · total %d\n", \
             in_t, cached, uncached, out, reason, in_t + billed_out;
      printf "- Est. cost: $%.4f  (rates/M: in $%.2f, cached $%.3f, out $%.2f)\n", cost, pin, pc, po;
    }'
  else
    printf '\n---\n_Codex stats: no usage event captured (older codex-cli or a failed turn)._\n'
  fi
fi
