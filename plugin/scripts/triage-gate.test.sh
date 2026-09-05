#!/usr/bin/env bash
# Tests for triage-gate.sh — the join between a branch's findings and the
# dispositions recorded for them.
#
# THE ROWS ARE WRITTEN BY record.sh, not by hand, wherever the case allows
# it: a fixture composed here would agree with this reader's idea of the
# format rather than with the writer's.
#
# Both directions everywhere: dropping a filter makes a gate MORE talkative,
# which no single-sided check would notice.
#
# Run: bash plugin/scripts/triage-gate.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATE="$HERE/triage-gate.sh"
REC="$HERE/record.sh"
LIB="$HERE/lib.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

# The interpreter under test, overridable so the whole suite can be replayed
# under an older bash (see the compatibility section at the end).
SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# One home for the fixtures, so nothing here can reach the developer's real
# ~/.hq. HQ_SINK is deliberately NOT set — the derivation of the sink from the
# home is one of the things under test — and is cleared in case the
# environment carries one.
unset HQ_SINK
export HQ_HOME="$TMP/home"

. "$HERE/testlib.sh"

# --- fixtures ---------------------------------------------------------------

# A repository whose directory name is deliberately NOT its remote's name: a
# derivation that fell back to the directory name would filter out every row
# the recorder wrote, and a fixture where the two spellings coincide could
# not tell.
mk_repo() { # <dir> [<remote url>]
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name "Test"
  git -C "$1" config commit.gpgsign false
  [ $# -ge 2 ] && git -C "$1" remote add origin "$2"
  git -C "$1" commit -q --allow-empty -m init
  git -C "$1" checkout -q -b feat/one
}

# A row, written by the script that writes them for real, from inside the
# repository and on the branch given.
rec_in() { # <dir> <branch> <args...>
  local dir=$1 branch=$2; shift 2
  git -C "$dir" checkout -q "$branch" 2>/dev/null || git -C "$dir" checkout -q -b "$branch"
  ( cd "$dir" && "$SH" "$REC" "$@" ) >/dev/null 2>&1
}

on_branch() { # <dir> <branch>
  git -C "$1" checkout -q "$2" 2>/dev/null || git -C "$1" checkout -q -b "$2"
}

task_dir() { # <dir> <branch>
  "$SH" "$LIB" hq_task_dir "$1" "$2"
}

# A findings file where the verifier would have written one. The shape is
# findings-gate.sh's contract; what matters here is the `id`.
findings_in() { # <dir> <branch> <id>...
  local dir=$1 branch=$2 d; shift 2
  d=$(task_dir "$dir" "$branch") || return 1
  mkdir -p "$d"
  : >"$d/findings.jsonl"
  append_findings_in "$dir" "$branch" "$@"
}

# What a LATER review pass does to that file: it adds rows under new numbers
# rather than replacing what is there. A fixture that rewrote the file would
# be testing a flow nothing produces.
append_findings_in() { # <dir> <branch> <id>...
  local dir=$1 branch=$2 d id; shift 2
  d=$(task_dir "$dir" "$branch") || return 1
  mkdir -p "$d"
  for id in "$@"; do
    printf '{"id":"%s","weight":"medium","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}\n' \
      "$id" >>"$d/findings.jsonl"
  done
}

gate_out() { # <mode> <dir> — stdout only
  "$SH" "$GATE" "$1" "$2" 2>/dev/null
}

gate_code() { # <args...>
  "$SH" "$GATE" "$@" >/dev/null 2>&1
  printf '%s' "$?"
}

lines() { # <text> — how many non-empty lines it holds
  [ -n "$1" ] || { printf '0'; return; }
  printf '%s\n' "$1" | /usr/bin/grep -c . | tr -d ' '
}

SINK="$HQ_HOME/stream.jsonl"

A="$TMP/wt-a"   # remote acme/widget — directory name differs on purpose
B="$TMP/wt-b"   # remote acme/gadget
C="$TMP/wt-c"   # no remote at all: the slug falls back to the directory name

mk_repo "$A" "git@example.com:acme/widget.git"
mk_repo "$B" "https://example.com/acme/gadget.git"
mk_repo "$C"

tap_begin

# --- open: the closing rule -------------------------------------------------

rec_in "$A" feat/one disposition finding=F1 verdict=defer source=review \
  reason='the escaper lives in three files outside this fence'
OPEN=$(gate_out open "$A")
check "a deferral with nothing after it is listed" 1 "$(lines "$OPEN")"
check "and it is filed under branch#id" "feat/one#F1" \
  "$(printf '%s' "$OPEN" | cut -f1)"
check "the reason is carried through to the reader" yes \
  "$(printf '%s' "$OPEN" | /usr/bin/grep -q 'outside this fence' && printf 'yes' || printf 'no')"
check "and so is the timestamp" yes \
  "$(printf '%s' "$OPEN" | cut -f2 | /usr/bin/grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' && printf 'yes' || printf 'no')"

# The branch that finally fixes a deferral is not the branch that raised it,
# and its own findings are numbered from F1 like everybody else's.
rec_in "$A" fix/later disposition finding='feat/one#F1' verdict=fix_now source=review
check "a later fix_now under the qualified id closes it" 0 \
  "$(lines "$(gate_out open "$A")")"

# A bare identifier closes a deferral raised on the same branch — the identity
# is composed from the envelope, so the two rows land on one id.
rec_in "$A" feat/two disposition finding=F9 verdict=defer source=external \
  reason='needs the schema bump first'
check "a deferral on another branch is listed" 1 "$(lines "$(gate_out open "$A")")"
rec_in "$A" feat/two disposition finding=F9 verdict=fix_now source=external
check "a bare fix_now on the same branch closes it" 0 \
  "$(lines "$(gate_out open "$A")")"

# ORDER IS THE RULE. A fix_now that came first closed something else; the
# deferral after it is open. Written by hand rather than through the recorder
# because the recorder timestamps in whole seconds and this pair would share
# one — which is exactly why the rule reads file order and not `t`.
cat >>"$SINK" <<'EOF'
{"schema":3,"ts":"2026-08-15T10:00:00Z","t":1786867200,"run_id":"r","repo":"acme/widget","branch":"feat/three","worktree":"/w","kind":"disposition","payload":{"finding":"F4","verdict":"fix_now","source":"review"}}
{"schema":3,"ts":"2026-08-15T10:00:00Z","t":1786867200,"run_id":"r","repo":"acme/widget","branch":"feat/three","worktree":"/w","kind":"disposition","payload":{"finding":"F4","verdict":"defer","source":"review","reason":"raised again after the first fix"}}
EOF
OPEN=$(gate_out open "$A")
check "a fix_now BEFORE the deferral does not close it" 1 "$(lines "$OPEN")"
check "and the open one is the later row" "feat/three#F4" \
  "$(printf '%s' "$OPEN" | cut -f1)"

# A reject is not a close. It is a different claim about a different finding
# state, and reading it as one would empty the list of things still owed.
cat >>"$SINK" <<'EOF'
{"schema":3,"ts":"2026-08-15T10:00:01Z","t":1786867201,"run_id":"r","repo":"acme/widget","branch":"feat/three","worktree":"/w","kind":"disposition","payload":{"finding":"F4","verdict":"reject","source":"review"}}
EOF
check "a later reject does not close a deferral" 1 "$(lines "$(gate_out open "$A")")"

# --- open: what scopes the answer -------------------------------------------

rec_in "$B" feat/one disposition finding=F1 verdict=defer source=review \
  reason='another repository entirely'
check "another repository's deferral is not listed here" 1 \
  "$(lines "$(gate_out open "$A")")"
check "and it is listed in its own repository" 1 "$(lines "$(gate_out open "$B")")"
check "with its own reason" yes \
  "$(gate_out open "$B" | /usr/bin/grep -q 'another repository entirely' && printf 'yes' || printf 'no')"

# The fallback half of the slug derivation: no remote, so the recorder files
# the row under the directory name, and a reader deriving differently would
# filter it out.
rec_in "$C" feat/one disposition finding=F1 verdict=defer source=review \
  reason='a checkout with no remote'
check "a repository with no remote is scoped by its directory name" 1 \
  "$(lines "$(gate_out open "$C")")"
check "and that row does not leak into the other fixtures" 1 \
  "$(lines "$(gate_out open "$A")")"

# --- open: the shape of the output ------------------------------------------
#
# One deferral is one line: a reason may carry newlines, and printed as they
# stand a single deferral would read as several.
rec_in "$A" feat/four disposition finding=F7 verdict=defer source=review \
  reason='first line
second line	with a tab'
OPEN=$(gate_out open "$A")
check "a reason spanning lines still prints as one line" 2 "$(lines "$OPEN")"
check "the newline was flattened rather than dropped" yes \
  "$(printf '%s' "$OPEN" | /usr/bin/grep -q 'first line second line with a tab' && printf 'yes' || printf 'no')"

# --- open: nothing to read is not a failure ---------------------------------

EMPTY="$TMP/empty-home"
check "no stream at all lists nothing" "" \
  "$(HQ_HOME="$EMPTY" "$SH" "$GATE" open "$A" 2>/dev/null)"
check "and exits 0 rather than reporting a problem" 0 \
  "$(HQ_HOME="$EMPTY" gate_code open "$A")"

# --- a line that cannot be read is reported, not skipped in silence ---------
#
# It may be the row that closes a deferral. Dropped without a word, that
# deferral is reported as open forever and the reader has no way to know why.
printf 'this is not JSON at all\n' >>"$SINK"
check "an unreadable line is named on stderr" yes \
  "$("$SH" "$GATE" open "$A" 2>&1 >/dev/null | /usr/bin/grep -q 'could not be parsed' && printf 'yes' || printf 'no')"
check "and the rows around it are still read" 2 "$(lines "$(gate_out open "$A")")"

# --- check: findings against dispositions -----------------------------------

on_branch "$A" feat/five
findings_in "$A" feat/five F1 F2
check "an undisposed finding is reported" "F2: no disposition was recorded for it" \
  "$(gate_out check "$A" | /usr/bin/grep F2)"
check "and the exit code says the gate is not clean" 1 "$(gate_code check "$A")"

rec_in "$A" feat/five disposition finding=F1 verdict=fix_now source=review
rec_in "$A" feat/five disposition finding=F2 verdict=reject source=review
on_branch "$A" feat/five
check "a fully disposed branch reports nothing" "" "$(gate_out check "$A")"
check "and exits 0" 0 "$(gate_code check "$A")"

# The identity is per branch: without the branch in it, any repository's F1
# would satisfy any other branch's F1 — and the F1 rows above are already in
# the stream.
on_branch "$A" feat/six
findings_in "$A" feat/six F1
check "another branch's disposition does not dispose of this branch's F1" 1 \
  "$(lines "$(gate_out check "$A")")"

# ...and the branch that fixes it later writes the qualified form. Both rows
# land on one identity — the bare one through the envelope, the qualified one
# as written — so either of them answers `check` here; `open` is where the
# closure has its effect.
rec_in "$A" feat/six disposition finding=F1 verdict=defer source=review reason='fixed on another branch'
rec_in "$A" fix/six-later disposition finding='feat/six#F1' verdict=fix_now source=review
on_branch "$A" feat/six
check "the deferral and the closure both name this finding, and it reads disposed of" 0 \
  "$(lines "$(gate_out check "$A")")"

# --- check: a second review pass appends and continues the numbering ---------
#
# The second pass ADDS to the findings file under new numbers rather than
# rewriting it from F1, so a disposition recorded by the first pass still
# answers the finding it answered then.
#
# THIS IS THE FIXTURE A BOUND ON THE FILE'S mtime TURNS RED: a fully judged
# branch reported as unjudged. The old rows are written by hand, which the
# recorder cannot do — it stamps `t` with the current second, and the gap IS
# the case.

old_row() { # <branch> <id> <age in seconds> [<verdict>] [<reason>]
  local t ts verdict="${4:-fix_now}" reason="${5:-}"
  t=$(( $(date +%s) - $3 ))
  ts=$(date -u -r "$t" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || ts=""
  [ -n "$ts" ] || ts="1970-01-01T00:00:00Z"
  printf '{"schema":3,"ts":"%s","t":%s,"run_id":"r","repo":"acme/widget","branch":"%s","worktree":"/w","kind":"disposition","payload":{"finding":"%s","verdict":"%s","source":"review"' \
    "$ts" "$t" "$1" "$2" "$verdict" >>"$SINK"
  [ -n "$reason" ] && printf ',"reason":"%s"' "$reason" >>"$SINK"
  printf '}}\n' >>"$SINK"
}

on_branch "$A" feat/again
findings_in "$A" feat/again F1            # the first pass
old_row feat/again F1 3600                # judged an hour ago
append_findings_in "$A" feat/again F2     # the second pass, appending just now
AGAIN=$(gate_out check "$A")
check "a disposition recorded long before the latest append still disposes of its finding" no \
  "$(printf '%s' "$AGAIN" | /usr/bin/grep -q '^F1:' && printf 'yes' || printf 'no')"
check "and the finding the second pass added is the one reported" \
  "F2: no disposition was recorded for it" "$AGAIN"
check "and the exit code says the gate is not clean" 1 "$(gate_code check "$A")"

# The other direction: a gate that stopped counting the findings file at all
# would pass the three checks above.
rec_in "$A" feat/again disposition finding=F2 verdict=fix_now source=review
on_branch "$A" feat/again
check "with the appended finding disposed of too, the branch reads clean" 0 \
  "$(lines "$(gate_out check "$A")")"

# --- check: the qualified spelling is the same identity ----------------------
#
# `<branch>#<id>` written by hand and a bare id recorded on that branch
# compose to one string, so a closure recorded from the branch that fixed
# something answers the finding the branch that raised it wrote down. Alone,
# with no bare row anywhere near it.

on_branch "$A" feat/closed-later
findings_in "$A" feat/closed-later F1
rec_in "$A" fix/closed-later-fix disposition finding='feat/closed-later#F1' \
  verdict=fix_now source=review
on_branch "$A" feat/closed-later
check "a row written under the qualified id disposes of that branch's finding" 0 \
  "$(lines "$(gate_out check "$A")")"

# The other direction, and it is the one that keeps the identity meaning
# anything: a qualified id naming a DIFFERENT branch answers nothing here.
on_branch "$A" feat/elsewhere-id
findings_in "$A" feat/elsewhere-id F1
rec_in "$A" feat/elsewhere-id disposition finding='feat/somewhere-else#F1' \
  verdict=fix_now source=review
on_branch "$A" feat/elsewhere-id
check "a qualified id naming another branch does not dispose of this one" 1 \
  "$(lines "$(gate_out check "$A")")"

# --- open: a deferral is closed whichever pass fixes it ----------------------
#
# The other face of the same rule: a deferral raised by one pass is closed by
# the bare row triage writes after a later pass has appended — there is no
# boundary for the fix to fall on the far side of.

on_branch "$A" feat/twice
findings_in "$A" feat/twice F1
old_row feat/twice F1 3600 defer 'raised by the first pass'
append_findings_in "$A" feat/twice F2     # the second pass appends
check "a deferral raised before the latest append is still listed" yes \
  "$(gate_out open "$A" | /usr/bin/grep -q 'feat/twice#F1' && printf 'yes' || printf 'no')"
rec_in "$A" feat/twice disposition finding=F1 verdict=fix_now source=review
check "and a bare fix recorded after the append closes it" no \
  "$(gate_out open "$A" | /usr/bin/grep -q 'feat/twice#F1' && printf 'yes' || printf 'no')"

# The qualified form does the same from another branch, which is what keeps the
# list emptiable at all.
rec_in "$A" feat/twice disposition finding=F2 verdict=defer source=review \
  reason='raised by the second pass'
check "the deferral of the appended finding is listed under its own id" yes \
  "$(gate_out open "$A" | /usr/bin/grep -q 'feat/twice#F2' && printf 'yes' || printf 'no')"
rec_in "$A" fix/twice-later disposition finding='feat/twice#F2' verdict=fix_now \
  source=review
check "a qualified fix from another branch closes it" no \
  "$(gate_out open "$A" | /usr/bin/grep -q 'feat/twice#F2' && printf 'yes' || printf 'no')"

# The other direction: a face that stopped letting bare rows close anything
# would pass the checks above.
on_branch "$A" feat/one-pass
findings_in "$A" feat/one-pass F1
rec_in "$A" feat/one-pass disposition finding=F1 verdict=defer source=review \
  reason='deferred and fixed on the same branch'
rec_in "$A" feat/one-pass disposition finding=F1 verdict=fix_now source=review
check "a bare fix on the branch that raised it closes the deferral" no \
  "$(gate_out open "$A" | /usr/bin/grep -q 'feat/one-pass#F1' && printf 'yes' || printf 'no')"

# Same branch name, same finding id, different repository. Nothing about the
# row's own text distinguishes it; only the scope does.
on_branch "$B" feat/seven
findings_in "$B" feat/seven F1
rec_in "$A" feat/seven disposition finding=F1 verdict=fix_now source=review
on_branch "$B" feat/seven
check "another repository's disposition does not count here" 1 \
  "$(lines "$(gate_out check "$B")")"

# Findings are listed once each however often the file names them: a
# duplicate id is findings-gate.sh's to reject.
on_branch "$A" feat/dup
findings_in "$A" feat/dup F1 F1
check "a duplicated id is reported once" 1 "$(lines "$(gate_out check "$A")")"

# A findings file that is not there is not a failure and not a silent pass.
on_branch "$A" feat/none
check "a branch with no findings file exits 0" 0 "$(gate_code check "$A")"
check "and says which file it looked for" yes \
  "$("$SH" "$GATE" check "$A" 2>&1 >/dev/null | /usr/bin/grep -q 'findings.jsonl' && printf 'yes' || printf 'no')"

# A findings line that cannot be parsed is one finding this face cannot see. It
# says so rather than shortening the list quietly.
on_branch "$A" feat/torn
findings_in "$A" feat/torn F1
printf '{"id":"F2","file":"a.sh"\n' >>"$(task_dir "$A" feat/torn)/findings.jsonl"
check "an unreadable findings line is named on stderr" yes \
  "$("$SH" "$GATE" check "$A" 2>&1 >/dev/null | /usr/bin/grep -q 'could not be parsed' && printf 'yes' || printf 'no')"
check "and the readable findings are still checked" 2 "$(lines "$(gate_out check "$A")")"

# The reason the line above prints on stdout: dispose of every id this face
# CAN read, and the torn one is all that is left — exit 0 here would be a
# clean branch over a finding nobody has seen.
rec_in "$A" feat/torn disposition finding=F1 verdict=fix_now source=review reason=x
on_branch "$A" feat/torn
check "a torn line keeps the branch from reading clean once the rest is disposed of" 1 \
  "$(gate_code check "$A")"
check "and it is named on stdout, where the caller is looking" yes \
  "$(gate_out check "$A" | /usr/bin/grep -q 'could not be parsed' && printf 'yes' || printf 'no')"

# --- a row that was read and cannot be used is not dropped in silence -------
#
# Between "read" and "unreadable" sits the row that parses and still cannot
# be joined: a finding with no id, a disposition naming no finding.
# findings-gate.sh blocks AFTER the write, so a file it rejected is still on
# disk for this face to read.
#
# The words are findings-gate.sh's, to the letter: two descriptions of one
# broken row is one description too many.

on_branch "$A" feat/nameless
findings_in "$A" feat/nameless F1
NAMELESS="$(task_dir "$A" feat/nameless)/findings.jsonl"
printf '{"id":null,"file":"a.sh","claim":"c","evidence":"e","consequence":"q"}\n' >>"$NAMELESS"
printf '{"file":"a.sh","claim":"c","evidence":"e","consequence":"q"}\n' >>"$NAMELESS"
rec_in "$A" feat/nameless disposition finding=F1 verdict=fix_now source=review
on_branch "$A" feat/nameless
NAMED=$(gate_out check "$A")
check "a findings row whose id is null is named where it sits" yes \
  "$(printf '%s' "$NAMED" | /usr/bin/grep -q 'line 2: id must be a string, got NoneType' && printf 'yes' || printf 'no')"
check "and one carrying no id at all is named too" yes \
  "$(printf '%s' "$NAMED" | /usr/bin/grep -q 'line 3: missing id' && printf 'yes' || printf 'no')"
# The other direction: the rows around them are still judged, and judged as
# disposed of. A face that had started reporting everything would pass the two
# checks above.
check "the finding that does have an id is still disposed of" no \
  "$(printf '%s' "$NAMED" | /usr/bin/grep -q 'F1' && printf 'yes' || printf 'no')"
# THE DEFECT THIS CLOSES: with every readable finding disposed of, the run came
# back clean and silent over a file holding findings nobody can ever record a
# disposition against.
check "and the gate does not come back clean" 1 "$(gate_code check "$A")"

# The same on the stream side. Written by hand because record.sh refuses to
# write it — which is the point: the rows that reach here are the ones nothing
# checked.
cat >>"$SINK" <<'EOF'
{"schema":3,"ts":"2026-08-15T11:00:00Z","t":1786870800,"run_id":"r","repo":"acme/widget","branch":"feat/eight","worktree":"/w","kind":"disposition","payload":{"finding":null,"verdict":"defer","source":"review","reason":"nothing can list this"}}
{"schema":3,"ts":"2026-08-15T11:00:01Z","t":1786870801,"run_id":"r","repo":"acme/widget","branch":"feat/eight","worktree":"/w","kind":"disposition","payload":{"verdict":"fix_now","source":"review"}}
EOF
check "a disposition row whose finding is null is named on stderr" yes \
  "$("$SH" "$GATE" open "$A" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'finding must be a string, got NoneType' && printf 'yes' || printf 'no')"
check "and one with no finding key at all is named too" yes \
  "$("$SH" "$GATE" open "$A" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'missing finding' && printf 'yes' || printf 'no')"

# --- rows of an older schema are out of scope, not broken -------------------
#
# The stream is append-only, so most of it may be what earlier versions wrote
# — dispositions in a vocabulary that has no `finding` at all. Read as this
# schema, every one would be reported as a broken row.
cat >>"$SINK" <<'EOF'
{"schema":2,"ts":"2026-08-03T09:52:21Z","t":1785750741,"run_id":"r","repo":"acme/widget","branch":"feat/old","worktree":"/w","kind":"disposition","payload":{"fb":"FB001","severity":"Medium","origin":"root-j3","disposition":"plan","prior_departure":"true"}}
EOF
check "an older schema's disposition is not counted as a broken row of this one" yes \
  "$("$SH" "$GATE" open "$A" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'triage-gate.sh: 2 row(s)' && printf 'yes' || printf 'no')"

# And it is the schema that scopes them out, not the missing field. A row of the
# older schema carrying this schema's payload is still not this schema's row.
rec_in "$A" feat/nine disposition finding=F1 verdict=defer source=review \
  reason='deferred under schema 3'
cat >>"$SINK" <<'EOF'
{"schema":2,"ts":"2026-08-15T11:00:02Z","t":1786870802,"run_id":"r","repo":"acme/widget","branch":"feat/nine","worktree":"/w","kind":"disposition","payload":{"finding":"F1","verdict":"fix_now","source":"review"}}
EOF
check "a row of the older schema does not close this schema's deferral" yes \
  "$(gate_out open "$A" | /usr/bin/grep -q 'feat/nine#F1' && printf 'yes' || printf 'no')"
# ...and this schema's row does, which is what says the check above is about the
# schema rather than about that row being ignored for some other reason.
rec_in "$A" feat/nine disposition finding=F1 verdict=fix_now source=review
check "and this schema's row does close it" no \
  "$(gate_out open "$A" | /usr/bin/grep -q 'feat/nine#F1' && printf 'yes' || printf 'no')"

# --- where it looks -----------------------------------------------------------

# HQ_SINK names a file outright and wins, which is what keeps a caller able to
# point this at one stream while its run files sit under the ordinary home.
ALT="$TMP/alt-stream.jsonl"
: >"$ALT"
check "HQ_SINK wins over the home's stream" 0 \
  "$(lines "$(HQ_SINK="$ALT" "$SH" "$GATE" open "$A" 2>/dev/null)")"

# The home is recovered by stripping the LAST `/repos/` off the run
# directory: the first-match form would cut a home containing that segment
# short and read a stream that is not there — a repository with no deferrals.
NESTED="$TMP/repos/home"
mkdir -p "$NESTED"
( cd "$A" && HQ_HOME="$NESTED" "$SH" "$REC" disposition finding=F1 verdict=defer \
    source=review reason='written into a home under a repos directory' ) >/dev/null 2>&1
check "a home whose path contains /repos/ is still found" 1 \
  "$(lines "$(HQ_HOME="$NESTED" "$SH" "$GATE" open "$A" 2>/dev/null)")"

# --- a file that is there and cannot be read is not an empty file ------------
#
# Absent and unreadable arrive at the same place in a naive reader — no rows —
# and the answers are opposite: no stream yet is a real "nothing is open", a
# stream this process cannot open is "could not look".
#
# The findings file is blocked with a permission bit and the stream with a
# directory, because the two paths are guarded differently: a directory is
# answered by the caller before the join ever runs, and the mode bit is the
# case that reaches the reader. Run as root the mode bit does not bind, so
# these two go red rather than quietly green — the direction to fail in.

on_branch "$A" feat/unreadable
findings_in "$A" feat/unreadable F1
UNREADABLE_F="$(task_dir "$A" feat/unreadable)/findings.jsonl"
chmod 000 "$UNREADABLE_F"
check "an unreadable findings file is could-not-look, not a clean branch" 2 \
  "$(gate_code check "$A")"
check "and it names the file it could not read" yes \
  "$("$SH" "$GATE" check "$A" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'cannot read' && printf 'yes' || printf 'no')"
chmod 644 "$UNREADABLE_F"

mv "$SINK" "$SINK.aside" && mkdir -p "$SINK"
check "an unreadable stream is could-not-look, not an empty deferral list" 2 \
  "$(gate_code open "$A")"
check "and check says the same rather than reporting a clean branch" 2 \
  "$(gate_code check "$A")"
rmdir "$SINK" && mv "$SINK.aside" "$SINK"

# The other direction, and it is the one that makes the pair mean something: a
# reader that refused everything would pass all four checks above. A stream that
# is simply not there is still the honest empty answer.
mv "$SINK" "$SINK.aside"
check "a stream that does not exist is still an empty list, not a refusal" 0 \
  "$(gate_code open "$A")"
mv "$SINK.aside" "$SINK"

# --- a branch name carrying the separator ------------------------------------
#
# git accepts a branch name carrying `#` (check-ref-format agrees), and the
# identity is `<branch>#<id>` — so such a name puts two separators in one
# identifier. Nothing splits it any more, which is the point of this pair: the
# bare row composes the same string the hand-written qualified row spells out,
# and the two meet. A reader that cut at the FIRST separator would take
# `feat/a` out of `feat/a#b#F1` and silently turn that branch's collision
# check off.

on_branch "$A" 'feat/hash#in-name'
findings_in "$A" 'feat/hash#in-name' F1
rec_in "$A" 'feat/hash#in-name' disposition finding=F1 verdict=defer source=review \
  reason='raised on a branch whose name carries the separator'
check "a deferral there is filed under the whole branch name" yes \
  "$(gate_out open "$A" | /usr/bin/grep -q 'feat/hash#in-name#F1' && printf 'yes' || printf 'no')"
rec_in "$A" fix/hash-later disposition finding='feat/hash#in-name#F1' verdict=fix_now \
  source=review
check "and the qualified form written by hand closes exactly it" no \
  "$(gate_out open "$A" | /usr/bin/grep -q 'feat/hash#in-name#F1' && printf 'yes' || printf 'no')"

# --- refusals ---------------------------------------------------------------

check "no subcommand is a usage error" 2 "$(gate_code)"
check "an unknown subcommand is a usage error" 2 "$(gate_code triage "$A")"
check "a second path argument is a usage error" 2 "$(gate_code open "$A" "$B")"
check "usage goes to stderr, not into the list" yes \
  "$("$SH" "$GATE" 2>&1 >/dev/null | /usr/bin/grep -q 'Usage:' && printf 'yes' || printf 'no')"

# A root that is not a repository is refused AS THAT. Asserted on the
# message, not only the exit code: the branch check answers this input too,
# with a true sentence about the wrong thing.
check "a root that is not a repository is refused" 2 "$(gate_code open "$TMP")"
check "and the refusal says that, rather than blaming the branch" yes \
  "$("$SH" "$GATE" open "$TMP" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'not a git repository' && printf 'yes' || printf 'no')"

# A detached HEAD has no branch, so there is no run directory any reader would
# derive and no identity to file a row under. Refused rather than answered.
git -C "$A" checkout -q --detach HEAD
check "a detached HEAD is refused" 2 "$(gate_code open "$A")"
check "and the refusal says so" yes \
  "$("$SH" "$GATE" open "$A" 2>&1 >/dev/null | /usr/bin/grep -q 'branch' && printf 'yes' || printf 'no')"
git -C "$A" checkout -q feat/one

# THE ABSENT PARSER IS THE BRANCH THAT MATTERS. Passing silently here would
# print an empty deferral list and a clean check — both of which are the answers
# this file exists to make trustworthy — so both faces refuse.
check "no parser: open refuses" 2 \
  "$(HQ_PYTHON="$TMP/no-such-python" gate_code open "$A")"
check "no parser: check refuses" 2 \
  "$(HQ_PYTHON="$TMP/no-such-python" gate_code check "$A")"
check "no parser: it says nothing was read" yes \
  "$(HQ_PYTHON="$TMP/no-such-python" "$SH" "$GATE" open "$A" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'nothing was checked' && printf 'yes' || printf 'no')"
check "no parser: and prints no list" "" \
  "$(HQ_PYTHON="$TMP/no-such-python" "$SH" "$GATE" open "$A" 2>/dev/null)"

# lib.sh is where a run's files are derived, and without it beside this script
# there is no directory to read. Reported rather than guessed at.
ORPHAN="$TMP/orphan"
mkdir -p "$ORPHAN"
cp "$GATE" "$ORPHAN/"
check "no lib.sh beside the script is refused" 2 \
  "$("$SH" "$ORPHAN/triage-gate.sh" open "$A" >/dev/null 2>&1; printf '%s' "$?")"

# The schema this face reads is record.sh's. Unreadable, there is no way to
# tell this format's rows from an older version's, so it refuses instead of
# answering from a guess.
NORECORD="$TMP/no-record"
mkdir -p "$NORECORD"
cp "$GATE" "$LIB" "$NORECORD/"
check "no record.sh beside the script is refused" 2 \
  "$("$SH" "$NORECORD/triage-gate.sh" open "$A" >/dev/null 2>&1; printf '%s' "$?")"
check "and the refusal names the schema, not the stream" yes \
  "$("$SH" "$NORECORD/triage-gate.sh" open "$A" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'schema number' && printf 'yes' || printf 'no')"
# The same directory with record.sh restored answers, which is what says the
# refusal above is about that file rather than about the copy.
cp "$REC" "$NORECORD/"
check "and with record.sh beside it, it answers" 0 \
  "$("$SH" "$NORECORD/triage-gate.sh" open "$A" >/dev/null 2>&1; printf '%s' "$?")"

# --- bash 3.2 compatibility ------------------------------------------------
#
# macOS ships bash 3.2 as /bin/bash while the PATH bash is usually 5.x, so a
# 4.0+ construct passes here and breaks on a stock machine — silently, with a
# wrong value rather than a crash. Two of the three compatibility checks live
# here; the third (the construct sweep) reads every script at once and
# lives in sweep.test.sh.

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

    # The success path of both faces, which is where a construct that only
    # writes to stderr would hide. The fixture is fresh so that the unreadable
    # line added above cannot account for the output.
    PROBE="$TMP/probe-home"
    P="$TMP/wt-probe"
    mk_repo "$P" "git@example.com:acme/probe.git"
    ( cd "$P" && HQ_HOME="$PROBE" "$OLD_BASH" "$REC" disposition finding=F1 \
        verdict=defer source=review reason='probe' ) >/dev/null 2>&1
    HQ_HOME="$PROBE" "$OLD_BASH" "$GATE" open "$P" >/dev/null 2>"$TMP/err1"
    HQ_HOME="$PROBE" "$OLD_BASH" "$GATE" check "$P" >/dev/null 2>>"$TMP/err1"
    # `check` on a branch with no findings file writes its one explanatory line
    # to stderr by design, so that line is what is expected here and anything
    # else is not. Its presence is asserted as well: an empty file would satisfy
    # the first of these on its own, and an empty file is also what a probe that
    # ran nothing looks like.
    check "triage-gate.sh writes nothing of its own to stderr under bash $OLD_VER" \
      0 "$(/usr/bin/grep -vc 'no findings file at' "$TMP/err1" | tr -d ' ')"
    check "and the probe reached the line it was supposed to write" \
      1 "$(/usr/bin/grep -c 'no findings file at' "$TMP/err1" | tr -d ' ')"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
