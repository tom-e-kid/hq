#!/usr/bin/env bash
# Suite for check.sh — the entry point that runs this repository's gate.
#
# What it has to get right is one thing: a failure underneath it must reach the
# caller. An entry point that runs two suites and returns 0 whatever they said
# is worse than no entry point, because the person who ran it now believes the
# tree was checked. So every case here is about the exit code.
#
# check.sh names the two scripts it runs by path, so a fixture is a directory
# holding stand-ins at those paths. That runs the real control flow — the same
# `|| STATUS=1` and the same order — against outcomes a real run rarely
# produces on demand.
#
# Output is TAP. Exit 0 when every check passes.
#
# Run: bash .claude/scripts/check.test.sh

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

N=0
FAILED=0
ok() { N=$((N + 1)); printf 'ok %d - %s\n' "$N" "$1"; }
not_ok() { # <name> <detail>
  N=$((N + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n  ---\n  detail: %s\n  ...\n' "$N" "$1" "$2"
}
check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "expected [$2], got [$3]"; fi
}

# <dir> <plugin exit> <docs exit> [<secrets exit>] — a tree with stand-ins that
# exit as told. The secrets stand-in defaults to passing: every case below is
# about one of the other two, and a third failure in all of them would make
# each case pass for a reason it is not testing.
mk_tree() {
  local d=$1
  mkdir -p "$d/plugin/scripts" "$d/.claude/scripts"
  printf '#!/usr/bin/env bash\nprintf "plugin ran\\n"\nexit %s\n' "$2" \
    >"$d/plugin/scripts/test.sh"
  printf '#!/usr/bin/env bash\nprintf "docs ran\\n"\nexit %s\n' "$3" \
    >"$d/.claude/scripts/docs-check.sh"
  printf '#!/usr/bin/env bash\nprintf "secrets ran\\n"\nexit %s\n' "${4:-0}" \
    >"$d/.claude/scripts/secrets-check.sh"
  cp "$HERE/check.sh" "$d/.claude/scripts/check.sh"
}

status_of() { # <dir>
  ( bash "$1/.claude/scripts/check.sh" >/dev/null 2>&1 )
  printf '%s' "$?"
}
output_of() { # <dir>
  ( bash "$1/.claude/scripts/check.sh" 2>&1 )
}

BOTH_OK="$TMP/both-ok"
mk_tree "$BOTH_OK" 0 0
check "both passing is a pass" 0 "$(status_of "$BOTH_OK")"

# One case per side, because an entry point that reports the last exit code
# passes the first of these and fails the second.
PLUGIN_BAD="$TMP/plugin-bad"
mk_tree "$PLUGIN_BAD" 1 0
check "the plugin suite failing fails the gate" 1 "$(status_of "$PLUGIN_BAD")"

DOCS_BAD="$TMP/docs-bad"
mk_tree "$DOCS_BAD" 0 1
check "the docs checks failing fails the gate" 1 "$(status_of "$DOCS_BAD")"

BOTH_BAD="$TMP/both-bad"
mk_tree "$BOTH_BAD" 1 1
check "both failing fails the gate" 1 "$(status_of "$BOTH_BAD")"

# The third side. It is here for the reason the other two are: without a case
# of its own, dropping its call from the gate leaves every check above passing.
SECRETS_BAD="$TMP/secrets-bad"
mk_tree "$SECRETS_BAD" 0 0 1
check "the secrets sweep failing fails the gate" 1 "$(status_of "$SECRETS_BAD")"
check "and it runs even when the others passed" yes \
  "$(printf '%s' "$(output_of "$SECRETS_BAD")" | /usr/bin/grep -q 'secrets ran' \
     && printf 'yes' || printf 'no')"

# A gate that stops at the first failure hides the second, and the person
# running it fixes one thing and runs again. Both halves run either way.
check "the second half runs even when the first failed" "plugin ran docs ran" \
  "$(output_of "$PLUGIN_BAD" | /usr/bin/grep -E '^(plugin|docs) ran$' | tr '\n' ' ' \
     | sed 's/ $//')"

# The stand-ins are what make the cases above mean anything: if check.sh looked
# somewhere else, every case would report whatever the real tree says instead.
check "the fixture's stand-ins are what ran" "plugin ran docs ran" \
  "$(output_of "$BOTH_OK" | /usr/bin/grep -E '^(plugin|docs) ran$' | tr '\n' ' ' \
     | sed 's/ $//')"

# The suites in this directory are found by glob, so the case that matters is
# one being present and failing — a loop that skipped it would leave the gate
# green with a red suite sitting next to it.
SUITE_BAD="$TMP/suite-bad"
mk_tree "$SUITE_BAD" 0 0
printf '#!/usr/bin/env bash\nprintf "suite ran\\n"\nexit 1\n' \
  >"$SUITE_BAD/.claude/scripts/probe.test.sh"
check "a failing suite in this directory fails the gate" 1 "$(status_of "$SUITE_BAD")"
check "and it was actually run" "suite ran" \
  "$(output_of "$SUITE_BAD" | /usr/bin/grep -c '^suite ran$' | sed 's/^1$/suite ran/')"

printf '1..%d\n' "$N"
if [ "$FAILED" -gt 0 ]; then
  printf '# %d of %d checks failed\n' "$FAILED" "$N"
  exit 1
fi
printf '# all %d checks passed\n' "$N"
