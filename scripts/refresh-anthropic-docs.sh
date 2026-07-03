#!/usr/bin/env bash
# Mirror code.claude.com docs to ~/.claude/anthropic-docs/ using llms.txt as index.
# Idempotent; safe to run from cron. Writes a manifest with per-page timestamps.
set -euo pipefail

INDEX_URL="https://code.claude.com/docs/llms.txt"
MIRROR_DIR="${HOME}/.claude/anthropic-docs"
MANIFEST="${MIRROR_DIR}/_manifest.json"
LOG_PREFIX="$(date -Iseconds) [refresh-anthropic-docs]"

mkdir -p "${MIRROR_DIR}"

echo "${LOG_PREFIX} fetching index ${INDEX_URL}" >&2
INDEX_TMP="$(mktemp)"
trap 'rm -f "${INDEX_TMP}"' EXIT

if ! curl -fsSL --max-time 30 "${INDEX_URL}" -o "${INDEX_TMP}"; then
  echo "${LOG_PREFIX} FATAL: could not fetch index" >&2
  exit 1
fi

# Extract markdown URLs from the llms.txt listing.
# Format: - [Title](https://code.claude.com/docs/en/<slug>.md): description
mapfile -t URLS < <(grep -oE 'https://code\.claude\.com/docs/[^)]+\.md' "${INDEX_TMP}" | sort -u)
TOTAL="${#URLS[@]}"

if [[ "${TOTAL}" -eq 0 ]]; then
  echo "${LOG_PREFIX} FATAL: no .md URLs found in index" >&2
  exit 1
fi

echo "${LOG_PREFIX} found ${TOTAL} pages" >&2

# Build manifest as we go: { "fetched_at": ..., "source": ..., "pages": { slug: { url, bytes, sha256, fetched_at } } }
TMP_MANIFEST="$(mktemp)"
{
  printf '{\n'
  printf '  "fetched_at": "%s",\n' "$(date -Iseconds)"
  printf '  "source": "%s",\n' "${INDEX_URL}"
  printf '  "total_pages": %d,\n' "${TOTAL}"
  printf '  "pages": {\n'
} > "${TMP_MANIFEST}"

OK_COUNT=0
FAIL_COUNT=0
FIRST=1
for url in "${URLS[@]}"; do
  # Slug = path under /docs/, with slashes replaced by __ so we don't need nested dirs
  rel="${url#https://code.claude.com/docs/}"
  slug="${rel%.md}"
  safe_slug="${slug//\//__}"
  out="${MIRROR_DIR}/${safe_slug}.md"

  if curl -fsSL --max-time 20 "${url}" -o "${out}.tmp"; then
    bytes=$(stat -c '%s' "${out}.tmp")
    sha=$(sha256sum "${out}.tmp" | awk '{print $1}')
    mv "${out}.tmp" "${out}"
    OK_COUNT=$((OK_COUNT + 1))

    [[ "${FIRST}" -eq 1 ]] || printf ',\n' >> "${TMP_MANIFEST}"
    FIRST=0
    printf '    "%s": { "url": "%s", "bytes": %d, "sha256": "%s", "fetched_at": "%s" }' \
      "${safe_slug}" "${url}" "${bytes}" "${sha}" "$(date -Iseconds)" >> "${TMP_MANIFEST}"
  else
    rm -f "${out}.tmp"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "${LOG_PREFIX} WARN: failed ${url}" >&2
  fi
done

{
  printf '\n  }\n}\n'
} >> "${TMP_MANIFEST}"

mv "${TMP_MANIFEST}" "${MANIFEST}"

# Also persist the raw index so the skill can re-resolve titles → slugs without re-fetching
cp "${INDEX_TMP}" "${MIRROR_DIR}/_llms.txt"

echo "${LOG_PREFIX} done: ${OK_COUNT} ok, ${FAIL_COUNT} failed, manifest at ${MANIFEST}" >&2

# Exit non-zero only if we got nothing
if [[ "${OK_COUNT}" -eq 0 ]]; then
  exit 2
fi
