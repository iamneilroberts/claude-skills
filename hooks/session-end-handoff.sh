#!/bin/bash
# session-end-handoff.sh — SessionEnd hook.
#
# Writes a mechanical handoff (auto-<date>-<sid>.md, same format as context-monitor.sh)
# when a session is torn down via /clear (or logout/exit) — so EARLY clears (well below
# the 75% auto-write threshold) still leave a fresh handoff for auto-resume.sh to load.
#
# It is MECHANICAL (git state + last 6 conversation turns from the transcript) — no
# curator, no model summary. It DEFERS to a fresher handoff: if any pause-*.md was
# written in the last 3 minutes (a /session-pause or a context-monitor 75% write), it
# skips so it never shadows the better one. Fails silently.

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

REASON=$(printf '%s' "$input" | jq -r '.reason // empty' 2>/dev/null)
case "$REASON" in
    clear|logout|prompt_input_exit) ;;     # real teardown where work would be lost
    *) exit 0 ;;                            # resume/compact/other → context kept, skip
esac

SID=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"
[ -n "$SID" ] || exit 0

# --- Output dir (per-worktree, same as context-monitor) ---
# Prefer the out-of-tree coordination handoffs dir (shared across worktrees, no churn).
COORD_DIR="$(bash "$HOME/.claude/coordination/resolve-coord-dir.sh" 2>/dev/null || true)"
if [ -n "$COORD_DIR" ]; then
    DIR="$COORD_DIR/handoffs"; mkdir -p "$DIR" 2>/dev/null
elif [ -d "$CWD/docs/summaries" ] || [ -d "$CWD/docs" ]; then
    DIR="$CWD/docs/summaries"; mkdir -p "$DIR" 2>/dev/null
else
    DIR="$CWD/.claude-sessions"; mkdir -p "$DIR" 2>/dev/null
fi

# --- Defer to a fresher handoff (model /session-pause, /handoff, or context-monitor 75%) ---
# Covers both namespaces: intentional `pause-*.md` AND another mechanical `auto-*.md`.
if [ -n "$(find "$DIR" -maxdepth 1 \( -name 'pause-*.md' -o -name 'auto-*.md' \) -newermt '-3 minutes' 2>/dev/null | head -1)" ]; then
    exit 0
fi

# --- Git state (best-effort) ---
BR=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "(not a git repo)")
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
ST=$(git -C "$CWD" status --short 2>/dev/null || echo "")
DF=$(git -C "$CWD" diff --stat 2>/dev/null || echo "")
LG=$(git -C "$CWD" log --oneline -5 2>/dev/null || echo "")
HAS_CHANGES="no"; [ -n "$ST" ] && HAS_CHANGES="yes"

# --- Last 6 meaningful turns from the transcript (reuses context-monitor's extraction) ---
CONV=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    CONV=$(python3 -c "
import sys, json
turns=[]
try:
    with open(sys.argv[1],'r',encoding='utf-8',errors='replace') as f:
        for line in f:
            line=line.strip()
            if not line: continue
            try: o=json.loads(line)
            except: continue
            t=o.get('type','')
            if t=='summary' or o.get('isSummary'): turns=[]; continue
            if t in ('human','assistant','user'):
                c=''
                m=o.get('message')
                if isinstance(m,dict):
                    p=m.get('content','')
                    if isinstance(p,list): c=' '.join(x.get('text','') for x in p if isinstance(x,dict) and x.get('type')=='text')
                    elif isinstance(p,str): c=p
                elif isinstance(m,str): c=m
                c=c.strip()
                if c:
                    role='Human' if t in ('human','user') else 'Assistant'
                    turns.append((role,c[:500]))
                    turns=turns[-6:]
    print('\n\n'.join(f'**{r}:** {c}' for r,c in turns))
except Exception:
    print('(conversation context unavailable)')
" "$TRANSCRIPT" 2>/dev/null) || CONV="(conversation context unavailable)"
fi

# Nothing worth handing off?
[ -z "$CONV" ] && [ "$HAS_CHANGES" = "no" ] && [ -z "$LG" ] && exit 0

DATE_STR=$(date '+%Y-%m-%d'); TIME_STR=$(date '+%H:%M'); SHORT="${SID:0:8}"
# MECHANICAL handoff → `auto-*.md` namespace (subordinate to intentional `pause-*.md`).
FILE="$DIR/auto-${DATE_STR}-${SHORT}.md"
REPO_LINE=""; [ -n "$ROOT" ] && REPO_LINE="**Repo:** ${ROOT}"

cat > "${FILE}.tmp" <<EOF
# Auto Session Pause (on ${REASON})
**Date:** ${DATE_STR} at ${TIME_STR}
${REPO_LINE}
**Session:** ${SHORT}
**Branch:** ${BR}
**Uncommitted changes:** ${HAS_CHANGES}

> Mechanical handoff written at /${REASON} (no curator/model summary). Verify against git
> before trusting; the full transcript is the source of truth if detail is missing.

## Git State
\`\`\`
${ST:-（clean）}
\`\`\`

## Recent Changes
\`\`\`
${DF:-（none）}
\`\`\`

## Recent Commits
\`\`\`
${LG}
\`\`\`

## Last Conversation Context
${CONV:-（unavailable）}

## Instructions
Continue the work from this session. **If \`docs/summaries/CHECKLIST.md\` exists, or a prior
\`pause-*.md\` here has a \`## Checklist\` section, rebuild your TodoWrite list from its
unchecked \`- [ ]\` items before doing anything else** (this mechanical handoff could not
capture the live TodoWrite list — it lives only in the previous session's context). Review
the git state and conversation context above to understand where things left off. Run
\`git status\` / \`git branch --show-current\` to confirm, and ask the user what to focus on
next if the direction isn't clear.
EOF
mv "${FILE}.tmp" "$FILE" 2>/dev/null && printf 'SessionEnd handoff written: %s\n' "$FILE" >&2
exit 0
