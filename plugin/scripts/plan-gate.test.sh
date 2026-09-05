#!/usr/bin/env bash
# Tests for plan-gate.sh — the shape check on a plan file.
#
# Every rejected shape here is one that reads as fine downstream — a `## Plan`
# holding bullets rather than checkboxes reads as zero outstanding work to the
# module that counts them. The accepted shapes matter as much: this gate
# blocks the module that writes plans, so a false rejection costs a rewrite
# for nothing, and the accepting side is checked throughout.
#
# Each case is the well-formed plan with ONE section dropped or replaced
# (`plan_without` below): a fixture written out whole would bury the one thing
# under test.
#
# Run: bash plugin/scripts/plan-gate.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATE="$HERE/plan-gate.sh"
LIB="$HERE/lib.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# The gate derives every path it touches from the home; pointing the home at
# the fixture directory is what keeps this suite off the developer's real
# ~/.hq.
export HQ_HOME="$TMP/home"

# Where a fixture repository's run files go, asked the same way the gate asks.
task_dir() { # <repo-root>
  "$SH" "$LIB" hq_task_dir "$1" 2>/dev/null
}

# The deepest existing ancestor of <path>, resolved, with whatever did not
# exist yet put back on the end: the directories this compares are derived,
# not created, and `cd` on a path that is not there yet answers nothing.
resolve_path() { # <path>
  local p=$1 tail="" base
  while [ -n "$p" ] && [ "$p" != "/" ] && [ ! -d "$p" ]; do
    base=$(basename "$p"); tail="/$base$tail"; p=$(dirname "$p")
  done
  printf '%s%s' "$(cd "$p" 2>/dev/null && pwd -P)" "$tail"
}

# `yes` when <path> is not under <repo-root>. An unresolvable root answers
# neither way — the prefix `/` would otherwise match every absolute path.
#
# BOTH SIDES ARE RESOLVED: `mktemp -d` on macOS hands back `/var/folders/…`
# while `pwd -P` returns `/private/var/folders/…`, so resolving only one side
# makes the prefix test a constant answer and the two checks below would
# assert nothing.
#
# A function rather than a `case` written inline: bash 3.2 cannot parse a case
# pattern's closing `)` inside a command substitution, and the replay at the
# bottom of this file is where that would surface.
outside() { # <repo-root> <path>
  local r p
  r=$(cd "$1" 2>/dev/null && pwd -P) || r=""
  if [ -z "$r" ]; then printf 'unresolvable'; return 0; fi
  p=$(resolve_path "$2")
  case "$p" in
    "$r"/*) printf 'no' ;;
    *) printf 'yes' ;;
  esac
}

. "$HERE/testlib.sh"

P="$TMP/plan.md"

# The plan a well-formed run produces. `## Plan` is absent on purpose: the
# builder writes that section after it has designed, so a plan as this module
# leaves it has no work items at all.
good_body() {
  cat <<'EOF'
# feat(core): add the plan module

## Summary

Every later module reads this branch's plan, and nothing checks the shape they
read it with. A plan missing a section fails inside the module that needed it,
long after the person who could have fixed it moved on.

## Requirements

| # | what must be true | how anyone confirms it |
|---|---|---|
| R1 | a plan missing a required section is refused as it is written | [manual] write one without the outcomes table and watch the block |
| R2 | the refusal names what is wrong, not merely that something is | [review] trace where each problem's text is composed |

## Notes

- constraint: the plan is untrusted input, so nothing in it is ever executed
- reach: `plugin/scripts/lib.sh` — the diff helper joins the dispatch list
- left alone: the review module, which could call the fence check later — it
  reads no plan today and giving it one is a separate decision

## Editable surface

- `plugin/scripts/plan-gate.sh` — [new] the gate itself
- `plugin/scripts/lib.sh` — [edit] expose the diff helper

## Floor

- [ ] [auto] `bash plugin/scripts/test.sh`
- [ ] [auto] `bash .claude/scripts/docs-check.sh`
EOF
}

good() { good_body >"$P"; }

# The well-formed plan with the named sections removed, on stdout. A
# replacement is appended by the caller; section order is nothing this gate
# reads.
plan_without() { # <section name>…
  local out s
  out=$(good_body)
  for s in "$@"; do
    out=$(printf '%s\n' "$out" | awk -v drop="## $s" '
      /^## / { skip = ($0 == drop) }
      !skip { print }
    ')
  done
  printf '%s\n' "$out"
}

write() { cat >"$P"; }

# exit code of `check`, with its output kept for `says`
code() { "$SH" "$GATE" check "$P" >"$TMP/out" 2>&1; printf '%s' "$?"; }

# whether the reported problems mention <substring>
says() { /usr/bin/grep -q -- "$1" "$TMP/out" && printf 'yes' || printf 'no'; }

tap_begin

# --- shapes that must be accepted ------------------------------------------

good
check "a well-formed plan is accepted" 0 "$(code)"

# `## Plan` is the builder's and arrives later. Both states are ordinary, and
# rejecting either would block a module that is doing the right thing.
{ good_body; printf '\n## Plan\n\n- [ ] write the gate\n- [x] write the tests\n'; } >"$P"
check "a plan carrying the builder's work items is accepted" 0 "$(code)"

# The plan is rewritten as the work proceeds; every item is checked by the end
# and the shape contract still holds.
good_body | sed 's/^- \[ \]/- [x]/' >"$P"
check "a fully checked plan is accepted" 0 "$(code)"

# This repository writes plan bodies in the conversation language, so non-ASCII
# is the normal case rather than an edge.
{ plan_without Summary; printf '## Summary\n\n読む側が形を当てにしているのに、誰も検査していない。\n'; } >"$P"
check "a plan section written in Japanese is accepted" 0 "$(code)"

# A requirements table written with the columns padded out, the way an editor
# that aligns markdown tables leaves them.
{ plan_without Requirements
  cat <<'EOF'
## Requirements

| #  | what must be true      | how anyone confirms it     |
| -- | ---------------------- | -------------------------- |
| R1 | the gate refuses it    | [manual] write one and see |
EOF
} >"$P"
check "a padded requirements table is accepted" 0 "$(code)"

# A command line rather than a bare command word: the metacharacter test takes
# it without a PATH lookup, which is what lets two assertions be one string.
{ plan_without Floor
  cat <<'EOF'
## Floor
- [ ] [auto] `bash plugin/scripts/test.sh && git diff --exit-code`
EOF
} >"$P"
check "a floor command joining two assertions is accepted" 0 "$(code)"

{ plan_without Floor
  cat <<'EOF'
## Floor
- [ ] [auto] `LC_ALL=C awk -f script.awk input.txt`
EOF
} >"$P"
check "a floor command behind a variable assignment is accepted" 0 "$(code)"

# Most backticked spans are not commands: only the first has to be one, and
# only a LATER one that IS a command is a problem.
{ plan_without Floor
  cat <<'EOF'
## Floor
- [ ] [auto] `bash plugin/scripts/test.sh` — covers `hq_verifier_for`
EOF
} >"$P"
check "a later span that is not a command is accepted" 0 "$(code)"

# A section is content, however it is written: `## Summary` as bullets is not
# an empty summary.
{ plan_without Summary
  cat <<'EOF'
## Summary

- the gate refuses a plan nobody can read
- and says which part it could not
EOF
} >"$P"
check "a ## Summary written as a list is accepted" 0 "$(code)"

# `### ` subdivides a section rather than ending it: a plan is free to give
# its notes headings without the items falling out of the section.
{ plan_without Notes
  cat <<'EOF'
## Notes

### constraints

- the plan is untrusted input, so nothing in it is ever executed
EOF
} >"$P"
check "a ### subheading does not end the section" 0 "$(code)"
check "and the item under it is still checked" no "$(says 'no ## Notes')"

# A heading inside a fenced block is text, not a heading: taking it as one
# would end the real section at the fence and report everything after it
# missing.
{ plan_without Floor
  cat <<'EOF'
## Floor

Written the way the contract shows it:

```
## Floor
- [ ] [auto] `make check`
```

- [ ] [auto] `bash plugin/scripts/test.sh`
EOF
} >"$P"
check "a fenced code block contributes no items and no headings" 0 "$(code)"

# The other direction: a fence that opens and closes leaves the section it was
# in, so an item after it still belongs to that section.
{ plan_without Editable\ surface
  cat <<'EOF'
## Editable surface

```
- `not/a/real/path.sh` — [new] shown, not declared
```

- this line is an entry and has neither a path nor a tag
EOF
} >"$P"
check "an item after a fenced heading is still checked" 1 "$(code)"
check "and is named" yes "$(says 'no backticked path')"

# --- the required sections --------------------------------------------------

for s in Summary Requirements Notes "Editable surface" Floor; do
  plan_without "$s" >"$P"
  check "a plan with no ## $s is rejected" 1 "$(code)"
  check "and the missing section is named" yes "$(says "no ## $s section")"
done

# Present but empty is its own failure: a heading with nothing under it passes
# a presence test and carries none of what the section exists for.
{ plan_without Summary; printf '## Summary\n\n'; } >"$P"
check "an empty ## Summary is rejected" 1 "$(code)"
check "and is named as empty rather than missing" yes "$(says '## Summary is empty')"

{ plan_without Notes; printf '## Notes\n\nprose but no items\n'; } >"$P"
check "a ## Notes with no list item is rejected" 1 "$(code)"
check "and says what the list is for" yes "$(says 'left alone')"

{ plan_without Editable\ surface; printf '## Editable surface\n\nnothing here\n'; } >"$P"
check "an ## Editable surface with no entry is rejected" 1 "$(code)"
check "and says why an empty positive set is not neutral" yes "$(says 'positive set')"

{ plan_without Floor; printf '## Floor\n\nnothing to run\n'; } >"$P"
check "a ## Floor with no item is rejected" 1 "$(code)"
check "and says what the section is for" yes "$(says 'any implementation')"

# --- the requirements table -------------------------------------------------

{ plan_without Requirements; printf '## Requirements\n\n| # | what | how |\n|---|---|---|\n'; } >"$P"
check "a requirements table with only furniture is rejected" 1 "$(code)"
check "and is named as holding no row" yes "$(says 'holds no row')"

{ plan_without Requirements
  cat <<'EOF'
## Requirements

| # | what must be true | how anyone confirms it |
|---|---|---|
| 1 | the gate refuses it | [manual] write one and see |
EOF
} >"$P"
check "a row whose id is not R<digits> is rejected" 1 "$(code)"
check "and the form is named" yes "$(says 'R<digits>')"

{ plan_without Requirements
  cat <<'EOF'
## Requirements

| # | what must be true | how anyone confirms it |
|---|---|---|
| R1 | the gate refuses it | [manual] write one and see |
| R1 | and says why | [manual] read the block |
EOF
} >"$P"
check "two rows carrying one id are rejected" 1 "$(code)"
check "and the duplicated id is named" yes "$(says 'the id R1')"

{ plan_without Requirements
  cat <<'EOF'
## Requirements

| # | what must be true | how anyone confirms it |
|---|---|---|
| R1 | the gate refuses it | |
EOF
} >"$P"
check "a row nobody confirms is rejected" 1 "$(code)"
check "and says an unconfirmable outcome is a wish" yes "$(says 'is a wish')"

{ plan_without Requirements
  cat <<'EOF'
## Requirements

| # | what must be true | how anyone confirms it |
|---|---|---|
| R1 | | [manual] write one and see |
EOF
} >"$P"
check "a row stating no outcome is rejected" 1 "$(code)"
check "and is named" yes "$(says 'states no outcome')"

# A row that lost its id still says something in its other cells. Reading it
# as table furniture would drop a requirement without a word, which is the
# shape of failure this gate exists to stop.
#
# A WELL-FORMED ROW SITS BESIDE IT on purpose: with the bad row alone, a gate
# that skipped it would still exit 1 — for holding no rows at all — and the
# check would pass while the defect it names went unnoticed.
{ plan_without Requirements
  cat <<'EOF'
## Requirements

| # | what must be true | how anyone confirms it |
|---|---|---|
| R1 | the gate refuses it | [manual] write one and see |
| | and says why | [manual] read the block |
EOF
} >"$P"
check "a row with an empty id is rejected rather than skipped" 1 "$(code)"
check "and is not mistaken for the table's rule" yes "$(says 'R<digits>')"

# The rule itself, and a row of nothing but empty cells, are shape and carry
# no requirement — but a table holding only those holds no row at all.
{ plan_without Requirements
  cat <<'EOF'
## Requirements

| # | what must be true | how anyone confirms it |
| :-- | --- | ---: |
| R1 | the gate refuses it | [manual] write one and see |
|  |  |  |
EOF
} >"$P"
check "an aligned rule and a blank row are not counted as requirements" 0 "$(code)"

{ plan_without Requirements
  cat <<'EOF'
## Requirements

| # | what must be true | how anyone confirms it |
|---|---|---|
| R1 | the gate refuses it | someone looks at it |
EOF
} >"$P"
check "a row naming no confirming party is rejected" 1 "$(code)"
check "and the accepted tags are listed" yes "$(says 'manual|review')"

# The builder's own word is not a confirmation, and the way that shows up in
# the shape is a row claiming both parties at once.
{ plan_without Requirements
  cat <<'EOF'
## Requirements

| # | what must be true | how anyone confirms it |
|---|---|---|
| R1 | the gate refuses it | [manual] [review] whoever gets to it |
EOF
} >"$P"
check "a row carrying two confirming parties is rejected" 1 "$(code)"
check "and says one party confirms one row" yes "$(says 'one party confirms one row')"

# --- the fence entries ------------------------------------------------------

{ plan_without Editable\ surface
  cat <<'EOF'
## Editable surface
- plugin/scripts/plan-gate.sh — [new] no backticks anywhere
EOF
} >"$P"
check "a fence entry with no backticked path is rejected" 1 "$(code)"
check "and is named" yes "$(says 'no backticked path')"

{ plan_without Editable\ surface
  cat <<'EOF'
## Editable surface
- `plugin/scripts/plan-gate.sh` — the gate itself
EOF
} >"$P"
check "a fence entry with no tag is rejected" 1 "$(code)"
check "and the accepted tags are listed" yes "$(says 'new|edit|delete')"

{ plan_without Editable\ surface
  cat <<'EOF'
## Editable surface
- `plugin/scripts/plan-gate.sh` — [new] [edit] both at once
EOF
} >"$P"
check "a fence entry carrying two tags is rejected" 1 "$(code)"
check "and says an entry is one kind of change" yes "$(says 'one kind of change')"

# --- the plan section, when the builder has written it ----------------------

{ good_body
  cat <<'EOF'

## Plan
- write the gate
- write the tests
EOF
} >"$P"
check "a ## Plan of bullets is rejected" 1 "$(code)"
check "each bullet is named" yes "$(says 'write the gate')"
check "and the empty section is named as its own problem" yes \
  "$(says 'holds no checkbox item')"

{ good_body
  cat <<'EOF'

## Plan
1. write the gate
EOF
} >"$P"
check "a numbered ## Plan item is rejected" 1 "$(code)"

# --- the floor section ------------------------------------------------------

{ plan_without Floor
  cat <<'EOF'
## Floor
- [ ] `bash plugin/scripts/test.sh`
EOF
} >"$P"
check "a floor item with no [auto] is rejected" 1 "$(code)"
check "and is named" yes "$(says 'carries no \[auto\]')"

{ plan_without Floor
  cat <<'EOF'
## Floor
- [ ] [auto] the tests pass
EOF
} >"$P"
check "a floor item with no backticked span is rejected" 1 "$(code)"
check "and is named" yes "$(says 'no backticked command')"

{ plan_without Floor
  cat <<'EOF'
## Floor
- [ ] [auto] `definitely-not-a-command-anywhere`
EOF
} >"$P"
check "a floor item whose first span is not a command is rejected" 1 "$(code)"
check "and is named" yes "$(says 'does not resolve as a command')"

# The name in the fixture above has to be one this machine really lacks, or
# the check above passes for the wrong reason.
check "a name that resolves to nothing was found for the fixture" no \
  "$(command -v definitely-not-a-command-anywhere >/dev/null 2>&1 && printf 'yes' || printf 'no')"

{ plan_without Floor
  cat <<'EOF'
## Floor
- [ ] [auto] `!!!`
EOF
} >"$P"
check "a first span that is only punctuation is rejected" 1 "$(code)"

# Two assertions joined by prose are half-run in practice, and the unrun half
# is where the defect sits.
{ plan_without Floor
  cat <<'EOF'
## Floor
- [ ] [auto] `bash plugin/scripts/test.sh` and then `git diff --exit-code`
EOF
} >"$P"
check "a floor item with a second command span is rejected" 1 "$(code)"
check "and the offending span is quoted" yes "$(says 'git diff --exit-code')"

{ plan_without Floor
  cat <<'EOF'
## Floor
- [ ] [auto] `bash plugin/scripts/test.sh`
- not a checkbox at all
EOF
} >"$P"
check "a ## Floor item that is not a checkbox is rejected" 1 "$(code)"
check "and is named" yes "$(says 'not a checkbox item')"

# --- the fence against the diff --------------------------------------------
#
# Both directions are reported: a change outside the fence was never
# declared, and a declared entry nothing touched means the plan and the work
# disagree about what the work was.

REPO="$TMP/repo"
mkdir -p "$REPO/b"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name t
printf 'seed\n' >"$REPO/a.txt"
printf 'seed\n' >"$REPO/b/c.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m seed
# Whatever git called the first branch here — the name is a git default, not
# something this suite gets to assume.
BASE=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
git -C "$REPO" checkout -q -b feat/thing
printf 'changed\n' >>"$REPO/a.txt"
printf 'changed\n' >>"$REPO/b/c.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m work

fence() { # <entries…> — a plan whose fence is exactly what is passed in
  { plan_without "Editable surface"
    printf '## Editable surface\n'
    printf -- '- `%s` — [edit] a note\n' "$@"
  } >"$P"
}

surface() { "$SH" "$GATE" surface "$P" "$BASE" "$REPO" >"$TMP/out" 2>&1; printf '%s' "$?"; }

fence a.txt b/c.txt
check "a fence naming exactly the changed files agrees with the diff" 0 "$(surface)"
check "and says nothing" "" "$(cat "$TMP/out")"

fence a.txt
check "a change outside the fence is reported" 1 "$(surface)"
check "and the undeclared path is named" yes "$(says "outside the fence: b/c.txt")"

fence a.txt b/c.txt d.txt
check "a declared path nothing touched is reported" 1 "$(surface)"
check "and the untouched entry is named" yes "$(says "declared, untouched: d.txt")"

# A directory entry covers what is under it; the fence still has to name the
# place.
fence a.txt b/
check "a directory-shaped entry covers the files under it" 0 "$(surface)"

fence x/
check "a directory-shaped entry that nothing touched is reported" 1 "$(surface)"
check "and both directions are reported at once" yes "$(says "outside the fence: a.txt")"

# The failure that must not read as agreement: a base that does not resolve
# yields an empty diff, which would report every declared entry as untouched
# and nothing as outside.
fence a.txt
"$SH" "$GATE" surface "$P" no-such-base "$REPO" >"$TMP/out" 2>&1
check "an unresolvable base is an error, not an empty diff" 2 "$?"
check "and the git message is passed through" yes "$(says "could not be taken")"

"$SH" "$GATE" surface "$P" >/dev/null 2>&1
check "surface with no base is a usage error" 2 "$?"

# lib.sh is what this plugin uses to decide what "changed" means, and it is
# called as a subprocess rather than sourced. A copy of the gate with no lib.sh
# beside it cannot answer, and says so.
ORPHAN="$TMP/orphan"
mkdir -p "$ORPHAN"
cp "$GATE" "$ORPHAN/plan-gate.sh"
"$SH" "$ORPHAN/plan-gate.sh" surface "$P" "$BASE" "$REPO" >"$TMP/out" 2>&1
check "a gate with no lib.sh beside it is an error, not an empty diff" 2 "$?"

# --- the hook face ---------------------------------------------------------

payload() { # <tool> <file_path>
  python3 -c '
import json, sys
print(json.dumps({
    "hook_event_name": "PostToolUse",
    "tool_name": sys.argv[1],
    "tool_input": {"file_path": sys.argv[2], "content": "..."},
}))' "$1" "$2"
}

bash_payload() { # <command string>
  python3 -c '
import json, sys
print(json.dumps({
    "hook_event_name": "PostToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[1]},
}))' "$1"
}

run_hook() { # <payload>
  printf '%s' "$1" | "$SH" "$GATE" hook >"$TMP/hook.out" 2>"$TMP/hook.err"
  printf '%s' "$?"
}

# The same, from inside a repository — for the cases where the gate resolves
# something out of the working directory rather than out of the payload.
run_hook_in() { # <dir> <payload>
  printf '%s' "$2" | ( cd "$1" && "$SH" "$GATE" hook ) >"$TMP/hook.out" 2>"$TMP/hook.err"
  printf '%s' "$?"
}

field() { # <key> — the named field of the last hook output
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$TMP/hook.out" "$1" 2>/dev/null
}

# The hook claims a plan by asking lib.sh where this repository's run files
# go, so the fixture goes exactly there, and every hook call below runs from
# inside the repository.
TASK=$(task_dir "$REPO")
check "the fixture's task directory was derived at all" yes \
  "$([ -n "$TASK" ] && printf 'yes' || printf 'no')"
check "and it is outside the repository being worked on" yes \
  "$(outside "$REPO" "$TASK")"
# Positive control for the helper itself. Without it the check above passes on
# a helper that answers `yes` to everything.
check "the outside helper answers no for a path inside the repository" no \
  "$(outside "$REPO" "$REPO/somewhere/under/it")"
check "and says so rather than guessing when the root does not resolve" unresolvable \
  "$(outside "$TMP/no-such-root" "$TMP/anything")"
mkdir -p "$TASK"
P="$TASK/plan.md"

good
check "the hook exits 0 on a well-formed plan" 0 "$(run_hook_in "$REPO" "$(payload Write "$P")")"
check "and says nothing" "" "$(cat "$TMP/hook.out")"

{ plan_without Plan; printf '## Plan\n- write the gate\n'; } >"$P"
check "the hook exits 0 on a malformed plan too" 0 "$(run_hook_in "$REPO" "$(payload Write "$P")")"
check "but emits a block decision" block "$(field decision)"
check "the block reason names the problem" yes \
  "$(field reason | /usr/bin/grep -q 'not a checkbox item' && printf 'yes' || printf 'no')"
check "and points at the contract rather than restating it" yes \
  "$(field reason | /usr/bin/grep -q 'plugin/commands/plan.md' && printf 'yes' || printf 'no')"
check "the block output is a single line" 1 "$(wc -l <"$TMP/hook.out" | tr -d ' ')"
check "the hook writes nothing to stderr" "" "$(cat "$TMP/hook.err")"

# Exec toggles checkboxes with Edit, and a plan is repaired with one. A gate
# watching Write alone would see a plan's first write and nothing after it.
check "an Edit of the plan is checked as well" block \
  "$(run_hook_in "$REPO" "$(payload Edit "$P")" >/dev/null; field decision)"

# The path the module definitions hand the writer comes out of lib.sh, and the
# gate has to claim that exact string: a pattern written out in the gate
# instead would be a second copy of the layout.
check "the path lib.sh hands the writer is the path the gate claims" block \
  "$(run_hook_in "$REPO" "$(payload Write "$(task_dir "$REPO")/plan.md")" >/dev/null; field decision)"

# A plan item carrying the two characters that end a JSON string. The reason
# reaches the model through a JSON field, so a plan that breaks the encoding
# turns a block into a parse failure — which is a silent pass.
{ plan_without Plan; printf '## Plan\n- the item says "quoted" and c:\\path\\to\\thing\n'; } >"$P"
run_hook_in "$REPO" "$(payload Write "$P")" >/dev/null
check "a plan holding quotes and backslashes still yields parseable JSON" block "$(field decision)"
check "and the offending item survives into the reason" yes \
  "$(field reason | /usr/bin/grep -q 'c:\\path\\to\\thing' && printf 'yes' || printf 'no')"

# --- the plan that went to another branch's directory -----------------------
#
# The directory names the branch, and every reader derives it that way, so a
# plan written from the wrong branch is invisible to all of them while the
# write itself succeeds.

good
TASKS_ROOT=$(dirname "$TASK")
OTHER_DIR="$TASKS_ROOT/feat-other"
mkdir -p "$OTHER_DIR"
cp "$P" "$OTHER_DIR/plan.md"
check "a well-formed plan in another branch's directory is blocked" block \
  "$(run_hook_in "$REPO" "$(payload Write "$OTHER_DIR/plan.md")" >/dev/null; field decision)"
check "and the reason names both directories" yes \
  "$(field reason | /usr/bin/grep -q 'feat-other' \
     && field reason | /usr/bin/grep -q 'feat-thing' && printf 'yes' || printf 'no')"
check "and does not tell the writer to create a branch to match" yes \
  "$(field reason | /usr/bin/grep -q 'do not create another branch' && printf 'yes' || printf 'no')"

check "the branch's own directory is not blocked for that reason" "" \
  "$(run_hook_in "$REPO" "$(payload Write "$TASK/plan.md")" >/dev/null; cat "$TMP/hook.out")"

# A detached HEAD has no branch to disagree with, and a plan file under
# another clone's run tree is not this repository's business. The fixture in
# both is a MALFORMED plan: a well-formed one produces silence from the shape
# check as readily as from the gate walking away — and walking away is what
# is under test.
BAD="$TMP/malformed-plan.md"
{ plan_without Plan; printf '## Plan\n- write the gate\n'; } >"$BAD"

cp "$BAD" "$OTHER_DIR/plan.md"
git -C "$REPO" checkout -q --detach
check "a detached HEAD says nothing at all" "" \
  "$(run_hook_in "$REPO" "$(payload Write "$OTHER_DIR/plan.md")" >/dev/null; cat "$TMP/hook.out")"
git -C "$REPO" checkout -q feat/thing

# Another clone's run tree. The directory name matches this branch's, so the
# only thing that can send the gate away is the tree it sits in.
ELSEWHERE="$TMP/home/repos/some-other-clone-.git/tasks/feat-thing"
mkdir -p "$ELSEWHERE"
cp "$BAD" "$ELSEWHERE/plan.md"
check "a plan under another clone's run tree says nothing" "" \
  "$(run_hook_in "$REPO" "$(payload Write "$ELSEWHERE/plan.md")" >/dev/null; cat "$TMP/hook.out")"

# And the fixture is worth nothing unless that same file, in this branch's
# own directory, is reported: both checks above would otherwise pass on a
# gate that had stopped checking anything.
cp "$BAD" "$TASK/plan.md"
check "while the same file in this branch's directory is not passed over" block \
  "$(run_hook_in "$REPO" "$(payload Write "$TASK/plan.md")" >/dev/null; field decision)"

# A control byte other than tab, newline and carriage return: JSON forbids
# every one of them unescaped, so a single form feed in a quoted plan item
# makes the whole block object unparseable — a block that never happened.
{ plan_without Plan; printf '## Plan\n- a bullet, not a checkbox\014 and a form feed\n'; } >"$P"
run_hook_in "$REPO" "$(payload Write "$P")" >/dev/null
check "a plan holding a control byte still yields parseable JSON" block "$(field decision)"
check "and the byte is gone rather than passed through" 0 \
  "$(/usr/bin/grep -c $'\014' "$TMP/hook.out" | tr -d ' ')"
check "while the problem it sat in is still reported" yes \
  "$(field reason | /usr/bin/grep -q 'not a checkbox item' && printf 'yes' || printf 'no')"

# --- the plan written through Bash rather than Write ------------------------
#
# The root session holds Bash as well as Write, so a heredoc into the plan
# path is an ordinary way to produce it. The command string is not parsed for
# a path; the gate derives it from the branch.

good
check "a Bash write of a well-formed plan exits 0" 0 \
  "$(run_hook_in "$REPO" "$(bash_payload "cat > $P <<'EOF'
...
EOF")")"
check "and says nothing" "" "$(cat "$TMP/hook.out")"

{ plan_without Plan; printf '## Plan\n- write the gate\n'; } >"$P"
check "a Bash write of a malformed plan exits 0" 0 \
  "$(run_hook_in "$REPO" "$(bash_payload "cat > $P <<'EOF'
...
EOF")")"
check "but emits a block decision" block "$(field decision)"

check "an unrelated Bash command: exits 0" 0 "$(run_hook_in "$REPO" "$(bash_payload 'ls -la')")"
check "an unrelated Bash command: says nothing" "" "$(cat "$TMP/hook.out")"

# --- the fence, asked after every commit ------------------------------------
#
# `## Editable surface` is a commitment made before the work, and the hook is
# what compares it against what the branch actually changed.
#
# The base is pinned in .hq/settings.json: this fixture's first branch is
# whatever name git chose, and the chain would otherwise fall through to
# `main`.

mkdir -p "$REPO/.hq"
printf '{"base_branch": "%s"}\n' "$BASE" >"$REPO/.hq/settings.json"

commit_payload() { bash_payload "git commit -q -m 'one plan item'"; }

fence a.txt b/c.txt
check "a commit inside the fence: exits 0" 0 "$(run_hook_in "$REPO" "$(commit_payload)")"
check "a commit inside the fence: says nothing" "" "$(cat "$TMP/hook.out")"

fence a.txt
check "a commit carrying an undeclared path is blocked" block \
  "$(run_hook_in "$REPO" "$(commit_payload)" >/dev/null; field decision)"
check "and the reason names the path" yes \
  "$(field reason | /usr/bin/grep -q 'b/c.txt' && printf 'yes' || printf 'no')"
check "and names the plan the entry belongs in" yes \
  "$(field reason | /usr/bin/grep -q 'feat-thing/plan.md' && printf 'yes' || printf 'no')"
check "and offers the expansion protocol rather than only a refusal" yes \
  "$(field reason | /usr/bin/grep -q 'never silent' && printf 'yes' || printf 'no')"

# WHAT A BLOCK STOPS LEAVES NO TRACE — the commit never happened, so nothing
# afterwards can tell a gate that fires constantly from one that has never
# fired. One row per refusal is the only evidence either way, and a gate whose
# recording quietly stopped would look exactly like a gate nobody trips.
export HQ_SINK="$TMP/stream.jsonl"
: >"$HQ_SINK"
fence a.txt
run_hook_in "$REPO" "$(commit_payload)" >/dev/null
check "a fence block writes one gate row" 1 \
  "$(/usr/bin/grep -c '"kind":"gate"' "$HQ_SINK" 2>/dev/null; true)"
check "and the row names the fence and the refusal" yes \
  "$(/usr/bin/grep -q '"name":"fence","outcome":"block"' "$HQ_SINK" && printf 'yes' || printf 'no')"

: >"$HQ_SINK"
fence a.txt b/c.txt
run_hook_in "$REPO" "$(commit_payload)" >/dev/null
check "a commit inside the fence writes no row" "" "$(cat "$HQ_SINK")"

# A sink that cannot be written must not turn into a gate that stopped
# refusing: letting a bad commit through because telemetry broke is the wrong
# trade in every direction.
# The parent is a FILE, so `mkdir -p` on the sink's directory fails on every
# platform and for every user — a permission bit would not, under a user that
# ignores them.
printf 'not a directory\n' >"$TMP/blocker"
export HQ_SINK="$TMP/blocker/nested/stream.jsonl"
check "the unwritable sink is genuinely unwritable" no \
  "$(mkdir -p "$(dirname "$HQ_SINK")" 2>/dev/null && printf 'yes' || printf 'no')"
fence a.txt
check "a block still blocks when the sink cannot be written" block \
  "$(run_hook_in "$REPO" "$(commit_payload)" >/dev/null; field decision)"
export HQ_SINK="$TMP/stream.jsonl"

# The direction that must NOT fire here: entries not yet touched are the
# ordinary state of a branch part way through its items.
fence a.txt b/c.txt d.txt
check "a declared path nothing has touched yet is not reported at commit time" "" \
  "$(run_hook_in "$REPO" "$(commit_payload)" >/dev/null; cat "$TMP/hook.out")"

# The trigger is the commit, not the tool. With the fence genuinely violated,
# every other Bash call still has to be silent — otherwise one undeclared path
# turns into a block on everything the session does next.
fence a.txt
check "an unrelated Bash call stays silent while the fence is violated" "" \
  "$(run_hook_in "$REPO" "$(bash_payload 'ls -la')" >/dev/null; cat "$TMP/hook.out")"

# A branch with no plan is not a branch in violation of one.
git -C "$REPO" checkout -q -b feat/planless
check "a commit on a branch with no plan: exits 0" 0 "$(run_hook_in "$REPO" "$(commit_payload)")"
check "a commit on a branch with no plan: says nothing" "" "$(cat "$TMP/hook.out")"
git -C "$REPO" checkout -q feat/thing

# Not-checked is not clean: a base that does not resolve makes `git diff`
# return nothing, which would read as "every path was declared".
printf '{"base_branch": "no-such-base"}\n' >"$REPO/.hq/settings.json"
check "a base that does not resolve blocks rather than passing" block \
  "$(run_hook_in "$REPO" "$(commit_payload)" >/dev/null; field decision)"
check "and says the fence was not checked" yes \
  "$(field reason | /usr/bin/grep -q 'NOT checked' && printf 'yes' || printf 'no')"
printf '{"base_branch": "%s"}\n' "$BASE" >"$REPO/.hq/settings.json"

# --- git speaks while exiting 0 ---------------------------------------------
#
# Folding git's stderr into its stdout turns every line it writes into a path,
# and git writes lines while succeeding. A tag sharing the base branch's name
# reproduces it in four commands: the diff warns, exits 0, and the warning
# then reads as an undeclared path — a plan that declared its surface exactly
# is told it went outside the fence, naming a file that does not exist.

AMB="$TMP/ambiguous"
mkdir -p "$AMB/.hq"
git -C "$AMB" init -q
git -C "$AMB" config user.email t@example.com
git -C "$AMB" config user.name t
printf 'seed\n' >"$AMB/a.txt"
git -C "$AMB" add -A
git -C "$AMB" commit -q -m seed
AMB_BASE=$(git -C "$AMB" rev-parse --abbrev-ref HEAD)
git -C "$AMB" tag "$AMB_BASE"
git -C "$AMB" checkout -q -b feat/x
printf 'more\n' >>"$AMB/a.txt"
git -C "$AMB" add -A
git -C "$AMB" commit -q -m work
printf '{"base_branch": "%s"}\n' "$AMB_BASE" >"$AMB/.hq/settings.json"
AMB_TASK=$(task_dir "$AMB")
mkdir -p "$AMB_TASK"
{ plan_without "Editable surface"
  printf '## Editable surface\n'
  printf -- '- `a.txt` — [edit] the only file this work touches\n'
} >"$AMB_TASK/plan.md"

# The fixture is only worth anything while git actually warns here: if a
# future git stops, this check fails rather than leaving the two below
# quietly vacuous.
check "the fixture really makes git speak on a successful diff" yes \
  "$([ -n "$(git -C "$AMB" diff --name-only "$AMB_BASE"...HEAD 2>&1 >/dev/null)" ] \
     && printf 'yes' || printf 'no')"
check "a warning on a successful diff does not become an undeclared path" "" \
  "$(run_hook_in "$AMB" "$(commit_payload)" >/dev/null; cat "$TMP/hook.out")"
"$SH" "$GATE" surface "$AMB_TASK/plan.md" "$AMB_BASE" "$AMB" >"$TMP/out" 2>/dev/null
check "and the surface face agrees with the fence too" 0 "$?"

# --- a repository that tracks .hq -------------------------------------------
#
# NO EXCLUSION COVERS A REPOSITORY THAT TRACKS `.hq`, and none is needed: a
# run's working files live under the home and never reach a diff at all. Both
# halves are checked here — the item commit is silent because there is
# nothing of the run's in it, and a file under the location those working
# files used to occupy is fenced like any other file in the repository.

TRACKED="$TMP/tracked"
mkdir -p "$TRACKED/.hq"
git -C "$TRACKED" init -q
git -C "$TRACKED" config user.email t@example.com
git -C "$TRACKED" config user.name t
printf 'seed\n' >"$TRACKED/a.txt"
git -C "$TRACKED" add -A
git -C "$TRACKED" commit -q -m seed
TRACKED_BASE=$(git -C "$TRACKED" rev-parse --abbrev-ref HEAD)
printf '{"base_branch": "%s"}\n' "$TRACKED_BASE" >"$TRACKED/.hq/settings.json"
git -C "$TRACKED" add -A
git -C "$TRACKED" commit -q -m settings
git -C "$TRACKED" checkout -q -b feat/x
TRACKED_TASK=$(task_dir "$TRACKED")
mkdir -p "$TRACKED_TASK"
{ plan_without "Editable surface"
  printf '## Editable surface\n'
  printf -- '- `a.txt` — [edit] the product file this work touches\n'
} >"$TRACKED_TASK/plan.md"
printf 'work\n' >>"$TRACKED/a.txt"
git -C "$TRACKED" add -A
git -C "$TRACKED" commit -q -m "feat: item one"

# The fixture is worth nothing unless `.hq` really is tracked here — in a
# repository like this one it is not, and every check below would pass without
# exercising anything.
check "the fixture really tracks .hq" yes \
  "$(git -C "$TRACKED" ls-files .hq | /usr/bin/grep -q . && printf 'yes' || printf 'no')"
check "and the run's working files are outside the tree" yes \
  "$(outside "$TRACKED" "$TRACKED_TASK")"
check "so an item commit carries nothing of the run's" "" \
  "$(run_hook_in "$TRACKED" "$(commit_payload)" >/dev/null; cat "$TMP/hook.out")"
"$SH" "$GATE" surface "$TRACKED_TASK/plan.md" "$TRACKED_BASE" "$TRACKED" >"$TMP/out" 2>/dev/null
check "and the surface face agrees" 0 "$?"

# Nothing in the repository is outside the fence. A leftover under the
# location the working files used to occupy is a repository file like any
# other, and an undeclared one is named.
#
# The prefix is assembled from a variable rather than written out: this file is
# inside the set swept for the old location, and a literal here would report
# itself.
LEGACY_SEG=tasks
LEGACY_DIR=".hq/$LEGACY_SEG/feat-x"
mkdir -p "$TRACKED/$LEGACY_DIR"
printf 'left over from before the move\n' >"$TRACKED/$LEGACY_DIR/plan.md"
printf 'undeclared\n' >"$TRACKED/b.txt"
git -C "$TRACKED" add -A
git -C "$TRACKED" commit -q -m "feat: item two"
run_hook_in "$TRACKED" "$(commit_payload)" >/dev/null
check "an undeclared product file is reported" yes \
  "$(field reason | /usr/bin/grep -q 'b.txt' && printf 'yes' || printf 'no')"
# Asked as a whole-line match against the list of offending paths, so that a
# reason merely long enough to contain the words cannot answer yes.
check "and so is an undeclared file under the old workspace location" yes \
  "$(field reason | /usr/bin/grep -qx "$LEGACY_DIR/plan.md" && printf 'yes' || printf 'no')"

# Without the scanner the declared set comes back EMPTY, and an empty fence
# makes every changed path a violation — the wrong answer here is a block
# naming files that were declared all along.
fence a.txt b/c.txt
printf '%s' "$(commit_payload)" | ( cd "$REPO" && HQ_AWK=no-such-scanner "$SH" "$GATE" hook ) \
  >"$TMP/hook.out" 2>"$TMP/hook.err"
check "a missing scanner blocks rather than passing silently" block "$(field decision)"
check "and says the fence was not checked" yes \
  "$(field reason | /usr/bin/grep -q 'NOT checked' && printf 'yes' || printf 'no')"
check "rather than naming declared files as violations" yes \
  "$(field reason | /usr/bin/grep -q 'a.txt' && printf 'no' || printf 'yes')"

# --- everything the hook must ignore ---------------------------------------

OTHER="$TMP/notes.md"
printf 'not a plan\n' >"$OTHER"
check "a write to another file: exits 0" 0 "$(run_hook_in "$REPO" "$(payload Write "$OTHER")")"
check "a write to another file: says nothing" "" "$(cat "$TMP/hook.out")"

# A plan.md the derivation does not claim is somebody else's file. Malformed, so
# that silence can only mean the gate walked away.
STRAY="$TMP/plan.md"
cp "$BAD" "$STRAY"
check "a plan.md outside the run tree: exits 0" 0 "$(run_hook_in "$REPO" "$(payload Write "$STRAY")")"
check "a plan.md outside the run tree: says nothing" "" "$(cat "$TMP/hook.out")"

check "a payload with no file_path: exits 0" 0 \
  "$(run_hook_in "$REPO" '{"hook_event_name":"PostToolUse","tool_name":"Write"}')"
check "a payload with no file_path: says nothing" "" "$(cat "$TMP/hook.out")"

check "an unparseable payload: exits 0" 0 "$(run_hook_in "$REPO" 'not json {{{')"
check "an unparseable payload: says nothing" "" "$(cat "$TMP/hook.out")"

check "an empty payload: exits 0" 0 "$(run_hook_in "$REPO" '')"

check "a plan that no longer exists: exits 0" 0 \
  "$(run_hook_in "$REPO" "$(payload Write "$TASKS_ROOT/gone/plan.md")")"
check "a plan that no longer exists: says nothing" "" "$(cat "$TMP/hook.out")"

# --- when the gate cannot check at all -------------------------------------
#
# Both faces have to say so: a plan nobody could check reads exactly like one
# checked and found clean. HQ_AWK is what makes the branch reachable; PATH
# surgery is not usable on this machine, where the interactive shell
# substitutes functions for several standard commands.

good
check "the hook exits 0 when the scanner is missing" 0 \
  "$(printf '%s' "$(payload Write "$P")" \
     | ( cd "$REPO" && HQ_AWK=no-such-scanner "$SH" "$GATE" hook ) \
     >"$TMP/hook.out" 2>"$TMP/hook.err"; printf '%s' "$?")"
check "but blocks rather than passing silently" block "$(field decision)"
check "and says the plan was not checked" yes \
  "$(field reason | /usr/bin/grep -q 'NOT checked' && printf 'yes' || printf 'no')"
check "naming what it looked for" yes \
  "$(field reason | /usr/bin/grep -q 'no-such-scanner' && printf 'yes' || printf 'no')"
check "and telling the reader what to check it against" yes \
  "$(field reason | /usr/bin/grep -q 'plugin/commands/plan.md' && printf 'yes' || printf 'no')"

HQ_AWK=no-such-scanner "$SH" "$GATE" check "$P" >/dev/null 2>&1
check "check reports a missing scanner as an error, not a pass" 2 "$?"
HQ_AWK=no-such-scanner "$SH" "$GATE" surface "$P" "$BASE" "$REPO" >/dev/null 2>&1
check "surface reports a missing scanner as an error, not as an empty fence" 2 "$?"

# --- usage -----------------------------------------------------------------

"$SH" "$GATE" check >/dev/null 2>&1
check "check with no file is a usage error" 2 "$?"
"$SH" "$GATE" check "$TMP/does-not-exist" >/dev/null 2>&1
check "check on a missing file is a usage error" 2 "$?"
"$SH" "$GATE" >/dev/null 2>&1
check "no mode is a usage error" 2 "$?"

# --- bash 3.2 compatibility ------------------------------------------------

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

    good
    "$OLD_BASH" "$GATE" check "$P" >/dev/null 2>"$TMP/err.txt"
      "$OLD_BASH" "$GATE" surface "$P" "$BASE" "$REPO" >/dev/null 2>>"$TMP/err.txt"
    printf '%s' "$(payload Write "$P")" | ( cd "$REPO" && "$OLD_BASH" "$GATE" hook ) \
      >/dev/null 2>>"$TMP/err.txt"
    check "plan-gate.sh writes nothing to stderr under bash $OLD_VER" "" "$(cat "$TMP/err.txt")"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
