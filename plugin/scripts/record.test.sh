#!/usr/bin/env bash
# Tests for record.sh — the schema 3 telemetry recorder.
#
# Every validation is exercised in both directions: the rejecting case must
# exit 2 and write nothing, and the adjacent accepted shape must produce a
# well-formed row. A check that only ever sees the passing input cannot tell
# whether it is still checking anything (red-on-revert).
#
# Run: bash plugin/scripts/record.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REC="$HERE/record.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

# The interpreter used to run record.sh. Overridable so that the whole suite
# can be replayed under an older bash (see the compatibility check at the end).
SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

export HQ_SINK="$TMP/stream.jsonl"
export HQ_RUN_ID="test-run"

. "$HERE/testlib.sh"

reset_sink() { : > "$HQ_SINK"; }

rows() { wc -l < "$HQ_SINK" | tr -d ' '; }

last_row() { tail -n 1 "$HQ_SINK"; }

# Reads a dotted path out of the last row. Uses python3 so that the test does
# not re-implement the JSON parsing it is trying to verify.
field() { # <dotted path>
  last_row | python3 -c '
import json,sys
o=json.loads(sys.stdin.readline())
for p in sys.argv[1].split("."):
    o = o[int(p)] if isinstance(o,list) else o[p]
print(o)
' "$1" 2>/dev/null
}

# Runs record.sh, captures the exit code, and reports how many rows exist.
run_rec() { # <args...>
  "$SH" "$REC" "$@" >/dev/null 2>&1
  printf '%s' "$?"
}

# A rejection must both fail and leave the sink untouched. Checking only the
# exit code would pass even if the row had already been appended.
rejects() { # <description> <args...>
  local desc=$1; shift
  reset_sink
  local code
  code=$(run_rec "$@")
  if [ "$code" = 2 ] && [ "$(rows)" = 0 ]; then
    ok "rejects: $desc"
  else
    not_ok "rejects: $desc" "exit=$code rows=$(rows)"
  fi
}

tap_begin

# --- envelope --------------------------------------------------------------

reset_sink
check "module row is accepted" 0 "$(run_rec module name=implement duration_s=42)"
check "envelope: schema is 3" 3 "$(field schema)"
check "envelope: kind" module "$(field kind)"
check "envelope: run_id honours HQ_RUN_ID" test-run "$(field run_id)"
# The `repo` field is not asserted here: its value depends on the repository
# the suite happens to run in. The repo-identification section below drives it
# from fixture repositories with known remotes instead.
check "payload: name" implement "$(field payload.name)"
check "payload: duration_s value" 42 "$(field payload.duration_s)"
# Separate from the value check above: python prints 42 for both 42 and "42",
# so only this one can tell a number from a string.
check "payload: duration_s is a number, not a string" "int" "$(last_row | python3 -c 'import json,sys;print(type(json.loads(sys.stdin.readline())["payload"]["duration_s"]).__name__)')"

reset_sink
run_rec module name=a duration_s=1 >/dev/null
run_rec module name=b duration_s=2 >/dev/null
check "appends rather than truncates" 2 "$(rows)"

# --- module validation -----------------------------------------------------

reset_sink
check "module accepts route and profile" 0 "$(run_rec module name=implement duration_s=5 route=micro directives=1 profile=code)"
check "payload: route" micro "$(field payload.route)"
check "payload: profile" code "$(field payload.profile)"

reset_sink
check "the other route is accepted too" 0 "$(run_rec module name=implement duration_s=5 route=fresh)"
check "payload: route" fresh "$(field payload.route)"

# `duration_s` is the only raw JSON number, so it is the only place an
# accepted input can produce a row no reader can parse: every accepted value
# must round-trip through a JSON parser.
row_parses() { last_row | python3 -c 'import json,sys;json.loads(sys.stdin.readline());print("yes")' 2>/dev/null || printf 'no'; }

reset_sink
check "duration 0 is accepted" 0 "$(run_rec module name=x duration_s=0)"
check "duration 0 produces parseable JSON" yes "$(row_parses)"
reset_sink
check "large duration is accepted" 0 "$(run_rec module name=x duration_s=86400)"
check "large duration produces parseable JSON" yes "$(row_parses)"

rejects "leading-zero duration (would emit invalid JSON)" module name=x duration_s=08
rejects "zero-padded zero duration" module name=x duration_s=00

# A timestamp recorded as a duration: a caller that leaves the `<START>`
# placeholder in place subtracts nothing, and the row is well formed while
# saying the module ran for decades. Nothing downstream can tell that from a
# real reading.
rejects "a unix timestamp passed as a duration" module name=x duration_s=1786544033
reset_sink
check "the message says what the value looks like" yes \
  "$(bash "$REC" module name=x duration_s=1786544033 2>&1 >/dev/null \
     | /usr/bin/grep -q 'timestamp' && printf 'yes' || printf 'no')"

# The bound has to sit far above any real reading, or it becomes the defect it
# was added to catch. A day is already generous for one module.
reset_sink
check "a week-long duration is still accepted" 0 "$(run_rec module name=x duration_s=604800)"

rejects "unknown kind" bogus name=x
rejects "missing required key" module name=implement
rejects "unknown key (typo protection)" module name=implement duration_s=1 durration=2
rejects "duplicate key" module name=a name=b duration_s=1
rejects "non-integer duration" module name=implement duration_s=abc
rejects "negative duration" module name=implement duration_s=-1
rejects "unknown profile" module name=implement duration_s=1 profile=binary
rejects "unknown route" module name=implement duration_s=1 route=hotfix
# The spelling that would actually be written by hand: a second name for the
# same route is not a typo that shows up as a broken row — it is two groups
# where there was one.
rejects "a second spelling of an accepted route" module name=implement duration_s=1 route=micro-fix
rejects "bare argument instead of key=value" module name=implement 42

# --- directives: what a micro pass duration is divided by -------------------
#
# One micro pass applies every directive of a triage round and runs the
# floor once, so its duration is no longer the cost of one fix.
# `directives` is the denominator, and everything wrong with it produces a
# well-formed row: an absent key leaves the population meaning something else
# than it did, a zero is a division nobody guards, and a quoted count is a
# number no aggregation can divide by. None of that reaches a reader as an
# error, which is why each is refused here.

reset_sink
check "module accepts directives on a micro row" 0 \
  "$(run_rec module name=implement duration_s=120 route=micro directives=3 profile=prose)"
check "payload: directives value" 3 "$(field payload.directives)"
# Separate from the value check above, for the reason duration_s is: python
# prints 3 for both 3 and "3", so only this one can tell a number from a string.
check "payload: directives is a number, not a string" int \
  "$(last_row | python3 -c 'import json,sys;print(type(json.loads(sys.stdin.readline())["payload"]["directives"]).__name__)')"
check "the row carrying it still parses" yes "$(row_parses)"
check "and the route it is bound to is still on the row" micro "$(field payload.route)"

reset_sink
check "one directive is the ordinary case and is accepted" 0 \
  "$(run_rec module name=implement duration_s=40 route=micro directives=1)"
check "payload: directives value" 1 "$(field payload.directives)"

# The count is REQUIRED on the route that has one. A micro row without it is
# well formed and reads as one fix costing the whole pass — the misreading the
# key exists to stop — and it is also indistinguishable from a row written
# before the count existed, which is the only thing separating the two
# populations. An omitted key and an empty value are the same absence, so both
# are refused; only a check on each can tell that the guard covers both.
rejects "a micro row carrying no directive count at all" module name=implement duration_s=1 route=micro
rejects "a micro row whose directive count is empty" module name=implement duration_s=1 route=micro directives=
reset_sink
check "the refusal names the key the micro route requires" yes \
  "$("$SH" "$REC" module name=x duration_s=1 route=micro 2>&1 >/dev/null \
     | /usr/bin/grep -q 'directives=' && printf 'yes' || printf 'no')"

# The key is bound to the route that has a count. On `fresh` there are plan
# items rather than directives, and a row naming no route at all belongs to no
# population the ratio is taken over — both would be well formed with the
# number sitting on them, and a reader dividing by it would be describing
# something else entirely. What is refused there is the KEY, empty value
# included: a key silently dropped is a caller's mistake nobody ever sees.
rejects "directives with no route at all" module name=implement duration_s=1 directives=2
rejects "directives on the fresh route" module name=implement duration_s=1 route=fresh directives=2
rejects "an empty directives key on the fresh route" module name=implement duration_s=1 route=fresh directives=
reset_sink
check "the refusal names the route the key belongs to" yes \
  "$("$SH" "$REC" module name=x duration_s=1 route=fresh directives=2 2>&1 >/dev/null \
     | /usr/bin/grep -q 'route=micro' && printf 'yes' || printf 'no')"

# A count of zero is not "no directives recorded": a pass that applied none is
# not a micro pass at all, and the row would be a denominator of zero.
rejects "a directive count of zero" module name=implement duration_s=1 route=micro directives=0
rejects "a non-integer directive count" module name=implement duration_s=1 route=micro directives=two
rejects "a negative directive count" module name=implement duration_s=1 route=micro directives=-1
# A leading zero is the same defect duration_s refuses: `{"directives":03}` is
# a row no JSON reader can parse.
rejects "a zero-padded directive count" module name=implement duration_s=1 route=micro directives=03

# --- disposition -----------------------------------------------------------

reset_sink
check "disposition row is accepted" 0 \
  "$(run_rec disposition finding=FB1 verdict=fix_now source=review class=drift reason='contract mismatch')"
check "disposition: verdict" fix_now "$(field payload.verdict)"
check "disposition: source" review "$(field payload.source)"
check "disposition: class" drift "$(field payload.class)"
check "disposition: reason" "contract mismatch" "$(field payload.reason)"

rejects "unknown verdict" disposition finding=FB1 verdict=maybe source=review
rejects "unknown source" disposition finding=FB1 verdict=reject source=hunch
rejects "unknown class" disposition finding=FB1 verdict=reject source=review class=styling

# --- reason, required on one verdict ---------------------------------------
#
# `defer` is the verdict that leaves work behind: the finding stays true and
# no diff answers it, so this row is the whole record of what has to hold
# before it can be fixed.
#
# Both directions, and the conditional half is the one that would go
# unnoticed: requiring a reason on every verdict would also pass every check
# below that names `defer`.

reset_sink
check "defer carrying a reason is accepted" 0 \
  "$(run_rec disposition finding=F5 verdict=defer source=review class=drift \
      reason='three of the four copies are outside this branch fence')"
check "disposition: verdict" defer "$(field payload.verdict)"
check "disposition: the reason survives into the row" \
  "three of the four copies are outside this branch fence" "$(field payload.reason)"

rejects "defer with no reason at all" disposition finding=F5 verdict=defer source=review
# An empty value is the same absence as a missing key, and it is the spelling
# a caller substituting a variable produces.
rejects "defer with an empty reason" disposition finding=F5 verdict=defer source=review reason=
reset_sink
check "the refusal names the key and the verdict that needs it" yes \
  "$("$SH" "$REC" disposition finding=F5 verdict=defer source=review 2>&1 >/dev/null \
     | /usr/bin/grep -q 'reason.*defer\|defer.*reason' && printf 'yes' || printf 'no')"

# --- an identifier that is still a placeholder ------------------------------
#
# `finding` takes a free string — ids come from the verifier, and closing a
# deferral raised on another branch files the row under `<branch>#<id>` — so
# an unsubstituted `<ID>` is accepted by every other rule here and produces a
# row filed under a finding nobody can look up.

rejects "a finding id that is still a placeholder" \
  disposition finding='<ID>' verdict=fix_now source=review
rejects "a qualified id with both halves unsubstituted" \
  disposition finding='<BRANCH>#<ID>' verdict=fix_now source=review
reset_sink
check "the refusal says a placeholder is what is wrong" yes \
  "$("$SH" "$REC" disposition finding='<ID>' verdict=fix_now source=review 2>&1 >/dev/null \
     | /usr/bin/grep -q 'placeholder' && printf 'yes' || printf 'no')"

# The same placeholder one field over: a caller who substitutes the id and
# leaves `reason='<WHY>'` produces a deferral that satisfies the requirement
# above and records nothing about what has to hold.
rejects "a defer reason still carrying the template placeholder" \
  disposition finding=F5 verdict=defer source=review reason='<WHY>'
rejects "a placeholder reason on a verdict that does not require one" \
  disposition finding=F5 verdict=reject source=review reason='<WHY>'
reset_sink
check "the refusal names the reason rather than the id" yes \
  "$("$SH" "$REC" disposition finding=F5 verdict=defer source=review reason='<WHY>' 2>&1 >/dev/null \
     | /usr/bin/grep -q "reason=.*placeholder" && printf 'yes' || printf 'no')"

# A reason is free prose and one bracket is ordinary in it. Both together is
# what this refuses, and that boundary is the whole cost of the guard.
reset_sink
check "a reason carrying a single angle bracket is still accepted" 0 \
  "$(run_rec disposition finding=F5 verdict=defer source=review \
      reason='the fix waits on the schema bump, and only rows with n < 3 are affected')"
check "and it survives into the row intact" \
  "the fix waits on the schema bump, and only rows with n < 3 are affected" \
  "$(field payload.reason)"

# The forms that must keep working: the qualified one is the whole mechanism
# for closing a deferral.
reset_sink
check "a bare finding id is still accepted" 0 \
  "$(run_rec disposition finding=F1 verdict=fix_now source=review)"
reset_sink
check "a qualified finding id is still accepted" 0 \
  "$(run_rec disposition finding='refactor/tasks-out#F3' verdict=fix_now source=review)"
check "and it survives into the row intact" 'refactor/tasks-out#F3' \
  "$(field payload.finding)"

# The requirement is conditional: a guard without the verdict test would stop
# the two verdicts triage records most, and every check above would still
# pass.
reset_sink
check "fix_now without a reason is still accepted" 0 \
  "$(run_rec disposition finding=F1 verdict=fix_now source=review)"
reset_sink
check "reject without a reason is still accepted" 0 \
  "$(run_rec disposition finding=F2 verdict=reject source=external)"

# --- residual: the three states --------------------------------------------

reset_sink
check "residual reviewed with findings is accepted" 0 \
  "$(run_rec residual pr=246 reviewer=codex-review state=reviewed finding=logic:missed finding=drift:missed)"
check "residual: state" reviewed "$(field payload.state)"
check "residual: two findings collected" 2 \
  "$(last_row | python3 -c 'import json,sys;print(len(json.loads(sys.stdin.readline())["payload"]["findings"]))')"
check "residual: first finding class" logic "$(field payload.findings.0.class)"
check "residual: first finding category" missed "$(field payload.findings.0.category)"

reset_sink
check "residual reviewed with zero findings is accepted" 0 \
  "$(run_rec residual pr=247 reviewer=user state=reviewed)"
check "zero findings is an empty array, not a missing key" 0 \
  "$(last_row | python3 -c 'import json,sys;print(len(json.loads(sys.stdin.readline())["payload"]["findings"]))')"

reset_sink
check "residual not_reviewed is accepted" 0 \
  "$(run_rec residual pr=248 reviewer=none state=not_reviewed)"
check "not_reviewed is distinguishable from zero findings" not_reviewed "$(field payload.state)"

# --- residual: the finding categories ---------------------------------------
#
# The category is what the constitution's first article is measured on, so a
# value silently dropped from the set would take a whole population of rows
# with it. Each accepted value is driven on its own rather than asserted as a
# group: a loop over the set record.sh holds would agree with itself whatever
# that set became.

CATS="prevented triaged_away missed out_of_scope false_positive"

for cat in $CATS; do
  reset_sink
  check "residual accepts category $cat" 0 \
    "$(run_rec residual pr=276 reviewer=codex-review state=reviewed "finding=logic:$cat")"
  check "category $cat survives into the row" "$cat" "$(field payload.findings.0.category)"
done

# The list above is a second copy of the set, and a value added to record.sh
# without a case here would leave the new value untested while every check
# stayed green. This is the machine that compares the two.
check "the categories driven here are exactly the set record.sh accepts" "$CATS" \
  "$(/usr/bin/grep -m1 '^CATEGORIES=' "$REC" | sed 's/^CATEGORIES="//; s/".*//')"

rejects "unknown residual state" residual pr=1 reviewer=x state=skipped
rejects "not_reviewed carrying findings" residual pr=1 reviewer=x state=not_reviewed finding=logic:missed
rejects "finding without a category" residual pr=1 reviewer=x state=reviewed finding=logic
rejects "unknown finding class" residual pr=1 reviewer=x state=reviewed finding=perf:missed
rejects "unknown finding category" residual pr=1 reviewer=x state=reviewed finding=logic:ignored

# --- gate: what a refusal leaves behind -------------------------------------
#
# A gate's whole effect is that something did not happen, so afterwards the
# tree looks the same whether it fired once or never. These rows are the only
# evidence, which makes an unknown value here worse than a missing row: a typo
# that lands in the stream reads as a gate nobody has heard of, and one that
# is rejected at least fails where the caller can see it.

reset_sink
check "gate block is accepted" 0 "$(run_rec gate name=fence outcome=block)"
check "gate: the gate that fired" fence "$(field payload.name)"
check "gate: what it did" block "$(field payload.outcome)"
check "gate: the kind is its own" gate "$(field kind)"

reset_sink
check "gate unchecked is accepted" 0 "$(run_rec gate name=plan-shape outcome=unchecked)"
check "unchecked is distinguishable from a refusal" unchecked "$(field payload.outcome)"

check "an unknown gate is refused" 2 "$(run_rec gate name=nope outcome=block)"
check "an unknown outcome is refused" 2 "$(run_rec gate name=fence outcome=maybe)"
check "gate requires the gate that fired" 2 "$(run_rec gate outcome=block)"
check "gate requires what it did" 2 "$(run_rec gate name=fence)"
check "gate takes no key from another kind" 2 \
  "$(run_rec gate name=fence outcome=block duration_s=1)"

# --- repo identification ---------------------------------------------------
#
# The `repo` field is what scopes a population, and a wrong slug still
# produces a well-formed row nothing downstream would notice. The function is
# not callable on its own, so each case is driven through the command from
# inside a throwaway repository.

mk_repo() { # <dir> [remote url]
  mkdir -p "$1"
  git -C "$1" init -q 2>/dev/null
  [ $# -ge 2 ] && git -C "$1" remote add origin "$2"
  return 0
}

repo_field_in() { # <dir>
  local sink="$TMP/slug.jsonl"
  : > "$sink"
  ( cd "$1" && HQ_SINK="$sink" "$SH" "$REC" module name=x duration_s=1 >/dev/null 2>&1 )
  python3 -c 'import json,sys;print(json.loads(open(sys.argv[1]).readline())["repo"])' "$sink" 2>/dev/null
}

mk_repo "$TMP/r-ssh"   "git@github.com:acme/widget.git"
mk_repo "$TMP/r-https" "https://github.com/acme/widget.git"
mk_repo "$TMP/r-bare"  "https://github.com/acme/widget"
mk_repo "$TMP/r-slash" "https://github.com/acme/widget/"
mk_repo "$TMP/r-none"
mkdir -p "$TMP/not-a-repo"

check "repo from ssh remote"            acme/widget "$(repo_field_in "$TMP/r-ssh")"
check "repo from https remote"          acme/widget "$(repo_field_in "$TMP/r-https")"
check "repo from remote without .git"   acme/widget "$(repo_field_in "$TMP/r-bare")"
check "repo from remote with trailing /" acme/widget "$(repo_field_in "$TMP/r-slash")"
check "repo falls back to the directory name when there is no remote" \
  r-none "$(repo_field_in "$TMP/r-none")"
check "repo falls back to the directory name outside a repository" \
  not-a-repo "$(repo_field_in "$TMP/not-a-repo")"

# --- help text -------------------------------------------------------------
#
# --help is the only place a user learns the accepted values, and a help
# sliced out of a header comment's line range breaks silently when the header
# grows. Checking that every kind and every accepted value appears keeps it
# complete and in step with the enums.

HELP=$("$SH" "$REC" --help 2>&1)
HELP_MISSING=""
for token in module disposition residual gate; do
  case "$HELP" in *"$token"*) ;; *) HELP_MISSING="$HELP_MISSING $token" ;; esac
done
for var in CLASSES PROFILES ROUTES VERDICTS SOURCES STATES CATEGORIES GATES OUTCOMES; do
  for token in $(/usr/bin/grep -m1 "^$var=" "$REC" | sed 's/^[A-Z]*="//; s/".*//'); do
    case "$HELP" in *"$token"*) ;; *) HELP_MISSING="$HELP_MISSING $token" ;; esac
  done
done
check "--help lists every kind and every accepted value" "" "$HELP_MISSING"

# The optional keys are not enums, so the loop above cannot reach them. This
# one is the only place a caller learns the key exists and which route takes
# it, and a recorder that accepts a key its help never names is a key nobody
# writes.
check "--help names the directives key and the route it belongs to" yes \
  "$(printf '%s' "$HELP" | /usr/bin/grep -q 'directives' \
     && printf '%s' "$HELP" | /usr/bin/grep -q 'route=micro' \
     && printf 'yes' || printf 'no')"

# The vocabularies this script enforces are also written in the verifier's
# definition; that agreement spans two files, so it is checked where both are
# in view (sweep.test.sh).

# --- JSON safety -----------------------------------------------------------

reset_sink
run_rec disposition finding='FB"1\' verdict=reject source=external reason='line one
line two	tabbed' >/dev/null
check "row with quote, backslash, newline and tab stays one line" 1 "$(rows)"
check "escaped value round-trips" 'FB"1\' "$(field payload.finding)"
check "newline round-trips" "line one
line two	tabbed" "$(field payload.reason)"

# --- sink handling ---------------------------------------------------------

HQ_SINK="$TMP/nested/deep/stream.jsonl" "$SH" "$REC" module name=implement duration_s=1 >/dev/null 2>&1
check "creates the sink directory when missing" 1 "$(wc -l < "$TMP/nested/deep/stream.jsonl" | tr -d ' ')"

# The header promises exit 1 when the append fails. A recorder that returned
# 0 having written nothing is the worst shape available here: the caller moves
# on, and the row that was supposed to make the run measurable is simply not
# there.

HQ_SINK=/dev/null/impossible.jsonl "$SH" "$REC" module name=x duration_s=1 >/dev/null 2>&1
check "a sink directory that cannot be created exits 1" 1 "$?"

mkdir -p "$TMP/readonly"
chmod 500 "$TMP/readonly"
HQ_SINK="$TMP/readonly/stream.jsonl" "$SH" "$REC" module name=x duration_s=1 >/dev/null 2>&1
check "a sink that cannot be written exits 1" 1 "$?"
chmod 700 "$TMP/readonly"

# --- the sink follows HQ_HOME ----------------------------------------------
#
# HQ_HOME is the one knob for where hq keeps everything of its own: if the
# stream did not follow, moving the knob would split the telemetry in two
# without saying so.
#
# HQ_SINK is exported for the whole file, so these run with it unset.

HOME_A="$TMP/home-a"
( unset HQ_SINK; HQ_HOME="$HOME_A" "$SH" "$REC" module name=implement duration_s=1 ) >/dev/null 2>&1
check "the sink defaults to <HQ_HOME>/stream.jsonl" 1 \
  "$(wc -l < "$HOME_A/stream.jsonl" 2>/dev/null | tr -d ' ')"

# HQ_SINK names a file outright, so it has to win — that is what keeps the rest
# of this suite off the real stream.
( unset HQ_SINK; HQ_HOME="$TMP/home-ignored" HQ_SINK="$TMP/explicit.jsonl" \
    "$SH" "$REC" module name=implement duration_s=1 ) >/dev/null 2>&1
check "HQ_SINK still wins over HQ_HOME" 1 \
  "$(wc -l < "$TMP/explicit.jsonl" 2>/dev/null | tr -d ' ')"

# A RELATIVE HOME IS REFUSED rather than followed: followed, it writes the
# stream relative to whatever directory the caller was in. HQ_SINK is unset
# for these — with it set the home is never consulted and the check would
# pass with the guard removed.
( unset HQ_SINK; cd "$TMP" && HQ_HOME=relative/home "$SH" "$REC" module name=x duration_s=1 ) >/dev/null 2>&1
check "a relative HQ_HOME is refused" 2 "$?"
check "and nothing was written where it pointed" no \
  "$([ -e "$TMP/relative/home/stream.jsonl" ] && printf 'yes' || printf 'no')"
check "the message names the variable that is wrong" yes \
  "$( ( unset HQ_SINK; cd "$TMP" && HQ_HOME=relative/home "$SH" "$REC" module name=x duration_s=1 ) 2>&1 >/dev/null \
     | /usr/bin/grep -q 'HQ_HOME' && printf 'yes' || printf 'no')"
check "and HQ_HOME was not written to as well" no \
  "$([ -e "$TMP/home-ignored" ] && printf 'yes' || printf 'no')"

# AN ENVIRONMENT WITH NO HOME AT ALL is refused by name rather than left to
# `set -u`, which aborts with `record.sh: line NN: HOME: unbound variable` and
# appends nothing.
#
# These turn on the message prefix rather than the exit code: `record.sh:` is
# this script speaking, `record.sh: line NN:` is bash speaking.
( unset HQ_SINK HQ_HOME HOME; cd "$TMP" && "$SH" "$REC" module name=x duration_s=1 ) >/dev/null 2>&1
check "no sink, no home and no HOME is refused" 2 "$?"
check "and the refusal comes from this script rather than from set -u" yes \
  "$( ( unset HQ_SINK HQ_HOME HOME; cd "$TMP" && "$SH" "$REC" module name=x duration_s=1 ) 2>&1 >/dev/null \
     | /usr/bin/grep -q '^record\.sh: [a-z]' && printf 'yes' || printf 'no')"

# HOME is read only where it is needed, and both of the other two ways to name
# a destination have to keep working without it. A guard placed ahead of the
# branch would stop a recorder that has somewhere to write.
( unset HQ_HOME HOME; HQ_SINK="$TMP/no-home-sink.jsonl" "$SH" "$REC" module name=x duration_s=1 ) >/dev/null 2>&1
check "HQ_SINK alone records with no HOME in the environment" 1 \
  "$(wc -l < "$TMP/no-home-sink.jsonl" 2>/dev/null | tr -d ' ')"
( unset HQ_SINK HOME; HQ_HOME="$TMP/no-home-home" "$SH" "$REC" module name=x duration_s=1 ) >/dev/null 2>&1
check "an absolute HQ_HOME alone records with no HOME in the environment" 1 \
  "$(wc -l < "$TMP/no-home-home/stream.jsonl" 2>/dev/null | tr -d ' ')"

# The expansion `${HQ_HOME:-$HOME/.hq}` is written out in this script and
# again in lib.sh; this check is what keeps the copy honest — an edit to one
# of them turns red here rather than quietly filing a run's working files
# beside a stream that is somewhere else.
TASK_DIR=$(HQ_HOME="$HOME_A" "$SH" "$HERE/lib.sh" hq_task_dir 2>/dev/null)
check "the task directory was derived at all" yes \
  "$([ -n "$TASK_DIR" ] && printf 'yes' || printf 'no')"
check "the recorder's home and lib.sh's home are the same directory" \
  "$HOME_A" "${TASK_DIR%%/repos/*}"

# --- the cycle identifier ---------------------------------------------------
#
# `run_id` groups the rows of one cycle, and every measure this project keeps
# is a sum over such a group.
#
# THESE RUN WITH HQ_RUN_ID UNSET, in a child process: this file exports it at
# the top, and a check for the DEFAULT written under that export would be
# testing the export. The pinned case below is what proves the unset took.
#
# The home is pointed at a fixture directory because lib.sh writes the
# identifier file under it; without this the suite would leave one in the
# developer's real ~/.hq.

RUN_REPO="$TMP/run-repo"
mkdir -p "$RUN_REPO"
git -C "$RUN_REPO" init -q
git -C "$RUN_REPO" config user.email t@example.com
git -C "$RUN_REPO" config user.name t
echo seed >"$RUN_REPO/seed.txt"
git -C "$RUN_REPO" add -A
git -C "$RUN_REPO" commit -q -m seed
git -C "$RUN_REPO" checkout -q -b feat/cycle

RUN_HOME="$TMP/run-home"

# One recording from the fixture repository, with nothing in the environment
# naming a cycle.
rec_cycle() { # <args...>
  ( unset HQ_RUN_ID; cd "$RUN_REPO" && HQ_HOME="$RUN_HOME" "$SH" "$REC" "$@" ) \
    >/dev/null 2>&1
}

RUN_TASK=$(HQ_HOME="$RUN_HOME" "$SH" "$HERE/lib.sh" hq_task_dir "$RUN_REPO" 2>/dev/null)
check "the fixture's run directory was derived at all" yes \
  "$([ -n "$RUN_TASK" ] && printf 'yes' || printf 'no')"

reset_sink
rec_cycle module name=a duration_s=1
RUN_FIRST=$(field run_id)
check "a row records a cycle identifier with no HQ_RUN_ID set" yes \
  "$([ -n "$RUN_FIRST" ] && printf 'yes' || printf 'no')"
check "which is the one in the run's own directory, not one composed here" \
  "$RUN_FIRST" "$(cat "$RUN_TASK/run_id" 2>/dev/null)"

rec_cycle module name=b duration_s=2
check "a second call records the same cycle" "$RUN_FIRST" "$(field run_id)"
check "and both rows are there" 2 "$(rows)"

# The deterministic form of the same property: a value no composition here
# could produce has to come back on the row — two calls in one second would
# agree even when composed per call, so this is the check that is red the
# moment the file stops being read.
printf 'pinned-cycle\n' >"$RUN_TASK/run_id"
reset_sink
rec_cycle module name=c duration_s=1
check "the identifier on the row is the one the file holds" pinned-cycle "$(field run_id)"

# HQ_RUN_ID still wins outright. It is how a caller files a row under a cycle
# this shell knows nothing about, and it is what the rest of this suite uses.
reset_sink
( cd "$RUN_REPO" && HQ_HOME="$RUN_HOME" HQ_RUN_ID=from-the-environment "$SH" "$REC" \
    module name=d duration_s=1 ) >/dev/null 2>&1
check "HQ_RUN_ID beats the file" from-the-environment "$(field run_id)"

# Where there is no cycle to name, a row is still written. The recorder records
# outside a repository too, and a missing identifier would be a row no reader
# can place.
SOLO="$TMP/solo"
mkdir -p "$SOLO"
cp "$REC" "$SOLO/record.sh"
reset_sink
( unset HQ_RUN_ID; cd "$RUN_REPO" && HQ_HOME="$RUN_HOME" "$SH" "$SOLO/record.sh" \
    module name=e duration_s=1 ) >/dev/null 2>&1
check "a copy with no lib.sh beside it still writes a row" 1 "$(rows)"
check "and the row still carries an identifier" yes \
  "$([ -n "$(field run_id)" ] && printf 'yes' || printf 'no')"
check "which is not the cycle's — there was no way to ask for it" no \
  "$([ "$(field run_id)" = pinned-cycle ] && printf 'yes' || printf 'no')"

reset_sink
( unset HQ_RUN_ID; cd "$TMP" && HQ_HOME="$RUN_HOME" "$SH" "$REC" module name=f duration_s=1 ) \
  >/dev/null 2>&1
check "outside a repository a row is still written" 1 "$(rows)"
check "and it still carries an identifier" yes \
  "$([ -n "$(field run_id)" ] && printf 'yes' || printf 'no')"

# --- bash 3.2 compatibility ------------------------------------------------
#
# On bash 3.2 an unsupported construct in a *script file* does not abort the
# script — it writes to stderr and carries on with a wrong value, so the
# failure mode is silent corruption, not a crash. Three checks, because no
# single one is sufficient:
#
#   1. Replay — the whole suite runs again under the old bash.
#      Blind spot: code paths the tests do not reach.
#   2. Clean stderr — a successful run under the old bash must print nothing.
#      Blind spot: paths not exercised here, and constructs that are silent.
#   3. Sweep — grep every script for known 4.0+ constructs.
#      Blind spot: constructs missing from the list.
#
# The first two live below; the sweep reads every script at once and lives in
# sweep.test.sh.

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

    : > "$HQ_SINK"
    HQ_SINK="$TMP/stderr-probe.jsonl" "$OLD_BASH" "$REC" module name=implement duration_s=1 \
      >/dev/null 2>"$TMP/err1"
    # Carries the reason `defer` requires. These three probes are the SUCCESS
    # path — the question is whether an old bash prints anything while doing
    # the work, so an invocation the script rejects would answer a different
    # question and this check would read the refusal as a stray diagnostic.
    HQ_SINK="$TMP/stderr-probe.jsonl" "$OLD_BASH" "$REC" disposition finding=F verdict=defer source=review reason='the fix needs the schema bump first' \
      >/dev/null 2>>"$TMP/err1"
    HQ_SINK="$TMP/stderr-probe.jsonl" "$OLD_BASH" "$REC" residual pr=1 reviewer=r state=reviewed finding=logic:missed \
      >/dev/null 2>>"$TMP/err1"
    check "record.sh writes nothing to stderr under bash $OLD_VER" "" "$(cat "$TMP/err1")"
  else
    # Not a silent pass: the guarantee is unavailable here and must say so.
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
