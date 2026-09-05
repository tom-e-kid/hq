#!/usr/bin/env bash
# Tests for testlib.sh — the TAP harness.
#
# This file uses the harness to test the harness. What the checks below
# actually verify is the format the runner parses, from the outside: each one
# runs a throwaway suite in a separate process and reads the text it
# produced.
#
# Run: bash plugin/scripts/testlib.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

. "$HERE/testlib.sh"

# Runs <body> as a suite in its own process. Output lands in $TMP/probe.out and
# the exit code is echoed.
probe() { # <body>
  cat >"$TMP/probe.sh" <<EOF
set -u
. "$HERE/testlib.sh"
tap_begin
$1
tap_end
EOF
  "$SH" "$TMP/probe.sh" >"$TMP/probe.out" 2>&1
  printf '%s' "$?"
}

out() { cat "$TMP/probe.out"; }
line() { sed -n "$1p" "$TMP/probe.out"; }

tap_begin

# --- the lines the runner parses -------------------------------------------

probe 'ok "first"' >/dev/null
check "tap_begin emits the version line" "TAP version 13" "$(line 1)"
check "ok emits an ok line numbered from 1" "ok 1 - first" "$(line 2)"

probe 'ok "first"
ok "second"
ok "third"' >/dev/null
check "the counter advances across checks" "ok 3 - third" "$(line 4)"
check "tap_end emits the plan with the final count" "1..3" "$(line 5)"

probe 'not_ok "broke" "because reasons"' >/dev/null
check "not_ok emits a not ok line" "not ok 1 - broke" "$(line 2)"
check "not_ok carries its detail" "  detail: because reasons" "$(line 4)"

# The runner greps for `^not ok`. An `ok` line must not be mistakable for one,
# and the detail block must not start a line with either token.
probe 'not_ok "broke" "expected [ok 1 - x], got [not ok 1 - y]"' >/dev/null
check "a detail quoting TAP tokens stays indented" 1 \
  "$(/usr/bin/grep -c '^not ok' "$TMP/probe.out")"

# --- the exit code ----------------------------------------------------------

check "a suite with no failures exits 0" 0 "$(probe 'ok "fine"')"
check "one failure exits 1" 1 "$(probe 'ok "fine"
not_ok "broke" "detail"')"
check "the summary counts only the failures" "# 1 of 2 checks failed" \
  "$(/usr/bin/grep '^# ' "$TMP/probe.out")"

check "a passing suite says how many passed" "# all 2 checks passed" \
  "$(probe 'ok "one"
ok "two"' >/dev/null; /usr/bin/grep '^# ' "$TMP/probe.out")"

# --- check() ----------------------------------------------------------------

check "check passes on equal strings" 0 "$(probe 'check "equal" a a')"
check "check fails on different strings" 1 "$(probe 'check "different" a b')"
check "a failing check reports both sides" "  detail: expected [a], got [b]" \
  "$(probe 'check "different" a b' >/dev/null; line 4)"

# Values that would break a naive comparison: empty strings, strings with
# spaces, and a string that looks like a flag.
check "check compares empty strings as equal" 0 "$(probe 'check "empty" "" ""')"
check "check sees an empty string differ from a space" 1 "$(probe 'check "space" "" " "')"
check "check handles a leading dash" 0 "$(probe 'check "dash" -n -n')"
check "check handles embedded spaces" 0 "$(probe 'check "spaced" "a b" "a b"')"

# --- bash 3.2 compatibility -------------------------------------------------

if [ "${HQ_TEST_INNER:-}" != 1 ]; then
  OLD_BASH=""
  if [ -x /bin/bash ]; then
    OLD_MAJOR=$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null || echo 99)
    [ "$OLD_MAJOR" -lt 4 ] 2>/dev/null && OLD_BASH=/bin/bash
  fi

  if [ -n "$OLD_BASH" ]; then
    OLD_VER=$("$OLD_BASH" -c 'echo $BASH_VERSION')

    if HQ_TEST_INNER=1 HQ_TEST_SH="$OLD_BASH" "$OLD_BASH" "$SELF" >"$TMP/old.tap" 2>&1; then
      ok "the whole suite passes under bash $OLD_VER"
    else
      not_ok "the whole suite passes under bash $OLD_VER" \
        "$(/usr/bin/grep -m3 '^not ok' "$TMP/old.tap" | tr '\n' ' ')"
    fi

    HQ_TEST_SH="$OLD_BASH" probe 'ok "one"
check "two" a a' >/dev/null
    check "the harness writes nothing to stderr under bash $OLD_VER" "" \
      "$(/usr/bin/grep -v '^ok\|^1\.\.\|^TAP\|^# ' "$TMP/probe.out")"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
