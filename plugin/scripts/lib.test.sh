#!/usr/bin/env bash
# Tests for lib.sh — the shared derivations.
#
# `hq_classify_file` decides whether a changed file gets a verifier at all,
# and `hq_resolve_base` decides what the diff is taken against — a wrong
# answer from either is invisible downstream, so both are exercised over
# their whole input shape rather than one happy case each.
#
# Run: bash plugin/scripts/lib.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB="$HERE/lib.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

. "$HERE/testlib.sh"

lib() { # <function> [args...]
  "$SH" "$LIB" "$@" 2>/dev/null
}

tap_begin

# --- hq_branch_dir ---------------------------------------------------------

check "branch dir: one slash"      feat-login  "$(lib hq_branch_dir feat/login)"
check "branch dir: several slashes" a-b-c      "$(lib hq_branch_dir a/b/c)"
check "branch dir: no slash"       develop     "$(lib hq_branch_dir develop)"

"$SH" "$LIB" hq_branch_dir >/dev/null 2>&1
check "branch dir: no argument is a usage error" 2 "$?"

# --- hq_classify_file ------------------------------------------------------
#
# The prose list is closed and everything else is code, so the checks that
# matter most are on the other side of that line: structured configuration,
# where a defect classified as prose would go unreviewed.

for f in a.sh a.bash a.py a.ts a.js a.go a.swift a.rb a.rs; do
  check "classify: $f is code" code "$(lib hq_classify_file "$f")"
done

for f in a.json a.yaml a.yml a.toml a.plist a.ini a.cfg a.conf a.xml; do
  check "classify: $f is code (machine-parsed configuration)" code "$(lib hq_classify_file "$f")"
done

for f in a.md a.markdown a.txt a.rst a.csv a.svg a.html a.htm a.css; do
  check "classify: $f is prose" prose "$(lib hq_classify_file "$f")"
done

check "classify: an extensionless file is code" code "$(lib hq_classify_file Makefile)"
check "classify: a dotfile with no extension is code" code "$(lib hq_classify_file .gitignore)"
check "classify: the extension is matched case-insensitively" prose "$(lib hq_classify_file README.MD)"
check "classify: a path is classified by its own extension" prose "$(lib hq_classify_file docs/notes.md)"

# A dotted directory holding a file with no extension. Both readings of the
# extension put this in code — see the note in lib.sh — so this pins the answer
# without claiming to separate them.
check "classify: a dotted directory with an extensionless file is code" \
  code "$(lib hq_classify_file config.d/Makefile)"

"$SH" "$LIB" hq_classify_file >/dev/null 2>&1
check "classify: no argument is a usage error" 2 "$?"

# --- fixtures for the git-backed functions ---------------------------------

mk_repo() { # <dir> [changed files...]
  local d=$1 f base
  shift
  mkdir -p "$d"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name t
  echo seed >"$d/seed.txt"
  git -C "$d" add -A
  git -C "$d" commit -q -m seed
  base=$(git -C "$d" rev-parse --abbrev-ref HEAD)
  git -C "$d" checkout -q -b topic
  for f in "$@"; do
    mkdir -p "$d/$(dirname "$f")"
    echo x >"$d/$f"
  done
  if [ $# -gt 0 ]; then
    git -C "$d" add -A
    git -C "$d" commit -q -m change
  fi
  printf '%s' "$base"
}

# --- hq_repo_key and hq_task_dir -------------------------------------------
#
# Where a run's working files live. These checks are what the single
# derivation owes every caller that queries it.
#
# HQ_HOME is passed per invocation rather than exported, so the default
# branch — the real ~/.hq — is exercised too; both functions only print.

home_lib() { # <HQ_HOME> <function> [args...]
  local h=$1
  shift
  HQ_HOME="$h" "$SH" "$LIB" "$@" 2>/dev/null
}

# A function rather than a `case` written inline: bash 3.2 cannot parse a case
# pattern's closing `)` inside a command substitution, and the replay at the
# bottom of this file is where that would surface.
leading_slash() { # <string>
  case "$1" in /*) printf 'yes' ;; *) printf 'no' ;; esac
}

CLONE_A="$TMP/clone-a"
mk_repo "$CLONE_A" >/dev/null
A_BRANCH=$(git -C "$CLONE_A" rev-parse --abbrev-ref HEAD)
CLONE_A_WT="$TMP/clone-a-worktree"
git -C "$CLONE_A" worktree add -q "$CLONE_A_WT" -b second >/dev/null 2>&1
CLONE_B="$TMP/clone-b"
mk_repo "$CLONE_B" >/dev/null

# The property the whole scheme rests on: the key names the CLONE. The
# fixture is worth nothing if the second worktree was not created, so that is
# asserted before the keys are compared.
check "repo key: the second worktree exists" yes \
  "$([ -d "$CLONE_A_WT" ] && printf 'yes' || printf 'no')"
check "repo key: it was not empty" yes \
  "$([ -n "$(lib hq_repo_key "$CLONE_A")" ] && printf 'yes' || printf 'no')"
check "repo key: every worktree of one clone answers the same key" yes \
  "$([ "$(lib hq_repo_key "$CLONE_A")" = "$(lib hq_repo_key "$CLONE_A_WT")" ] \
     && printf 'yes' || printf 'no')"
check "repo key: a different clone answers a different key" yes \
  "$([ "$(lib hq_repo_key "$CLONE_A")" != "$(lib hq_repo_key "$CLONE_B")" ] \
     && printf 'yes' || printf 'no')"

# `--git-common-dir` answers relative to where git ran, so a root that is not
# the top level has to resolve to the same place rather than to a key of its
# own.
mkdir -p "$CLONE_A/deep/er"
check "repo key: a subdirectory of the worktree answers the same key" yes \
  "$([ "$(lib hq_repo_key "$CLONE_A")" = "$(lib hq_repo_key "$CLONE_A/deep/er")" ] \
     && printf 'yes' || printf 'no')"

# The fold, and the leading slash. A key that kept its leading `/` would make
# `<home>/repos/<key>` an absolute path somewhere else entirely.
SPACEY="$TMP/two words@and.more"  # secrets-allow: a path fixture, not an address
mk_repo "$SPACEY" >/dev/null
check "repo key: nothing outside [A-Za-z0-9._-] survives the fold" "" \
  "$(lib hq_repo_key "$SPACEY" | tr -d 'A-Za-z0-9._-')"
check "repo key: the leading slash is gone" no \
  "$(leading_slash "$(lib hq_repo_key "$SPACEY")")"

"$SH" "$LIB" hq_repo_key "$TMP/not-a-repo" >/dev/null 2>&1
check "repo key: outside a repository is a usage error" 2 "$?"

KEY=$(lib hq_repo_key "$CLONE_A")

check "task dir: home, key and branch directory, in that order" \
  "$TMP/home/repos/$KEY/tasks/$A_BRANCH" \
  "$(home_lib "$TMP/home" hq_task_dir "$CLONE_A")"

check "task dir: the home defaults to ~/.hq" \
  "$HOME/.hq/repos/$KEY/tasks/$A_BRANCH" \
  "$( ( unset HQ_HOME; "$SH" "$LIB" hq_task_dir "$CLONE_A" 2>/dev/null ) )"

# A RELATIVE HOME IS REFUSED BY BOTH FACES. Everything is composed from it, so
# a relative value makes a run's files land relative to whatever directory the
# caller was in — for a hook, the repository being worked on.
#
# The second check is the one that matters: a command substitution swallows a
# non-zero return, and without propagating it the refusal turns into
# `/repos/…` at the filesystem root. Asked through hq_task_dir rather than
# hq_home directly — the home is not on the dispatch list, so a direct call
# answers the usage error's own exit 2, a check that would pass with the
# guard removed.
HQ_HOME=relative/home "$SH" "$LIB" hq_task_dir "$CLONE_A" >/dev/null 2>&1
check "task dir: the refusal reaches the caller rather than becoming /repos/…" 2 "$?"
check "task dir: and nothing is printed for it to use" "" \
  "$(HQ_HOME=relative/home "$SH" "$LIB" hq_task_dir "$CLONE_A" 2>/dev/null)"
check "task dir: the message names the variable that is wrong" yes \
  "$(HQ_HOME=relative/home "$SH" "$LIB" hq_task_dir "$CLONE_A" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'HQ_HOME' && printf 'yes' || printf 'no')"

check "task dir: a trailing slash on the home does not double up" \
  "$TMP/home/repos/$KEY/tasks/$A_BRANCH" \
  "$(home_lib "$TMP/home//" hq_task_dir "$CLONE_A")"

# AN ENVIRONMENT WITH NO HOME IS REFUSED BY NAME: left to `set -u`, the abort
# message goes nowhere (every caller reads through `2>/dev/null`) and the
# § Context lines print `unknown`. These checks turn on the prefix, not the
# exit code: `hq_home:` is this function speaking, `lib.sh: line NN:` is bash
# speaking about a line number nobody can act on.
( unset HOME HQ_HOME; "$SH" "$LIB" hq_task_dir "$CLONE_A" ) >/dev/null 2>&1
check "task dir: no HOME and no HQ_HOME is refused" 2 "$?"
check "task dir: and nothing is printed for it to use" "" \
  "$( ( unset HOME HQ_HOME; "$SH" "$LIB" hq_task_dir "$CLONE_A" 2>/dev/null ) )"
check "task dir: the refusal names the derivation, not a line of this file" yes \
  "$( ( unset HOME HQ_HOME; "$SH" "$LIB" hq_task_dir "$CLONE_A" 2>&1 >/dev/null ) \
     | /usr/bin/grep -q '^hq_home:' && printf 'yes' || printf 'no')"
check "task dir: and says which variable would settle it" yes \
  "$( ( unset HOME HQ_HOME; "$SH" "$LIB" hq_task_dir "$CLONE_A" 2>&1 >/dev/null ) \
     | /usr/bin/grep -q 'HQ_HOME' && printf 'yes' || printf 'no')"

# The other direction, and it is the one that keeps the guard honest: HOME is
# read ONLY when HQ_HOME does not answer. A guard placed before that branch
# would refuse an environment that has everywhere it needs.
check "task dir: HQ_HOME alone answers with no HOME in the environment" \
  "$TMP/home/repos/$KEY/tasks/$A_BRANCH" \
  "$( ( unset HOME; HQ_HOME="$TMP/home" "$SH" "$LIB" hq_task_dir "$CLONE_A" 2>/dev/null ) )"

git -C "$CLONE_A" checkout -q -b feat/deep/thing
check "task dir: the branch's slashes become dashes" \
  "$TMP/home/repos/$KEY/tasks/feat-deep-thing" \
  "$(home_lib "$TMP/home" hq_task_dir "$CLONE_A")"

check "task dir: an explicit branch overrides the checkout" \
  "$TMP/home/repos/$KEY/tasks/other-work" \
  "$(home_lib "$TMP/home" hq_task_dir "$CLONE_A" other/work)"

# The same branch worked from a second worktree of the same clone has to reach
# the same directory — otherwise the plan is invisible from one of them and a
# second one gets written.
check "task dir: a second worktree of the clone lands in the same place" yes \
  "$([ "$(home_lib "$TMP/home" hq_task_dir "$CLONE_A" feat/x)" \
     = "$(home_lib "$TMP/home" hq_task_dir "$CLONE_A_WT" feat/x)" ] \
     && printf 'yes' || printf 'no')"
check "task dir: a different clone does not" no \
  "$([ "$(home_lib "$TMP/home" hq_task_dir "$CLONE_A" feat/x)" \
     = "$(home_lib "$TMP/home" hq_task_dir "$CLONE_B" feat/x)" ] \
     && printf 'yes' || printf 'no')"

# A detached HEAD has no branch, so there is no directory any later reader
# would derive. Answering would file the run under `HEAD/`, where the next
# detached run would find it and read it as its own.
git -C "$CLONE_A" checkout -q --detach
"$SH" "$LIB" hq_task_dir "$CLONE_A" >/dev/null 2>&1
check "task dir: a detached HEAD is refused" 2 "$?"
check "task dir: and answers nothing at all" "" "$(lib hq_task_dir "$CLONE_A")"
git -C "$CLONE_A" checkout -q "$A_BRANCH"

"$SH" "$LIB" hq_task_dir "$TMP/not-a-repo" >/dev/null 2>&1
check "task dir: outside a repository is a usage error" 2 "$?"
check "task dir: and says so as a repository problem, not a branch one" yes \
  "$("$SH" "$LIB" hq_task_dir "$TMP/not-a-repo" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'not a git repository' && printf 'yes' || printf 'no')"

# --- hq_run_id -------------------------------------------------------------
#
# One identifier per cycle, and the file under the run's directory is what
# makes it survive the process that composed it: a second call has to answer
# what the first one wrote, not something new that looks just as well formed.

RUN_HOME="$TMP/run-home"
RUN_KEY=$(lib hq_repo_key "$CLONE_A")
RUN_DIR="$RUN_HOME/repos/$RUN_KEY/tasks/$A_BRANCH"

RUN_FIRST=$(home_lib "$RUN_HOME" hq_run_id "$CLONE_A")
check "run id: it answered at all" yes \
  "$([ -n "$RUN_FIRST" ] && printf 'yes' || printf 'no')"
check "run id: the file was created under the run's directory" yes \
  "$([ -f "$RUN_DIR/run_id" ] && printf 'yes' || printf 'no')"
check "run id: what it printed is what it wrote" "$RUN_FIRST" \
  "$(cat "$RUN_DIR/run_id" 2>/dev/null)"

# The property the whole change exists for. Two calls are two processes, and
# the second one must not compose anything.
check "run id: a second call answers the first one's value" "$RUN_FIRST" \
  "$(home_lib "$RUN_HOME" hq_run_id "$CLONE_A")"

# And it is READ, not re-derived to something that happens to match. A value
# no composition here could produce comes back verbatim.
printf 'pinned-cycle-identifier\n' >"$RUN_DIR/run_id"
check "run id: an existing file is read rather than recomposed" pinned-cycle-identifier \
  "$(home_lib "$RUN_HOME" hq_run_id "$CLONE_A")"

# The home is the one knob, and this file goes with everything else under it.
# Asked while the pinned value above is still in place: a derivation that
# ignored HQ_HOME and read the first home's file would answer the pinned
# identifier here, and a composed id cannot discriminate — both homes compose
# the same string.
RUN_HOME_B="$TMP/run-home-b"
RUN_B=$(home_lib "$RUN_HOME_B" hq_run_id "$CLONE_A")
check "run id: HQ_HOME decides which file is read" yes \
  "$([ -f "$RUN_HOME_B/repos/$RUN_KEY/tasks/$A_BRANCH/run_id" ] && printf 'yes' || printf 'no')"
check "run id: and a different home is a different cycle" no \
  "$([ "$RUN_B" = pinned-cycle-identifier ] && printf 'yes' || printf 'no')"

# A torn write leaves a file with nothing in it, which is not an identifier.
# Returning it would put an empty run_id on every row from then on, and the
# noclobber write below would never replace it.
: >"$RUN_DIR/run_id"
RUN_AFTER_EMPTY=$(home_lib "$RUN_HOME" hq_run_id "$CLONE_A")
check "run id: an empty file is replaced rather than returned" yes \
  "$([ -n "$RUN_AFTER_EMPTY" ] && printf 'yes' || printf 'no')"

# A branch is a cycle, so two branches of one clone do not share an identifier
# — the composed value carries the branch's directory name for that reason.
RUN_OTHER=$(home_lib "$RUN_HOME" hq_run_id "$CLONE_A" other/work)
check "run id: another branch gets its own" no \
  "$([ "$RUN_OTHER" = "$(home_lib "$RUN_HOME" hq_run_id "$CLONE_A")" ] \
     && printf 'yes' || printf 'no')"
check "run id: which is filed under that branch's directory" yes \
  "$([ -f "$RUN_HOME/repos/$RUN_KEY/tasks/other-work/run_id" ] && printf 'yes' || printf 'no')"

# Where there is no cycle to name, nothing is printed. The recorder reads this
# through a command substitution and falls back to a per-call value; a printed
# path fragment or an error line would become the identifier on every row.
git -C "$CLONE_A" checkout -q --detach
"$SH" "$LIB" hq_run_id "$CLONE_A" >/dev/null 2>&1
check "run id: a detached HEAD is refused" 2 "$?"
check "run id: and answers nothing at all" "" \
  "$(HQ_HOME="$RUN_HOME" "$SH" "$LIB" hq_run_id "$CLONE_A" 2>/dev/null)"
git -C "$CLONE_A" checkout -q "$A_BRANCH"

"$SH" "$LIB" hq_run_id "$TMP/not-a-repo" >/dev/null 2>&1
check "run id: outside a repository is refused" 2 "$?"
check "run id: and nothing is printed for it to use" "" \
  "$("$SH" "$LIB" hq_run_id "$TMP/not-a-repo" 2>/dev/null)"

HQ_HOME=relative/home "$SH" "$LIB" hq_run_id "$CLONE_A" >/dev/null 2>&1
check "run id: a relative home is refused rather than followed" 2 "$?"
check "run id: and nothing was written where it pointed" no \
  "$([ -e "relative/home" ] && printf 'yes' || printf 'no')"

# --- hq_resolve_base -------------------------------------------------------

R1="$TMP/base-settings"
mk_repo "$R1" >/dev/null
mkdir -p "$R1/.hq"
printf '{\n  "base_branch": "develop"\n}\n' >"$R1/.hq/settings.json"
check "resolve base: settings.json wins" develop "$(lib hq_resolve_base "$R1")"

# No remote and no settings file: the chain has to reach its last step rather
# than return empty.
R2="$TMP/base-fallback"
mk_repo "$R2" >/dev/null
check "resolve base: falls back to main" main "$(lib hq_resolve_base "$R2")"

# A settings file that exists but says nothing about the base branch must not
# stop the chain.
R3="$TMP/base-silent-settings"
mk_repo "$R3" >/dev/null
mkdir -p "$R3/.hq"
printf '{\n  "rail_exclude_paths": ["a"]\n}\n' >"$R3/.hq/settings.json"
check "resolve base: an unrelated settings file falls through" main "$(lib hq_resolve_base "$R3")"

# Whitespace around the colon, and the value not being the first key.
R4="$TMP/base-spacing"
mk_repo "$R4" >/dev/null
mkdir -p "$R4/.hq"
printf '{"a":1,"base_branch"   :    "trunk","b":2}\n' >"$R4/.hq/settings.json"
check "resolve base: spacing and key order do not matter" trunk "$(lib hq_resolve_base "$R4")"

# origin/HEAD, when there is no settings file. Set directly rather than by
# fetching: the check is the `origin/` strip, not git's remote protocol.
R5="$TMP/base-remote"
mk_repo "$R5" >/dev/null
git -C "$R5" remote add origin https://example.com/acme/widget.git
git -C "$R5" update-ref refs/remotes/origin/trunk "$(git -C "$R5" rev-parse HEAD)"
git -C "$R5" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
check "resolve base: origin/HEAD is used with the prefix stripped" \
  trunk "$(lib hq_resolve_base "$R5")"

"$SH" "$LIB" hq_resolve_base "$TMP/not-a-repo" >/dev/null 2>&1
check "resolve base: outside a repository is a usage error" 2 "$?"

# --- hq_verifier_for -------------------------------------------------------
#
# One verifier today, taking both classes. These checks pin that mapping rather
# than assert it is right — when a second verifier arrives they are what says
# which files moved.

check "verifier: code goes to the reviewer"  reviewer "$(lib hq_verifier_for a.sh)"
check "verifier: prose goes to the reviewer" reviewer "$(lib hq_verifier_for a.md)"

"$SH" "$LIB" hq_verifier_for >/dev/null 2>&1
check "verifier: no argument is a usage error" 2 "$?"

# --- hq_review_targets and hq_diff_profile ---------------------------------

MIXED="$TMP/diff-mixed"
BASE=$(mk_repo "$MIXED" src/app.sh docs/readme.md config/plugin.json)
check "review targets: every changed file is paired with a verifier" \
  "reviewer	config/plugin.json reviewer	docs/readme.md reviewer	src/app.sh" \
  "$(lib hq_review_targets "$BASE" HEAD "$MIXED" | sort | tr '\n' ' ' | sed 's/ $//')"
check "diff profile: code and prose together are mixed" \
  mixed "$(lib hq_diff_profile "$BASE" HEAD "$MIXED")"

CODE="$TMP/diff-code"
BASE=$(mk_repo "$CODE" src/app.sh src/other.py)
check "diff profile: code only" code "$(lib hq_diff_profile "$BASE" HEAD "$CODE")"
check "review targets: both are listed" 2 "$(lib hq_review_targets "$BASE" HEAD "$CODE" | wc -l | tr -d ' ')"

# The mapping covers prose as well as code — under a code-only rule this
# would list nothing at all.
PROSE="$TMP/diff-prose"
BASE=$(mk_repo "$PROSE" docs/a.md docs/b.md)
check "diff profile: prose only" prose "$(lib hq_diff_profile "$BASE" HEAD "$PROSE")"
check "review targets: a prose-only diff still has targets" 2 \
  "$(lib hq_review_targets "$BASE" HEAD "$PROSE" | wc -l | tr -d ' ')"

EMPTY="$TMP/diff-empty"
BASE=$(mk_repo "$EMPTY")
check "diff profile: an empty diff is none" none "$(lib hq_diff_profile "$BASE" HEAD "$EMPTY")"
check "review targets: an empty diff lists nothing" "" "$(lib hq_review_targets "$BASE" HEAD "$EMPTY")"

# --- a diff that cannot be taken is not an empty diff ----------------------
#
# These two states produce identical output — nothing — and the caller reads
# nothing as "no changes, no review needed"; the exit code is what separates
# them.

UNRESOLVED="$TMP/diff-unresolved"
mk_repo "$UNRESOLVED" src/app.sh >/dev/null

"$SH" "$LIB" hq_review_targets no-such-branch HEAD "$UNRESOLVED" >/dev/null 2>&1
check "review targets: an unresolvable base exits 3, not 0" 3 "$?"
"$SH" "$LIB" hq_diff_profile no-such-branch HEAD "$UNRESOLVED" >/dev/null 2>&1
check "diff profile: an unresolvable base exits 3, not 0" 3 "$?"

check "review targets: the git error reaches stderr rather than being swallowed" yes \
  "$("$SH" "$LIB" hq_review_targets no-such-branch HEAD "$UNRESOLVED" 2>&1 >/dev/null \
     | /usr/bin/grep -q 'no-such-branch' && printf 'yes' || printf 'no')"

# The same repository with a base that does resolve must still succeed — an
# error path that fires on everything would be worse than the silence it
# replaced.
"$SH" "$LIB" hq_review_targets "$(git -C "$UNRESOLVED" rev-list --max-parents=0 HEAD)" HEAD "$UNRESOLVED" >/dev/null 2>&1
check "review targets: a resolvable base still exits 0" 0 "$?"

# A path with a space has to survive the read loop; the pipeline splits on
# newlines only.
SPACED="$TMP/diff-spaced"
BASE=$(mk_repo "$SPACED" "src/two words.sh")
check "review targets: a path with a space stays one entry" \
  "reviewer	src/two words.sh" "$(lib hq_review_targets "$BASE" HEAD "$SPACED")"

"$SH" "$LIB" hq_diff_profile >/dev/null 2>&1
check "diff profile: no argument is a usage error" 2 "$?"

# --- hq_changed_files, as a face of its own --------------------------------
#
# The two functions above are both built on it, and it is dispatchable so
# that a caller outside this file can ask the same question rather than
# implement "what changed" a second time; the face has the same three
# outcomes checked as the callers that wrap it.

BASE=$(mk_repo "$TMP/changed" src/app.sh docs/a.md)
check "changed files: every changed path is listed, one per line" \
  "docs/a.md src/app.sh" \
  "$(lib hq_changed_files "$BASE" HEAD "$TMP/changed" | sort | tr '\n' ' ' | sed 's/ $//')"
check "changed files: an empty diff lists nothing" "" \
  "$(lib hq_changed_files "$(mk_repo "$TMP/changed-empty")" HEAD "$TMP/changed-empty")"
"$SH" "$LIB" hq_changed_files no-such-branch HEAD "$UNRESOLVED" >/dev/null 2>&1
check "changed files: an unresolvable base exits 3, not 0" 3 "$?"
"$SH" "$LIB" hq_changed_files >/dev/null 2>&1
check "changed files: no argument is a usage error" 2 "$?"

# git writes to stderr while exiting 0, and everything this function prints is
# read as a path by somebody: the verifier is handed one, a telemetry row is
# labelled from one, a plan's declared surface is compared against one.
# Folding the streams would turn three lines of trace into three files nobody
# wrote.
#
# GIT_TRACE is the trigger used here because it is deterministic and needs no
# broken environment. Whether this git actually traces is PROBED rather than
# assumed — a git that stayed silent would make the check below pass while
# testing nothing.
CHANGED="$TMP/changed"
TRACE_PROBE=$(GIT_TRACE=1 git -C "$CHANGED" diff --name-only "$BASE...HEAD" 2>&1 >/dev/null)
if [ -n "$TRACE_PROBE" ]; then
  check "changed files: what git writes to stderr is not listed as a path" \
    "docs/a.md src/app.sh" \
    "$(GIT_TRACE=1 "$SH" "$LIB" hq_changed_files "$BASE" HEAD "$CHANGED" 2>/dev/null \
       | sort | tr '\n' ' ' | sed 's/ $//')"
  check "changed files: and it still reaches stderr rather than being swallowed" yes \
    "$(GIT_TRACE=1 "$SH" "$LIB" hq_changed_files "$BASE" HEAD "$CHANGED" 2>&1 >/dev/null \
       | /usr/bin/grep -q 'trace' && printf 'yes' || printf 'no')"
  check "review targets: a traced run still lists only the changed files" 2 \
    "$(GIT_TRACE=1 "$SH" "$LIB" hq_review_targets "$BASE" HEAD "$CHANGED" 2>/dev/null | wc -l | tr -d ' ')"
  check "diff profile: a traced run still classifies the diff itself" mixed \
    "$(GIT_TRACE=1 "$SH" "$LIB" hq_diff_profile "$BASE" HEAD "$CHANGED" 2>/dev/null)"
else
  ok "SKIP this git writes nothing to stderr under GIT_TRACE — stream separation unverified"
  ok "SKIP — stderr forwarding unverified"
  ok "SKIP — review targets under trace unverified"
  ok "SKIP — diff profile under trace unverified"
fi

"$SH" "$LIB" hq_not_a_function >/dev/null 2>&1
check "dispatch: an unknown function is a usage error" 2 "$?"

# --- bash 3.2 compatibility ------------------------------------------------
#
# Two of the three faces; the construct sweep is the runner's.

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

    ERR="$TMP/err.txt"
    : >"$ERR"
    "$OLD_BASH" "$LIB" hq_branch_dir feat/x >/dev/null 2>>"$ERR"
    "$OLD_BASH" "$LIB" hq_repo_key "$CLONE_A" >/dev/null 2>>"$ERR"
    HQ_HOME="$TMP/home" "$OLD_BASH" "$LIB" hq_task_dir "$CLONE_A" >/dev/null 2>>"$ERR"
    "$OLD_BASH" "$LIB" hq_classify_file a.json >/dev/null 2>>"$ERR"
    "$OLD_BASH" "$LIB" hq_resolve_base "$R1" >/dev/null 2>>"$ERR"
    "$OLD_BASH" "$LIB" hq_review_targets "$BASE" HEAD "$MIXED" >/dev/null 2>>"$ERR"
    "$OLD_BASH" "$LIB" hq_diff_profile "$BASE" HEAD "$MIXED" >/dev/null 2>>"$ERR"
    check "lib.sh writes nothing to stderr under bash $OLD_VER" "" "$(cat "$ERR")"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
