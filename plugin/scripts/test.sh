#!/usr/bin/env bash
# hq test runner — runs every *.test.sh in this directory and reports each
# one as a single check.
#
# That is all it does. The checks that read the whole tree are a suite of
# their own (sweep.test.sh) and run from here like any other. test.test.sh
# drives this runner over throwaway fixture directories, so the runner must
# not read anything outside its own directory.
#
# A suite's individual TAP lines are not reproduced here; a suite is one check,
# and a failing one reports its first few `not ok` lines. Run a suite directly
# to read all of its output.
#
# Run: bash plugin/scripts/test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

. "$HERE/testlib.sh"

tap_begin

# --- per-script suites -----------------------------------------------------
#
# The suites run CONCURRENTLY, each its own process over its own fixtures, so
# none shares state with another. Output stays deterministic because nothing
# is reported from the background: each suite writes its TAP and exit code to
# its own files, and the second loop reads them back in the glob's order.
#
# The exit code travels through a file because bash 3.2's `wait` reports
# nothing per job. A code file that is missing or empty reads as a failure —
# what a suite that died before its first check looks like.

SUITES=0
for t in "$HERE"/*.test.sh; do
  [ -e "$t" ] || continue
  SUITES=$((SUITES + 1))
  name=$(basename "$t")
  ( bash "$t" >"$TMP/$name.tap" 2>&1; printf '%s' "$?" >"$TMP/$name.code" ) &
done
wait

for t in "$HERE"/*.test.sh; do
  [ -e "$t" ] || continue
  name=$(basename "$t")
  code=$(cat "$TMP/$name.code" 2>/dev/null)
  if [ "$code" = 0 ]; then
    # A suite that exits 0 having asserted nothing is not a passing suite. It
    # is what a suite looks like when its checks stopped running — or when the
    # `ok` line stopped being the shape this count reads.
    passed=$(/usr/bin/grep -c '^ok' "$TMP/$name.tap" | tr -d ' ')
    if [ "$passed" -gt 0 ]; then
      ok "$name — $passed checks"
    else
      not_ok "$name" "exited 0 but reported no passing checks"
    fi
  else
    not_ok "$name" "$(/usr/bin/grep -m3 '^not ok' "$TMP/$name.tap" 2>/dev/null | tr '\n' ' ')"
  fi
done

# An unmatched glob leaves SUITES at 0: a runner that ran nothing would
# otherwise exit 0, indistinguishable from a suite set that all passed.
check "at least one suite ran" yes "$([ "$SUITES" -gt 0 ] && echo yes || echo no)"


tap_end
