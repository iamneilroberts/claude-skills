#!/usr/bin/env bash
# survey.sh — shallow-clone an open-source repo to a scratch dir and print an
# inventory the /evaluate calling session uses to partition the codebase for
# subagent crawl. READ-ONLY: clones and inspects; never installs or runs anything.
#
# Usage: bash survey.sh <git-url> <slug>
#   <git-url>  https://github.com/owner/repo(.git)
#   <slug>     short kebab name for the scratch dir (e.g. "heku")
#
# Clone lands in /tmp/evaluate/<slug>/. Re-running reuses an existing clone.

set -euo pipefail

URL="${1:-}"
SLUG="${2:-}"
if [[ -z "$URL" || -z "$SLUG" ]]; then
  echo "usage: bash survey.sh <git-url> <slug>" >&2
  exit 2
fi

ROOT="/tmp/evaluate/${SLUG}"
mkdir -p /tmp/evaluate

if [[ -d "$ROOT/.git" ]]; then
  echo "## clone: reusing existing $ROOT"
else
  echo "## clone: shallow-cloning $URL -> $ROOT"
  # --depth 1: no history. No submodule init, no hooks, nothing executed.
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 --no-tags "$URL" "$ROOT" 2>&1 | sed 's/^/   /'
fi

cd "$ROOT"

echo
echo "## license"
# Surface the license file + its first lines (drives the lift-vs-reimplement call).
LIC=$(ls LICENSE* COPYING* 2>/dev/null | head -1 || true)
if [[ -n "$LIC" ]]; then
  echo "   file: $LIC"
  head -3 "$LIC" | sed 's/^/   /'
else
  echo "   (no LICENSE file found — treat as all-rights-reserved; reimplement, don't copy)"
fi
# package.json license field, if present
if [[ -f package.json ]]; then
  grep -m1 '"license"' package.json | sed 's/^/   pkg: /' || true
fi

echo
echo "## manifests & entry points"
for f in package.json pyproject.toml Cargo.toml go.mod pom.xml build.gradle \
         requirements.txt setup.py composer.json Gemfile deno.json wrangler.toml \
         tsconfig.json Dockerfile README.md; do
  [[ -f "$f" ]] && echo "   $f"
done

echo
echo "## size: tracked files by extension (top 20)"
# Use git ls-files so we only count source, never node_modules/dist/vendored deps.
git ls-files | sed -n 's/.*\.\([A-Za-z0-9_]\{1,8\}\)$/\1/p' \
  | sort | uniq -c | sort -rn | head -20 | sed 's/^/   /'

echo
echo "## size: lines of code by top-level dir (source files only)"
# Group LOC by first path segment so the caller can partition by subsystem.
git ls-files \
  | grep -Ei '\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|rb|php|c|h|cpp|cc|cs|swift|kt|scala|sh|sql|graphql|proto)$' \
  | while IFS= read -r f; do
      top="${f%%/*}"; [[ "$top" == "$f" ]] && top="(root)"
      lines=$(wc -l < "$f" 2>/dev/null || echo 0)
      echo "$top $lines"
    done \
  | awk '{a[$1]+=$2} END {for (d in a) printf "%8d  %s\n", a[d], d}' \
  | sort -rn | sed 's/^/   /'

echo
echo "## tree (dirs + source files, depth 3, noise pruned)"
git ls-files \
  | grep -Ev '(^|/)(node_modules|dist|build|\.next|out|coverage|vendor|__pycache__|\.github)/' \
  | awk -F/ 'NF<=3' \
  | grep -Ei '\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|rb|php|c|h|cpp|cc|cs|swift|kt|scala|sh|sql|graphql|proto|json|md|toml|yaml|yml)$' \
  | sort | sed 's/^/   /' | head -200

echo
echo "## done. scratch: $ROOT"
echo "## next: partition the dirs above into subsets, one subagent each (see SKILL.md step 3)."
