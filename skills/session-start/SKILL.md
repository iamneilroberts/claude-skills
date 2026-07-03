---
name: session-start
description: Begin a documented coding session — create a per-session log so progress is tracked and later wrap-up (/session-end) has something to append to. Use at the start of a work session. Triggers on `/session-start`, "start a coding session", "begin a session".
user_invocable: true
---

# Start Coding Session

Begin a documented coding session so progress is tracked and context survives a `/clear`.

Create a session record with:
- Timestamp: current date/time
- Git state: current branch and commit
- Session goals: what the session aims to accomplish

```bash
SESSION_DIR=".claude-sessions"
mkdir -p "$SESSION_DIR"
SESSION_FILE="$SESSION_DIR/session_$(date +%Y%m%d_%H%M%S).log"

echo "=== Claude Coding Session ===" > "$SESSION_FILE"
echo "Started: $(date)" >> "$SESSION_FILE"
echo "Branch: $(git branch --show-current 2>/dev/null || echo 'no git')" >> "$SESSION_FILE"
echo "Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'no git')" >> "$SESSION_FILE"
echo "" >> "$SESSION_FILE"
echo "Goals:" >> "$SESSION_FILE"
```

Ask the user:
1. What are we working on today?
2. What specific goals should this session accomplish?
3. Any context worth knowing up front?

Record those goals in the session file and track progress against them through the session.