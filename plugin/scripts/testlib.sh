#!/usr/bin/env bash
# The TAP harness every test file here uses, and the runner with it. One
# definition because the runner reads each suite's output back — it counts
# `^ok` lines and quotes `^not ok` ones — and nothing checks that coupling: a
# suite that formatted its lines differently would still run and still pass.
#
# Source it, then bracket the checks:
#
#   . "$HERE/testlib.sh"
#   tap_begin
#   check "the thing holds" expected "$actual"
#   tap_end
#
# tap_end exits 1 when anything failed, so it belongs on the last line.
#
# `set -u` and the locale are the caller's to set; this file only defines.
#
# Portability: bash 3.2.

COUNT=0
FAIL=0

tap_begin() {
  echo "TAP version 13"
}

ok() { # <description>
  COUNT=$((COUNT + 1))
  printf 'ok %s - %s\n' "$COUNT" "$1"
}

not_ok() { # <description> <detail>
  COUNT=$((COUNT + 1))
  FAIL=$((FAIL + 1))
  printf 'not ok %s - %s\n' "$COUNT" "$1"
  printf '  ---\n  detail: %s\n  ...\n' "$2"
}

check() { # <description> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "expected [$2], got [$3]"; fi
}

tap_end() {
  echo "1..$COUNT"
  [ "$FAIL" -eq 0 ] || { printf '# %s of %s checks failed\n' "$FAIL" "$COUNT"; exit 1; }
  printf '# all %s checks passed\n' "$COUNT"
}
