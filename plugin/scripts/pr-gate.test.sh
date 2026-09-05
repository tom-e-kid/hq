#!/usr/bin/env bash
# Tests for pr-gate.sh — the conditions checked when a pull request is opened.
#
# Every condition is exercised from both sides: a gate's failure mode is that
# it stops noticing while staying green, so each condition is shown a tree
# that violates it AND the adjacent tree that does not — a gate that denies
# everything stops the work just as surely.
#
# The paths that must NOT fire have their own section: a branch with no plan,
# a repository with no changelog, a machine with no scanner, a Bash call that
# has nothing to do with pull requests — every one a state a person is
# entitled to be in.
#
# Run: bash plugin/scripts/pr-gate.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATE="$HERE/pr-gate.sh"
LIB="$HERE/lib.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# The gate derives the plan's path from the home; pointing the home at the
# fixture directory is what keeps the suite off the developer's real one.
export HQ_HOME="$TMP/home"

. "$HERE/testlib.sh"

tap_begin

# --- fixtures ---------------------------------------------------------------

# A repository with a changelog on its base branch and a topic branch checked
# out. The base is written into .hq/settings.json rather than assumed: git's
# default branch name differs between installations.
mk_repo() { # <dir> — prints the base branch name
  local d=$1 base
  mkdir -p "$d/.hq"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name t
  printf 'seed\n' >"$d/seed.txt"
  printf '# Changelog\n\n## [Unreleased]\n' >"$d/CHANGELOG.md"
  git -C "$d" add -A
  git -C "$d" commit -q -m seed
  # Taken after the first commit: on a repository with no commits at all
  # `--abbrev-ref HEAD` has nothing to answer with.
  base=$(git -C "$d" rev-parse --abbrev-ref HEAD)
  printf '{"base_branch": "%s"}\n' "$base" >"$d/.hq/settings.json"
  git -C "$d" add -A
  git -C "$d" commit -q -m settings
  git -C "$d" checkout -q -b feat/thing
  printf '%s' "$base"
}

REPO="$TMP/repo"
BASE=$(mk_repo "$REPO")

TASK=$("$SH" "$LIB" hq_task_dir "$REPO" 2>/dev/null)
check "the fixture's run directory was derived at all" yes \
  "$([ -n "$TASK" ] && printf 'yes' || printf 'no')"
mkdir -p "$TASK"
P="$TASK/plan.md"

# A plan carrying exactly the two sections this gate reads. Written whole each
# time so that one case cannot leave state in the next.
plan_with() { # <## Plan body> <## Floor body>
  cat >"$P" <<EOF
# a plan

## Plan

$1

## Floor

$2
EOF
}

DONE_PLAN='- [x] the one item'
DONE_ACC='- [x] [auto] `true`'

# The tree every case departs from: plan finished, floor finished, nothing
# uncommitted, changelog in the diff.
clean_tree() {
  plan_with "$DONE_PLAN" "$DONE_ACC"
  printf 'work\n' >"$REPO/a.txt"
  printf '# Changelog\n\n## [Unreleased]\n\n- something\n' >"$REPO/CHANGELOG.md"
  git -C "$REPO" add -A
  # Silenced: after the first call there is often nothing left to commit, and
  # git says so on stdout — the stream this suite's TAP output travels on.
  git -C "$REPO" commit -q -m "feat: the work" >/dev/null 2>&1 || true
}

# Runs the gate and fills GATE_OUT and GATE_CODE. The whole command line is
# passed in, because a command substitution runs in a subshell — assigning the
# exit code inside one and reading it outside is a variable that is never set.
run_check() { # <command...>
  GATE_OUT=$("$@" 2>&1)
  GATE_CODE=$?
}

says() { # <pattern> — yes when the last gate output carried it
  printf '%s' "$GATE_OUT" | /usr/bin/grep -q "$1" && printf 'yes' || printf 'no'
}

GATE_OUT=""
GATE_CODE=0

# --- the clean tree, which must pass ----------------------------------------
#
# First, because a gate that denies unconditionally would pass every later
# check that expects a violation.

clean_tree
run_check "$SH" "$GATE" check "$REPO"
check "a finished branch: exit 0" 0 "$GATE_CODE"
check "a finished branch: nothing said" "" "$GATE_OUT"

# --- condition 1: unchecked ## Plan items ------------------------------------

plan_with "$DONE_PLAN
- [ ] the item nobody did" "$DONE_ACC"
run_check "$SH" "$GATE" check "$REPO"
check "an unchecked plan item: exit 1" 1 "$GATE_CODE"
check "an unchecked plan item is named" yes "$(says 'the item nobody did')"
check "and the finished one is not" no "$(says 'the one item')"

# The section boundary: items in a section the gate does not read are outside it,
# and counting them would deny every pull request that has any.
cat >"$P" <<EOF
# a plan

## Plan

$DONE_PLAN

## Floor

$DONE_ACC

## Notes

- [ ] somebody looks at the screen
EOF
run_check "$SH" "$GATE" check "$REPO"
check "an unchecked item outside the two sections read is not a violation: exit 0" 0 "$GATE_CODE"
check "and is not named" no "$(says 'looks at the screen')"

# A fenced code block quoting a heading must not end the section. The heading
# inside the fence is a DIFFERENT one on purpose: quoting `## Plan` there
# would re-enter the section a broken scan had just left — a fixture that
# passes whatever the rule does.
cat >"$P" <<EOF
# a plan

## Plan

$DONE_PLAN

\`\`\`
## Floor
\`\`\`

- [ ] the item after the fence

## Floor

$DONE_ACC
EOF
run_check "$SH" "$GATE" check "$REPO"
check "an item after a fenced heading is still counted: exit 1" 1 "$GATE_CODE"
check "and named under the section it is actually in" yes   "$(says '## Plan has an unchecked item: - \[ \] the item after the fence')"

# THE CLOSING BRACKET NEEDS NOTHING AFTER IT. plan-gate.sh reads `- [ ]item`
# and a bare `- [ ]` as checkbox items, so a plan spelled either way passes the
# shape gate — and a scan here that demanded a space would return an empty
# count for it, which is the same empty count a finished plan produces.
plan_with "$DONE_PLAN
- [ ]no space after the bracket" "$DONE_ACC"
run_check "$SH" "$GATE" check "$REPO"
check "an unchecked item with no space after the bracket: exit 1" 1 "$GATE_CODE"
check "and is named" yes "$(says 'no space after the bracket')"

plan_with "$DONE_PLAN
- [ ]" "$DONE_ACC"
run_check "$SH" "$GATE" check "$REPO"
check "an unchecked box carrying no text at all: exit 1" 1 "$GATE_CODE"
check "and is named" yes "$(says '## Plan has an unchecked item: - \[ \]$')"

# The checked spelling on the same terms: reading `- [x]done` as no checkbox
# would deny a finished plan over the spelling of its own items.
plan_with "- [x]no space after this bracket either" "$DONE_ACC"
run_check "$SH" "$GATE" check "$REPO"
check "a plan whose checked items have no space after the bracket: exit 0" 0 "$GATE_CODE"
check "a plan whose checked items have no space after the bracket: nothing said" \
  "" "$GATE_OUT"

# --- condition 2: a ## Plan item condition 1 cannot see ----------------------
#
# A plan whose items are a numbered list makes condition 1 answer "nothing
# outstanding" on every call — the same empty count a finished plan produces.
#
# THE CONDITION ASKS WHETHER EVERY ITEM IS A CHECKBOX, not whether any item
# is: a reading that raised a flag on the first checkbox it met would let the
# mixed case below pass both faces with three outstanding items. The mixed
# case is checked first, because the all-numbered case passes under either
# reading.

plan_with "- [x] set the scene
1. NOT DONE the first thing
2. NOT DONE the second thing" "$DONE_ACC"
run_check "$SH" "$GATE" check "$REPO"
check "one checkbox beside two numbered items: exit 1" 1 "$GATE_CODE"
check "and names the first item the count cannot see" yes \
  "$(says '1\. NOT DONE the first thing')"
check "and names the second one too, rather than stopping at one" yes \
  "$(says '2\. NOT DONE the second thing')"
check "and does not name the checkbox item, which is readable" no \
  "$(says 'set the scene')"

plan_with "1. the first thing
2. the second thing" "$DONE_ACC"
run_check "$SH" "$GATE" check "$REPO"
check "a plan written without checkboxes: exit 1" 1 "$GATE_CODE"
check "and names an item the count cannot see" yes "$(says 'the first thing')"

# A section holding prose and no list at all: its count is empty for a third
# reason again, and each empty count is reported as its own thing.
plan_with "the work is described here in prose, with no list at all." "$DONE_ACC"
run_check "$SH" "$GATE" check "$REPO"
check "a ## Plan holding no list item: exit 1" 1 "$GATE_CODE"
check "and says there was nothing to read" yes "$(says 'nothing to read')"

# The adjacent tree that must NOT fire: without this the condition could deny
# every plan and every check above would still pass.
plan_with "- [x] the first thing
- [x] the second thing
- [x] the third thing" "$DONE_ACC"
run_check "$SH" "$GATE" check "$REPO"
check "a plan whose items are all checked checkboxes: exit 0" 0 "$GATE_CODE"
check "a plan whose items are all checked checkboxes: nothing said" "" "$GATE_OUT"

cat >"$P" <<EOF
# a plan

## Floor

$DONE_ACC
EOF
run_check "$SH" "$GATE" check "$REPO"
check "a plan with no ## Plan section at all: exit 1" 1 "$GATE_CODE"
check "and says there was nothing to count" yes "$(says 'nothing to count')"

# THE OTHER SECTION, MISSING. An absent `## Floor` produces the same empty
# count as one whose items are all checked, and the two other readers of that
# section — hq:pr and the verifier — each run the items they find. So a plan
# without it has its build, types, linter and tests run by nobody, and this
# gate, that module and the verifier all report nothing wrong. The way in is a
# plan written before the section existed: the shape check runs when a plan is
# WRITTEN, and a file already on disk is never written again.
cat >"$P" <<EOF
# a plan

## Plan

$DONE_PLAN
EOF
run_check "$SH" "$GATE" check "$REPO"
check "a plan with no ## Floor section at all: exit 1" 1 "$GATE_CODE"
check "and says no machine check was run" yes "$(says 'no machine check was named')"

# An item the count cannot see, in the section whose whole job is to name the
# commands somebody runs.
plan_with "$DONE_PLAN" "- [x] [auto] \`true\`
- not a checkbox at all"
run_check "$SH" "$GATE" check "$REPO"
check "a ## Floor item that is not a checkbox: exit 1" 1 "$GATE_CODE"
check "and is named" yes "$(says 'not a checkbox')"

# A `## Floor` heading with nothing under it: the count is empty for the third
# possible reason, and it is not a pass either.
plan_with "$DONE_PLAN" ""
run_check "$SH" "$GATE" check "$REPO"
check "an empty ## Floor section: exit 1" 1 "$GATE_CODE"
check "and says the count came back empty for want of anything to read" yes \
  "$(says 'holds no item at all')"

# --- condition 3: unchecked ## Floor items ------------------------------

plan_with "$DONE_PLAN" "$DONE_ACC
- [ ] [auto] \`false\`"
run_check "$SH" "$GATE" check "$REPO"
check "an unchecked floor item: exit 1" 1 "$GATE_CODE"
check "and is named as a floor item" yes "$(says '## Floor has an unchecked item')"

# The same spelling under the other heading: a check that only exercised
# `## Plan` would not notice the day the two stop being the same scan.
plan_with "$DONE_PLAN" "$DONE_ACC
- [ ][auto] \`false\`"
run_check "$SH" "$GATE" check "$REPO"
check "an unchecked floor item with no space after the bracket: exit 1" \
  1 "$GATE_CODE"
check "and is named as a floor item" yes "$(says '## Floor has an unchecked item')"

# --- condition 4: a dirty working tree ---------------------------------------

clean_tree
printf 'never added\n' >"$REPO/untracked.txt"
run_check "$SH" "$GATE" check "$REPO"
check "an untracked file: exit 1" 1 "$GATE_CODE"
check "and is named" yes "$(says 'untracked.txt')"

rm -f "$REPO/untracked.txt"
printf 'edited\n' >>"$REPO/a.txt"
run_check "$SH" "$GATE" check "$REPO"
check "an uncommitted edit: exit 1" 1 "$GATE_CODE"
check "and is named" yes "$(says 'a.txt')"

# Nothing is excluded: a run's files are outside the repository, so a path
# under `.hq` is a repository fact like any other, and a stale exclusion is a
# hole nobody can see from inside the gate.
git -C "$REPO" checkout -q -- a.txt
printf 'a note\n' >"$REPO/.hq/knowledge.md"
run_check "$SH" "$GATE" check "$REPO"
check "an uncommitted file under .hq is not excluded: exit 1" 1 "$GATE_CODE"
check "and is named" yes "$(says 'knowledge.md')"
rm -f "$REPO/.hq/knowledge.md"

# --- condition 5: the changelog ----------------------------------------------
#
# The failure this catches is writing nothing at all, which is what the
# deliberately weak predicate is for.

# Branched from the BASE rather than from the branch above: a branch that
# inherits the changelog commit has it in its diff, satisfying the condition
# for a reason the fixture did not intend.
git -C "$REPO" checkout -q -b feat/no-changelog "$BASE"
printf 'more\n' >"$REPO/b.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "feat: no changelog entry"
NOCL_TASK=$("$SH" "$LIB" hq_task_dir "$REPO" 2>/dev/null)
mkdir -p "$NOCL_TASK"
cat >"$NOCL_TASK/plan.md" <<EOF
# a plan

## Plan

$DONE_PLAN

## Floor

$DONE_ACC
EOF
run_check "$SH" "$GATE" check "$REPO"
check "a branch that never touched the changelog: exit 1" 1 "$GATE_CODE"
check "and the file is named" yes "$(says 'CHANGELOG.md is not in the diff')"

printf '# Changelog\n\n## [Unreleased]\n\n- and now an entry\n' >"$REPO/CHANGELOG.md"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "docs: changelog"
run_check "$SH" "$GATE" check "$REPO"
check "adding the entry clears it: exit 0" 0 "$GATE_CODE"
check "adding the entry clears it: nothing said" "" "$GATE_OUT"

git -C "$REPO" checkout -q feat/thing

# --- the paths that must not fire -------------------------------------------

# A branch with no plan. Ordinary: not every branch has one, and the three
# conditions that read a plan simply do not apply.
clean_tree
rm -f "$P"
run_check "$SH" "$GATE" check "$REPO"
check "a branch with no plan: exit 0" 0 "$GATE_CODE"
check "a branch with no plan: nothing said" "" "$GATE_OUT"
plan_with "$DONE_PLAN" "$DONE_ACC"

# A repository with no changelog. The rule belongs to repositories that keep
# one; this plugin is installed in others.
NOCHANGE="$TMP/no-changelog"
NC_BASE=$(mk_repo "$NOCHANGE")
git -C "$NOCHANGE" rm -q CHANGELOG.md
printf 'work\n' >"$NOCHANGE/a.txt"
git -C "$NOCHANGE" add -A
git -C "$NOCHANGE" commit -q -m "feat: no changelog in this repository"
run_check "$SH" "$GATE" check "$NOCHANGE"
check "a repository with no changelog: exit 0" 0 "$GATE_CODE"
check "a repository with no changelog: nothing said" "" "$GATE_OUT"

# --- what could not be looked at is not a pass -------------------------------
#
# A condition nobody could evaluate reads exactly like one that passed. The
# check face says so and exits non-zero for it; the hook stays silent — the
# same judgement taken about different readers.

clean_tree
run_check env HQ_AWK=no-such-scanner "$SH" "$GATE" check "$REPO"
check "no scanner: exit 2 rather than 0" 2 "$GATE_CODE"
check "and it says the plan was not read" yes "$(says '^unchecked: the plan')"
check "naming what it looked for" yes "$(says 'no-such-scanner')"

# A violation outranks a not-checked condition, or a caller reading only the
# exit code treats a real violation as an unavailable check.
printf 'never added\n' >"$REPO/untracked.txt"
run_check env HQ_AWK=no-such-scanner "$SH" "$GATE" check "$REPO"
check "a violation beside an unchecked condition: exit 1" 1 "$GATE_CODE"
check "and both are reported" yes \
  "$(printf '%s' "$GATE_OUT" | /usr/bin/grep -q 'untracked.txt' \
     && printf '%s' "$GATE_OUT" | /usr/bin/grep -q '^unchecked:' && printf 'yes' || printf 'no')"
rm -f "$REPO/untracked.txt"

# A copy with no lib.sh beside it can neither find the plan nor take the diff.
# Both have to come back as unchecked rather than as nothing to report.
ORPHAN="$TMP/orphan"
mkdir -p "$ORPHAN"
cp "$GATE" "$ORPHAN/pr-gate.sh"
clean_tree
run_check "$SH" "$ORPHAN/pr-gate.sh" check "$REPO"
check "a gate with no lib.sh beside it: exit 2" 2 "$GATE_CODE"
check "and says the plan could not be located" yes "$(says 'no run directory')"
check "and that the changelog was not checked" yes "$(says 'CHANGELOG.md was not checked')"

# --- the hook face ----------------------------------------------------------

payload() { # <command> [<cwd>]
  python3 -c '
import json, sys
o = {
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[1], "description": "a description"},
}
if len(sys.argv) > 2:
    o["cwd"] = sys.argv[2]
print(json.dumps(o))' "$@"
}

run_hook() { # <payload> — prints the exit code, output in $TMP/hook.out
  printf '%s' "$1" | "$SH" "$GATE" hook >"$TMP/hook.out" 2>"$TMP/hook.err"
  printf '%s' "$?"
}

run_hook_in() { # <dir> <payload>
  printf '%s' "$2" | ( cd "$1" && "$SH" "$GATE" hook ) \
    >"$TMP/hook.out" 2>"$TMP/hook.err"
  printf '%s' "$?"
}

field() { # <dotted key> — read out of the last hook output
  python3 -c '
import json, sys
o = json.load(open(sys.argv[1]))
for p in sys.argv[2].split("."):
    o = o[p]
print(o)' "$TMP/hook.out" "$1" 2>/dev/null
}

CREATE=$(payload 'gh pr create --base develop --title x --body y' "$REPO")

clean_tree
check "a finished branch: the hook exits 0" 0 "$(run_hook "$CREATE")"
check "a finished branch: and says nothing" "" "$(cat "$TMP/hook.out")"

plan_with "$DONE_PLAN
- [ ] the item nobody did" "$DONE_ACC"
check "an unchecked item: the hook still exits 0" 0 "$(run_hook "$CREATE")"
check "but denies" deny "$(field hookSpecificOutput.permissionDecision)"
check "and the reason names the item" yes \
  "$(field hookSpecificOutput.permissionDecisionReason \
     | /usr/bin/grep -q 'the item nobody did' && printf 'yes' || printf 'no')"
check "and the event name is the one the harness reads" PreToolUse \
  "$(field hookSpecificOutput.hookEventName)"
check "and nothing went to stderr" "" "$(cat "$TMP/hook.err")"

# The reason is JSON the caller parses: one unescaped control byte makes the
# object unreadable, and a deny nobody can parse is a deny that did not
# happen.
plan_with "$DONE_PLAN
- [ ] an item with a \"quote\" and a backslash \\ in it" "$DONE_ACC"
run_hook "$CREATE" >/dev/null
check "a plan item carrying JSON metacharacters still parses" yes \
  "$(python3 -c 'import json,sys;json.load(open(sys.argv[1]));print("yes")' \
     "$TMP/hook.out" 2>/dev/null || printf 'no')"

# The session's directory comes out of the payload: without it the answer
# would come from wherever the harness happened to run the hook.
mkdir -p "$REPO/deep/er"
check "the repository is found from the payload's cwd" deny \
  "$(run_hook "$(payload 'gh pr create' "$REPO/deep/er")" >/dev/null; \
     field hookSpecificOutput.permissionDecision)"

# And without one, from where the hook is running.
check "with no cwd in the payload it falls back to its own" deny \
  "$(run_hook_in "$REPO" "$(payload 'gh pr create')" >/dev/null; \
     field hookSpecificOutput.permissionDecision)"

# --- everything the hook must ignore ----------------------------------------
#
# This fires on every Bash call in every repository the plugin is installed in.
# A false deny does not annoy; it stops the work.

check "a Bash call that is not creating a pull request: exits 0" 0 \
  "$(run_hook "$(payload 'git status --porcelain' "$REPO")")"
check "a Bash call that is not creating a pull request: says nothing" "" \
  "$(cat "$TMP/hook.out")"

check "an unparseable payload: exits 0" 0 "$(run_hook 'not json {{{')"
check "an unparseable payload: says nothing" "" "$(cat "$TMP/hook.out")"

check "an empty payload: exits 0" 0 "$(run_hook '')"
check "an empty payload: says nothing" "" "$(cat "$TMP/hook.out")"

check "outside a repository: exits 0" 0 \
  "$(run_hook_in "$TMP" "$(payload 'gh pr create')")"
check "outside a repository: says nothing" "" "$(cat "$TMP/hook.out")"

# The fail-open direction that matters most: with the scanner gone the hook
# cannot read the plan, and denying on that would stop a run for the gate's own
# failure. The check face above says so instead.
clean_tree
printf '%s' "$CREATE" | ( HQ_AWK=no-such-scanner "$SH" "$GATE" hook ) \
  >"$TMP/hook.out" 2>"$TMP/hook.err"
check "no scanner: the hook exits 0" 0 "$?"
check "no scanner: and says nothing rather than denying" "" "$(cat "$TMP/hook.out")"

# --- usage ------------------------------------------------------------------

"$SH" "$GATE" >/dev/null 2>&1
check "no mode is a usage error" 2 "$?"
"$SH" "$GATE" nonsense >/dev/null 2>&1
check "an unknown mode is a usage error" 2 "$?"
"$SH" "$GATE" check "$TMP/not-a-repository-at-all" >/dev/null 2>&1
check "check outside a repository is an error, not a pass" 2 "$?"
"$SH" "$GATE" check a b >/dev/null 2>&1
check "check with too many arguments is a usage error" 2 "$?"

# --- bash 3.2 compatibility -------------------------------------------------
#
# macOS ships bash 3.2 as /bin/bash while the PATH bash is usually 5.x. In a
# script file an unsupported construct does not abort — it writes to stderr and
# carries on with a wrong value — and under this file's fail-open trap even the
# abort would be silent, which is the one failure the gate cannot detect in
# itself.

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

    clean_tree
    ERR="$TMP/err.txt"
    "$OLD_BASH" "$GATE" check "$REPO" >/dev/null 2>"$ERR"
    printf '%s' "$CREATE" | "$OLD_BASH" "$GATE" hook >/dev/null 2>>"$ERR"
    plan_with "$DONE_PLAN
- [ ] one left" "$DONE_ACC"
    printf '%s' "$CREATE" | "$OLD_BASH" "$GATE" hook >/dev/null 2>>"$ERR"
    check "pr-gate.sh writes nothing to stderr under bash $OLD_VER" "" "$(cat "$ERR")"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
