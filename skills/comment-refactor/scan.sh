#!/usr/bin/env bash
# comment-refactor scan — print the worklist: which code files need refactoring
# (marker missing/stale) vs are up-to-date (marker matches). Mechanical only:
# it applies the extension + vendored/generated exclusions and the marker check.
# The SEMANTIC "is this file actually used?" filter (dead/abandoned code) is the
# model's job via repowise get_dead_code — this script just narrows the field.
#
# Usage:
#   scan.sh [path-or-glob ...]     # default: whole repo (git-tracked files)
# Output: one line per candidate — "PROCESS <file>" or "SKIP-UPTODATE <file>".
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MARKER="python3 $HERE/marker.py"

# Code extensions the marker helper knows how to stamp.
EXTS='ts|tsx|js|jsx|mjs|cjs|c|h|cc|cpp|hpp|java|go|rs|swift|kt|kts|scala|php|cs|dart|proto|zig|py|rb|sh|bash|zsh|r|pl|pm|sql|lua|hs|elm|ex|exs|css|scss|less|vue|svelte'
# Never touch: dependencies, build output, minified, vendored, snapshots, generated.
EXCLUDE='node_modules/|/dist/|/build/|/out/|/coverage/|/vendor/|/.git/|/.wrangler/|\.min\.|\.d\.ts$|__generated__|/generated/|\.snap$'

list_files() {
  if [ "$#" -gt 0 ]; then
    for a in "$@"; do
      if [ -f "$a" ]; then echo "$a"
      elif [ -d "$a" ]; then git -C "$a" ls-files 2>/dev/null | sed "s#^#$a/#" || find "$a" -type f
      else ls -1 $a 2>/dev/null || true   # glob
      fi
    done
  else
    git ls-files 2>/dev/null || find . -type f
  fi
}

list_files "$@" \
  | grep -Ei "\.($EXTS)\$" \
  | grep -Ev "$EXCLUDE" \
  | sort -u \
  | while IFS= read -r f; do
      [ -f "$f" ] || continue
      if $MARKER check "$f" >/dev/null 2>&1; then
        echo "SKIP-UPTODATE $f"
      else
        echo "PROCESS $f"
      fi
    done
