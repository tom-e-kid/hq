#!/usr/bin/env bash
# hq telemetry recorder — appends one row per call to the sink (schema 3).
#
# Usage: `record.sh --help` — usage() below is the copy the help test pins.
# `reason` is optional except on `verdict=defer`, where it is required, and
# `directives` is required on `route=micro` and refused on every other row.
#
# Row shape. The envelope is unchanged from schema 2;
# `schema` is what separates the two populations:
#   {"schema":3,"ts":"<ISO8601 UTC>","t":<unix seconds>,"run_id":"<id>",
#    "repo":"<owner/name>","branch":"<branch>","worktree":"<abs path>",
#    "kind":"<kind>","payload":{...}}
#
# Every value that is an enum is checked here, and every unknown key is
# rejected: a typo must fail loudly.
#
# The sink defaults to <HQ_HOME>/stream.jsonl — HQ_HOME being the one knob for
# where hq keeps everything of its own, default ~/.hq — and HQ_SINK overrides
# the file outright so that tests never write to the real one.
#
# HQ_HOME is spelled out here rather than asked of lib.sh, and the expansion
# is one line; record.test.sh pins the two answers to the same root so the
# copy cannot drift on its own.
#
# THIS FILE SOURCES NOTHING. It asks lib.sh one question — which cycle this
# row belongs to — in a SUBPROCESS: a syntax error in a sourced file would
# abort this script and the row would simply not be there, while a broken
# subprocess is a non-zero exit that can be read and answered.
#
# Exit codes: 0 appended, 2 usage / validation error, 1 append failed.

set -u
LC_ALL=C
export LC_ALL

SCHEMA=3

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || HERE=""

# The sink follows the same home as a run's working files (lib.sh, hq_home);
# HQ_SINK names a single file and wins outright — the tests use it.
#
# A RELATIVE HQ_HOME IS REFUSED here as well, where it is read: a relative
# home writes the stream relative to whatever directory the caller was in —
# for a hook, the repository being worked on.
# A MISSING `HOME` IS REFUSED BY NAME here as well, and only on the path that
# actually needs it: with HQ_SINK or an absolute HQ_HOME set, HOME is never
# read, and a guard that fired anyway would stop a recorder that has
# everywhere it needs to write.
case "${HQ_SINK:-}" in
  '') case "${HQ_HOME:-}" in
        '') [ -n "${HOME:-}" ] || {
              printf 'record.sh: none of HQ_SINK, HQ_HOME or HOME is set, so there is nowhere to put the stream. Set HQ_HOME to an absolute path, or HQ_SINK to a file.\n' >&2
              exit 2
            } ;;
        /*) ;;
        *) printf 'record.sh: HQ_HOME must be an absolute path, got %s\n' "$HQ_HOME" >&2; exit 2 ;;
      esac ;;
esac
SINK="${HQ_SINK:-${HQ_HOME:-$HOME/.hq}/stream.jsonl}"

CLASSES="logic drift vacuous-test dead-code security unmet-requirement"
PROFILES="code prose mixed none"
# How hq:implement was entered: `fresh` works a plan's items, `micro` applies a
# fix directive triage sent back. The two spellings ARE the population split —
# `micro-fix` in one row would divide the same route into two groups, and the
# row stays well formed while it does.
ROUTES="fresh micro"
VERDICTS="fix_now defer reject"
SOURCES="review external"
STATES="reviewed not_reviewed"
# Where the loop stopped an external finding — except for the last value,
# which says the finding was not true at all. `false_positive` is a DIFFERENT
# AXIS from the other four: it does not answer the first line's question but
# denies that question's premise, so a series counted over all five reads a
# finding the reviewer got wrong as reach the loop is missing. THE READING,
# in full, so that no other page has to be found for it: a category is carried
# by one element of a row's `findings` array and not by the row, so a reader
# sizing the loop's reach drops that one finding from the population instead of
# counting it, and keeps the rest of the row — the findings recorded beside it
# are still ones the loop could have caught.
CATEGORIES="prevented triaged_away missed out_of_scope false_positive"
# Which gate fired, and what it did. A gate that never fires and a gate that
# fires constantly want opposite decisions, and neither is visible from the
# other rows — a block leaves no trace in the diff, because the thing it
# stopped never happened.
GATES="fence plan-shape plan-location"
# `block` refused the call. `unchecked` could not answer — a gate that could
# not run is not a gate that passed, and folding the two would read as a clean
# result for every run on a machine where the check cannot work.
OUTCOMES="block unchecked"

die() { printf 'record.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

# Written out rather than sliced out of the header comment with a line range:
# a range silently drifts the moment the header is edited.
usage() {
  cat <<'EOF'
Usage:
  record.sh module      name=<id> duration_s=<int> [route=<r>] [profile=<p>]
                        directives=<n>   (route=micro only, and required there,
                                          n >= 1)
  record.sh disposition finding=<id> verdict=<v> source=<s> [class=<c>] [reason=<text>]
  record.sh residual    pr=<n> reviewer=<id> state=<st> [finding=<class>:<category>]...
  record.sh gate        name=<g> outcome=<o>

Values:
  verdict   fix_now | defer | reject
  source    review | external
  state     reviewed | not_reviewed
  class     logic | drift | vacuous-test | dead-code | security |
            unmet-requirement
  category  prevented | triaged_away | missed | out_of_scope | false_positive
  route     fresh | micro
  profile   code | prose | mixed | none
  name      fence | plan-shape | plan-location      (gate rows)
  outcome   block | unchecked                       (gate rows)

A `gate` row is written when a gate refuses a call or cannot answer. Nothing
else records it: what a gate stops leaves no trace in the diff, so a gate that
never fires and one that fires on every commit look identical afterwards.

`directives` is how many fix directives one micro pass was handed. A micro pass
applies all of them and runs the floor once, so the pass duration
divided by this count is the per-directive cost. Every route=micro row must
carry it; no other row may.

`reason` is required when verdict=defer, and optional otherwise. A deferral
leaves the finding true; the row is the only record of what has to hold before
it can be fixed.

The sink defaults to <HQ_HOME>/stream.jsonl (HQ_HOME defaults to ~/.hq) and is
overridable with HQ_SINK.
EOF
}

# --- helpers ---------------------------------------------------------------

# Membership test over a space-separated set: macOS ships bash 3.2, which
# has no associative arrays.
in_set() { # <needle> <set>
  local item
  for item in $2; do [ "$item" = "$1" ] && return 0; done
  return 1
}

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

# Digits only, and no leading zero: `duration_s` is the one value emitted as
# a raw JSON number, and JSON forbids leading zeros — `{"duration_s":08}` is
# a row no reader can parse. Rejected rather than normalised: the caller's
# mistake surfaces at the caller.
is_uint() { # <string>
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 0 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

# Digits only, no leading zero, and not zero: `directives` is emitted as a raw
# JSON number like `duration_s`, and it is a DENOMINATOR — the per-directive
# cost of a micro pass is its duration divided by this value. Zero is refused
# rather than accepted as "none": a pass that applied no directive is not a
# micro pass, and a zero on the row is a division nobody downstream guards.
is_pos_int() { # <string>
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

# An elapsed time no module can have taken, separating a duration from a
# TIMESTAMP: a caller that leaves the start-time placeholder in place records
# the current epoch as a well-formed integer. A year is orders above any real
# run and orders below an epoch.
MAX_DURATION=31536000

# The value every row is scoped by. Other scripts here derive it again to
# decide which rows in a shared stream belong to the repository they were
# asked about: a reader scoping by a slug this writer never wrote matches
# nothing and reports it as nothing to do. Keeping the copies identical is the
# machine's job — sweep.test.sh compares the bodies as text, and editing one
# fails until they all match; they are not extracted into a shared file for
# the reason this file gives above for sourcing nothing at all.
repo_slug() { # <worktree>
  local url name owner rest
  url=$(git -C "$1" config --get remote.origin.url 2>/dev/null) || url=""
  if [ -z "$url" ]; then
    printf '%s' "$(basename "$1")"
    return 0
  fi
  url=${url%.git}
  url=${url%/}
  name=${url##*/}
  rest=${url%/*}
  owner=${rest##*/}
  owner=${owner##*:}
  printf '%s/%s' "$owner" "$name"
}

# --- argument parsing ------------------------------------------------------

KIND=""
KEYS=""
declare -a FINDINGS
FINDINGS=()

get() { # <key> — echoes the collected value, empty when unset
  eval "printf '%s' \"\${KV_$1:-}\""
}

set_kv() { # <key> <value>
  eval "KV_$1=\$2"
}

# --- main ------------------------------------------------------------------

[ $# -ge 1 ] || { usage >&2; exit 2; }

case "$1" in
  -h|--help|help) usage; exit 0 ;;
esac

KIND=$1
shift

case "$KIND" in
  module)      required="name duration_s"; allowed="name duration_s route profile directives" ;;
  disposition) required="finding verdict source"; allowed="finding verdict source class reason" ;;
  residual)    required="pr reviewer state"; allowed="pr reviewer state finding" ;;
  gate)        required="name outcome"; allowed="name outcome" ;;
  *) die "unknown kind '$KIND' (module | disposition | residual | gate)" ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    *=*) ;;
    *) die "expected key=value, got '$1'" ;;
  esac
  key=${1%%=*}
  val=${1#*=}
  [ -n "$key" ] || die "empty key in '$1'"
  in_set "$key" "$allowed" || die "kind '$KIND' does not accept key '$key' (allowed: $allowed)"

  if [ "$KIND" = residual ] && [ "$key" = finding ]; then
    FINDINGS[${#FINDINGS[@]}]=$val
  else
    case " $KEYS " in
      *" $key "*) die "duplicate key '$key'" ;;
    esac
    KEYS="$KEYS $key"
    set_kv "$key" "$val"
  fi
  shift
done

for key in $required; do
  case " $KEYS " in
    *" $key "*) ;;
    *) die "kind '$KIND' requires '$key='" ;;
  esac
done

# --- per-kind validation ---------------------------------------------------

case "$KIND" in
  module)
    is_uint "$(get duration_s)" || die "duration_s must be a non-negative integer, got '$(get duration_s)'"
    [ "$(get duration_s)" -le "$MAX_DURATION" ] || \
      die "duration_s=$(get duration_s) is not an elapsed time — it is around $(( $(get duration_s) / 31536000 )) years, which is what a unix timestamp looks like. Subtract the start time rather than recording it."
    if [ -n "$(get route)" ]; then
      in_set "$(get route)" "$ROUTES" || die "unknown route '$(get route)' (one of: $ROUTES)"
    fi
    if [ -n "$(get profile)" ]; then
      in_set "$(get profile)" "$PROFILES" || die "unknown profile '$(get profile)' (one of: $PROFILES)"
    fi
    # ONE MICRO PASS CARRIES SEVERAL DIRECTIVES, so the row's duration alone no
    # longer says what one fix cost. This key is the denominator, and it is
    # BOUND TO THE ROUTE THAT HAS ONE IN BOTH DIRECTIONS: every `route=micro`
    # row must carry it, and no other row may.
    #
    # REQUIRED, NOT OPTIONAL, ON THAT ROUTE: a micro row without it is well
    # formed and reads as one fix costing the whole pass, which is the exact
    # misreading this key was added to stop — and it is also indistinguishable
    # from a row written before the count existed, so an absent count would
    # erase the boundary between the two populations. AN EMPTY VALUE IS THE
    # SAME ABSENCE as a missing key.
    #
    # On `fresh`, or on a row that names no route at all, there is nothing for
    # it to count, and a reader dividing by it would be reading a number about
    # some other population. THE KEY'S PRESENCE IS WHAT IS REFUSED THERE, empty
    # value included — an ignored key is a caller's mistake nobody ever sees.
    if [ "$(get route)" = micro ]; then
      [ -n "$(get directives)" ] || \
        die "route=micro requires directives=<n>: one micro pass applies every directive of a triage round and runs the floor once, so its duration is the cost of the round, and only this count turns it back into a per-directive cost. A micro row without it cannot be told from one written before the count existed."
      is_pos_int "$(get directives)" || \
        die "directives must be a positive integer, got '$(get directives)'"
    else
      case " $KEYS " in
        *" directives "*)
          die "directives='$(get directives)' is only accepted with route=micro, and this row has route='$(get route)': the value is how many fix directives one micro pass was handed, and it is what turns that pass's duration into a per-directive cost." ;;
      esac
    fi
    payload=$(printf '{"name":"%s","duration_s":%s' \
      "$(json_escape "$(get name)")" "$(get duration_s)")
    [ -n "$(get route)" ] && payload="$payload$(printf ',"route":"%s"' "$(json_escape "$(get route)")")"
    [ -n "$(get directives)" ] && payload="$payload$(printf ',"directives":%s' "$(get directives)")"
    [ -n "$(get profile)" ] && payload="$payload$(printf ',"profile":"%s"' "$(json_escape "$(get profile)")")"
    payload="$payload}"
    ;;
  disposition)
    in_set "$(get verdict)" "$VERDICTS" || die "unknown verdict '$(get verdict)' (one of: $VERDICTS)"
    in_set "$(get source)" "$SOURCES" || die "unknown source '$(get source)' (one of: $SOURCES)"
    # `reason` is required for one verdict and only one: a deferral leaves
    # the finding true, and this row is the only place the next reader learns
    # what has to hold before it can be fixed. The other two answer for
    # themselves — `fix_now` leaves a diff, `reject` states its case where
    # the finding was raised.
    #
    # AN EMPTY VALUE IS THE SAME ABSENCE AS A MISSING KEY: the payload below
    # drops an empty reason, so one predicate covers both. WHAT MAKES A
    # REASON WORTH WRITING IS NOT DECIDABLE HERE — this guard is the
    # decidable half.
    if [ "$(get verdict)" = defer ] && [ -z "$(get reason)" ]; then
      die "verdict=defer requires reason=<text>: a deferral leaves the finding true, and this row is the only record of what has to hold before it can be fixed"
    fi
    # AN IDENTIFIER STILL CARRYING A PLACEHOLDER: `finding` is a free string,
    # so nothing else here can tell `<ID>` from a real one — the row would be
    # well formed and filed under a finding nobody can look up. THE COST IS A
    # BRANCH NAMED WITH BOTH BRACKETS (git accepts `feat/a<b>c`), whose
    # qualified id cannot be recorded; the message says so.
    case "$(get finding)" in
      *'<'*'>'*)
        die "finding='$(get finding)' still carries a placeholder — substitute the finding's own id, or '<branch>#<id>' when closing a deferral raised elsewhere. (A branch name containing both angle brackets cannot be recorded in the qualified form.)" ;;
    esac
    # THE SAME PLACEHOLDER, ONE FIELD OVER: a caller who substitutes the id
    # and leaves `reason='<WHY>'` writes a deferral whose only record of what
    # has to hold is the word WHY. THE COST is a reason that legitimately
    # needs both brackets, which has to be worded differently.
    case "$(get reason)" in
      *'<'*'>'*)
        die "reason='$(get reason)' still carries a placeholder — write what has to hold before this finding can be fixed. (A reason needing both angle brackets has to be worded without them.)" ;;
    esac
    if [ -n "$(get class)" ]; then
      in_set "$(get class)" "$CLASSES" || die "unknown class '$(get class)' (one of: $CLASSES)"
    fi
    payload=$(printf '{"finding":"%s","verdict":"%s","source":"%s"' \
      "$(json_escape "$(get finding)")" "$(get verdict)" "$(get source)")
    [ -n "$(get class)" ] && payload="$payload$(printf ',"class":"%s"' "$(get class)")"
    [ -n "$(get reason)" ] && payload="$payload$(printf ',"reason":"%s"' "$(json_escape "$(get reason)")")"
    payload="$payload}"
    ;;
  residual)
    in_set "$(get state)" "$STATES" || die "unknown state '$(get state)' (one of: $STATES)"
    if [ "$(get state)" = not_reviewed ] && [ ${#FINDINGS[@]} -gt 0 ]; then
      die "state=not_reviewed cannot carry findings"
    fi
    findings_json="["
    i=0
    while [ $i -lt ${#FINDINGS[@]} ]; do
      entry=${FINDINGS[$i]}
      case "$entry" in
        *:*) ;;
        *) die "finding must be '<class>:<category>', got '$entry'" ;;
      esac
      fclass=${entry%%:*}
      fcat=${entry#*:}
      in_set "$fclass" "$CLASSES" || die "unknown class '$fclass' (one of: $CLASSES)"
      in_set "$fcat" "$CATEGORIES" || die "unknown category '$fcat' (one of: $CATEGORIES)"
      [ $i -gt 0 ] && findings_json="$findings_json,"
      findings_json="$findings_json$(printf '{"class":"%s","category":"%s"}' "$fclass" "$fcat")"
      i=$((i + 1))
    done
    findings_json="$findings_json]"
    payload=$(printf '{"pr":"%s","reviewer":"%s","state":"%s","findings":%s}' \
      "$(json_escape "$(get pr)")" "$(json_escape "$(get reviewer)")" "$(get state)" "$findings_json")
    ;;
  gate)
    in_set "$(get name)" "$GATES" || die "unknown gate '$(get name)' (one of: $GATES)"
    in_set "$(get outcome)" "$OUTCOMES" || die "unknown outcome '$(get outcome)' (one of: $OUTCOMES)"
    payload=$(printf '{"name":"%s","outcome":"%s"}' "$(get name)" "$(get outcome)")
    ;;
esac

# --- envelope + append -----------------------------------------------------

worktree=$(git rev-parse --show-toplevel 2>/dev/null) || worktree=$PWD
branch=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
repo=$(repo_slug "$worktree")

# THE CYCLE THIS ROW BELONGS TO. THE ORDER IS: the environment, then lib.sh,
# then a composed fallback. HQ_RUN_ID wins outright — it files a row under a
# cycle this shell knows nothing about, and the tests use it. lib.sh keeps
# the identifier in a file under the run's own directory, so every call on
# one branch reads the same value; only its stdout is used — a message on the
# way out would otherwise become the identifier itself.
#
# THE FALLBACK IS REACHED exactly where there is no cycle to name: outside a
# repository, on a detached HEAD, with no home, or with this script copied
# away from lib.sh. A row still has to be written there, and it carries no
# branch, so it names none: `<dir>-<branch>-<stamp>` came from a cycle,
# `<dir>-<stamp>` from somewhere that has none.
run_id="${HQ_RUN_ID:-}"
if [ -z "$run_id" ] && [ -n "$HERE" ] && [ -f "$HERE/lib.sh" ]; then
  run_id=$(bash "$HERE/lib.sh" hq_run_id "$worktree" 2>/dev/null) || run_id=""
fi
[ -n "$run_id" ] || run_id="$(basename "$worktree")-$(date -u +%Y%m%dT%H%M%S)"

line=$(printf '{"schema":%s,"ts":"%s","t":%s,"run_id":"%s","repo":"%s","branch":"%s","worktree":"%s","kind":"%s","payload":%s}' \
  "$SCHEMA" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date +%s)" \
  "$(json_escape "$run_id")" "$(json_escape "$repo")" "$(json_escape "$branch")" \
  "$(json_escape "$worktree")" "$KIND" "$payload")

mkdir -p "$(dirname "$SINK")" 2>/dev/null || die "cannot create sink directory" 1
# One line per call, well under PIPE_BUF and appended with O_APPEND, so
# concurrent writers cannot interleave a row.
printf '%s\n' "$line" >> "$SINK" 2>/dev/null || die "cannot append to $SINK" 1
