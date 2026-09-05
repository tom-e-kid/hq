#!/usr/bin/env bash
# hq pull request gate — the conditions that have to hold before a branch's
# work is offered to a reviewer, asked at the moment `gh pr create` runs.
#
#   pr-gate.sh check [<repo-root>]
#       Prints one line per violation, and one `unchecked: …` line per
#       condition it could not evaluate. exit 0 everything was looked at and
#       nothing is wrong, 1 violations, 2 nothing wrong but something was not
#       looked at (or a usage error). A not-checked result gets its own exit
#       code because a condition nobody could evaluate reads exactly like one
#       that passed.
#
#   pr-gate.sh hook
#       Reads a PreToolUse payload (JSON) on stdin and prints exactly one JSON
#       object when the pull request is refused:
#           {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#            "permissionDecision":"deny","permissionDecisionReason":"..."}}
#       and NOTHING on every other path. Silence takes no position and leaves
#       the user's normal permission flow intact; "allow" is never emitted,
#       which would bypass it. Exits 0 on EVERY path — see the trap below.
#
# A step in a definition is a step that can be skipped; intercepting the tool
# call is what makes the conditions hold whether or not the definition was
# followed.
#
# THE FIVE CONDITIONS, and what each one is for:
#
#   1. No unchecked `- [ ]` item under `## Plan` — the builder's own word that
#      the work is done; self-report, not verification.
#   2. EVERY item under `## Plan` is a checkbox — not merely one of them: a
#      section condition 1 cannot read yields an empty count, which reads as
#      a finished plan, and one `- [x]` beside three numbered items would
#      otherwise answer "readable" while hiding all three. A plan file with no
#      `## Plan` section at all is the same failure at its limit: that section
#      is written by the builder once it has designed, so its absence says the
#      building never reached that step.
#   3. No unchecked `- [ ]` item under `## Floor`, every item under it is a
#      checkbox, and the section is there at all. The last of the three is not
#      pedantry: an absent section counts as zero unchecked items, and the two
#      other readers of that section — `hq:pr` and the verifier — each run the
#      items they find, so a plan with no `## Floor` has its build, types,
#      linter and tests run by nobody while all three report nothing wrong.
#   4. The working tree is clean, untracked files included. A file never added
#      is a file missing from the diff the reviewer reads.
#   5. `CHANGELOG.md` is somewhere in the diff from the base to HEAD. The
#      predicate is deliberately the weak one: a file's absence from the diff
#      catches writing nothing at all; whether the entry says anything is not
#      decidable here.
#
# WHAT IS NOT A CONDITION. Whether the body follows the format `.hq/pr.md`
# declared — neither side of that question has a predicate. Whether every
# finding's disposition was recorded — that is `triage-gate.sh`'s question,
# and it answers a third state ("could not look") that a fail-open hook has
# no way to act on.
#
# EACH CONDITION FAILS OPEN ON ITS OWN: a branch with no plan file leaves 1-3
# unasked, a repository with no CHANGELOG.md leaves 5 unasked. Neither is a
# violation, and neither silences the others.
#
# BEING UNABLE TO LOOK IS NOT A VIOLATION EITHER, and the two faces part
# here: the hook stays silent — it fires on every Bash call, and a false deny
# stops the work — while `check` says what it could not evaluate and exits
# non-zero for it, because the reader of that face asked.
#
# THE PAYLOAD IS UNTRUSTED INPUT. Nothing in it is executed; it is only ever
# pattern-matched, and `set -f` keeps an unquoted token from pathname-expanding.
#
# THIS SCRIPT SOURCES NOTHING. It CALLS lib.sh in a subprocess, which is the
# deliberate difference: a syntax error in a sourced file would abort this hook
# and the fail-open trap would make that abort silent — the gate would quietly
# stop existing. A broken subprocess is a non-zero exit this file can read.
#
# Portability: bash 3.2, BSD userland. A bash-4-only construct would abort the
# script, and under the trap the abort is silent, which is the one failure this
# file cannot detect in itself.

set -u
set -f

# Arm the fail-open trap before anything else can go wrong in hook mode.
case "${1:-}" in hook) trap 'exit 0' EXIT ;; esac

# Byte-oriented, pinned once: under a multibyte locale BSD awk and sed abort
# on an invalid byte having already emitted what they got through — the item
# list truncates, the unchecked item is never seen, and the pull request goes
# out.
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || HERE=""

# The file the changelog rule is about. One spelling, at the repository root.
CHANGELOG=CHANGELOG.md

# How many offending lines are listed per condition before the rest are
# summarised: a deny reason listing two hundred files is one nobody reads.
MAX_LISTED=10

# Where the format of a plan is defined, for a reader who has to go and fix
# one. The SAME file plan-gate.sh names: two gates sending a reader to two
# places would be the drift this plugin declares it detects.
CONTRACT="plugin/commands/plan.md"

# The scanner, overridable so the tests can drive the branch where there is
# none.
AWK="${HQ_AWK:-awk}"

have_awk() { command -v "$AWK" >/dev/null 2>&1; }

# JSON string escaping, kept BYTE-IDENTICAL in every script here that emits
# JSON — this comment included. A test compares the copies as text; when one is
# edited the others fail until they match (sweep.test.sh).
#
# Not shared through a sourced file: callers here include hooks that fail open,
# and a syntax error in a sourced file would be swallowed by the trap, leaving a
# gate that has silently stopped existing.
#
# JSON forbids every unescaped U+0000-U+001F byte inside a string. The three
# that carry meaning are spelled out; the rest of that range is DROPPED rather
# than escaped, which is the honest trade — a form feed means nothing in any of
# the text this handles, while ONE of them reaching the output makes the object
# unparseable, and an unparseable block is a block that never happened.
json_escape() { # <string>
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037'
}

# --- reading the plan -------------------------------------------------------
#
# The two scans below are this file's own rather than plan-gate.sh's, and the
# duplication is deliberate: this file sources nothing. They also answer a
# different question — plan-gate.sh asks whether a plan has the shape, these
# ask what is left outstanding in a plan that already has it.

# The unchecked items under one `## ` heading, trimmed, one per line.
#
# Four properties, and each one is a way a scan goes quietly wrong:
#   - fenced lines are neither headings nor items: a `## Plan` quoted inside a
#     code block would otherwise end the real section there.
#   - `## ` starts and resets a section, `### ` does not, so `## Manual
#     Verification` — a person's items, unchecked by design — is never read by
#     a scan asked for `Plan`.
#   - leading whitespace is trimmed, so an indented item is still an item.
#   - NOTHING IS REQUIRED AFTER THE CLOSING BRACKET, which is what
#     plan-gate.sh accepts: the two gates must not disagree about what a
#     checkbox is.
unchecked_under() { # <plan file> <heading text>
  "$AWK" -v want="$2" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    !fence && /^##([[:space:]]|$)/ {
      h = $0; sub(/^##[[:space:]]*/, "", h)
      inside = (trim(h) == want)
      next
    }
    !fence && inside && /^[[:space:]]*-[[:space:]]*\[[[:space:]]\]/ { print trim($0) }
  ' "$1" 2>/dev/null
}

# The list items under a section that are NOT checkbox items.
#
# THE QUESTION IS WHETHER EVERY ITEM IS ONE, not whether any item is: a
# single `- [x]` under `## Plan` would otherwise hide every numbered item
# beside it from the unchecked count. WHAT AN ITEM IS AND WHAT A CHECKBOX IS
# ARE plan-gate.sh's PREDICATES — scan() and is_box() — rather than a third
# definition of either; same scan properties as unchecked_under above.
#
#   stdout — one offending item per line, trimmed
#   exit   — 0 every item is a checkbox, and there is at least one
#            1 the section holds an item that is not one, or holds none at all
#            2 there is no such section to read
non_box_under() { # <plan file> <heading text>
  "$AWK" -v want="$2" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    !fence && /^##([[:space:]]|$)/ {
      h = $0; sub(/^##[[:space:]]*/, "", h)
      inside = (trim(h) == want)
      if (inside) seen = 1
      next
    }
    !fence && inside && /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]/ {
      items = 1
      if (trim($0) !~ /^-[[:space:]]*\[[ xX]\]/) { bad = 1; print trim($0) }
      next
    }
    END {
      if (!seen) exit 2
      exit (items && !bad) ? 0 : 1
    }
  ' "$1" 2>/dev/null
}

# The plan file this branch owns, or a non-zero exit when there is no answer:
# outside a repository, on a detached HEAD, in an environment with no home.
# ASKED OF lib.sh RATHER THAN COMPOSED HERE — the derivation is one function
# and every caller queries it.
plan_path_for_branch() { # <repo-root>
  local dir
  [ -n "$HERE" ] && [ -f "$HERE/lib.sh" ] || return 1
  dir=$(bash "$HERE/lib.sh" hq_task_dir "$1" 2>/dev/null) || return 1
  [ -n "$dir" ] || return 1
  printf '%s/plan.md' "$dir"
}

# --- the conditions ---------------------------------------------------------

VIOLATIONS=""
UNCHECKED=""

add_v() { VIOLATIONS="$VIOLATIONS$1
"; }
add_u() { UNCHECKED="$UNCHECKED$1
"; }

# One violation line per offending line, up to MAX_LISTED, then a count of
# the rest: the lines are what a caller acts on, so they are named.
list_v() { # <label> <block>
  local line n i=0
  [ -n "$2" ] || return 0
  n=$(printf '%s\n' "$2" | /usr/bin/grep -c . || true)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    i=$((i + 1))
    [ "$i" -le "$MAX_LISTED" ] && add_v "$1: $line"
  done <<EOF
$2
EOF
  [ "$n" -gt "$MAX_LISTED" ] && add_v "$1: ... and $((n - MAX_LISTED)) more"
  return 0
}

in_list() { # <needle> <newline-separated list>
  local line
  while IFS= read -r line; do
    [ "$line" = "$1" ] && return 0
  done <<EOF
$2
EOF
  return 1
}

# Fills VIOLATIONS and UNCHECKED. Returns 0 either way — what a violation means
# is the caller's to decide, and the two faces decide it differently.
inspect() { # <repo-root>
  local root=$1 plan nonbox out base changed err status

  VIOLATIONS=""
  UNCHECKED=""

  # --- the plan's checkboxes (conditions 1-3) ---
  #
  # Every reason the plan cannot be read is reported as unchecked rather than
  # skipped. An absent plan is the one case that is neither: a branch without
  # a plan is an ordinary state, with nothing there to be outstanding.
  if ! have_awk; then
    add_u "the plan's items were not read: the scanner is not on PATH (looked for: $AWK)"
  else
    plan=$(plan_path_for_branch "$root") || plan=""
    if [ -z "$plan" ]; then
      add_u "the plan's items were not read: this branch has no run directory — a detached HEAD, no home to derive one from, or no lib.sh beside this script"
    elif [ -f "$plan" ]; then
      list_v "## Plan has an unchecked item" "$(unchecked_under "$plan" Plan)"

      nonbox=$(non_box_under "$plan" Plan)
      case "$?" in
        0) ;;
        1) if [ -n "$nonbox" ]; then
             list_v "## Plan holds an item that is not a checkbox, so the count above cannot see it — not done is indistinguishable from done here" "$nonbox"
           else
             add_v "## Plan holds no list item at all, so the count above came back empty because there was nothing to read — not because the work is finished ($plan)"
           fi ;;
        *) add_v "$plan has no ## Plan section, so there was nothing to count — the builder writes that section once it has designed, and its absence says the building never got that far" ;;
      esac

      # THE SAME THREE ANSWERS THE PLAN SECTION GETS, and for a sharper
      # reason. An absent section and a section whose items are all checked
      # produce the SAME empty count, so a plan carrying no `## Floor` at all
      # reads here as a floor that passed — and it is not only this gate that
      # goes quiet: `hq:pr` runs the items it finds and the verifier runs the
      # items it finds, so with no section the build, the types, the linter
      # and the tests are never run by anybody, and all three report nothing
      # wrong. The reachable way in is a plan written before this section
      # existed: the shape check runs when a plan is WRITTEN, and a file
      # already on disk is never written again.
      list_v "## Floor has an unchecked item" "$(unchecked_under "$plan" Floor)"

      nonbox=$(non_box_under "$plan" Floor)
      case "$?" in
        0) ;;
        1) if [ -n "$nonbox" ]; then
             list_v "## Floor holds an item that is not a checkbox, so the count above cannot see it — a check nobody ran is indistinguishable from one that passed" "$nonbox"
           else
             add_v "## Floor holds no item at all, so the count above came back empty because there was nothing to read — not because anything passed ($plan)"
           fi ;;
        *) add_v "$plan has no ## Floor section, so no machine check was named and none was run — nothing here, in hq:pr, or in the verifier reports that, because each of them runs the items it finds. A plan written before this section existed is the way in: the shape check runs when a plan is written, not when it is read" ;;
      esac
    fi
  fi

  # --- the working tree (condition 4) ---
  #
  # NOTHING IS EXCLUDED. A run's working files live under the home, so a path
  # under `.hq` in a status is a repository fact like any other. An exclusion
  # kept past its reason is a hole nobody can see.
  if out=$(git -C "$root" status --porcelain 2>/dev/null); then
    list_v "the working tree is not clean" "$out"
  else
    add_u "the working tree was not checked: git status failed in $root"
  fi

  # --- the changelog (condition 5) ---
  #
  # Silent where the repository has no such file: the rule is this
  # repository's and the plugin is installed in others. Where it does have
  # one, the question is whether this branch's diff touches it.
  if [ -f "$root/$CHANGELOG" ]; then
    if [ -z "$HERE" ] || [ ! -f "$HERE/lib.sh" ]; then
      add_u "$CHANGELOG was not checked: lib.sh is not beside this script, so the diff could not be taken"
    else
      base=$(bash "$HERE/lib.sh" hq_resolve_base "$root" 2>/dev/null)
      if [ -z "$base" ]; then
        add_u "$CHANGELOG was not checked: the base branch did not resolve"
      else
        # NEVER `2>&1`: git writes warnings while exiting 0, and every line it
        # wrote would become a path in this list, which is read as one.
        err=$(mktemp) || err=""
        if [ -n "$err" ]; then
          changed=$(bash "$HERE/lib.sh" hq_changed_files "$base" HEAD "$root" 2>"$err")
          status=$?
          out=$(cat "$err" 2>/dev/null)
          rm -f "$err"
        else
          changed=$(bash "$HERE/lib.sh" hq_changed_files "$base" HEAD "$root" 2>/dev/null)
          status=$?
          out=""
        fi
        if [ "$status" -ne 0 ]; then
          add_u "$CHANGELOG was not checked: the diff against $base could not be taken: $out"
        elif ! in_list "$CHANGELOG" "$changed"; then
          add_v "$CHANGELOG is not in the diff against $base — this repository asks for the entry in the pull request that makes the change, and it is the one thing here nobody can add afterwards without a second one"
        fi
      fi
    fi
  fi

  return 0
}

deny() { # <reason>
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "$1")"
}

case "${1:-}" in
  check)
    [ $# -le 2 ] || { echo "usage: pr-gate.sh check [<repo-root>]" >&2; exit 2; }
    root="${2:-$(git rev-parse --show-toplevel 2>/dev/null)}"
    [ -n "$root" ] || { echo "pr-gate.sh: not in a git repository" >&2; exit 2; }
    [ -d "$root" ] || { echo "pr-gate.sh: not a directory: $root" >&2; exit 2; }

    inspect "$root"

    # Both kinds go to stdout, told apart by a prefix; the exit code says
    # which kind decided it.
    [ -n "$VIOLATIONS" ] && printf '%s' "$VIOLATIONS"
    [ -n "$UNCHECKED" ] && printf '%s' "$UNCHECKED" | sed 's/^/unchecked: /'
    [ -n "$VIOLATIONS" ] && exit 1
    [ -n "$UNCHECKED" ] && exit 2
    exit 0
    ;;

  hook)
    payload=$(cat 2>/dev/null) || exit 0
    [ -n "$payload" ] || exit 0

    # THE DETECTION IS A SUBSTRING TEST OVER THE WHOLE PAYLOAD, loose on
    # purpose: a shell command is full of quotes, so a `[^"]*` capture of
    # `tool_input.command` stops at the first `\"` and yields a prefix.
    # Over-firing is loud and recoverable; under-firing is the whole gate
    # gone. The cost is that a Bash call merely MENTIONING the phrase is
    # judged too.
    case "$payload" in
      *'gh pr create'*) ;;
      *) exit 0 ;;
    esac

    # The session's directory, because a session may sit in a subdirectory of
    # the repository. Narrow read: this value cannot contain an unescaped
    # quote, so stopping at the first one is safe — unlike the command.
    cwd=$(printf '%s' "$payload" \
      | /usr/bin/grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    [ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$PWD

    root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
    [ -n "$root" ] || exit 0

    inspect "$root"
    [ -n "$VIOLATIONS" ] || exit 0

    # What could not be evaluated goes in the reason too, and never on its own.
    # A caller being stopped is entitled to know which of the conditions nobody
    # asked — but a launch stopped BY that silence would be a run stopped for
    # the gate's own failure.
    deny "This branch is not ready for a pull request:
$VIOLATIONS$([ -n "$UNCHECKED" ] && printf 'And these were not checked at all:\n%s' "$UNCHECKED")
Fix these and try again. What a plan has to look like is in $CONTRACT. Do not work around this by opening the pull request another way — the same conditions are what the reviewer reads the diff against."
    exit 0
    ;;

  *)
    echo "usage: pr-gate.sh {check [<repo-root>]|hook}" >&2
    exit 2
    ;;
esac
