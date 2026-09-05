#!/usr/bin/env bash
# hq loop entry state — what a cycle is entered on, and the module that
# derivation names.
#
# Usage: `loop-state.sh [<repo-root>]`, or `loop-state.sh --help`.
#
# Output is one `key=value` per line, in this order, and every one of them on
# every run:
#
#   branch=<name>            the branch the run is on
#   base=<name>              what this branch is diffed against
#   plan=<path>|none         this branch's plan, or that there is none
#   reports=<count>          review passes already written under `reports/`
#   gate=0|1                 what `triage-gate.sh check` answered
#   entry=hq:<module>        the module this run enters at
#   why=<reason>|none        what could not be read, or that nothing failed
#
# THE TABLE IS HERE AND NOWHERE ELSE. Three of the observations decide the
# entry, and the derivation is a pure function of them:
#
#   the plan is `none`                          -> hq:plan
#   a plan, and the gate exited 1               -> hq:triage
#   a plan, gate 0, no review passes            -> hq:implement
#   a plan, gate 0, one or more review passes   -> hq:review
#
# THE PASS COUNT IS WHAT PARTS THE LAST TWO ROWS. The gate exits 0 both for a
# branch with no findings at all and for one whose findings are every one
# disposed of, and it does not part them. The count does: the verifier writes
# a report under `reports/` on every pass, whether or not it found anything,
# so no report means it has never run and the work is still the builder's.
#
# THE LAST ROW IS THE ONE TO BE CAREFUL ABOUT. A clean gate with passes on
# record says every finding is disposed of. It does not say the `fix_now` ones
# were built — nothing on this machine records that — so the entry is the
# verifier rather than the module after it.
#
# `base` is not read by the table. It is emitted because a person reading a
# stopped run needs it, and because deriving it here is what lets the caller
# ask one question instead of four.
#
# NOTHING HERE ASKS A FORGE ANYTHING. Every value is read off this machine: a
# network answer would make the entry of a run depend on something that can be
# down.
#
# WHAT CANNOT BE DERIVED IS NOT GUESSED. A value that could not be read is
# emitted as `unknown`, `entry` is `unknown` with it, and the exit code is 2 —
# a run entered on a guess is worse than a run that did not start.
#
# THE REASON IS A VALUE, NOT JUST A MESSAGE. `why=` carries it on stdout,
# beside the values it explains, because the `unknown`s alone do not say what
# failed — outside a repository every one of them is `unknown` and none of
# them names the cause. The same text goes to stderr as it happens, and
# whether a caller ever sees that stderr is not this script's to know.
#
# WHAT CAN STOP A RUN THIS WAY IS NOT A CLOSED LIST. It is whatever one of the
# reads below refuses, and `why=` is what names which one it was: this is not
# a repository, `lib.sh` is not beside this script, no branch is checked out
# (`hq_task_dir` refuses a detached HEAD, because answering would file the run
# under `HEAD/`), the gate could not look. `hq_resolve_base` answers for any
# repository — its last step is `main` — so the base is not a stop of its own.
#
# WHEN MORE THAN ONE READ FAILED, EVERY REASON IS IN THE VALUE, joined by
# `; ` in the order they happened. One stop causes the next often enough that
# reporting only the first would send the reader after a symptom: a detached
# HEAD takes the run directory and the gate with it.
#
# A branch that is literally named `unknown` prints `branch=unknown` while
# every other value derives and the exit code is 0. The exit code and `why=none`
# are the machine-readable answers; the word is for the reader.
#
# WHAT THE GATE SAID IS NOT THROWN AWAY. Its stdout — the findings nothing has
# disposed of, and the rows it could not see behind — would collide with the
# `key=value` face, so it is forwarded to stderr verbatim rather than dropped;
# its own stderr is never redirected at all.
#
# Exit codes: 0 derived, 2 usage error or a value that could not be derived.
#
# Portability: bash 3.2 (stock macOS /bin/bash) and BSD userland. No jq.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || HERE=""

usage() {
  cat <<'EOF'
Usage:
  loop-state.sh [<repo-root>]

Prints one key=value per line, always every one and always in this order:

  branch    the branch the run is on
  base      what this branch is diffed against
  plan      the path of this branch's plan, or `none`
  reports   how many review passes are already on record
  gate      what `triage-gate.sh check` answered: 0 or 1
  entry     the module this run enters at
  why       what could not be read, or `none` when nothing failed

A value that could not be derived is `unknown`, `entry` is `unknown` with it,
`why` says what could not be read, and the exit code is 2. Otherwise the exit
code is 0.
EOF
}

BRANCH=unknown
BASE=unknown
PLAN=unknown
REPORTS=unknown
GATE=unknown
ENTRY=unknown
WHY=none
FAILED=0

note() { # <message> — says why a value is missing, without inventing one
  printf 'loop-state.sh: %s\n' "$1" >&2
  if [ "$FAILED" -eq 0 ]; then WHY=$1; else WHY="$WHY; $1"; fi
  FAILED=1
}

# Emitted from one place, so that every exit carries the whole face: a caller
# reading `entry=` must never have to wonder whether the line was printed.
emit() {
  printf 'branch=%s\nbase=%s\nplan=%s\nreports=%s\ngate=%s\nentry=%s\nwhy=%s\n' \
    "$BRANCH" "$BASE" "$PLAN" "$REPORTS" "$GATE" "$ENTRY" "$WHY"
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
esac
[ $# -le 1 ] || { usage >&2; exit 2; }

# --- the repository ---------------------------------------------------------

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
if [ -z "$ROOT" ] || ! git -C "$ROOT" rev-parse --git-common-dir >/dev/null 2>&1; then
  note "not a git repository${ROOT:+: $ROOT}, so there is no run to derive"
  emit
  exit 2
fi

[ -n "$HERE" ] && [ -f "$HERE/lib.sh" ] || {
  note "lib.sh is not beside this script; there is no way to find this run's files"
  emit
  exit 2
}

# Display only. `hq_task_dir` below is what decides whether there is a branch
# to work on — asking twice here would report a detached HEAD in two
# vocabularies and send the reader looking for two defects.
b=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || b=""
case "$b" in
  ''|HEAD) ;;
  *) BRANCH=$b ;;
esac

# --- base -------------------------------------------------------------------

if v=$(bash "$HERE/lib.sh" hq_resolve_base "$ROOT"); then
  BASE=$v
else
  note "the base branch could not be resolved, so every module below it would diff against nothing"
fi

# --- the run's own files ----------------------------------------------------

if DIR=$(bash "$HERE/lib.sh" hq_task_dir "$ROOT"); then
  if [ -f "$DIR/plan.md" ]; then PLAN="$DIR/plan.md"; else PLAN=none; fi
  n=0
  for f in "$DIR/reports"/*; do
    [ -e "$f" ] && n=$((n + 1))
  done
  REPORTS=$n
else
  note "this branch's run directory could not be derived, so neither the plan nor the review passes can be read"
fi

# --- the triage gate --------------------------------------------------------
#
# Run whatever the plan line said. The first row of the table does not consult
# it, but a gate that could not look is a gate whose answer is missing for the
# other three rows, and a run that entered at `hq:plan` goes on to need it.

out=$(bash "$HERE/triage-gate.sh" check "$ROOT")
code=$?
[ -n "$out" ] && printf '%s\n' "$out" >&2
case "$code" in
  0|1) GATE=$code ;;
  *) note "triage-gate.sh could not look (exit $code), so whether this branch's findings are disposed of is unknown" ;;
esac

# --- the derivation ---------------------------------------------------------

if [ "$FAILED" -eq 0 ]; then
  if [ "$PLAN" = none ]; then
    ENTRY=hq:plan
  elif [ "$GATE" = 1 ]; then
    ENTRY=hq:triage
  elif [ "$REPORTS" -eq 0 ]; then
    ENTRY=hq:implement
  else
    ENTRY=hq:review
  fi
fi

emit
[ "$FAILED" -eq 0 ] || exit 2
exit 0
