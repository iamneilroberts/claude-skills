#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
run() { "$DIR/persona-test.sh" "$@"; }

run --help >/dev/null 2>&1 || { echo "FAIL: --help should exit 0"; fail=1; }
run --bogus-flag >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: bad flag should exit 3"; fail=1; }
run notamode >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: bad mode should exit 3"; fail=1; }
run scenario --n 99 >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: n>10 should exit 3"; fail=1; }
run --n >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: --n with no value should exit 3"; fail=1; }

# Python unit suite must pass.
( cd "$DIR/tests" && python3 -m unittest -v ) || { echo "FAIL: python unit suite"; fail=1; }

# Adapter contract: each adapter dir must have adapter.md.
for adp in example-http voygent; do
  [ -f "$DIR/adapters/$adp/adapter.md" ] || { echo "FAIL: adapter $adp missing adapter.md"; fail=1; }
done
# SKILL.md must exist and declare the skill name.
grep -q "name: persona-test" "$DIR/SKILL.md" || { echo "FAIL: SKILL.md missing name"; fail=1; }
# Skill body must NOT hardcode the app (generic constraint).
if grep -riq "voygent" "$DIR/SKILL.md" "$DIR/lib/" "$DIR/sinks/"; then
  echo "FAIL: app name leaked into generic skill body"; fail=1
fi
# Gated live e2e — default suite makes NO live calls.
if [ "${PERSONA_TEST_LIVE:-0}" = "1" ]; then
  echo "live e2e: (dispatch a 1-persona run against example-http stub here)"
fi

[ $fail -eq 0 ] && echo "integration PASS" || { echo "integration FAIL"; exit 1; }
