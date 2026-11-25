#!/usr/bin/env bash
# Launch the Reddit-only Playwright fetcher. Setup is deliberately separate so a
# fetch request never performs a hidden package or browser installation.

set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v node >/dev/null 2>&1 || {
  echo "error: node is required" >&2
  exit 6
}

if [[ ! -f "$SKILL_ROOT/node_modules/playwright-core/package.json" ]]; then
  echo "get-reddit: Playwright Core is not installed for this skill." >&2
  echo "setup: bash $SKILL_ROOT/scripts/setup.sh" >&2
  exit 9
fi

if [[ -n "${GET_REDDIT_CHROME:-}" ]]; then
  BROWSER_PATH="$GET_REDDIT_CHROME"
else
  BROWSER_PATH=""
  for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      BROWSER_PATH="$(command -v "$candidate")"
      break
    fi
  done
fi
if [[ -z "$BROWSER_PATH" || ! -x "$BROWSER_PATH" ]]; then
  echo "get-reddit: no Chrome/Chromium executable found." >&2
  echo "hint: set GET_REDDIT_CHROME=/absolute/path/to/chrome" >&2
  exit 10
fi

export GET_REDDIT_CHROME="$BROWSER_PATH"
exec node "$SKILL_ROOT/scripts/get-reddit.mjs" "$@"
