#!/usr/bin/env bash
# hq plan gate — checks the shape of a plan file.
#
#   plan-gate.sh check <file>
#       Prints one line per problem. exit 0 clean, 1 problems found, 2 usage.
#
#   plan-gate.sh surface <file> <base> [<repo-root>]
#       The set difference between the paths `## Editable surface` declares and
#       the paths the branch actually changed, reported in both directions.
#       exit 0 when they agree, 1 when they do not, 2 when the diff could not
#       be taken. A person runs this at the end of a pass; the hook below asks
#       one half of the same question after every commit.
#
#   plan-gate.sh hook
#       Reads a PostToolUse payload (JSON) on stdin and prints
#           {"decision":"block","reason":"..."}
#       for either of two things, and nothing otherwise. Exits 0 on every path.
#         - a plan file was written and its shape is wrong
#         - a commit just happened and it carries paths the plan does not
#           declare
#
# THE FENCE IS CHECKED AFTER EVERY COMMIT, IN ONE DIRECTION. `## Editable
# surface` is the plan's positive set of paths the work may touch; whenever a
# Bash call names `git commit`, the hook asks the half that is decidable then
# — paths changed and never declared. Entries declared and not yet touched are
# the ordinary state of a branch part way through its plan; the `surface` face
# asks both, once, at the end of a pass.
#
# The reach stops where the commit does: a change sitting in the working tree
# is invisible to `git diff base...HEAD`, and nothing here says so.
#
# WHAT IT DOES NOT CHECK. Whether the plan is any good — whether these are the
# right outcomes, whether the survey found what mattered. Those are judgments,
# and running a floor command would mean executing a string out of the plan.
# THE PLAN IS UNTRUSTED INPUT: nothing in it is ever executed here, in any
# mode. The command test below is a PATH lookup (`command -v` resolves a name,
# it never runs it) plus a test for shell metacharacters, and `set -f` keeps an
# unquoted token from pathname-expanding.
#
# THE CONTRACT IS NOT DEFINED HERE: what a plan file must look like is written
# once, in plugin/commands/plan.md, and the block reason points there
# rather than restating it. The lists below are the machine-readable half of
# that contract, and a test checks them against the document.
#
# WHERE THE SCANNER IS ABSENT, BOTH FACES SAY SO. `check` exits 2 with a
# message; the hook blocks with the reason. A plan nobody could check reads
# exactly like a plan that was checked and found clean.
#
# Portability: bash 3.2, BSD userland.

set -u
set -f

# Arm the fail-open trap before anything else can go wrong in hook mode.
case "${1:-}" in hook) trap 'exit 0' EXIT ;; esac

# Byte-oriented, pinned once: under a multibyte locale BSD awk and sed abort
# on an invalid byte having already emitted what they got through — the item
# list truncates, the violating item is never seen, and the plan passes.
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || HERE=""

# The sections a plan must carry. The separator is `|` because one of the
# names has a space in it. There are no optional ones: `## Plan` is written
# later, by the builder, and is checked here only when it is present.
REQUIRED_SECTIONS="Summary|Requirements|Notes|Editable surface|Floor"

# The tags an `## Editable surface` entry chooses between, read as a set
# below, and the tags a `## Requirements` row chooses between. Both are sets:
# an entry is one kind of change, and a row is confirmed by one party.
SURFACE_TAGS="new edit delete"
CONFIRM_TAGS="manual review"

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

# One record per line, under the section it appeared in:
#   `S<TAB><section>`             a heading
#   `I<TAB><section><TAB><item>`  a list item
#   `R<TAB><section><TAB><row>`   a table row
#   `B<TAB><section>`             a line of body prose
# Everything else — blank lines, fenced content — contributes nothing.
#
# Four properties, and each one is a way a scan goes quietly wrong:
#   - fenced lines are neither headings nor items: a `## Plan` quoted inside a
#     code block would otherwise end the real section there.
#   - `## ` starts and resets a section, `### ` does not: a plan is free to
#     subdivide a section without falling out of it.
#   - leading whitespace is trimmed, so an indented item is still an item.
#   - a table row is its own kind, not an item: `## Requirements` is a table
#     and `## Plan` is a list, and a scan that folded the two together would
#     let a row satisfy a list's predicates and the other way about.
scan() { # <file>
  "$AWK" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    !fence && /^##([[:space:]]|$)/ {
      h = $0; sub(/^##[[:space:]]*/, "", h)
      sec = trim(h)
      print "S\t" sec
      next
    }
    !fence && sec != "" && /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]/ {
      print "I\t" sec "\t" trim($0)
      next
    }
    !fence && sec != "" && /^[[:space:]]*\|/ {
      print "R\t" sec "\t" trim($0)
      next
    }
    !fence && sec != "" && trim($0) != "" { print "B\t" sec }
  ' "$1" 2>/dev/null
}

# The Nth `|`-delimited cell of a table row, trimmed. A row starts with `|`,
# so the first cell is empty and the columns a reader sees begin at 2.
cell() { # <row> <n>
  printf '%s\n' "$1" | "$AWK" -F'|' -v n="$2" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    { print (n <= NF ? trim($n) : "") }'
}

# Is this row the head or the rule of a table, rather than a row of data? Both
# are shape, and neither carries a requirement.
#
# AN EMPTY FIRST COLUMN IS NOT FURNITURE. A row that lost its id still says
# something in its other cells, and skipping it would drop a requirement
# without a word — the exact shape of failure this gate exists to stop. Only a
# row with nothing in it at all is shape.
is_table_furniture() { # <row>
  case "$(cell "$1" 2)" in
    '#') return 0 ;;
  esac
  # `|---|:--:|` and friends: a rule is dashes and colons and nothing else.
  # A row of empty cells reduces to the same characters and is caught here too.
  case "$1" in
    *[!\|:\ -]*) return 1 ;;
    *) return 0 ;;
  esac
}

# The single-backtick spans of one line, in order: a span is the text between
# an opening and a CLOSING backtick, so an unbalanced trailing one
# contributes nothing.
spans() { # <item>
  printf '%s\n' "$1" | "$AWK" -F'`' '{ for (i = 2; i <= NF - 1; i += 2) print $i }'
}

is_box() { # <item> — a checkbox list item, checked or not
  local s=$1
  case "$s" in -*) s=${s#-} ;; *) return 1 ;; esac
  while :; do
    case "$s" in ' '*) s=${s# } ;; *) break ;; esac
  done
  case "$s" in
    '[ ]'*|'[x]'*|'[X]'*) return 0 ;;
    *) return 1 ;;
  esac
}

has_tag() { # <item> <tag>
  case "$1" in *"[$2]"*) return 0 ;; *) return 1 ;; esac
}

# The first token of a shell fragment, skipping leading `VAR=value` assignments
# so that `LC_ALL=C awk ...` answers `awk`. Splitting is on whitespace, and
# `set -f` at the top keeps a token like `*.md` from pathname-expanding.
first_word() { # <fragment>
  local IFS=$' \t\n'
  set -- $1
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*)
        case "${1%%=*}" in
          *[!A-Za-z0-9_]*) ;;      # not a valid name — it IS the command word
          *) shift; continue ;;
        esac
        ;;
    esac
    printf '%s' "$1"
    return 0
  done
  return 0
}

# The span up to the first shell separator: `a && b` and `a | b` both start
# with `a`, and that is the part whose first word names the command.
first_segment() { # <span>
  local s=$1
  s=${s%%&&*}
  s=${s%%|*}
  s=${s%%;*}
  printf '%s' "$s"
}

# Is this span a command? One test and no vocabulary list: the first word of
# its first segment resolves through a PATH / builtin lookup. Every function in
# this file would also resolve, which is why none of them is named like
# something a plan would write.
#
# The lookup is as coarse as the filesystem under it: where lookups are
# case-insensitive — the macOS default — `Write` resolves to `write`. That
# makes the test accept slightly more than it appears to, which is the
# harmless direction.
is_command() { # <span>
  local word
  word=$(first_word "$(first_segment "$1")")
  [ -n "$word" ] || return 1
  command -v -- "$word" >/dev/null 2>&1
}

# Is this span a command LINE — something an item could be running as a second
# assertion? A bare word is not, even when it resolves: `test` and `head` are
# ordinary English in a note. The cases the whitespace requirement lets
# through cost a weaker item, not a stopped run.
is_command_line() { # <span>
  case "$1" in
    *[[:space:]]*) is_command "$1" ;;
    *) return 1 ;;
  esac
}

# --- the fence --------------------------------------------------------------

# The paths the `## Editable surface` entries declare: the first backticked
# span of each entry, one per line.
fence_paths() { # <file>
  local type sec item p
  while IFS=$'\t' read -r type sec item; do
    [ "$type" = I ] || continue
    [ "$sec" = "Editable surface" ] || continue
    p=$(spans "$item" | head -1)
    [ -n "$p" ] && printf '%s\n' "$p"
  done <<EOF
$(scan "$1")
EOF
  return 0
}

# Does a fence entry cover this path? An entry ending in `/` covers everything
# under it; every other entry matches its path exactly.
matches() { # <entry> <path>
  case "$1" in
    */) case "$2" in "$1"*) return 0 ;; esac ;;
    *)  [ "$2" = "$1" ] && return 0 ;;
  esac
  return 1
}

# Is this path covered by any entry, or this entry touched by any path? One
# question asked in both directions.
any_match() { # <fixed side> <list> <direction: entry|path>
  local other
  while IFS= read -r other; do
    [ -n "$other" ] || continue
    if [ "$3" = entry ]; then
      matches "$1" "$other" && return 0
    else
      matches "$other" "$1" && return 0
    fi
  done <<EOF
$2
EOF
  return 1
}

# The changed paths, with git's own chatter kept off the list. Fills CHANGED;
# on failure fills CHANGED_ERR. exit 0: CHANGED holds the paths (CHANGED_ERR
# may hold a warning); exit 3: the diff could not be taken.
#
# NEVER `2>&1`: git writes warnings while exiting 0, and every line it writes
# would become a path in this list. lib.sh is called as a subprocess rather
# than sourced: this file sources nothing, so a syntax error over there
# cannot be swallowed by the fail-open trap.
CHANGED=""
CHANGED_ERR=""
take_changed() { # <base> <repo-root>
  local err status
  CHANGED=""; CHANGED_ERR=""
  err=$(mktemp) || { CHANGED_ERR="mktemp failed, so the diff could not be taken"; return 3; }
  CHANGED=$(bash "$HERE/lib.sh" hq_changed_files "$1" HEAD "$2" 2>"$err")
  status=$?
  CHANGED_ERR=$(cat "$err" 2>/dev/null)
  rm -f "$err"
  [ "$status" -eq 0 ] || return 3
  return 0
}

# NOTHING IN THE REPOSITORY IS OUTSIDE THE FENCE. The run's working files live
# under the home (lib.sh, `hq_task_dir`) and never reach a diff; a path under
# `.hq` in a diff is a repository fact, and the fence governs it like any
# other.

# The half of the set difference that is decidable at any commit: the paths
# this branch has changed that no fence entry covers. exit 0 inside the fence
# (nothing printed), 1 the offending paths one per line, 2 a message saying
# why the question could not be answered — not folded into the first, because
# a base that does not resolve makes `git diff` return nothing and the gate
# would report a clean fence for every commit on a branch it could not diff.
#
fence_problem() { # <plan file> <repo-root>
  local plan=$1 root=$2 base changed status declared outside f
  # Without the scanner the declared set comes back EMPTY, and an empty fence
  # makes every path in the diff a violation. That is the one wrong answer this
  # function can give, so the check for it comes first.
  have_awk || { printf 'the scanner it needs is not on PATH (looked for: %s)' "$AWK"; return 2; }
  [ -n "$HERE" ] && [ -f "$HERE/lib.sh" ] || {
    printf 'lib.sh is not beside this script, so the diff could not be taken'
    return 2
  }
  base=$(bash "$HERE/lib.sh" hq_resolve_base "$root" 2>/dev/null)
  [ -n "$base" ] || { printf 'the base branch did not resolve'; return 2; }

  take_changed "$base" "$root" || {
    printf 'the diff against %s could not be taken: %s' "$base" "$CHANGED_ERR"
    return 2
  }
  changed=$CHANGED

  declared=$(fence_paths "$plan")
  outside=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    any_match "$f" "$declared" path || outside="$outside$f
"
  done <<EOF
$changed
EOF

  [ -n "$outside" ] || return 0
  printf '%s' "$outside"
  return 1
}

# --- the checks -------------------------------------------------------------

# Fills PROBLEMS with one line per problem; empty means the plan is well
# formed. Returns 0 either way — the caller decides what a problem means.
PROBLEMS=""

# The headings the scan found, as `|name|` runs. A section name can hold a
# space, so the set is a delimited string rather than a word list.
SEEN=""
seen() { # <section>
  case "$SEEN" in *"|$1|"*) return 0 ;; *) return 1 ;; esac
}

inspect() { # <file>
  local type sec item structural items s tag hits row id ids
  local summary_lines=0 req_rows=0 notes_items=0 surface_items=0
  local plan_boxes=0 floor_items=0
  local i span first_cmd nspans

  PROBLEMS=""
  items=""
  structural=""
  SEEN=""
  ids=""

  while IFS=$'\t' read -r type sec item; do
    case "$type" in
      S) SEEN="$SEEN|$sec|"; continue ;;
      B) [ "$sec" = Summary ] && summary_lines=$((summary_lines + 1)); continue ;;
      R) ;;
      I) ;;
      *) continue ;;
    esac

    # --- table rows -------------------------------------------------------
    if [ "$type" = R ]; then
      [ "$sec" = Requirements ] || continue
      row=$item
      is_table_furniture "$row" && continue
      req_rows=$((req_rows + 1))

      id=$(cell "$row" 2)
      case "$id" in
        R[0-9]*)
          case "${id#R}" in
            *[!0-9]*) items="$items## Requirements: the id is not R<digits>: $id
" ;;
            *) case "$ids" in
                 *"|$id|"*) items="$items## Requirements: two rows carry the id $id — an id names one row
" ;;
                 *) ids="$ids|$id|" ;;
               esac ;;
          esac
          ;;
        *) items="$items## Requirements: the first column is not an id of the form R<digits>: $id
" ;;
      esac

      [ -n "$(cell "$row" 3)" ] || \
        items="$items## Requirements: $id states no outcome
"

      s=$(cell "$row" 4)
      if [ -z "$s" ]; then
        items="$items## Requirements: $id says how nobody confirms it — an outcome nobody can confirm is a wish
"
      else
        hits=0
        for tag in $CONFIRM_TAGS; do
          has_tag "$s" "$tag" && hits=$((hits + 1))
        done
        case "$hits" in
          1) ;;
          0) items="$items## Requirements: $id carries none of [$(printf '%s' "$CONFIRM_TAGS" | tr ' ' '|')] — say who confirms it
" ;;
          *) items="$items## Requirements: $id carries $hits of [$(printf '%s' "$CONFIRM_TAGS" | tr ' ' '|')] — one party confirms one row
" ;;
        esac
      fi
      continue
    fi

    # --- list items -------------------------------------------------------
    case "$sec" in
      # A list item is content like any other line: `## Summary` written as
      # bullets is not an empty summary, and `## Notes` is a list to begin
      # with.
      Summary) summary_lines=$((summary_lines + 1)) ;;
      Notes) notes_items=$((notes_items + 1)) ;;
    esac

    case "$sec" in
      "Editable surface")
        surface_items=$((surface_items + 1))
        [ -n "$(spans "$item" | head -1)" ] || \
          items="$items## Editable surface: no backticked path: $item
"
        hits=0
        for tag in $SURFACE_TAGS; do
          has_tag "$item" "$tag" && hits=$((hits + 1))
        done
        case "$hits" in
          1) ;;
          0) items="$items## Editable surface: carries none of [$(printf '%s' "$SURFACE_TAGS" | tr ' ' '|')]: $item
" ;;
          *) items="$items## Editable surface: carries $hits of [$(printf '%s' "$SURFACE_TAGS" | tr ' ' '|')] — an entry is one kind of change: $item
" ;;
        esac
        ;;

      # `## Plan` is the builder's, written after it designs. It is not
      # required here; when it is present it is checked, because the ship gate
      # counts these boxes and a numbered line it cannot see is a work item
      # nothing counts.
      Plan)
        if is_box "$item"; then
          plan_boxes=$((plan_boxes + 1))
        else
          items="$items## Plan: not a checkbox item: $item
"
        fi
        ;;

      Floor)
        floor_items=$((floor_items + 1))
        is_box "$item" || items="$items## Floor: not a checkbox item: $item
"

        # The command checks run on `[auto]` items only. An item without the
        # tag has already been named for that, and asking a second time what
        # command it fails to carry buries the one problem it has.
        if ! has_tag "$item" auto; then
          items="$items## Floor: carries no [auto] — every floor item is one the machine runs: $item
"
          continue
        fi

        i=0; nspans=0; first_cmd=0
        while IFS= read -r span; do
          [ -n "$span" ] || continue
          i=$((i + 1)); nspans=$i
          if [ "$i" -eq 1 ]; then
            is_command "$span" && first_cmd=1
          elif is_command_line "$span"; then
            # Two assertions joined by prose are half-run in practice, and the
            # unrun half is where the defect sits. One shell string.
            items="$items## Floor: backticked span #$i is a second command — fold the assertions into one shell string: \`$span\`
"
          fi
        done <<EOF
$(spans "$item")
EOF
        if [ "$nspans" -eq 0 ]; then
          items="$items## Floor: no backticked command: $item
"
        elif [ "$first_cmd" -eq 0 ]; then
          items="$items## Floor: the first backticked span does not resolve as a command: $item
"
        fi
        ;;
    esac
  done <<EOF
$(scan "$1")
EOF

  # Every required section, in the order the contract lists them, reported
  # once per missing section: each one is a different thing to go and write.
  local old_ifs=$IFS
  IFS='|'
  for s in $REQUIRED_SECTIONS; do
    [ -n "$s" ] || continue
    seen "$s" || structural="${structural}no ## $s section
"
  done
  IFS=$old_ifs

  # Present but empty: a heading with nothing under it passes a presence test
  # and carries none of what the section exists to carry.
  seen Summary && [ "$summary_lines" -eq 0 ] && structural="${structural}## Summary is empty — three to five lines saying what this change does, in this repository's own words
"
  seen Requirements && [ "$req_rows" -eq 0 ] && \
    structural="${structural}## Requirements holds no row — one row per outcome, with how anyone confirms it
"
  seen Notes && [ "$notes_items" -eq 0 ] && \
    structural="${structural}## Notes holds no list item — what the survey found that the work has to reckon with, and what you left alone and why
"
  seen "Editable surface" && [ "$surface_items" -eq 0 ] && \
    structural="${structural}## Editable surface holds no entry — it is the positive set, so an empty one declares that nothing may be touched
"
  seen Floor && [ "$floor_items" -eq 0 ] && \
    structural="${structural}## Floor holds no item — the machine checks any implementation of this must pass
"
  seen Plan && [ "$plan_boxes" -eq 0 ] && \
    structural="${structural}## Plan holds no checkbox item — the builder writes its work items here, and the pull request gate counts them
"

  PROBLEMS="$structural$items"
  return 0
}

# --- the faces --------------------------------------------------------------

# WHAT A GATE STOPS LEAVES NO TRACE. The commit that was refused never
# happened, so afterwards a gate that fires on every branch and one that has
# never fired look identical — and the question "is this gate still earning
# its place" has no evidence either way. One row per refusal is that evidence.
#
# Only the refusing paths write one, so the common path is untouched. A sink
# that cannot be written is never allowed to fail the gate: letting a bad
# commit through because telemetry broke is the wrong trade in every direction.
note_gate() { # <gate> <outcome>
  [ -n "$HERE" ] && [ -f "$HERE/record.sh" ] || return 0
  bash "$HERE/record.sh" gate name="$1" outcome="$2" >/dev/null 2>&1 || return 0
  return 0
}

deny_unchecked() { # <why>
  printf '{"decision":"block","reason":"%s"}\n' \
    "$(json_escape "The plan was NOT checked: $1. Nothing downstream checks it either — hq:implement, the pull request gate and the reviewer all read it as it stands. Verify its shape by hand against $CONTRACT.")"
}

# The plan file this session's branch owns. Derived from the branch rather
# than from anything in the payload, by asking lib.sh — the one place this
# plugin decides where a run's working files live. Non-zero when there is no
# answer: outside a repository, or on a detached HEAD.
#
# lib.sh is called as a subprocess rather than sourced, for the reason at
# take_changed above.
plan_path_for_branch() { # <repo-root>
  local dir
  [ -n "$HERE" ] && [ -f "$HERE/lib.sh" ] || return 1
  dir=$(bash "$HERE/lib.sh" hq_task_dir "$1" 2>/dev/null) || return 1
  [ -n "$dir" ] || return 1
  printf '%s/plan.md' "$dir"
}

case "${1:-}" in
  check)
    [ $# -eq 2 ] || { echo "usage: plan-gate.sh check <file>" >&2; exit 2; }
    [ -f "$2" ] || { echo "plan-gate.sh: cannot read $2" >&2; exit 2; }
    have_awk || { echo "plan-gate.sh: $AWK not found; shape unchecked" >&2; exit 2; }
    inspect "$2"
    [ -n "$PROBLEMS" ] || exit 0
    printf '%s' "$PROBLEMS"
    exit 1
    ;;

  surface)
    [ $# -ge 3 ] || { echo "usage: plan-gate.sh surface <file> <base> [<repo-root>]" >&2; exit 2; }
    [ -f "$2" ] || { echo "plan-gate.sh: cannot read $2" >&2; exit 2; }
    have_awk || { echo "plan-gate.sh: $AWK not found" >&2; exit 2; }
    root="${4:-$(git rev-parse --show-toplevel 2>/dev/null)}"
    [ -n "$root" ] || { echo "plan-gate.sh: not in a git repository" >&2; exit 2; }
    [ -n "$HERE" ] && [ -f "$HERE/lib.sh" ] || {
      echo "plan-gate.sh: lib.sh is not beside this script; the diff cannot be taken" >&2; exit 2; }

    # The diff comes from lib.sh, and its exit 3 must not be read as an empty
    # diff: a base that does not resolve would otherwise report every declared
    # entry as untouched and nothing as outside the fence.
    take_changed "$3" "$root" || {
      printf 'plan-gate.sh: the diff could not be taken against %s:\n%s\n' "$3" "$CHANGED_ERR" >&2
      exit 2
    }
    changed=$CHANGED
    # A person is reading this face, so anything git said on the way reaches
    # them — on the stream it was written to, where it cannot be mistaken for a
    # path. The hook stays quiet instead: its stderr is the harness's.
    [ -n "$CHANGED_ERR" ] && printf '%s\n' "$CHANGED_ERR" >&2

    declared=$(fence_paths "$2")
    outside=""
    untouched=""

    while IFS= read -r f; do
      [ -n "$f" ] || continue
      any_match "$f" "$declared" path || outside="$outside$f
"
    done <<EOF
$changed
EOF

    while IFS= read -r d; do
      [ -n "$d" ] || continue
      any_match "$d" "$changed" entry || untouched="$untouched$d
"
    done <<EOF
$declared
EOF

    [ -z "$outside" ] && [ -z "$untouched" ] && exit 0
    [ -n "$outside" ] && printf '%s' "$outside" | sed 's/^/outside the fence: /'
    [ -n "$untouched" ] && printf '%s' "$untouched" | sed 's/^/declared, untouched: /'
    exit 1
    ;;

  hook)
    payload=$(cat 2>/dev/null) || exit 0
    [ -n "$payload" ] || exit 0

    # Nothing below can fire unless the payload names the plan file or a
    # commit: the Write/Edit branch requires a file_path ending in plan.md, and
    # the Bash branch requires plan.md or `git commit` in the command — all of
    # them substrings of the payload. Deciding that first, with no subprocess,
    # keeps the common path at the cost of this one comparison.
    case "$payload" in
      *plan.md*|*'git commit'*) ;;
      *) exit 0 ;;
    esac

    tool=$(printf '%s' "$payload" \
      | /usr/bin/grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 | sed 's/.*"\([^"]*\)"$/\1/')

    # Both ways the file gets written. The plan is composed in the root
    # session, which holds Bash as well as Write, so a heredoc into the plan
    # path is an ordinary thing for it to do — and hq:implement later toggles
    # checkboxes with Edit. A gate watching one of the three would be bypassed
    # by the others.
    case "$tool" in
      Write|Edit)
        path=$(printf '%s' "$payload" \
          | /usr/bin/grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
          | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        [ -n "$path" ] || exit 0
        case "$path" in
          */plan.md) ;;
          *) exit 0 ;;
        esac

        # WHETHER THIS IS ONE OF OUR PLANS IS ASKED OF lib.sh, NOT OF THE
        # STRING: a pattern here would be a second copy of the layout.
        # Anything the derivation does not claim — a plan.md in somebody's
        # notes, another repository's run — leaves quietly.
        root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
        [ -n "$root" ] || exit 0
        want=$(plan_path_for_branch "$root") || exit 0
        wantdir=${want%/*}          # …/tasks/<branch-dir>
        tasks=${wantdir%/*}         # …/tasks, this repository's whole run tree
        cur=${wantdir##*/}          # the branch's own directory name

        # Both sides are resolved before being compared: a prefix test on the
        # strings answers "no" whenever the two spell one directory
        # differently — `/var/...` against `/private/var/...` on macOS — and
        # the check would quietly apply to nothing. Resolving also folds a
        # relative path into the same test.
        tasksp=$(cd "$tasks" 2>/dev/null && pwd -P) || exit 0
        pdir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || exit 0
        case "$pdir" in
          "$tasksp"/*) ;;
          *) exit 0 ;;
        esac

        # The directory a plan sits in IS the branch it belongs to: a plan
        # written while a different branch is checked out lands where no
        # later reader will look — and the write succeeds, so nothing else
        # says otherwise. A detached HEAD never reaches here:
        # plan_path_for_branch has no answer for it.
        dir=${pdir##*/}
        if [ "$dir" != "$cur" ]; then
          note_gate plan-location block
          printf '{"decision":"block","reason":"%s"}\n' \
            "$(json_escape "This plan went to a directory named $dir, but the branch checked out owns $want. Every module that reads a plan derives the directory from the branch, so nothing will find this one. Check out the branch this work belongs on and write it there — do not create another branch to match the directory.")"
          exit 0
        fi
        ;;
      Bash)
        # The command string is not parsed — quoting, variables and redirection
        # make that guesswork. Naming either thing at all is reason to look, and
        # what to look at comes from the branch. Everything else leaves before
        # the two git calls below: this fires on every Bash call in the session.
        case "$payload" in
          *plan.md*|*"git commit"*) ;;
          *) exit 0 ;;
        esac
        root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
        [ -n "$root" ] || exit 0
        path=$(plan_path_for_branch "$root") || exit 0
        [ -f "$path" ] || exit 0

        # A commit makes the fence decidable: the diff now holds what was just
        # committed. The answer comes from the repository, not from the
        # command string, so a call that merely mentions the words cannot
        # produce a false report.
        case "$payload" in
          *"git commit"*)
            fence_out=$(fence_problem "$path" "$root")
            case "$?" in
              1) note_gate fence block
                 printf '{"decision":"block","reason":"%s"}\n' \
                   "$(json_escape "This commit carries paths that $path does not declare under ## Editable surface:
$fence_out
The fence is the positive set of paths this work may touch. Expanding it is allowed and is never silent: add the entry with its note and the reason, and only then keep going. If a path should not have been touched, revert it. The contract is $CONTRACT.")"
                 exit 0 ;;
              2) note_gate fence unchecked
                 printf '{"decision":"block","reason":"%s"}\n' \
                   "$(json_escape "The fence was NOT checked on this commit: $fence_out. Nothing else compares what $path declares against what the branch changed, so this is not a clean result — it is no result. Ask it by hand with: bash $HERE/plan-gate.sh surface $path <base>")"
                 exit 0 ;;
            esac
            ;;
        esac

        # Nothing further to do unless the call also named the plan file, which
        # is where the shape check below picks up.
        case "$payload" in
          *plan.md*) ;;
          *) exit 0 ;;
        esac
        ;;
      *) exit 0 ;;
    esac
    [ -f "$path" ] || exit 0

    # Not being able to check is reported, not passed over: a plan nobody
    # could check reads exactly like one checked and found clean.
    have_awk || { note_gate plan-shape unchecked; deny_unchecked "the scanner it needs is not on PATH (looked for: $AWK)"; exit 0; }

    inspect "$path"
    [ -n "$PROBLEMS" ] || exit 0
    note_gate plan-shape block
    printf '{"decision":"block","reason":"%s"}\n' \
      "$(json_escape "The plan does not have the shape every later module reads it with:
$PROBLEMS
The contract is $CONTRACT. Rewrite the offending items and write the plan again.")"
    exit 0
    ;;

  *)
    echo "usage: plan-gate.sh {check <file>|surface <file> <base> [<repo-root>]|hook}" >&2
    exit 2
    ;;
esac
