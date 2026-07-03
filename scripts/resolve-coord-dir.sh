#!/usr/bin/env bash
# Echoes the shared, out-of-tree coordination dir for the current repo (creating it).
# Keyed by the MAIN clone's directory name via --git-common-dir, so every worktree of
# the same repo resolves to the SAME dir → one journal, shared across sessions, never
# inside the tracked tree. Silent (empty) if not in a git repo.
common="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
[ -z "$common" ] && exit 0
common="$(cd "$common" 2>/dev/null && pwd)" || exit 0     # absolutize (handles relative ".git")
repo_key="$(basename "$(dirname "$common")")"
dir="$HOME/.claude/coordination/$repo_key"
mkdir -p "$dir/handoffs"
printf '%s\n' "$dir"
