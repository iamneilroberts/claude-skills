#!/usr/bin/env bash
# One-time setup. Run only after the user approves the dependency install.

set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v node >/dev/null 2>&1 || { echo "error: node is required" >&2; exit 6; }
command -v npm >/dev/null 2>&1 || { echo "error: npm is required" >&2; exit 6; }

cd "$SKILL_ROOT"
npm install --ignore-scripts --no-audit --no-fund --save-exact

echo "get-reddit setup complete"
