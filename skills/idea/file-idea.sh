#!/usr/bin/env bash
# file-idea.sh — deterministic backend for the /idea skill.
#
# Ensures the idea label set exists, creates a GitHub Issue from a prepared
# body file, and prints the resulting issue URL + number for the skill to
# backlink into the planning doc.
#
# The interview, title/slug inference, and planning-doc authoring are done by
# the model (see SKILL.md). This script owns only the side effects that must be
# reliable and idempotent: label creation + `gh issue create`.
#
# Usage:
#   file-idea.sh --title "..." --type fix|feature|research \
#                --priority now|next|someday \
#                --body-file <path> [--milestone M3] [--dry-run]
#
# Output (stdout, parseable):
#   ISSUE_NUMBER=<n>
#   ISSUE_URL=<url>
#
# Exit non-zero on any failure (missing args, gh not authed, create failed).

set -euo pipefail

TITLE="" TYPE="" PRIORITY="" BODY_FILE="" MILESTONE="" DRY_RUN=0

die() { echo "file-idea: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)     TITLE="${2:-}"; shift 2 ;;
    --type)      TYPE="${2:-}"; shift 2 ;;
    --priority)  PRIORITY="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --milestone) MILESTONE="${2:-}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$TITLE" ]]     || die "--title is required"
[[ -n "$BODY_FILE" ]] || die "--body-file is required"
[[ -f "$BODY_FILE" ]] || die "body file not found: $BODY_FILE"

case "$TYPE" in
  fix|feature|research) ;;
  *) die "--type must be fix|feature|research (got: '${TYPE}')" ;;
esac
case "$PRIORITY" in
  now|next|someday) ;;
  *) die "--priority must be now|next|someday (got: '${PRIORITY}')" ;;
esac
if [[ -n "$MILESTONE" && ! "$MILESTONE" =~ ^M[1-9][0-9]*$ ]]; then
  die "--milestone must look like M1..M9 (got: '${MILESTONE}')"
fi

# label name -> "color|description"  (color is 6-hex, no leading #)
declare -A LABELS=(
  [idea]="c5def5|Captured via /idea (engineering backlog)"
  [fix]="d73a4a|/idea type: bug/defect to fix"
  [feature]="a2eeef|/idea type: new capability"
  [research]="fef2c0|/idea type: investigation/spike"
  [p:now]="b60205|/idea priority: do now"
  [p:next]="fbca04|/idea priority: do next"
  [p:someday]="0e8a16|/idea priority: someday/backlog"
)

ensure_label() {
  local name="$1" spec="${2}" color desc
  color="${spec%%|*}"; desc="${spec#*|}"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] ensure label: $name (#$color)" >&2
    return 0
  fi
  # --force creates if missing, updates color/desc if present (idempotent).
  gh label create "$name" --color "$color" --description "$desc" --force >/dev/null
}

# Resolve milestone -> real gh milestone if one exists, else an area:<M> label.
MS_ARGS=()
if [[ -n "$MILESTONE" ]]; then
  if [[ $DRY_RUN -eq 0 ]] && gh api repos/:owner/:repo/milestones --jq '.[].title' 2>/dev/null | grep -qx "$MILESTONE"; then
    MS_ARGS=(--milestone "$MILESTONE")
  else
    LABELS["area:$MILESTONE"]="ededed|/idea milestone area: $MILESTONE"
    ensure_label "area:$MILESTONE" "${LABELS["area:$MILESTONE"]}"
    MS_ARGS=()  # applied as a label below
  fi
fi

for name in idea "$TYPE" "p:$PRIORITY"; do
  ensure_label "$name" "${LABELS[$name]}"
done

LABEL_ARGS=(--label idea --label "$TYPE" --label "p:$PRIORITY")
if [[ -n "$MILESTONE" && ${#MS_ARGS[@]} -eq 0 ]]; then
  LABEL_ARGS+=(--label "area:$MILESTONE")
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] gh issue create --title \"$TITLE\" --body-file \"$BODY_FILE\" ${LABEL_ARGS[*]} ${MS_ARGS[*]}" >&2
  echo "ISSUE_NUMBER=DRYRUN"
  echo "ISSUE_URL=https://github.com/DRYRUN/issues/0"
  exit 0
fi

URL="$(gh issue create --title "$TITLE" --body-file "$BODY_FILE" "${LABEL_ARGS[@]}" "${MS_ARGS[@]}")"
[[ -n "$URL" ]] || die "gh issue create returned no URL"
NUMBER="${URL##*/}"

echo "ISSUE_NUMBER=$NUMBER"
echo "ISSUE_URL=$URL"
