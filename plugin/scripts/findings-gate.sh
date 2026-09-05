#!/usr/bin/env bash
# hq findings gate — checks the shape of a verifier's findings.jsonl.
#
#   findings-gate.sh check <file>
#       Prints one line per problem. exit 0 clean, 1 problems found, 2 usage.
#
#   findings-gate.sh hook
#       Reads a PostToolUse payload (JSON) on stdin. When the write was a
#       findings.jsonl and its shape is wrong, prints
#           {"decision":"block","reason":"..."}
#       and nothing otherwise. Exits 0 on every path.
#
# WHAT IT DOES NOT CHECK: whether a finding is any good. Those are judgments
# and no gate can stand in for them; this one only asks whether the row can
# be read at all.
#
# THE DUPLICATE-ID CHECK CARRIES MORE THAN IT LOOKS LIKE. A later review pass
# continues the numbering and appends rather than rewriting, so uniqueness
# within the file IS uniqueness across passes. A pass that instead rewrites
# the file from F1 walks through — this gate sees one file at a time. That
# hole is stated rather than papered over; nothing downstream closes it.
#
# THE CLASS VOCABULARY IS NOT DEFINED HERE. It is read out of record.sh, which
# is where the telemetry enum lives; a second copy would drift.
#
# PostToolUse cannot prevent the write — it has already happened. `block` sends
# the problems back to the model that wrote the file, which is the only party
# able to rewrite it.
#
# JSON is parsed with python3 rather than by hand: a hand-rolled parser that
# is subtly wrong would reject good findings.
#
# WHERE THE PARSER IS ABSENT, BOTH FACES SAY SO. `check` exits 2 with a
# message; the hook blocks with the reason. Silence would leave a file nobody
# validated, indistinguishable from one validated and found clean.
#
# Portability: bash 3.2, BSD userland.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || HERE=""
RECORD="$HERE/record.sh"

REQUIRED="id weight file claim evidence consequence"
OPTIONAL="class line against"

# THE WEIGHT VOCABULARY IS DEFINED HERE, the only copy a machine enforces;
# the verifier's definition states the same three spellings, and a test
# compares that table against this line (sweep.test.sh).
WEIGHTS="high medium low"

# The single source is record.sh's enum. Reading it here keeps one definition
# for both the finding and the disposition it turns into.
classes() {
  [ -f "$RECORD" ] || return 1
  /usr/bin/grep -m1 '^CLASSES=' "$RECORD" | sed 's/^CLASSES="//; s/".*//'
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

# Prints one line per problem; prints nothing when the file is well formed.
inspect() { # <file> <classes>
  "$PY" -c '
import json, sys

path, classes = sys.argv[1], set(sys.argv[2].split())
required = sys.argv[3].split()
allowed = set(required) | set(sys.argv[4].split())
weights = set(sys.argv[5].split())

seen = {}
try:
    lines = open(path, encoding="utf-8").read().splitlines()
except OSError as e:
    print("cannot read %s: %s" % (path, e))
    raise SystemExit(0)

for n, raw in enumerate(lines, 1):
    if not raw.strip():
        print("line %d: blank line" % n)
        continue
    try:
        row = json.loads(raw)
    except ValueError as e:
        print("line %d: not valid JSON (%s)" % (n, e))
        continue
    if not isinstance(row, dict):
        print("line %d: not a JSON object" % n)
        continue
    for key in required:
        # Type first, then emptiness: str() would turn null into "None" and a
        # number into its digits, so {"consequence": null} would read as a
        # row carrying a consequence — and triage decides on consequence.
        if key not in row:
            print("line %d: missing %s" % (n, key))
        elif not isinstance(row[key], str):
            print("line %d: %s must be a string, got %s"
                  % (n, key, type(row[key]).__name__))
        elif not row[key].strip():
            print("line %d: %s is empty" % (n, key))
    for key in row:
        if key not in allowed:
            print("line %d: unknown key %s" % (n, key))
    cls = row.get("class")
    if cls is not None and cls not in classes:
        print("line %d: unknown class %s (one of: %s)"
              % (n, cls, " ".join(sorted(classes))))
    # A drift finding is one definition disagreeing with another, so it always
    # has a second definition to name: the class cannot be written without one.
    # The verifier reads `against` back on a later pass to tell whether it is
    # looking at a pair it has already reported, and a drift row that omits it
    # is invisible to that comparison — the pair goes on producing one
    # sentence-level finding per pass, which is what the rule exists to stop.
    if cls == "drift":
        against = row.get("against")
        if not isinstance(against, str) or not against.strip():
            print("line %d: a drift finding must carry against — the definition "
                  "this one disagrees with" % n)
    # Only a weight that survived the type and emptiness checks above reaches
    # the enum, so a row carrying {"weight": null} is reported once, as the
    # type error it is, rather than twice in two vocabularies.
    weight = row.get("weight")
    if isinstance(weight, str) and weight.strip() and weight not in weights:
        print("line %d: unknown weight %s (one of: %s)"
              % (n, weight, " ".join(sorted(weights))))
    # Only rows whose id passed the type check above reach the duplicate test.
    fid = row.get("id")
    if isinstance(fid, str) and fid.strip():
        if fid in seen:
            print("line %d: id %s already used on line %d" % (n, fid, seen[fid]))
        else:
            seen[fid] = n
' "$1" "$2" "$REQUIRED" "$OPTIONAL" "$WEIGHTS" 2>&1
}

# The interpreter, overridable so the tests can drive the absent-parser branch.
PY="${HQ_PYTHON:-python3}"

have_python() { command -v "$PY" >/dev/null 2>&1; }

deny_unchecked() { # <why>
  printf '{"decision":"block","reason":"%s"}\n' \
    "$(json_escape "findings.jsonl was NOT checked: $1. Nothing downstream checks it either — triage reads the file as it stands. Verify the shape by hand before relying on it: every line one JSON object with $REQUIRED (optional: $OPTIONAL), and weight one of: $WEIGHTS.")"
}

case "${1:-}" in
  check)
    [ $# -eq 2 ] || { echo "usage: findings-gate.sh check <file>" >&2; exit 2; }
    [ -f "$2" ] || { echo "findings-gate.sh: cannot read $2" >&2; exit 2; }
    have_python || { echo "findings-gate.sh: python3 not found; shape unchecked" >&2; exit 2; }
    CLS=$(classes) || { echo "findings-gate.sh: cannot read the class list from record.sh" >&2; exit 2; }
    problems=$(inspect "$2" "$CLS")
    [ -n "$problems" ] || exit 0
    printf '%s\n' "$problems"
    exit 1
    ;;

  hook)
    trap 'exit 0' EXIT
    payload=$(cat 2>/dev/null) || exit 0
    [ -n "$payload" ] || exit 0

    # Nothing below can fire unless the payload carries the file's name at all:
    # the Write/Edit branch requires a file_path ending in findings.jsonl, and
    # the Bash branch requires the name in the command — both are substrings of
    # the payload. Deciding that first, with no subprocess, keeps the common
    # path at the cost of this one comparison.
    case "$payload" in
      *findings.jsonl*) ;;
      *) exit 0 ;;
    esac

    tool=$(printf '%s' "$payload" \
      | /usr/bin/grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 | sed 's/.*"\([^"]*\)"$/\1/')

    # Two ways this file gets written, and the second is not optional to
    # cover: the verifier holds Bash as well as Write, so `cat >
    # findings.jsonl <<EOF` is an ordinary thing for it to do, and a gate
    # watching only Write would be bypassed by it without anyone choosing to.
    case "$tool" in
      Write|Edit)
        # A path can contain neither a quote nor a newline in this capture's
        # terms, which holds for the paths this gate cares about.
        path=$(printf '%s' "$payload" \
          | /usr/bin/grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
          | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        [ -n "$path" ] || exit 0
        case "$path" in
          */findings.jsonl|findings.jsonl) ;;
          *) exit 0 ;;
        esac
        ;;
      Bash)
        # The command string is not parsed for a path — quoting makes that
        # guesswork. Mentioning the file at all is reason to look, and where
        # to look is derived from the branch rather than from the command.
        case "$payload" in
          *findings.jsonl*) ;;
          *) exit 0 ;;
        esac
        root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
        [ -n "$root" ] || exit 0
        # Where a run's working files live is lib.sh's answer, called as a
        # subprocess: a syntax error over there would otherwise be swallowed
        # by the fail-open trap above. No answer means there is no run here
        # to check.
        [ -n "$HERE" ] && [ -f "$HERE/lib.sh" ] || exit 0
        dir=$(bash "$HERE/lib.sh" hq_task_dir "$root" 2>/dev/null) || exit 0
        [ -n "$dir" ] || exit 0
        path="$dir/findings.jsonl"
        ;;
      *) exit 0 ;;
    esac
    [ -f "$path" ] || exit 0

    # Not being able to check is reported, not passed over: staying quiet
    # would leave a findings.jsonl nobody ever looked at, indistinguishable
    # from one that was looked at and found clean.
    have_python || {
      deny_unchecked "the JSON parser this gate needs is not on PATH (looked for: $PY)"
      exit 0
    }
    CLS=$(classes) || {
      deny_unchecked "the class list could not be read from record.sh, so no row could be validated"
      exit 0
    }

    problems=$(inspect "$path" "$CLS")
    [ -n "$problems" ] || exit 0
    printf '{"decision":"block","reason":"%s"}\n' \
      "$(json_escape "findings.jsonl is not readable as it stands, and triage reads it next:
$problems

Every line is one JSON object with $REQUIRED. Optional: $OPTIONAL. weight is one of: $WEIGHTS. Correct the offending lines in place; do not append a corrected copy — a second row under the same id is a second finding as far as everything downstream can tell.")"
    exit 0
    ;;

  *)
    echo "usage: findings-gate.sh {check <file>|hook}" >&2
    exit 2
    ;;
esac
