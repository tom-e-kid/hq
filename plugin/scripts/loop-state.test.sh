#!/usr/bin/env bash
# Tests for loop-state.sh — the observations a cycle enters on, and the module
# they derive.
#
# THE TABLE IS DRIVEN FROM REPOSITORIES ON DISK, one per row, rather than from
# a list of inputs this file believes the script reads. The derivation is the
# only thing in the tree with no second face: a fixture that set `gate=1` by
# hand would agree with this file's idea of the observation instead of with
# the gate's answer.
#
# BOTH DIRECTIONS ON EVERY STOP. A script that exited 2 for everything would
# pass every failure check here on its own, so each stop is checked alongside
# the values that still derived through it: a detached HEAD still resolves a
# base, and a gate that could not look still leaves the plan readable.
#
# Run: bash plugin/scripts/loop-state.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE="$HERE/loop-state.sh"
LIB="$HERE/lib.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

# The interpreter under test, overridable so the whole suite can be replayed
# under an older bash (see the compatibility section at the end).
SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# One home for the fixtures, so nothing here can reach the developer's real
# ~/.hq. HQ_SINK is left unset — the gate derives the stream from the same
# home, and a fixture that pointed it elsewhere would be answering a question
# this suite is not asking.
unset HQ_SINK
export HQ_HOME="$TMP/home"

. "$HERE/testlib.sh"

# --- fixtures ---------------------------------------------------------------

# A repository whose base is named in its own settings, so the base this suite
# expects is one the resolution chain had to read rather than one it fell back
# to: `main` is what the chain answers for any repository at all.
mk_repo() { # <dir> <base> <branch>
  mkdir -p "$1/.hq"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name "Test"
  git -C "$1" config commit.gpgsign false
  printf '{"base_branch":"%s"}\n' "$2" >"$1/.hq/settings.json"
  git -C "$1" commit -q --allow-empty -m init
  git -C "$1" checkout -q -b "$3"
}

task_dir() { # <dir> <branch>
  "$SH" "$LIB" hq_task_dir "$1" "$2"
}

plan_in() { # <dir> <branch>
  local d
  d=$(task_dir "$1" "$2") || return 1
  mkdir -p "$d"
  printf '# a plan\n' >"$d/plan.md"
}

# A findings file where the verifier would have written one. The shape is
# findings-gate.sh's contract; what matters here is that the id has no
# disposition row anywhere, which is what makes the gate exit 1.
findings_in() { # <dir> <branch> <id>...
  local d id; d=$(task_dir "$1" "$2") || return 1
  mkdir -p "$d"
  : >"$d/findings.jsonl"
  shift 2
  for id in "$@"; do
    printf '{"id":"%s","weight":"medium","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}\n' \
      "$id" >>"$d/findings.jsonl"
  done
}

reports_in() { # <dir> <branch> <n>
  local d i; d=$(task_dir "$1" "$2") || return 1
  mkdir -p "$d/reports"
  i=1
  while [ "$i" -le "$3" ]; do
    printf 'a pass\n' >"$d/reports/pass-$i.md"
    i=$((i + 1))
  done
}

# --- driving the script -----------------------------------------------------
#
# stdout, stderr and the exit code are kept apart. Folded together, a line the
# gate wrote would be indistinguishable from a key this script emitted — which
# is the one property the forwarding is there to keep.

OUT=""
ERR=""
CODE=""

run_state() { # <env assignments, one string, may be empty> <args...>
  local assigns=$1; shift
  local errf="$TMP/stderr.txt"
  # The assignments are split on purpose: this is how a case substitutes one
  # variable into the run without exporting it into every case after it.
  OUT=$(env $assigns "$SH" "$STATE" "$@" 2>"$errf")
  CODE=$?
  ERR=$(cat "$errf")
}

val() { # <key> — the value of one key of the last run
  printf '%s\n' "$OUT" | sed -n "s/^$1=//p"
}

emitted_keys() { # the keys of the last run, in the order they were printed
  printf '%s\n' "$OUT" | sed -n 's/^\([a-z][a-z]*\)=.*/\1/p' | tr '\n' ' '
}

KEY_ORDER="branch base plan reports gate entry why "

tap_begin

# --- the table, one repository per row ---------------------------------------

# Row 1: no plan. The run directory does not exist at all here, which is what a
# branch nobody has planned on looks like.
R1="$TMP/r-noplan"
mk_repo "$R1" develop feat/one
run_state "" "$R1"
check "no plan: exits 0" 0 "$CODE"
check "no plan: the plan line says none" none "$(val plan)"
check "no plan: enters at the planning module" hq:plan "$(val entry)"

# Row 2: a plan, and a finding nothing has disposed of.
R2="$TMP/r-undisposed"
mk_repo "$R2" develop feat/one
plan_in "$R2" feat/one
findings_in "$R2" feat/one F1
run_state "" "$R2"
check "undisposed findings: exits 0" 0 "$CODE"
check "undisposed findings: the gate answered 1" 1 "$(val gate)"
check "undisposed findings: enters at triage" hq:triage "$(val entry)"
# The gate names the findings on ITS stdout, which would land in the middle of
# the value face. Forwarded, not dropped: a caller parsing keys never sees it,
# and a person reading the run still does.
check "the gate's own list does not reach the value face" "" \
  "$(printf '%s\n' "$OUT" | /usr/bin/grep 'no disposition was recorded' || true)"
check "the gate's own list is forwarded to stderr" yes \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -q 'F1: no disposition was recorded for it' && echo yes || echo no)"

# Row 3: a plan, a clean gate, and no verification pass on record. The work is
# still the builder's.
R3="$TMP/r-fresh"
mk_repo "$R3" develop feat/one
plan_in "$R3" feat/one
run_state "" "$R3"
check "a plan and no pass: exits 0" 0 "$CODE"
check "a plan and no pass: the gate answered 0" 0 "$(val gate)"
check "a plan and no pass: no report is on record" 0 "$(val reports)"
check "a plan and no pass: enters at the builder" hq:implement "$(val entry)"

# Row 4: the same clean gate, with passes on record. The gate cannot part this
# row from the one above — the count is what does.
R4="$TMP/r-reviewed"
mk_repo "$R4" develop feat/one
plan_in "$R4" feat/one
reports_in "$R4" feat/one 2
run_state "" "$R4"
check "passes on record: exits 0" 0 "$CODE"
check "passes on record: the gate answered 0 here too" 0 "$(val gate)"
check "passes on record: every entry under reports/ is counted" 2 "$(val reports)"
check "passes on record: enters at the verifier" hq:review "$(val entry)"

# --- the observations that are emitted but not derived from ------------------

check "the branch is the one checked out" feat/one "$(val branch)"
# `main` is what the chain answers for any repository, so a fixture that agreed
# with the fallback could not tell a resolved base from an unresolved one.
check "the base is the one the resolution chain read" develop "$(val base)"
R_BASE="$TMP/r-otherbase"
mk_repo "$R_BASE" trunk-x feat/two
run_state "" "$R_BASE"
check "a differently named base resolves to that name" trunk-x "$(val base)"
check "and the branch follows the checkout" feat/two "$(val branch)"

run_state "" "$R3"
check "the plan is the one in this branch's run directory" \
  "$(task_dir "$R3" feat/one)/plan.md" "$(val plan)"

# --- the face itself ---------------------------------------------------------

check "the value face is one key per line, in a fixed order" "$KEY_ORDER" "$(emitted_keys)"
# The reason line is carried on a run that derived too, so a caller reading it
# never has to tell an absent key from an absent reason.
check "a run that derived says so in the reason line" none "$(val why)"

HELP=$("$SH" "$STATE" --help 2>&1)
HELP_CODE=$?
check "--help exits 0" 0 "$HELP_CODE"
HELP_MISSING=""
for k in $(emitted_keys); do
  case "$HELP" in *"$k"*) ;; *) HELP_MISSING="$HELP_MISSING $k" ;; esac
done
check "--help names every key the output carries" "" "$HELP_MISSING"

run_state "" "$R3" "$R3"
check "a second argument is a usage error" 2 "$CODE"
check "and it emits no value face to parse" "" "$OUT"

# --- the ways a run cannot be entered ----------------------------------------

# Not a repository. Nothing here derives, and the exit code says so rather than
# the caller having to read the values.
mkdir -p "$TMP/not-a-repo"
run_state "" "$TMP/not-a-repo"
check "outside a repository: exits 2" 2 "$CODE"
check "outside a repository: entry is unknown" unknown "$(val entry)"
check "outside a repository: the face is still whole" "$KEY_ORDER" "$(emitted_keys)"
check "outside a repository: it says why" yes \
  "$(printf '%s\n' "$ERR" | /usr/bin/grep -q 'not a git repository' && echo yes || echo no)"
# THIS IS THE STOP WHERE NO OTHER LINE CAN NAME THE CAUSE. Every value is
# `unknown` here, so a caller told to read the reason off the other lines has
# nothing to read; the reason is a value of its own, on stdout, for that.
check "outside a repository: no other value could have named the cause" \
  "unknown unknown unknown unknown unknown unknown" \
  "$(val branch) $(val base) $(val plan) $(val reports) $(val gate) $(val entry)"
check "outside a repository: the reason is on stdout, not only on stderr" yes \
  "$(printf '%s\n' "$(val why)" | /usr/bin/grep -q 'not a git repository' && echo yes || echo no)"

# A detached HEAD. The run directory would be filed under `HEAD/`, where the
# next detached run would read it as its own, so lib.sh refuses it.
R5="$TMP/r-detached"
mk_repo "$R5" develop feat/one
plan_in "$R5" feat/one
git -C "$R5" checkout -q --detach
run_state "" "$R5"
check "detached HEAD: exits 2" 2 "$CODE"
check "detached HEAD: entry is unknown" unknown "$(val entry)"
check "detached HEAD: the branch is unknown" unknown "$(val branch)"
check "detached HEAD: so is the plan, which is filed under the branch" unknown "$(val plan)"
# The stop is scoped to what actually failed. A blanket `unknown` would pass
# every check above it and tell the reader nothing about where the run broke.
check "detached HEAD: the base still resolved" develop "$(val base)"
# One stop takes the next with it here — no run directory means the gate cannot
# look either — and both reasons are in the one value. Keeping only the first
# would leave the reader with a cause and no account of the second `unknown`.
check "detached HEAD: the reason names the run directory" yes \
  "$(printf '%s\n' "$(val why)" | /usr/bin/grep -q "run directory could not be derived" && echo yes || echo no)"
check "detached HEAD: and the gate it took with it — no reason is dropped" yes \
  "$(printf '%s\n' "$(val why)" | /usr/bin/grep -q "triage-gate.sh could not look" && echo yes || echo no)"

# The gate could not look. HQ_PYTHON is the substitution the gate carries for
# exactly this: with no parser the stream cannot be read, and a gate that
# answered anyway would be guessing.
run_state "HQ_PYTHON=hq-no-such-python" "$R3"
check "the gate could not look: exits 2" 2 "$CODE"
check "the gate could not look: entry is unknown" unknown "$(val entry)"
check "the gate could not look: so is the gate's own value" unknown "$(val gate)"
check "the gate could not look: the plan still read" \
  "$(task_dir "$R3" feat/one)/plan.md" "$(val plan)"
check "the gate could not look: the report count still read" 0 "$(val reports)"

# --- bash 3.2 compatibility --------------------------------------------------
#
# macOS ships bash 3.2 as /bin/bash while the PATH bash is usually 5.x, so a
# 4.0+ construct passes here and breaks on a stock machine — silently, with a
# wrong value rather than a crash. The construct sweep that reads the source
# itself lives in sweep.test.sh; these two run it.

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

    # The success path, which is where a construct that only writes to stderr
    # would hide. The one line the gate writes for a branch with no findings
    # file is expected here and everything else is not; its presence is
    # asserted too, since an empty file is also what a probe that ran nothing
    # looks like.
    PROBE="$TMP/r-probe"
    mk_repo "$PROBE" develop feat/one
    plan_in "$PROBE" feat/one
    "$OLD_BASH" "$STATE" "$PROBE" >/dev/null 2>"$TMP/err-old"
    check "loop-state.sh writes nothing of its own to stderr under bash $OLD_VER" \
      0 "$(/usr/bin/grep -vc 'no findings file at' "$TMP/err-old" | tr -d ' ')"
    check "and the probe reached the line the gate was supposed to write" \
      1 "$(/usr/bin/grep -c 'no findings file at' "$TMP/err-old" | tr -d ' ')"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
