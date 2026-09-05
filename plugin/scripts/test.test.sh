#!/usr/bin/env bash
# Tests for test.sh — the runner every other check goes through.
#
# If the runner stops propagating a suite's failure, every suite it runs
# reports green and nothing else is watching. So each check builds a fixture
# directory, runs the runner inside it, and requires a named check to go red
# — the runner passing on a clean fixture proves only that it can say yes.
#
# The fixture holds a copy of the runner plus a suite for it, because the
# runner requires a test file beside every script including itself.
#
# Run: bash plugin/scripts/test.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUNNER="$HERE/test.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

# The interpreter used to run the runner. Overridable so the suite can be
# replayed under an older bash (see the compatibility check at the end).
SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

. "$HERE/testlib.sh"

# --- fixtures --------------------------------------------------------------

passing_suite() { # <path>
  cat >"$1" <<'EOF'
#!/usr/bin/env bash
echo "TAP version 13"
echo "ok 1 - fixture suite"
echo "1..1"
EOF
}

failing_suite() { # <path>
  cat >"$1" <<'EOF'
#!/usr/bin/env bash
echo "TAP version 13"
echo "not ok 1 - deliberate failure"
echo "1..1"
exit 1
EOF
}

# A fixture the runner must find clean. It holds the runner, the harness the
# runner sources, and a suite for each of them — the runner requires a test
# file beside every script it finds, and does not exempt its own.
mk_fixture() { # <name> — echoes the directory
  local dir="$TMP/$1"
  mkdir -p "$dir"
  cp "$RUNNER" "$dir/test.sh"
  cp "$HERE/testlib.sh" "$dir/testlib.sh"
  passing_suite "$dir/test.test.sh"
  passing_suite "$dir/testlib.test.sh"
  printf '%s' "$dir"
}

run_in() { # <dir> — runs the runner there, echoes its exit code
  ( cd "$1" && "$SH" "$1/test.sh" >"$1/out.tap" 2>"$1/err.txt" )
  printf '%s' "$?"
}

# Whether a `not ok` line mentioning <substring> is present.
red_on() { # <dir> <substring>
  if /usr/bin/grep -q "^not ok .*$2" "$1/out.tap"; then printf 'yes'; else printf 'no'; fi
}

tap_begin

# --- the clean baseline ----------------------------------------------------
#
# Every mutation below is read against this one. If the baseline were red, a
# mutation going red would say nothing about the mutation.

BASE=$(mk_fixture baseline)
check "a fixture holding only the runner and its suite passes" 0 "$(run_in "$BASE")"
check "the baseline reports no failing check" no "$(red_on "$BASE" '')"

# --- a suite's failure must reach the runner's exit code -------------------
#
# This is the regression that would otherwise be invisible: the runner keeps
# listing suites while no failure among them can make the run fail.

FAILING=$(mk_fixture failing-suite)
failing_suite "$FAILING/broken.test.sh"
check "a failing suite makes the runner exit non-zero" 1 "$(run_in "$FAILING")"
check "a failing suite is named in the output" yes "$(red_on "$FAILING" 'broken.test.sh')"
check "the failing suite's own not-ok line is carried into the detail" yes \
  "$(/usr/bin/grep -q 'deliberate failure' "$FAILING/out.tap" && printf 'yes' || printf 'no')"

# --- a suite that asserts nothing must not read as passing ------------------
#
# A suite can exit 0 having run no check at all — its body stopped early, or
# the `ok` line changed shape — and look identical to a clean pass.

SILENT=$(mk_fixture silent-suite)
printf '#!/usr/bin/env bash\necho "TAP version 13"\necho "1..0"\n' >"$SILENT/silent.test.sh"
check "a suite that asserts nothing makes the runner exit non-zero" 1 "$(run_in "$SILENT")"
check "the silent suite is named" yes "$(red_on "$SILENT" 'silent.test.sh')"

# The checks that read the whole tree are sweep.test.sh's, which the runner
# executes like any other suite.

# --- an empty suite set must not read as success ----------------------------

EMPTY=$(mk_fixture empty)
rm -f "$EMPTY"/*.test.sh
check "a directory with no suites makes the runner exit non-zero" 1 "$(run_in "$EMPTY")"
check "the empty suite set is named" yes "$(red_on "$EMPTY" 'at least one suite ran')"

# --- bash 3.2 compatibility -------------------------------------------------
#
# Same two faces record.test.sh carries, for the same reason:
# on bash 3.2 an unsupported construct does not abort the script, it writes to
# stderr and carries on with a wrong value. The third face — the construct
# sweep — is the runner's own check and already reads this file.

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

    # The baseline fixture is the runner's success path; running it under the
    # old bash must print nothing at all.
    STDERR_FIX=$(mk_fixture stderr-probe)
    ( cd "$STDERR_FIX" && "$OLD_BASH" "$STDERR_FIX/test.sh" >/dev/null 2>"$STDERR_FIX/err.txt" )
    check "the runner writes nothing to stderr under bash $OLD_VER" "" \
      "$(cat "$STDERR_FIX/err.txt")"
  else
    # Not a silent pass: the guarantee is unavailable here and must say so.
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
