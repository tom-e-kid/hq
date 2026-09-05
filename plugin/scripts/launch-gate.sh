#!/usr/bin/env bash
# hq layer-2 gate — refuses to launch an agent this plugin owns when the
# launch prompt is missing something the caller was the only party able to put
# there. Two things, checked independently:
#
#   the repository context, as the listed files stand right now, and
#   the directory this run's files live in.
#
# Both are the caller's to compose and nothing else reads what it composed.
#
#   launch-gate.sh hook
#       Reads the PreToolUse payload (JSON) on stdin. Prints exactly one JSON
#       object when the launch is denied:
#           {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#            "permissionDecision":"deny","permissionDecisionReason":"..."}}
#       and NOTHING on every other path. Silence takes no position and leaves
#       the user's normal permission flow intact; "allow" is never emitted,
#       which would bypass it. Exits 0 on EVERY path — see the trap below.
#
#   launch-gate.sh lint <prompt-file> [<repo-root>]
#       Applies the same rule to a prompt held in a file and says what it found
#       in readable form. exit 0 clean, 1 would-deny, 2 usage OR an expectation
#       it could not form — a not-checked result is never reported as clean. A
#       person runs this, and it must predict what the hook does.
#
# WHAT IT COMPARES. inject.sh frames its output with markers and closes with
# `=== end hq repository context sha256:<hex> ===`; this gate recomputes those
# lines and requires every one as a substring of the raw payload. It does not
# compare the bodies: the payload is JSON from an encoder that is not ours,
# and body comparison would fail on encoding rather than content. The marker
# lines are ASCII whatever the bodies hold, and the digest moves when a
# listed file moves. The exact limit of that guarantee is stated at
# `required_lines` below.
#
# THE ASYMMETRY THAT MATTERS. This hook fires on every agent launch, and a
# false deny stops the run: the gate stays silent unless it can positively
# confirm a mismatch on an owned agent type — every failure of its own
# machinery exits 0 without a word.
#
# THE LAUNCH PROMPT IS UNTRUSTED INPUT. Nothing in it is executed. It is only
# ever pattern-matched, never eval'd, and `set -f` keeps an unquoted token from
# pathname-expanding.
#
# WHAT THE SECOND REQUIREMENT IS FOR. A subagent cannot derive where a run's
# files live — `${CLAUDE_PLUGIN_ROOT}` is substituted at render time and is
# not a shell variable, so an agent cannot reach this plugin's scripts — so
# the caller derives the path and passes it in the prompt. The findings gate
# cannot cover it from the other end: it exits 0 when the file is absent,
# because a review that found nothing writes no file.
#
# One string covers both owned agents: the reviewer's output directory is a
# prefix of the plan path the implementer is given, so one check catches both
# versions of the mistake.
#
# THIS SCRIPT SOURCES NOTHING — not lib.sh, not testlib.sh. It CALLS inject.sh
# and lib.sh in subprocesses: a syntax error in a sourced file would abort this
# hook, and the fail-open trap would make that abort silent — the gate would
# quietly stop existing. A broken subprocess is a non-zero exit this script
# can read and answer with silence.
#
# Portability: bash 3.2, BSD userland. A bash-4-only construct would abort the
# script, and under the trap the abort is silent, which is the one failure this
# file cannot detect in itself.

set -u
set -f

# Arm the fail-open trap before anything else can go wrong in hook mode.
case "${1:-}" in hook) trap 'exit 0' EXIT ;; esac

# Byte-oriented, pinned once. Under a multibyte locale BSD grep and sed abort
# on a byte that is not valid in it, and this file reads a payload assembled by
# the harness out of model-composed text — no byte-level guarantee. Such an
# abort would land in the silent direction.
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || HERE=""
INJECT="$HERE/inject.sh"
LIB="$HERE/lib.sh"

# The agents this plugin owns. A launch of anything else is none of this
# gate's business.
#
# A name here that matches no agent file is the quiet failure: the gate keeps
# passing its own tests while the launch it was added for goes ungated. The
# sweep compares this list against plugin/agents/.
OWNED="hq:reviewer hq:implementer"

BEGIN_MARKER="=== hq repository context ==="

in_set() { # <needle> <space-separated set>
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

# Every line the prompt must contain: the opening marker, one marker per
# listed file, and the closing digest line — all ASCII whatever the files
# hold, so the payload's encoder cannot alter them. The digest alone is not
# enough: a prompt carrying only the closing line would pass while the agent
# runs with none of the context.
#
# WHAT THIS STILL DOES NOT CATCH: a prompt that keeps the markers and the
# current digest while dropping the text between them. The file bodies — the
# only evidence that the content itself arrived — are exactly what the
# encoder may rewrite, and closing that would mean comparing bodies, which
# fails on every launch under a \uXXXX encoder. So the
# guarantee is: something was injected, it was the current version, and it had
# the right shape. Not: every byte of it is present.
#
# Empty output means this gate says nothing at all — it has no expectation to
# compare against, and denying on that would punish the launch for the gate's
# own failure.
required_lines() { # <repo-root>
  [ -n "$HERE" ] || return 0
  [ -f "$INJECT" ] || return 0
  # Asked for, not pattern-matched out of the full output: a context file is
  # markdown, and every pattern loose enough to match a real file marker also
  # matches lines a context file may hold.
  bash "$INJECT" --markers "$1" 2>/dev/null || true
}

# The directory this run's files live in, or nothing when this gate cannot
# hold that expectation. ASKED OF lib.sh RATHER THAN COMPOSED HERE. Empty on
# every failure — a detached HEAD, not a repository, no HOME and no HQ_HOME,
# a plugin tree without lib.sh: none of them are something the caller did to
# this prompt.
#
# A PATH THIS GATE CANNOT COMPARE IS ALSO EMPTY: the payload's encoder may
# emit non-ASCII as \uXXXX and must escape `"` and `\`, so under such a path
# the substring comparison would deny a prompt that carried the path
# perfectly. Silence only means the guarantee is unavailable there.
destination() { # <repo-root>
  local d
  [ -n "$HERE" ] || return 0
  [ -f "$LIB" ] || return 0
  d=$(bash "$LIB" hq_task_dir "$1" 2>/dev/null) || return 0
  [ -n "$d" ] || return 0
  case "$d" in
    *[![:print:]]*|*'"'*|*'\'*) return 0 ;;
  esac
  printf '%s' "$d"
}

deny() { # <reason>
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(json_escape "$1")"
}

# The two ways a prompt can be wrong, told apart by whether any injected
# block is present at all — they need different fixes:
#   absent — nothing was injected; the launch forgot the step.
#   stale  — a block is there but incomplete or out of date; re-running the
#            injector is the fix, and the old text must not be reused.
verdict() { # <prompt text> <required lines>
  local line missing
  missing=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$1" in
      *"$line"*) ;;
      *) missing=$((missing + 1)) ;;
    esac
  done <<EOF
$2
EOF
  [ "$missing" -eq 0 ] && { printf 'ok'; return; }
  case "$1" in
    *"$BEGIN_MARKER"*) printf 'stale' ;;
    *) printf 'absent' ;;
  esac
}

# The reason carries no subject — a sentence naming one gated agent would be
# wrong for the other; the caller puts the launch it is answering in front.
reason_for() { # <verdict>
  case "$1" in
    absent)
      printf 'The repository context is not in this launch prompt. Run `bash %s/inject.sh` and paste its entire output into the prompt verbatim (layer 2).' \
        "$HERE" ;;
    stale)
      printf 'The repository context in this launch prompt is out of date or incomplete — a file it covers has changed since it was pasted, or part of the block did not make it in. Run `bash %s/inject.sh` again and paste the whole block, first line through the sha256 line; do not edit the old one and do not paste only part of it.' \
        "$HERE" ;;
  esac
}

# The path itself goes in the reason: the reader is holding a denial rather
# than a shell, and telling it to derive the path again would be asking for
# the step it just got wrong.
reason_for_destination() { # <task directory>
  printf 'This launch prompt does not carry the directory this run keeps its files in: %s. The agent cannot derive it — a subagent has no access to this plugin'"'"'s scripts — so a launch without it is an agent with nowhere to write. Put that path in the prompt: for the reviewer it is the output directory, for the implementer it is the directory its plan sits in.' \
    "$1"
}

# Everything wrong with this prompt, one `<tag><TAB><reason>` line each. No
# lines covers both "the prompt is right" and "this gate could not form an
# expectation": denying because the gate's own machinery failed would stop
# the run for something the caller did not do.
#
# THE TWO CHECKS ARE INDEPENDENT, and are reported together. They come from
# different scripts, so one being unavailable says nothing about the other;
# and a caller can paste a current context block and still forget the
# destination.
problems() { # <prompt text> <repo-root>
  local expected dest v
  expected=$(required_lines "$2")
  if [ -n "$expected" ]; then
    v=$(verdict "$1" "$expected")
    [ "$v" = ok ] || printf '%s\t%s\n' "$v" "$(reason_for "$v")"
  fi
  dest=$(destination "$2")
  if [ -n "$dest" ]; then
    case "$1" in
      *"$dest"*) ;;
      *) printf '%s\t%s\n' no-destination "$(reason_for_destination "$dest")" ;;
    esac
  fi
}

case "${1:-}" in
  hook)
    payload=$(cat 2>/dev/null) || exit 0
    [ -n "$payload" ] || exit 0

    # Narrow read: this value cannot contain a quote. The prompt is NOT read
    # this way — full of quotes, that capture would yield a prefix — so the
    # comparison runs against the raw payload instead.
    stype=$(printf '%s' "$payload" \
      | /usr/bin/grep -o '"subagent_type"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    [ -n "$stype" ] || exit 0
    in_set "$stype" "$OWNED" || exit 0

    root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    [ -n "$root" ] || exit 0

    probs=$(problems "$payload" "$root")
    [ -n "$probs" ] || exit 0

    # One decision object per launch: several problems become one sentence
    # each in a single reason. The tags are for the lint face, which prints
    # them.
    deny "$stype: $(printf '%s\n' "$probs" | cut -f2- | tr '\n' ' ' | sed 's/ *$//')"
    exit 0
    ;;

  lint)
    [ $# -ge 2 ] || { echo "usage: launch-gate.sh lint <prompt-file> [<repo-root>]" >&2; exit 2; }
    [ -f "$2" ] || { echo "launch-gate.sh: cannot read $2" >&2; exit 2; }
    root="${3:-$(git rev-parse --show-toplevel 2>/dev/null)}"
    [ -n "$root" ] || { echo "launch-gate.sh: not in a git repository" >&2; exit 2; }

    # The hook is silent when it cannot form an expectation; a person running
    # lint is told instead — the one place the two faces differ.
    #
    # NEITHER EXPECTATION SHORT-CIRCUITS THE OTHER, and the ok line names only
    # what was actually compared: a face a person runs before launching must
    # not report not-checked as checked.
    expected=$(required_lines "$root")
    dest=$(destination "$root")
    probs=$(problems "$(cat "$2")" "$root")

    unchecked=""
    [ -n "$expected" ] || unchecked="${unchecked}unchecked: the repository context could not be derived — inject.sh failed, or is not beside this script
"
    [ -n "$dest" ] || unchecked="${unchecked}unchecked: the run's directory could not be derived, or holds bytes this gate cannot compare through the payload's encoder
"
    [ -n "$unchecked" ] && printf '%s' "$unchecked" >&2

    if [ -z "$probs" ]; then
      if [ -n "$unchecked" ]; then
        # Nothing to report and something not looked at is not a clean result.
        [ -n "$expected" ] && echo "ok so far: the prompt carries the current repository context"
        [ -n "$dest" ] && echo "ok so far: the prompt carries the run's directory"
        exit 2
      fi
      echo "ok: the prompt carries the current repository context and the run's directory"
      exit 0
    fi

    # Tab-separated, so the tag cannot be confused with the first word of a
    # reason. Split with IFS rather than sed: BSD sed does not read `\t` in a
    # pattern as a tab, and this file has to run on stock macOS.
    while IFS=$'\t' read -r tag text; do
      [ -n "$tag" ] || continue
      printf '%s: %s\n' "$tag" "$text"
    done <<EOF
$probs
EOF
    exit 1
    ;;

  *)
    echo "usage: launch-gate.sh {hook|lint <prompt-file> [<repo-root>]}" >&2
    exit 2
    ;;
esac
