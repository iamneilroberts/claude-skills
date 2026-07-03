#!/usr/bin/env bash
# get-reddit.sh — thin launcher for get-reddit.mjs (the Playwright browser-session fetcher).
# Ensures deps are present on first run, then fetches a Reddit post as markdown.
#
# Usage:  .claude/skills/get-reddit/get-reddit.sh <reddit-url-or-post-id> [comment_limit]
# Env:    GET_REDDIT_HEADLESS=0  show the browser window (use if a fetch gets challenged)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v node >/dev/null 2>&1 || { echo "error: node is required but not installed" >&2; exit 6; }

# First-run setup: install Playwright + the Chromium binary (shared at ~/.cache/ms-playwright).
if [[ ! -d "$DIR/node_modules/playwright" ]]; then
  echo "get-reddit: first run — installing Playwright (one-time)..." >&2
  ( cd "$DIR" && npm install --silent )
fi
if ! ( cd "$DIR" && node -e "require('playwright').chromium.executablePath()" ) >/dev/null 2>&1; then
  echo "get-reddit: installing Chromium browser binary (one-time)..." >&2
  ( cd "$DIR" && npx --yes playwright install chromium )
fi

exec node "$DIR/get-reddit.mjs" "$@"
