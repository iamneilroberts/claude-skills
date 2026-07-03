#!/bin/bash
# session-end-nudge.sh — Stop hook. Reminds (does NOT auto-run) to run /session-end
# when meaningful committed work has accrued since the last SESSION_LOG entry.
#
# Fires at most ONCE per "log epoch": after it nudges, it stays quiet until a new
# SESSION_LOG.md entry is written (mtime advances) — so it's not naggy. Per-repo.
# Fails silently. /session-end stays a manual model+curator ritual; this only nudges.

allow() { exit 0; }

input=$(cat)
command -v jq >/dev/null 2>&1 || allow
CWD=$(printf '%s' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || allow
LOG="$ROOT/SESSION_LOG.md"

# commits since the last SESSION_LOG entry (its mtime); if no log yet, count commits
# not on origin/main (unlogged local work).
if [ -f "$LOG" ]; then
    LOG_MTIME=$(stat -c %Y "$LOG" 2>/dev/null || echo 0)
    N=$(git -C "$ROOT" log --since="@${LOG_MTIME}" --oneline 2>/dev/null | wc -l | tr -d ' ')
else
    LOG_MTIME=0
    N=$(git -C "$ROOT" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
fi

THRESHOLD=3
[ "$N" -ge "$THRESHOLD" ] 2>/dev/null || allow

# Dedup: one nudge per log epoch (keyed by repo path hash + the log mtime we last nudged at).
KEY=$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)
MARKER="${TMPDIR:-/tmp}/claude-sessionend-nudge-${KEY}"
LAST=$(cat "$MARKER" 2>/dev/null || echo "")
[ "$LAST" = "$LOG_MTIME" ] && allow            # already nudged this epoch
printf '%s' "$LOG_MTIME" > "$MARKER" 2>/dev/null || true

MSG="💡 ${N} commit(s) since the last SESSION_LOG entry. Before you /clear, consider /session-end (curator-verifies + logs) or /handoff. Both now add a right-sized wrap-up self-check (least-confident · not-done · breaks-in-3-months) that captures any gap as a handoff note or /idea rather than fixing it now — so it won't derail you. Optional; quiet until the next log entry."
jq -n --arg m "$MSG" '{systemMessage: $m}'
exit 0
