#!/bin/bash
# Auto-Resume Hook — runs on SessionStart with matcher "clear"
# Finds the most recent handoff file and injects it as system context.
#
# PRECEDENCE (fix for mechanical handoffs shadowing intentional ones):
#   INTENTIONAL handoffs (model-written: /handoff, /session-pause) are named
#   `pause-*.md`. MECHANICAL handoffs (thin auto-pauses from context-monitor.sh
#   at ~75% and session-end-handoff.sh on /clear) are named `auto-*.md`.
#   We PREFER the newest fresh `pause-*.md`; only when none is fresh do we fall
#   back to the newest fresh `auto-*.md`. A legacy `pause-*.md` whose first line
#   is "# Auto Session Pause" is treated as mechanical (belt-and-suspenders for
#   files written before this split).
# Receives JSON on stdin: {session_id, cwd, ...}

set -euo pipefail

INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
if [[ -z "$CWD" ]]; then
  CWD="$HOME"
fi

MAX_AGE_SECONDS=86400  # 24 hours
NOW=$(date +%s)
MECH_TITLE='# Auto Session Pause'

# Search locations in priority order. Out-of-tree coordination handoffs first
# (shared across worktrees), then the legacy in-tree locations for back-compat.
COORD_DIR="$(bash "$HOME/.claude/coordination/resolve-coord-dir.sh" 2>/dev/null || true)"
SEARCH_DIRS=()
[[ -n "$COORD_DIR" ]] && SEARCH_DIRS+=("$COORD_DIR/handoffs")
SEARCH_DIRS+=("$CWD/docs/summaries" "$CWD/.claude-sessions")

# Also search worktree summaries directories
if [[ -d "$CWD/.worktrees" ]]; then
  for wt_dir in "$CWD"/.worktrees/*/docs/summaries; do
    [[ -d "$wt_dir" ]] && SEARCH_DIRS+=("$wt_dir")
  done
fi

# Print "<mtime> <path>" for every file matching $1 across all SEARCH_DIRS.
gather() {
  local glob="$1" d
  for d in "${SEARCH_DIRS[@]}"; do
    [[ -d "$d" ]] && find "$d" -maxdepth 1 -name "$glob" -type f -printf '%T@ %p\n' 2>/dev/null
  done
}

# 0 (true) if the file's first line marks it as a mechanical auto-pause.
is_mechanical_file() {
  local first=""
  [[ -f "$1" ]] || return 1
  IFS= read -r first < "$1" 2>/dev/null || true
  [[ "$first" == "$MECH_TITLE"* ]]
}

# Newest INTENTIONAL handoff: a pause-*.md that is NOT a (legacy) mechanical file.
INTENTIONAL=""
while read -r _mt path; do
  [[ -z "${path:-}" ]] && continue
  if is_mechanical_file "$path"; then continue; fi
  INTENTIONAL="$path"; break
done < <(gather 'pause-*.md' | sort -rn)

# Newest MECHANICAL handoff: auto-*.md plus any legacy pause-*.md flagged mechanical.
MECHANICAL=""
while read -r _mt path; do
  [[ -z "${path:-}" ]] && continue
  MECHANICAL="$path"; break
done < <( { gather 'auto-*.md'; gather 'pause-*.md' | while read -r m p; do is_mechanical_file "$p" && echo "$m $p"; done; } | sort -rn )

# True if $1 exists and was modified within MAX_AGE_SECONDS.
is_fresh() {
  local p="${1:-}" mt
  [[ -n "$p" ]] || return 1
  mt=$(stat -c %Y "$p" 2>/dev/null) || return 1
  (( (NOW - mt) <= MAX_AGE_SECONDS ))
}

# Choose: prefer a fresh intentional handoff; else a fresh mechanical one.
HANDOFF=""
if is_fresh "$INTENTIONAL"; then
  HANDOFF="$INTENTIONAL"
elif is_fresh "$MECHANICAL"; then
  HANDOFF="$MECHANICAL"
fi

# No fresh handoff chosen
if [[ -z "$HANDOFF" ]]; then
  if [[ -n "$INTENTIONAL" || -n "$MECHANICAL" ]]; then
    # There are handoffs, just all stale (>24h). Report the nearest age.
    NEAREST_MT=0
    for p in "$INTENTIONAL" "$MECHANICAL"; do
      [[ -n "$p" ]] || continue
      mt=$(stat -c %Y "$p" 2>/dev/null) || mt=0
      (( mt > NEAREST_MT )) && NEAREST_MT="$mt"
    done
    AGE_MIN=$(( (NOW - NEAREST_MT) / 60 ))
    printf '{"systemMessage": "SessionStart:clear hook success: No recent handoff found (nearest is %d min old). If you'\''re resuming previous work, run /session-resume to load an older handoff."}' "$AGE_MIN"
  else
    printf '{"systemMessage": "SessionStart:clear hook success: Success"}'
  fi
  exit 0
fi

# --- Validate handoff completeness ---
# Intentional handoffs and both mechanical writers always emit `## Instructions`.
# If the chosen one somehow lacks it, fall back to the other fresh candidate.
if ! grep -q '## Instructions' "$HANDOFF" 2>/dev/null; then
  ALT=""
  if [[ "$HANDOFF" == "$INTENTIONAL" ]] && is_fresh "$MECHANICAL"; then ALT="$MECHANICAL"; fi
  if [[ -n "$ALT" ]] && grep -q '## Instructions' "$ALT" 2>/dev/null; then
    HANDOFF="$ALT"
  else
    printf '{"systemMessage": "SessionStart:clear hook success: Found handoff but it appears incomplete. Run /session-resume to review it manually."}'
    exit 0
  fi
fi

# --- Load handoff into context ---
CONTENTS=$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r') as f:
        content = f.read()
    # Detect if handoff is from a worktree
    import os
    handoff_path = sys.argv[1]
    worktree_note = ''
    if '/.worktrees/' in handoff_path:
        # Extract worktree root (everything up to and including the worktree name)
        parts = handoff_path.split('/.worktrees/')
        wt_name = parts[1].split('/')[0]
        wt_path = parts[0] + '/.worktrees/' + wt_name
        if os.path.isdir(wt_path):
            worktree_note = (
                'WORKTREE DETECTED: This handoff is from a worktree at ' + wt_path + '. '
                'You MUST cd into that worktree directory FIRST before doing anything else. '
                'Then verify git state from there.\\n\\n'
            )
        else:
            worktree_note = (
                'WARNING: This handoff references a worktree at ' + wt_path + ' '
                'which no longer exists. Warn the user and check if the branch was merged.\\n\\n'
            )

    instructions = (
        'SESSION HANDOFF LOADED\\n\\n'
        + worktree_note +
        'INSTRUCTIONS: Present a brief summary of this handoff to the user: '
        'what was accomplished, what branch/state it was on, and what remains. '
        'Then run git status --short and git branch --show-current to verify '
        'current git state matches the handoff. Warn if there is a mismatch '
        '(different branch, unexpected changes). If there is a Remaining Work '
        'section, present it and ask: Should I continue with the remaining work, '
        'or do you have something else in mind?\\n\\n'
    )
    msg = instructions + content
    print(json.dumps({'systemMessage': 'SessionStart:clear hook success: ' + msg}))
except Exception as e:
    fallback = {'systemMessage': 'SessionStart:clear hook success: Failed to load handoff: ' + str(e)}
    print(json.dumps(fallback))
" "$HANDOFF" 2>/dev/null) || {
  printf '{"systemMessage": "SessionStart:clear hook success: Error reading handoff file."}'
  exit 0
}

echo "$CONTENTS"
exit 0
