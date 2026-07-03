#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
"$DIR/review-panel.sh" --help >/dev/null 2>&1 || { echo "FAIL: --help should exit 0"; fail=1; }
"$DIR/review-panel.sh" --bogus-flag >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: bad flag should exit 3"; fail=1; }
"$DIR/review-panel.sh" --block-at 9 >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: block-at out of range should exit 3"; fail=1; }
[ $fail -eq 0 ] && echo "usage tests PASS"

# Adapter contract. Every adapter must exist and be executable.
for adp in codex claude gemini; do
  [ -x "$DIR/reviewers/$adp.sh" ] || { echo "FAIL: $adp adapter missing/not executable"; fail=1; }
done
# Live model calls are gated behind REVIEW_PANEL_LIVE=1 — the default suite makes
# NO live calls (the ~$60 lesson). Absent CLIs are a clean SKIP, never a FAIL.
if [ "${REVIEW_PANEL_LIVE:-0}" = "1" ]; then
  printf 'diff --git a/x.py b/x.py\n@@\n+q="SELECT * FROM u WHERE id="+id\n' > /tmp/rp_target.txt
  for adp in codex claude gemini; do
    "$DIR/reviewers/$adp.sh" --target /tmp/rp_target.txt --out /tmp/rp_$adp.json --timeout 120 2>/dev/null
    rc=$?
    if [ $rc -eq 0 ]; then
      python3 -c "import json;json.load(open('/tmp/rp_$adp.json'))" || { echo "FAIL: $adp emitted non-JSON"; fail=1; }
      echo "adapter $adp: produced valid JSON"
    else
      echo "adapter $adp: SKIP (CLI absent or unavailable, rc=$rc)"
    fi
  done
else
  echo "adapter live-contract checks: SKIP (set REVIEW_PANEL_LIVE=1 to run)"
fi

# Offline end-to-end: stub reviewers via REVIEW_PANEL_REVIEWER_DIR. Deterministic,
# no model CLIs — asserts the full orchestrator → merge.py exit-code contract.
STUB="$(mktemp -d)"
cat > "$STUB/codex.sh" <<'EOF'
#!/usr/bin/env bash
FINDINGS='[{"priority":0,"title":"bug","code_location":"x.py:1","body":"b"}]'
while [ $# -gt 0 ]; do case "$1" in --out) O="$2"; shift 2;; *) shift;; esac; done
echo "{\"overall_correctness\":\"incorrect\",\"findings\":$FINDINGS,\"_model\":\"codex\"}" > "$O"
EOF
cat > "$STUB/gemini.sh" <<'EOF'
#!/usr/bin/env bash
FINDINGS='[{"priority":0,"title":"bug","code_location":"x.py:1","body":"b"}]'
while [ $# -gt 0 ]; do case "$1" in --out) O="$2"; shift 2;; *) shift;; esac; done
echo "{\"overall_correctness\":\"incorrect\",\"findings\":$FINDINGS,\"_model\":\"gemini\"}" > "$O"
EOF
cat > "$STUB/claude.sh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --out) O="$2"; shift 2;; *) shift;; esac; done
echo '{"overall_correctness":"correct","findings":[],"_model":"claude"}' > "$O"
EOF
chmod +x "$STUB"/*.sh
printf 'diff --git a/x.py b/x.py\n@@\n+bad\n' > /tmp/rp_buggy.patch

# Corroborated blocking finding → exit 1.
REVIEW_PANEL_REVIEWER_DIR="$STUB" "$DIR/review-panel.sh" --plan /tmp/rp_buggy.patch --out /tmp/rp_e2e.json >/dev/null 2>&1
[ $? -eq 1 ] && echo "e2e buggy→exit1 PASS" || { echo "FAIL: buggy e2e should exit 1"; fail=1; }

# All reviewers clean → exit 0.
CLEAN="$(mktemp -d)"
for m in codex gemini claude; do cat > "$CLEAN/$m.sh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --out) O="$2"; shift 2;; *) shift;; esac; done
echo '{"overall_correctness":"correct","findings":[]}' > "$O"
EOF
done
chmod +x "$CLEAN"/*.sh
REVIEW_PANEL_REVIEWER_DIR="$CLEAN" "$DIR/review-panel.sh" --plan /tmp/rp_buggy.patch --out /tmp/rp_e2e_clean.json >/dev/null 2>&1
[ $? -eq 0 ] && echo "e2e clean→exit0 PASS" || { echo "FAIL: clean e2e should exit 0"; fail=1; }

# Lone finding refuted by the challenge round → demoted → exit 0.
LONE="$(mktemp -d)"
cat > "$LONE/codex.sh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --out) O="$2"; shift 2;; *) shift;; esac; done
echo '{"overall_correctness":"minor_issues","findings":[{"priority":1,"title":"Missing null check","code_location":"src/auth.py:88","body":"b"}],"_model":"codex"}' > "$O"
EOF
for m in gemini claude; do cat > "$LONE/$m.sh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --out) O="$2"; shift 2;; *) shift;; esac; done
echo '{"overall_correctness":"correct","findings":[]}' > "$O"
EOF
done
chmod +x "$LONE"/*.sh
REVIEW_PANEL_REVIEWER_DIR="$LONE" "$DIR/review-panel.sh" --plan /tmp/rp_buggy.patch --out /tmp/rp_e2e_lone.json >/dev/null 2>&1
[ $? -eq 0 ] && echo "e2e lone-refuted→exit0 PASS" || { echo "FAIL: lone-refuted e2e should exit 0"; fail=1; }

exit $fail
