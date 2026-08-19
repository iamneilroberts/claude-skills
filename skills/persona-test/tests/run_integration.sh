#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
run() { "$DIR/persona-test.sh" "$@"; }

run --help >/dev/null 2>&1 || { echo "FAIL: --help should exit 0"; fail=1; }
run --bogus-flag >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: bad flag should exit 3"; fail=1; }
run notamode >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: bad mode should exit 3"; fail=1; }
run scenario --n 99 >/dev/null 2>&1; [ $? -eq 3 ] || { echo "FAIL: n>10 should exit 3"; fail=1; }

# Python unit suite must pass.
( cd "$DIR/tests" && python3 -m unittest -v ) || { echo "FAIL: python unit suite"; fail=1; }

[ $fail -eq 0 ] && echo "integration PASS" || { echo "integration FAIL"; exit 1; }
