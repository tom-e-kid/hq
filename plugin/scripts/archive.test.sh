#!/usr/bin/env bash
# Tests for archive.sh — which merged pull requests still owe a residual
# record.
#
# THE ROWS ARE WRITTEN BY record.sh wherever the case allows it: a fixture
# composed here would agree with this reader's idea of the format rather than
# with the writer's. Hand-written rows appear only where the case cannot be
# produced otherwise.
#
# Both directions everywhere: dropping a filter makes `missing` MORE
# talkative, which no single-sided check would notice.
#
# Run: bash plugin/scripts/archive.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/archive.sh"
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

# --- fixtures -----------------------------------------------------------------

# A repository whose directory name is deliberately NOT its remote's name: the
# slug in a row is `owner/name` from the remote, and archive.sh derives it
# again to scope what it reads. The base is pinned in .hq/settings.json, which
# is the first step of the resolution chain every caller takes.
mk_repo() { # <dir> [<remote url>]
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" symbolic-ref HEAD refs/heads/main
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name "Test"
  git -C "$1" config commit.gpgsign false
  [ $# -ge 2 ] && git -C "$1" remote add origin "$2"
  mkdir -p "$1/.hq"
  printf '{"base_branch":"main"}\n' >"$1/.hq/settings.json"
  git -C "$1" add .hq/settings.json
  git -C "$1" commit -q -m init
}

# A merged pull request, the way the forge leaves one on the base branch: a
# merge commit whose subject carries the number and the head `owner/branch`.
merge_pr() { # <dir> <number> <branch>
  git -C "$1" checkout -q -b "$3" main
  git -C "$1" commit -q --allow-empty -m "work on $3"
  git -C "$1" checkout -q main
  git -C "$1" merge -q --no-ff -m "Merge pull request #$2 from acme/$3" "$3"
}

# A residual row, written by the script that writes them for real, from inside
# the repository given.
rec_in() { # <dir> <args...>
  local dir=$1; shift
  ( cd "$dir" && "$SH" "$REC" "$@" ) >/dev/null 2>&1
}

arch_out() { # <dir> <args...> — stdout only
  local dir=$1; shift
  ( cd "$dir" && "$SH" "$SCRIPT" "$@" ) 2>/dev/null
}

arch_err() { # <dir> <args...> — stderr only
  local dir=$1; shift
  ( cd "$dir" && "$SH" "$SCRIPT" "$@" ) 2>&1 >/dev/null
}

arch_code() { # <dir> <args...>
  local dir=$1; shift
  ( cd "$dir" && "$SH" "$SCRIPT" "$@" ) >/dev/null 2>&1
  printf '%s' "$?"
}

lines() { # <text> — how many non-empty lines it holds
  [ -n "$1" ] || { printf '0'; return; }
  printf '%s\n' "$1" | /usr/bin/grep -c . | tr -d ' '
}

SINK="$HQ_HOME/stream.jsonl"

A="$TMP/wt-a"   # remote acme/widget — directory name differs on purpose
B="$TMP/wt-b"   # remote acme/gadget, whose #101 must not answer for A's

mk_repo "$A" "git@example.com:acme/widget.git"
merge_pr "$A" 101 feat/a
merge_pr "$A" 102 feat/b
mk_repo "$B" "https://example.com/acme/gadget.git"
merge_pr "$B" 101 feat/z

tap_begin

# --- missing: the list ----------------------------------------------------------

OUT=$(arch_out "$A" missing)
check "every merged pull request with no row is listed" 2 "$(lines "$OUT")"
check "newest first" 102 "$(printf '%s\n' "$OUT" | head -1 | cut -f1)"
check "the branch travels in the second column, owner prefix stripped" \
  "feat/b" "$(printf '%s\n' "$OUT" | head -1 | cut -f2)"

rec_in "$A" residual pr=102 reviewer=ext-review state=reviewed
OUT=$(arch_out "$A" missing)
check "a recorded pull request drops off the list" 1 "$(lines "$OUT")"
check "and the one left is the unrecorded one" 101 "$(printf '%s' "$OUT" | cut -f1)"

# --- missing: what scopes the answer --------------------------------------------

rec_in "$B" residual pr=101 reviewer=ext-review state=reviewed
check "another repository's row does not record this one's pull request" 1 \
  "$(lines "$(arch_out "$A" missing)")"
check "and in its own repository it does" 0 "$(lines "$(arch_out "$B" missing)")"

# --- missing: the count caps the output, not how far back the walk looks ---------

check "a cap of 1 walks past the recorded newest merge to the unrecorded one" \
  101 "$(arch_out "$A" missing 1 | cut -f1)"
check "and a cap wider than the backlog adds nothing" 1 \
  "$(lines "$(arch_out "$A" missing 2)")"
check "a cap that is not a number is refused" 2 "$(arch_code "$A" missing x)"
check "a cap of zero is refused — it would answer an empty list anywhere" 2 \
  "$(arch_code "$A" missing 0)"

# --- missing: a backlog deeper than the cap surfaces run after run ----------------
#
# The failure this pins: a window of the newest <count> MERGE COMMITS stops
# moving when its commits are recorded, so a backlog deeper than one window
# is never listed again. The non-PR merge on top is part of the fixture:
# under a window it would consume a slot, under the cap it must not.
C="$TMP/wt-c"
mk_repo "$C" "git@example.com:acme/thing.git"
merge_pr "$C" 201 feat/one
merge_pr "$C" 202 feat/two
merge_pr "$C" 203 feat/three
git -C "$C" checkout -q -b chore/top main
git -C "$C" commit -q --allow-empty -m "top work"
git -C "$C" checkout -q main
git -C "$C" merge -q --no-ff -m "Merge branch 'chore/top'" chore/top

OUT=$(arch_out "$C" missing 2)
check "a cap of 2 over a backlog of 3 prints the 2 newest unrecorded" 2 \
  "$(lines "$OUT")"
check "and the non-PR merge on top did not occupy the cap" 203 \
  "$(printf '%s\n' "$OUT" | head -1 | cut -f1)"

rec_in "$C" residual pr=203 reviewer=ext-review state=reviewed
rec_in "$C" residual pr=202 reviewer=ext-review state=reviewed
check "what the cap left unprinted surfaces on the next run, once the newer are recorded" \
  201 "$(arch_out "$C" missing 2 | cut -f1)"

# --- missing: one number, two spellings ------------------------------------------
#
# Hand-written: the recorder normalises nothing, so a row whose pr carries a
# leading `#` is an ordinary thing for a person to have written by hand — and
# it names the same pull request.
printf '{"schema":3,"ts":"2026-01-01T00:00:00Z","t":1767225600,"run_id":"r","repo":"acme/widget","branch":"main","worktree":"/w","kind":"residual","payload":{"pr":"#101","reviewer":"ext-review","state":"reviewed","findings":[]}}\n' >>"$SINK"
check "a recorded number carrying a leading # still counts as recorded" 0 \
  "$(lines "$(arch_out "$A" missing)")"

# --- missing: a merge that is not a pull request ---------------------------------

git -C "$A" checkout -q -b chore/x main
git -C "$A" commit -q --allow-empty -m "local work"
git -C "$A" checkout -q main
git -C "$A" merge -q --no-ff -m "Merge branch 'chore/x'" chore/x
check "a merge that names no pull request is skipped, not misread" 0 \
  "$(lines "$(arch_out "$A" missing)")"
check "and it is invisible to the cap too — a cap of 1 still answers about pull requests only" 0 \
  "$(lines "$(arch_out "$A" missing 1)")"

# --- missing: what cannot be read is said, and the rest is still processed -------

merge_pr "$A" 103 feat/c
printf 'this is not JSON at all\n' >>"$SINK"
OUT=$(arch_out "$A" missing)
check "an unreadable stream line is counted on stderr" yes \
  "$(arch_err "$A" missing | /usr/bin/grep -q 'could not be parsed' && printf 'yes' || printf 'no')"
check "and the rows around it are still read" 103 "$(printf '%s' "$OUT" | cut -f1)"

# The recorder refuses to write a residual row without a pr, so the row that
# names no pull request is hand-written — and it must be named, not skipped in
# silence: it records nothing this face can join.
printf '{"schema":3,"ts":"2026-01-01T00:00:00Z","t":1767225600,"run_id":"r","repo":"acme/widget","branch":"main","worktree":"/w","kind":"residual","payload":{"pr":null,"reviewer":"ext-review","state":"reviewed","findings":[]}}\n' >>"$SINK"
check "a residual row naming no pull request is said out loud" yes \
  "$(arch_err "$A" missing | /usr/bin/grep -q 'name no pull request' && printf 'yes' || printf 'no')"
check "and it does not count as a record for anything" 103 \
  "$(arch_out "$A" missing | cut -f1)"

# --- missing: failure and empty are different answers -----------------------------

NOBASE="$TMP/nobase"
mkdir -p "$NOBASE"
git -C "$NOBASE" init -q
git -C "$NOBASE" symbolic-ref HEAD refs/heads/main
git -C "$NOBASE" config user.email t@example.com
git -C "$NOBASE" config user.name "Test"
git -C "$NOBASE" config commit.gpgsign false
mkdir -p "$NOBASE/.hq"
printf '{"base_branch":"ghost"}\n' >"$NOBASE/.hq/settings.json"
git -C "$NOBASE" add .hq/settings.json
git -C "$NOBASE" commit -q -m init
check "a base that does not resolve is a refusal, not an empty list" 2 \
  "$(arch_code "$NOBASE" missing)"
check "and it prints no list at all" "" "$(arch_out "$NOBASE" missing)"

EMPTY="$TMP/empty-home"
check "no stream at all is an answer: everything is owed" 3 \
  "$(HQ_HOME="$EMPTY" "$SH" -c 'cd "$1" && bash "$2" missing' _ "$A" "$SCRIPT" 2>/dev/null | /usr/bin/grep -c .)"
check "and it exits 0 rather than reporting a problem" 0 \
  "$(HQ_HOME="$EMPTY" arch_code "$A" missing)"

BADHOME="$TMP/bad-home"
mkdir -p "$BADHOME/stream.jsonl"
check "a stream that is there and cannot be opened is a refusal" 2 \
  "$(HQ_HOME="$BADHOME" arch_code "$A" missing)"

check "no parser refuses rather than listing nothing" 2 \
  "$(HQ_PYTHON="$TMP/no-such-python" arch_code "$A" missing)"
check "no parser: and it says nothing was listed" yes \
  "$(HQ_PYTHON="$TMP/no-such-python" arch_err "$A" missing \
     | /usr/bin/grep -q 'nothing was listed' && printf 'yes' || printf 'no')"

git -C "$A" checkout -q --detach HEAD
check "a detached HEAD is refused — there is no run to stand in" 2 \
  "$(arch_code "$A" missing)"
git -C "$A" checkout -q main

ORPHAN="$TMP/orphan"
mkdir -p "$ORPHAN"
cp "$SCRIPT" "$ORPHAN/"
check "no lib.sh beside the script is refused" 2 \
  "$( ( cd "$A" && "$SH" "$ORPHAN/archive.sh" missing ) >/dev/null 2>&1; printf '%s' "$?" )"

NORECORD="$TMP/no-record"
mkdir -p "$NORECORD"
cp "$SCRIPT" "$LIB" "$NORECORD/"
check "no record.sh beside the script is refused" 2 \
  "$( ( cd "$A" && "$SH" "$NORECORD/archive.sh" missing ) >/dev/null 2>&1; printf '%s' "$?" )"
check "and the refusal names the schema, not the stream" yes \
  "$( ( cd "$A" && "$SH" "$NORECORD/archive.sh" missing ) 2>&1 >/dev/null \
     | /usr/bin/grep -q 'schema number' && printf 'yes' || printf 'no')"

# --- cleanup: a merged branch's directory goes, and only then ---------------------

task_dir() { # <dir> <branch>
  "$SH" "$LIB" hq_task_dir "$1" "$2"
}
mk_task_dir() { # <dir> <branch> — a run directory where lib.sh says it lives
  local d
  d=$(task_dir "$1" "$2") || return 1
  mkdir -p "$d"
  printf 'x\n' >"$d/plan.md"
  printf '%s' "$d"
}

D=$(mk_task_dir "$A" feat/a)
OUT=$( ( cd "$A" && "$SH" "$SCRIPT" cleanup feat/a ) 2>/dev/null )
check "a merged branch's run directory is removed" no \
  "$([ -e "$D" ] && echo yes || echo no)"
check "and the removal says what it removed" yes \
  "$(printf '%s' "$OUT" | /usr/bin/grep -q '^removed ' && printf 'yes' || printf 'no')"
# The second removal, and it is a separate one: a finished run leaves a
# directory under the home AND a branch in the repository, and a face that
# only took the first left the second for a person to notice.
check "the merged branch's local ref goes with it" no \
  "$(git -C "$A" rev-parse --verify --quiet refs/heads/feat/a >/dev/null && echo yes || echo no)"
check "and the deletion names the branch it took" yes \
  "$(printf '%s' "$OUT" | /usr/bin/grep -q '^deleted local branch feat/a' && printf 'yes' || printf 'no')"
# What a full cleanup leaves behind, in a clone whose origin never held this
# branch: nothing resolves any more. The merge commit on the base still names
# it, so the second proof is available and the call is the clean no-op that a
# call about two absent things should be. It used to be a refusal, and the
# refusal was the price of the branch deletion above.
check "a second call, once nothing holds the branch any more, is a no-op" 0 \
  "$(arch_code "$A" cleanup feat/a)"

# --- cleanup: the head branch deleted on merge, which is a forge setting -----------
#
# Where `deleteBranchOnMerge` is on, this is the ONLY state this face ever runs
# in: by the time anyone gets here the ref is gone and the ancestor proof can
# never be taken. Before the merge commit was accepted as proof, the directory
# stayed for good and nothing else ever removed it.
merge_pr "$A" 111 feat/gone
git -C "$A" branch -q -D feat/gone
D=$(mk_task_dir "$A" feat/gone)
check "the branch is really gone before the call" no \
  "$(git -C "$A" rev-parse --verify --quiet refs/heads/feat/gone >/dev/null && echo yes || echo no)"
check "a branch deleted on merge is cleaned up on its merge commit" 0 \
  "$(arch_code "$A" cleanup feat/gone)"
check "and its run directory is gone" no "$([ -e "$D" ] && echo yes || echo no)"

# The proof is the subject the forge writes, not any merge. A branch merged
# with git's own default message is not a pull request as far as this face can
# tell, and the doubt stays a refusal.
git -C "$A" checkout -q -b feat/plainmerge main
git -C "$A" commit -q --allow-empty -m "work on feat/plainmerge"
git -C "$A" checkout -q main
git -C "$A" merge -q --no-ff -m "Merge branch 'feat/plainmerge'" feat/plainmerge
git -C "$A" branch -q -D feat/plainmerge
D=$(mk_task_dir "$A" feat/plainmerge)
check "a merge commit that is not a pull request proves nothing" 1 \
  "$(arch_code "$A" cleanup feat/plainmerge)"
check "and that directory stays" yes "$([ -e "$D" ] && echo yes || echo no)"
check "and the refusal says no merge commit names it" yes \
  "$(arch_err "$A" cleanup feat/plainmerge | /usr/bin/grep -q 'no merge commit on' && printf 'yes' || printf 'no')"

# A branch whose own name holds slashes: the owner is stripped and the rest is
# the branch, so `acme/feat/new-x` must not be read as `feat`.
merge_pr "$A" 112 feat/deep/name
git -C "$A" branch -q -D feat/deep/name
D=$(mk_task_dir "$A" feat/deep/name)
check "a branch name holding slashes is matched whole" 0 \
  "$(arch_code "$A" cleanup feat/deep/name)"
check "and its directory goes" no "$([ -e "$D" ] && echo yes || echo no)"

# The first refusal: not merged. The directory of a live branch is live state,
# and so is the branch.
git -C "$A" checkout -q -b feat/wip main
git -C "$A" commit -q --allow-empty -m "unmerged work"
git -C "$A" checkout -q main
D=$(mk_task_dir "$A" feat/wip)
check "an unmerged branch is refused" 1 "$(arch_code "$A" cleanup feat/wip)"
check "and its directory stays" yes "$([ -e "$D" ] && echo yes || echo no)"
check "and so does the branch" yes \
  "$(git -C "$A" rev-parse --verify --quiet refs/heads/feat/wip >/dev/null && echo yes || echo no)"
check "and the refusal says why" yes \
  "$(arch_err "$A" cleanup feat/wip | /usr/bin/grep -q 'not merged' && printf 'yes' || printf 'no')"

# A branch that does not resolve cannot be shown merged, and the benefit of
# the doubt would delete on a typo.
D=$(mk_task_dir "$A" feat/ghost)
check "a branch that does not resolve is refused" 1 "$(arch_code "$A" cleanup feat/ghost)"
check "a typo deletes nothing" yes "$([ -e "$D" ] && echo yes || echo no)"

# A branch the merge deleted locally still resolves through origin — that is
# the ordinary state this face runs in, and the one where the two removals
# come apart: there is a directory to remove and no local branch to delete.
git -C "$A" update-ref refs/remotes/origin/feat/rem "$(git -C "$A" rev-parse feat/b)"
D=$(mk_task_dir "$A" feat/rem)
OUT=$( ( cd "$A" && "$SH" "$SCRIPT" cleanup feat/rem ) 2>/dev/null ); CODE=$?
check "a merged branch that only origin still has is removed" 0 "$CODE"
check "and that directory is gone" no "$([ -e "$D" ] && echo yes || echo no)"
check "the local branch that was never there is reported, not an error" yes \
  "$(printf '%s' "$OUT" | /usr/bin/grep -q '^nothing to delete: no local branch feat/rem' && printf 'yes' || printf 'no')"
# The remote branch is deliberately left alone. The ref this whole case is
# built on is the one that would go.
check "and the remote ref it resolved through is left alone" yes \
  "$(git -C "$A" rev-parse --verify --quiet refs/remotes/origin/feat/rem >/dev/null && echo yes || echo no)"

# Running it again on that same branch is an answer, not an error: each half
# reports what it found, and neither is there.
OUT=$( ( cd "$A" && "$SH" "$SCRIPT" cleanup feat/rem ) 2>/dev/null ); CODE=$?
check "a second call with nothing left to do exits 0" 0 "$CODE"
check "and says the directory was not there" yes \
  "$(printf '%s' "$OUT" | /usr/bin/grep -q '^nothing to remove' && printf 'yes' || printf 'no')"
check "and that the local branch was not either" yes \
  "$(printf '%s' "$OUT" | /usr/bin/grep -q '^nothing to delete' && printf 'yes' || printf 'no')"

# The second refusal: the derived path resolves outside the home. A symlink
# planted at the task directory must not walk the deletion out of repos/.
OUTSIDE="$TMP/outside"
mkdir -p "$OUTSIDE"
printf 'keep\n' >"$OUTSIDE/precious"
LNK=$(task_dir "$A" feat/b)
mkdir -p "$(dirname "$LNK")"
ln -s "$OUTSIDE" "$LNK"
check "a directory resolving outside the home is refused" 1 \
  "$(arch_code "$A" cleanup feat/b)"
check "and what it points at is untouched" yes \
  "$([ -f "$OUTSIDE/precious" ] && echo yes || echo no)"
check "and the refusal names where it resolved" yes \
  "$(arch_err "$A" cleanup feat/b | /usr/bin/grep -q 'resolves to' && printf 'yes' || printf 'no')"
rm -f "$LNK"

# The other half of that same step: a run directory that is there and cannot
# be entered. Where it resolves cannot be checked, so the test above can be
# taken neither way — and the answer must not fall through to "no directory",
# which would delete the branch and report nothing to remove while the
# directory sat on disk. Reached with a mode that denies this process.
merge_pr "$A" 107 feat/locked
D=$(mk_task_dir "$A" feat/locked)
chmod 000 "$D"
if (cd "$D" >/dev/null 2>&1); then
  # A process no mode can stop — root — cannot be put in this state at all.
  ok "SKIP this process enters a 000 directory: unenterable case unverified"
  ok "SKIP unenterable: the report is unverified"
  ok "SKIP unenterable: the branch is unverified"
  ok "SKIP unenterable: the reason is unverified"
else
  # ONE CALL, then the state — as in the standing-on-the-branch block below.
  # A helper per check would run the face again over what the first run had
  # already changed, and an implementation that deleted the branch here would
  # be asked the second time about a branch that no longer resolves.
  OUT=$( ( cd "$A" && "$SH" "$SCRIPT" cleanup feat/locked ) 2>"$TMP/locked.err" ); CODE=$?
  check "a run directory that exists and cannot be entered is refused" 1 "$CODE"
  # Not asserted here: that the directory survives — this fixture's own mode
  # stops `rm` as well, so no change to the script could make that go red.
  # What a fall-through produces instead is a report, and the report is false.
  check "and it is not reported as a directory that was not there" no \
    "$(printf '%s' "$OUT" | /usr/bin/grep -q 'nothing to remove' && echo yes || echo no)"
  check "and the branch is left alone — this refusal is in front of both removals" yes \
    "$(git -C "$A" rev-parse --verify --quiet refs/heads/feat/locked >/dev/null \
       && echo yes || echo no)"
  check "and the refusal says it could not enter" yes \
    "$(/usr/bin/grep -q 'cannot be entered' "$TMP/locked.err" && printf 'yes' || printf 'no')"
fi
chmod 755 "$D"

# THE THIRD SHAPE OF THAT SAME REFUSAL, and the one that got out: a symlink
# whose target is gone. `-e` follows the link, so a test written with it alone
# answers "no directory" about a link that is sitting right there — and the
# run walks past the whole resolution block, deletes the branch, and prints
# `nothing to remove` over the link it left behind. THE FALSE REPORT IS THE
# DEFECT: what is on disk and what was said about it disagree, and with the
# branch gone the second call can no longer prove anything merged, so the run
# is not even retryable. Placed with the unenterable case because it reaches
# the same refusal, in front of both removals.
merge_pr "$A" 108 feat/dangling
DANGLING=$(task_dir "$A" feat/dangling)
mkdir -p "$(dirname "$DANGLING")"
ln -s "$TMP/no-such-target" "$DANGLING"
OUT=$( ( cd "$A" && "$SH" "$SCRIPT" cleanup feat/dangling ) 2>/dev/null ); CODE=$?
check "a run directory that is a symlink with no target is refused" 1 "$CODE"
check "and it is not reported as a directory that was not there" no \
  "$(printf '%s' "$OUT" | /usr/bin/grep -q 'nothing to remove' && echo yes || echo no)"
check "the dangling link is left where it is" yes \
  "$([ -L "$DANGLING" ] && echo yes || echo no)"
check "and the branch is left alone — nothing is removed on an undecidable path" yes \
  "$(git -C "$A" rev-parse --verify --quiet refs/heads/feat/dangling >/dev/null \
     && echo yes || echo no)"

# The refusal in front of the merged proof: the base branch itself, whose tip
# is trivially its own ancestor and whose run directory is live state. One
# typo must not end it.
D=$(mk_task_dir "$A" main)
check "the base branch itself is refused" 1 "$(arch_code "$A" cleanup main)"
check "and its run directory stays" yes "$([ -e "$D" ] && echo yes || echo no)"
check "and the refusal names the base" yes \
  "$(arch_err "$A" cleanup main | /usr/bin/grep -q 'base branch itself' && printf 'yes' || printf 'no')"

# --- cleanup: the branch this shell is standing on --------------------------------
#
# A branch cannot be deleted while it is the one checked out, so the base is
# checked out first. Each of these runs the face ONCE and reads the state
# afterwards: a second call over a helper would be acting on what the first
# one already changed.

merge_pr "$A" 104 feat/self
git -C "$A" checkout -q feat/self
D=$(mk_task_dir "$A" feat/self)
OUT=$( ( cd "$A" && "$SH" "$SCRIPT" cleanup feat/self ) 2>/dev/null ); CODE=$?
check "standing on the branch is not a refusal" 0 "$CODE"
check "the shell is moved to the base" main "$(git -C "$A" rev-parse --abbrev-ref HEAD)"
# Named on stdout because it is a change to the repository the caller did not
# ask for by name, and a person reading the run has to know it happened.
check "and the move is reported" yes \
  "$(printf '%s' "$OUT" | /usr/bin/grep -q '^checked out main' && printf 'yes' || printf 'no')"
check "the branch that was underfoot is deleted" no \
  "$(git -C "$A" rev-parse --verify --quiet refs/heads/feat/self >/dev/null && echo yes || echo no)"
check "and its directory with it" no "$([ -e "$D" ] && echo yes || echo no)"

# The checkout is the one step an ordinary working tree can refuse, which is
# why it comes before either removal: a run that stops there has taken
# nothing. THE BASE HAS TO HAVE MOVED ON for the checkout to fail at all — a
# branch merged into the base leaves the base holding the branch's own
# content, and a local change on top of it then carries across cleanly.
git -C "$A" checkout -q -b feat/dirty main
printf 'on the branch\n' >"$A/d.txt"
git -C "$A" add d.txt
git -C "$A" commit -q -m "d on the branch"
git -C "$A" checkout -q main
git -C "$A" merge -q --no-ff -m "Merge pull request #105 from acme/feat/dirty" feat/dirty
printf 'the base moved on\n' >"$A/d.txt"
git -C "$A" commit -q -am "the base moved on"
git -C "$A" checkout -q feat/dirty
printf 'uncommitted\n' >"$A/d.txt"
D=$(mk_task_dir "$A" feat/dirty)
check "a checkout the working tree refuses is a refusal here too" 1 \
  "$(arch_code "$A" cleanup feat/dirty)"
check "the shell is left where it was" feat/dirty "$(git -C "$A" rev-parse --abbrev-ref HEAD)"
check "the directory is untouched" yes "$([ -e "$D" ] && echo yes || echo no)"
check "and so is the branch" yes \
  "$(git -C "$A" rev-parse --verify --quiet refs/heads/feat/dirty >/dev/null && echo yes || echo no)"
check "and the refusal says nothing was removed" yes \
  "$(arch_err "$A" cleanup feat/dirty | /usr/bin/grep -q 'nothing was removed' && printf 'yes' || printf 'no')"
git -C "$A" checkout -q -- d.txt
git -C "$A" checkout -q main

# The base has to be a LOCAL branch to move to. Checking out `origin/<base>`
# would leave a detached HEAD, which hq_task_dir refuses — this face would be
# handing the next run a repository it cannot derive anything in.
E="$TMP/wt-e"
mk_repo "$E" "git@example.com:acme/edge.git"
merge_pr "$E" 301 feat/only
git -C "$E" update-ref refs/remotes/origin/main "$(git -C "$E" rev-parse main)"
git -C "$E" checkout -q feat/only
git -C "$E" branch -q -D main
D=$(mk_task_dir "$E" feat/only)
check "standing on the branch with no local base is refused" 1 \
  "$(arch_code "$E" cleanup feat/only)"
check "the refusal names the detached HEAD it would have caused" yes \
  "$(arch_err "$E" cleanup feat/only | /usr/bin/grep -q 'detached HEAD' && printf 'yes' || printf 'no')"
check "and it removed nothing" yes "$([ -e "$D" ] && echo yes || echo no)"
check "and left the branch alone" yes \
  "$(git -C "$E" rev-parse --verify --quiet refs/heads/feat/only >/dev/null && echo yes || echo no)"

# --- cleanup: a branch git itself will not let go of -------------------------------
#
# EVERY OTHER REFUSAL HAPPENS BEFORE ANYTHING MOVES; this one cannot. The two
# removals are independent and the directory's goes first, so a branch git
# will not delete — another worktree of this repository has it checked out —
# is refused with the directory already gone. Asserted because the pages that
# enumerate the refusals say "nothing was removed", and here that sentence is
# false: a report copying it would tell the user their run directory is still
# there.

merge_pr "$A" 106 feat/held
git -C "$A" worktree add "$TMP/held-wt" feat/held >/dev/null 2>&1
D=$(mk_task_dir "$A" feat/held)
OUT=$( ( cd "$A" && "$SH" "$SCRIPT" cleanup feat/held ) 2>"$TMP/held.err" ); CODE=$?
check "a branch another worktree holds is a refusal, not a silent skip" 1 "$CODE"
check "and git's answer stands — the branch is still there" yes \
  "$(git -C "$A" rev-parse --verify --quiet refs/heads/feat/held >/dev/null && echo yes || echo no)"
check "but the run directory it had already removed is gone" no \
  "$([ -e "$D" ] && echo yes || echo no)"
check "and stdout names that removal, which is what the report has to carry" yes \
  "$(printf '%s' "$OUT" | /usr/bin/grep -q '^removed ' && printf 'yes' || printf 'no')"
check "and the refusal names the branch it could not delete" yes \
  "$(/usr/bin/grep -q "local branch 'feat/held' could not be deleted" "$TMP/held.err" \
     && printf 'yes' || printf 'no')"
git -C "$A" worktree remove --force "$TMP/held-wt" >/dev/null 2>&1
git -C "$A" branch -q -D feat/held >/dev/null 2>&1

# --- the user-visible output ------------------------------------------------------

check "no arguments is usage, not a run" 2 "$("$SH" "$SCRIPT" >/dev/null 2>&1; printf '%s' "$?")"
check "help names both faces" yes \
  "$("$SH" "$SCRIPT" --help | /usr/bin/grep -q 'missing' && "$SH" "$SCRIPT" --help | /usr/bin/grep -q 'cleanup' && printf 'yes' || printf 'no')"
check "cleanup with no branch is refused about its own text" 2 \
  "$(arch_code "$A" cleanup)"
check "and the message is the face's own, not the general usage" yes \
  "$(arch_err "$A" cleanup | /usr/bin/grep -q 'cleanup takes exactly one argument' && printf 'yes' || printf 'no')"

# --- bash 3.2 compatibility -------------------------------------------------------
#
# macOS ships bash 3.2 as /bin/bash while the PATH bash is usually 5.x, so a
# 4.0+ construct passes here and breaks on a stock machine — silently, with a
# wrong value rather than a crash. Two of the three compatibility checks live
# here; the third (the construct sweep) reads every script at once and lives
# in sweep.test.sh.

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
    # would hide: a fresh repository with one unrecorded merge must list it
    # with nothing on stderr.
    PROBE="$TMP/probe-home"
    P="$TMP/wt-probe"
    mk_repo "$P" "git@example.com:acme/probe.git"
    merge_pr "$P" 7 feat/p
    HQ_HOME="$PROBE" "$SH" -c 'cd "$1" && "$2" "$3" missing' _ "$P" "$OLD_BASH" "$SCRIPT" \
      >"$TMP/probe.out" 2>"$TMP/probe.err"
    check "archive.sh writes nothing of its own to stderr under bash $OLD_VER" \
      0 "$(/usr/bin/grep -c . "$TMP/probe.err" | tr -d ' ')"
    check "and the probe listed the merge it was supposed to list" \
      7 "$(cut -f1 <"$TMP/probe.out")"

    # The same probe for cleanup's success path.
    PD=$(HQ_HOME="$PROBE" mk_task_dir "$P" feat/p)
    HQ_HOME="$PROBE" "$SH" -c 'cd "$1" && "$2" "$3" cleanup feat/p' _ "$P" "$OLD_BASH" "$SCRIPT" \
      >/dev/null 2>"$TMP/probe2.err"
    check "cleanup writes nothing of its own to stderr under bash $OLD_VER" \
      0 "$(/usr/bin/grep -c . "$TMP/probe2.err" | tr -d ' ')"
    check "and the probe's directory is gone" no "$([ -e "$PD" ] && echo yes || echo no)"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
    ok "SKIP no bash older than 4 on this machine — cleanup stderr check unverified"
    ok "SKIP no bash older than 4 on this machine — cleanup probe unverified"
  fi
fi

tap_end
