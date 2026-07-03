#!/usr/bin/env bash
# review-panel.sh — multi-reviewer fan-out + consensus/challenge gate. See SKILL.md.
# Exit: 0 clean · 1 findings · 2 infra · 3 usage.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$DIR/../codex-review/sev.schema.json"
RDIR="${REVIEW_PANEL_REVIEWER_DIR:-$DIR/reviewers}"

TARGET_MODE="base"; BASE_REF="origin/main"; PLAN_FILE=""
REVIEWERS="codex,gemini,claude"; BLOCK_AT=1; FOCUS=""; FOCUS_FILE=""
STRICT=0; OUT="/tmp/review-panel.json"; TIMEOUT=300

usage() { sed -n '2,4p' "$0"; cat <<'EOF'
Usage: review-panel.sh [--base <ref> | --staged | --plan <file>]
  [--reviewers codex,gemini,claude] [--block-at 0-3] [--focus "…" | --focus-file <f>]
  [--strict] [--out <path>] [--timeout <sec>]
EOF
}

die_usage() { echo "usage error: $1" >&2; usage >&2; exit 3; }

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --base) BASE_REF="${2:-}"; TARGET_MODE="base"; shift 2 ;;
    --staged) TARGET_MODE="staged"; shift ;;
    --plan) PLAN_FILE="${2:-}"; TARGET_MODE="plan"; shift 2 ;;
    --reviewers) REVIEWERS="${2:-}"; shift 2 ;;
    --block-at) BLOCK_AT="${2:-}"; shift 2 ;;
    --focus) FOCUS="${2:-}"; shift 2 ;;
    --focus-file) FOCUS_FILE="${2:-}"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

[[ "$BLOCK_AT" =~ ^[0-3]$ ]] || die_usage "--block-at must be 0-3"
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die_usage "--timeout must be an integer"
[ "$TARGET_MODE" = "plan" ] && [ ! -f "$PLAN_FILE" ] && die_usage "--plan file not found: $PLAN_FILE"
IFS=',' read -ra RSEL <<< "$REVIEWERS"
for r in "${RSEL[@]}"; do case "$r" in codex|gemini|claude) ;; *) die_usage "unknown reviewer: $r";; esac; done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
TARGET="$WORK/target.txt"

# 1) Assemble the target once.
case "$TARGET_MODE" in
  base)   git diff "$BASE_REF"...HEAD > "$TARGET" ;;
  staged) git diff --cached > "$TARGET" ;;
  plan)   cp "$PLAN_FILE" "$TARGET" ;;
esac
[ -s "$TARGET" ] || { echo "review-panel: empty target (nothing to review)" >&2; exit 3; }

FOCUS_ARGS=()
if [ -n "$FOCUS_FILE" ]; then FOCUS_ARGS=(--focus-file "$FOCUS_FILE")
elif [ -n "$FOCUS" ]; then printf '%s' "$FOCUS" > "$WORK/focus.txt"; FOCUS_ARGS=(--focus-file "$WORK/focus.txt"); fi

# Mode passthrough — lets the codex adapter use codex-review's native --base/--staged
# git-diff path instead of the --plan-file framing (other adapters ignore these args).
MODE_ARGS=(--review-mode "$TARGET_MODE")
[ "$TARGET_MODE" = "base" ] && MODE_ARGS+=(--base-ref "$BASE_REF")

# 2) Round 1: fan out to selected adapters in parallel.
declare -a R1=()
for r in "${RSEL[@]}"; do
  out="$WORK/r1_$r.json"
  "$RDIR/$r.sh" --target "$TARGET" --out "$out" --timeout "$TIMEOUT" "${MODE_ARGS[@]}" "${FOCUS_ARGS[@]}" &
done
wait
for r in "${RSEL[@]}"; do [ -s "$WORK/r1_$r.json" ] && R1+=("$WORK/r1_$r.json"); done

STRICT_ARG=(); [ "$STRICT" -eq 1 ] && STRICT_ARG=(--strict)

# 3) Classify: which lone blocking findings need challenging.
CLASSIFY="$(python3 "$DIR/merge.py" --phase classify "${R1[@]}" --block-at "$BLOCK_AT" "${STRICT_ARG[@]}")"
mapfile -t _LONE < <(python3 -c "import json,sys;print('\n'.join(json.loads(sys.argv[1])['lone_blocking']))" "$CLASSIFY")
LONE=(); for k in "${_LONE[@]}"; do [ -n "$k" ] && LONE+=("$k"); done
[ "${#LONE[@]}" -gt 1 ] && echo "review-panel: ${#LONE[@]} lone findings challenged (each tagged with its own finding_key via a per-round sidecar)" >&2

# 4) Challenge round: ask the NON-flagging adapters to confirm/refute each lone finding.
declare -a CH=()
if [ "${#LONE[@]}" -gt 0 ]; then
  idx=0
  for key in "${LONE[@]}"; do
    # A lone finding (agreement 1) was flagged by exactly one model; find it so we
    # challenge only with the others. finding_key comes from merge.py so the
    # normalization matches the classify phase exactly.
    flagger="$(RP_DIR="$DIR" KEY="$key" python3 - "${R1[@]}" <<'PY'
import os,sys
sys.path.insert(0, os.environ["RP_DIR"])
import merge
key=os.environ["KEY"]
for p in sys.argv[1:]:
    d=merge.load_verdict(p)
    if not d: continue
    for f in d.get("findings",[]):
        if merge.finding_key(f)==key:
            print(d.get("_model","")); sys.exit()
PY
)"
    printf '%s' "CONFIRM OR REFUTE this specific finding against the diff. Finding key: $key" > "$WORK/ch_prompt_$idx.txt"
    # Record THIS round's target key in a sidecar so tagging associates each
    # challenge verdict with its exact finding — not by re-indexing an array.
    printf '%s' "$key" > "$WORK/ch_${idx}.key"
    for r in "${RSEL[@]}"; do
      [ "$r" = "$flagger" ] && continue
      chout="$WORK/ch_${idx}_$r.json"
      "$RDIR/$r.sh" --target "$TARGET" --out "$chout" --timeout "$TIMEOUT" "${MODE_ARGS[@]}" --focus-file "$WORK/ch_prompt_$idx.txt" &
    done
    idx=$((idx+1))
  done
  wait
  # Tag each challenge verdict with its target finding key (read from the per-round
  # sidecar, so association is explicit per finding, not positional) and a
  # confirmed/refuted read: a challenger who independently flags the finding at or
  # above the gate = confirmed, else refuted.
  for chf in "$WORK"/ch_*_*.json; do
    [ -s "$chf" ] || continue
    base="$(basename "$chf")"; cidx="${base#ch_}"; cidx="${cidx%%_*}"
    keyfile="$WORK/ch_${cidx}.key"
    [ -s "$keyfile" ] || continue
    ckey="$(cat "$keyfile")"
    [ -z "$ckey" ] && continue
    CKEY="$ckey" BLOCK_AT="$BLOCK_AT" python3 - "$chf" <<'PY' || true
import json,os,sys
p=sys.argv[1]
try: d=json.load(open(p))
except Exception: sys.exit()
block_at=int(os.environ["BLOCK_AT"])
conf = any(f.get('priority',3) <= block_at for f in d.get('findings',[]))
d['_challenge_of']=os.environ['CKEY']
d['_verdict']='confirmed' if conf else 'refuted'
json.dump(d, open(p,'w'))
PY
    CH+=("$chf")
  done
fi

# 5) Finalize: apply the gate.
CH_ARGS=(); [ "${#CH[@]}" -gt 0 ] && CH_ARGS=(--challenge "${CH[@]}")
python3 "$DIR/merge.py" --phase finalize "${R1[@]}" "${CH_ARGS[@]}" --block-at "$BLOCK_AT" "${STRICT_ARG[@]}" > "$OUT"
rc=$?
echo "review-panel: verdict → $OUT (exit $rc)" >&2
cat "$OUT" >&2
exit $rc
