#!/usr/bin/env bash
# codex adapter — wraps the committed codex-review.sh, tags _model=codex.
# Uniform contract: --target <file> [--focus-file <f>] --out <file> [--timeout <s>]
#   plus optional [--review-mode base|staged|plan] [--base-ref <ref>].
# Exit 0 = verdict written to --out; non-zero = unavailable (no --out written).
#
# codex-review.sh has native --base/--staged modes that read the LIVE git diff.
# When the panel is reviewing a git diff (--review-mode base|staged), we use those
# directly — codex reviews the real repo diff, which avoids the "--plan" framing
# artifacts (e.g. spurious "file not in this repository") and is more robust than
# feeding a pre-assembled file. Only when there is no git mode (a --plan review, or
# no mode passed) do we fall back to `--plan "$TARGET"`, codex-review's only mode
# that reads an arbitrary file's contents.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""; OUT=""; FOCUS_FILE=""; TIMEOUT=300; REVIEW_MODE=""; BASE_REF=""
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="$2"; shift 2;; --out) OUT="$2"; shift 2;;
  --focus-file) FOCUS_FILE="$2"; shift 2;; --timeout) TIMEOUT="$2"; shift 2;;
  --review-mode) REVIEW_MODE="$2"; shift 2;; --base-ref) BASE_REF="$2"; shift 2;;
  *) shift;; esac; done
command -v codex >/dev/null 2>&1 || { echo "codex CLI absent" >&2; exit 2; }
CR="$DIR/../../codex-review/codex-review.sh"
[ -x "$CR" ] || { echo "codex-review.sh missing (Phase 0 not landed?)" >&2; exit 2; }
tmp="$(mktemp)"
FOCUS_ARG=(); [ -n "$FOCUS_FILE" ] && FOCUS_ARG=(--focus-file "$FOCUS_FILE")

# Pick codex-review's mode. Native git-diff modes when the panel is on a git diff;
# else feed the assembled target as a --plan file (preserves prior behavior).
case "$REVIEW_MODE" in
  base)   [ -n "$BASE_REF" ] && CR_MODE=(--base "$BASE_REF") || CR_MODE=(--plan "$TARGET") ;;
  staged) CR_MODE=(--staged) ;;
  *)      CR_MODE=(--plan "$TARGET") ;;
esac

if timeout "$TIMEOUT" "$CR" "${CR_MODE[@]}" --out "$tmp" "${FOCUS_ARG[@]}" >/dev/null 2>&1 || [ -s "$tmp" ]; then
  python3 -c "import json,sys; d=json.load(open('$tmp')); d['_model']='codex'; json.dump(d,open('$OUT','w'))" 2>/dev/null \
    && exit 0
fi
echo "codex adapter produced no verdict" >&2; exit 2
