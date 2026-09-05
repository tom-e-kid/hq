#!/usr/bin/env bash
# hq triage gate — the two questions that need the findings file and the
# telemetry stream joined.
#
#   triage-gate.sh check [<repo-root>]
#       Every finding this branch's verifier wrote has a disposition row.
#       Prints one line per finding that has none, and one per row of the file
#       this face cannot see behind — a row with no usable id, or lines it could
#       not parse. exit 0 clean (a branch with no findings file included), 1
#       findings this face cannot report as disposed of, 2 could not look.
#
#   triage-gate.sh open [<repo-root>]
#       The deferrals in this repository nobody has closed, one per line:
#           <branch>#<id><TAB><ts><TAB><reason>
#       exit 0 whether or not the list is empty, 2 could not look. A line of the
#       stream it could not parse is named on stderr and the rest is still
#       listed: the stream is never edited, so refusing would take this list
#       away for good over one torn append.
#
# THE CLOSING RULE IS IMPLEMENTED HERE AND STATED NOWHERE ELSE. A deferral is
# closed when a LATER `fix_now` row carries the same qualified identifier.
# Finding identifiers are only unique within a branch, so the identity a row
# is filed under is `<branch>#<id>`, taken from the envelope's branch when the
# row's own identifier does not already carry one — which is what lets the
# branch that finally fixes a deferral close it, writing `<other-branch>#F3`
# where its own findings would be bare.
#
# AN IDENTIFIER NAMES ONE FINDING FOR THE LIFE OF A BRANCH: a later review
# pass CONTINUES THE NUMBERING AND APPENDS to the findings file rather than
# rewriting it, so `feat/x#F1` denotes the same defect before and after a
# second pass, and neither face asks which pass a row belongs to.
#
# WHAT HOLDS THE RULE UP IS findings-gate.sh's DUPLICATE-ID CHECK, exactly as
# far as the appending goes. A pass that truncates the file and renumbers
# from F1 walks past it, and this face then reads the earlier pass's rows as
# answers to the new pass's findings. NOTHING HERE DETECTS THAT — it is
# written down rather than papered over.
#
# ORDER COMES FROM THE FILE, NOT FROM `t`: the stream is appended to under
# O_APPEND, so its order is the order things happened, while `t` has
# one-second resolution and a triage pass writes several rows inside one
# second — a coin toss exactly where it decides whether a deferral is open.
#
# ROWS ARE SCOPED TO THE SCHEMA THE RECORDER WRITES: earlier versions'
# vocabularies cannot answer one of this plugin's findings or close its deferrals, so they are
# out of scope in the way another repository's rows are, and skipped without
# a word — read as this schema, every one would be reported as a row that
# names no finding. The number is read out of record.sh rather than written
# here: a second copy left behind at a schema bump would read only rows
# nobody writes any more.
#
# ROWS ARE SCOPED TO THIS REPOSITORY: the stream is shared by every
# repository on this machine, and an unscoped answer would offer another
# project's deferrals to act on. The scope is the `repo` field; the
# derivation is copied below rather than shared, and the copies are held to
# one text by the machine (sweep.test.sh). Two clones of one repository share
# a `repo` value and not a task directory — a deferral made in one is listed
# in the other, with its own branch named.
#
# JSON is parsed with python3: a hand-rolled parser that is subtly wrong here
# drops rows, which reads as a clean branch and an empty deferral list. Where
# the parser is absent, both faces exit 2 and say so.
#
# NOTHING THAT WAS READ IS DROPPED IN SILENCE. A line has three states here,
# and the middle one is the one that gets lost:
#
#   read           it joins.
#   read, unusable parsed and still cannot be joined — a finding with no
#                  `id`, a disposition naming no `finding`. Every one is
#                  named, in the words findings-gate.sh uses for the same
#                  defect; on `check` they go to stdout and the exit code
#                  follows the list.
#   unreadable     not JSON at all. Counted on stderr: there is no row to say
#                  anything about, only that the answer is short by that many.
#
# Both are reachable in ordinary use: findings-gate.sh blocks after the write,
# so a findings file it rejected is still on disk for this one to read.
#
# WHAT IT DOES NOT CHECK: whether a disposition was the right one, whether a
# reason is worth reading, whether the finding was any good. Those are
# judgments, and this file only takes set differences.
#
# Portability: bash 3.2, BSD userland.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || HERE=""
RECORD="$HERE/record.sh"

# The interpreter, overridable so the tests can drive the branch where there is
# none.
PY="${HQ_PYTHON:-python3}"

have_python() { command -v "$PY" >/dev/null 2>&1; }

# The schema this join reads, taken from the script that writes it. Same shape
# as findings-gate.sh's `classes`, and for the same reason — see the header.
schema() {
  [ -f "$RECORD" ] || return 1
  /usr/bin/grep -m1 '^SCHEMA=' "$RECORD" | sed 's/^SCHEMA=//'
}

die() { printf 'triage-gate.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

usage() {
  cat <<'EOF'
Usage:
  triage-gate.sh check [<repo-root>]   findings on this branch with no disposition
  triage-gate.sh open  [<repo-root>]   deferrals in this repository nobody closed

check: exit 0 clean, 1 findings it cannot report as disposed of (undisposed,
       carrying no usable id, or on a line it could not parse), 2 could not look.
open:  exit 0 (an empty list is an answer), 2 could not look.
EOF
}

# The repository slug an envelope carries: `owner/name` from the origin
# remote, falling back to the directory name. KEPT BYTE-IDENTICAL to
# record.sh's copy, which writes the value this reads — the collation is the
# machine's (sweep.test.sh). Not shared through a sourced file: a reader that
# sourced the writer would append a row every time it looked.
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

# --- the join ---------------------------------------------------------------
#
# One program for both faces: two copies of the identity rule would be two
# rules.
join() { # <mode> <sink> <repo> <branch> <findings file> <schema>
  "$PY" -c '
import json, sys

mode, sink, repo, branch, findings, schema = sys.argv[1:7]
SCHEMA = int(schema)

def rows_of(path):
    """Every JSON object in an append-only file, as (line number, row).

    Returns (rows, unreadable, existed). A file that is not there is not an
    error — a machine with no stream yet has no dispositions, which is a real
    answer. A line that cannot be parsed IS reported: it may be the row that
    closes a deferral, and dropping it in silence would report that deferral as
    open forever. The line number travels with the row so that a row which
    parses and still cannot be used can be named where it sits.

    A FILE THAT IS THERE AND CANNOT BE OPENED IS NOT THE SAME ANSWER, and the
    first spelling of this returned the empty set for both. A permission bit or
    a directory in that path then read as "no dispositions yet": `check` called
    an unjudged branch clean and `open` printed the empty list that this face
    exists to make trustworthy. Both are the failure this gate is built around,
    so it exits 2 — could not look — and names the file.
    """
    bad = 0
    out = []
    try:
        fh = open(path, encoding="utf-8")
    except FileNotFoundError:
        return out, bad, False
    except OSError as exc:
        sys.stderr.write("triage-gate.sh: cannot read %s: %s\n"
                         % (path, exc.strerror or exc))
        raise SystemExit(2)
    with fh:
        for n, raw in enumerate(fh, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                row = json.loads(raw)
            except ValueError:
                bad += 1
                continue
            if isinstance(row, dict):
                out.append((n, row))
            else:
                bad += 1
    return out, bad, True

def unusable(n, holder, key):
    """findings-gate.sh word for word, on the field this file needs.

    One vocabulary for one defect: the gate that validates the findings file
    says `line 3: id is empty`, and a reader that renamed it would leave the
    person holding two descriptions of one broken row. Type before emptiness,
    for the reason that gate gives — str() would turn null into the text None
    and a number into its digits, so a row with no identifier at all would read
    as a row that has one. Returns None when the field is usable.
    """
    if not isinstance(holder, dict):
        return "line %d: not a JSON object where %s was expected" % (n, key)
    if key not in holder:
        return "line %d: missing %s" % (n, key)
    value = holder[key]
    if not isinstance(value, str):
        return "line %d: %s must be a string, got %s" % (n, key,
                                                         type(value).__name__)
    if not value.strip():
        return "line %d: %s is empty" % (n, key)
    return None

def dispositions(rows):
    """The disposition rows of this repository, and the ones that name no
    finding.

    A row that says something was disposed of without saying what is the one
    kind this join cannot place: as a `defer` it is an outstanding item that
    would never appear on the list, as a `fix_now` it is a close that lands on
    nothing. Neither is visible in the output, so it is said out loud.
    """
    out = []
    broken = []
    for n, row in rows:
        # Schema first: a row of another vocabulary is not a row of this
        # format that went wrong.
        if row.get("schema") != SCHEMA:
            continue
        if row.get("kind") != "disposition":
            continue
        if row.get("repo") != repo:
            continue
        problem = unusable(n, row.get("payload"), "finding")
        if problem:
            broken.append(problem)
            continue
        out.append(row)
    return out, broken

def qualified(row):
    """The identity a disposition row is filed under: <branch>#<id>.

    An identifier that already carries a `#` is taken as written — that is how
    a later branch closes a deferral it did not raise. It needs no further
    parsing: the identity is the whole string, and nothing here has to work out
    which part of it was the branch. An earlier form did, to find a per-branch
    pass boundary, and got a branch name carrying a `#` wrong on the first try.
    """
    finding = row["payload"]["finding"].strip()
    if "#" in finding:
        return finding
    return "%s#%s" % (row.get("branch") or "", finding)

def one_line(text):
    """Whitespace flattened, because one deferral is one line.

    A reason may carry newlines: record.sh escapes them into the row and a
    parser gives them back. Printed as they stand, one deferral would read as
    several.
    """
    return " ".join((text or "").split())

rows, bad, existed = rows_of(sink)
disp, broken = dispositions(rows)
if bad:
    sys.stderr.write(
        "triage-gate.sh: %d line(s) of %s could not be parsed and were "
        "skipped\n" % (bad, sink))
if broken:
    sys.stderr.write(
        "triage-gate.sh: %d row(s) of %s dispose of no finding this join "
        "can name, and were not counted:\n" % (len(broken), sink))
    for problem in broken:
        sys.stderr.write("  %s\n" % problem)

if mode == "open":
    # Last defer per identity, and the last fix_now. Open when the defer is
    # the later of the two — a deferral raised again after a fix is open
    # again. The identity is the qualified id and nothing else: a bare fix
    # and a hand-qualified one land on the same key, two spellings of one
    # identity rather than two scopes.
    last_defer = {}
    last_fix = {}
    for i, row in enumerate(disp):
        verdict = row["payload"].get("verdict")
        qid = qualified(row)
        if verdict == "defer":
            last_defer[qid] = (i, row)
        elif verdict == "fix_now":
            last_fix[qid] = i
    still_open = []
    for qid, pair in last_defer.items():
        i, row = pair
        if last_fix.get(qid, -1) > i:
            continue
        still_open.append((i, qid, row))
    still_open.sort(key=lambda e: e[0])
    for i, qid, row in still_open:
        print("%s\t%s\t%s" % (qid, row.get("ts", ""),
                              one_line(row["payload"].get("reason"))))
    raise SystemExit(0)

# mode == "check"
#
# Every disposition this repository holds under one of the identities of this
# branch answers the finding of that identity, whenever it was recorded. There
# is no time bound: the findings file is appended to and its ids are not reused,
# so a row written three passes ago still names the finding it named then.
#
# (No apostrophes in here: this whole program is one single-quoted argument to
# the shell, and one would end it.)
addressed = set()
for row in disp:
    addressed.add(qualified(row))
seen = []
nameless = []
unreadable = []
ids, fbad, fexisted = rows_of(findings)
if fbad:
    # ON STDOUT, WHICH IS WHAT MAKES THE ANSWER NOT CLEAN. A line of the
    # findings file this reader could not parse is a finding it cannot see, and
    # a finding it cannot see is one it must not report as disposed of.
    #
    # The stream is the other direction and stays a warning: a disposition this
    # reader skips can only make it report a finding as undisposed, which is the
    # talkative side. `open` cannot say that, and refuses there instead.
    unreadable.append(
        "%s: %d line(s) could not be parsed, so this face cannot see what they "
        "name and cannot report this branch clean" % (findings, fbad))
for n, row in ids:
    problem = unusable(n, row, "id")
    if problem:
        # A finding the file names and no disposition can ever refer to. It is
        # not dropped and it is not counted as judged: it goes on the list, so
        # that the exit code says what it says for every other finding here
        # that nothing has answered.
        nameless.append(problem)
        continue
    fid = row["id"].strip()
    if fid not in seen:
        seen.append(fid)
for problem in unreadable:
    print(problem)
for problem in nameless:
    print("%s — no disposition can name this finding, so this face cannot "
          "report it disposed of" % problem)
for fid in seen:
    qid = "%s#%s" % (branch, fid)
    if qid in addressed:
        continue
    print("%s: no disposition was recorded for it" % fid)
raise SystemExit(0)
' "$1" "$2" "$3" "$4" "$5" "$6"
}

# --- main -------------------------------------------------------------------

MODE="${1:-}"
case "$MODE" in
  check|open) ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
shift
[ $# -le 1 ] || { usage >&2; exit 2; }

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] || die "not in a git repository"
# The repository is settled before the branch: a path that is not a
# repository has no branch either, and the branch check below would answer
# for it with the wrong sentence.
git -C "$ROOT" rev-parse --git-common-dir >/dev/null 2>&1 || \
  die "not a git repository: $ROOT"
[ -n "$HERE" ] && [ -f "$HERE/lib.sh" ] || \
  die "lib.sh is not beside this script; there is no way to find this run's files"
have_python || die "$PY is not on PATH, so the stream cannot be read; nothing was checked"
SCHEMA=$(schema) || SCHEMA=""
case "$SCHEMA" in
  ''|*[!0-9]*)
    die "the schema number could not be read from $RECORD, so there is no way to tell this format's rows from an older version's; nothing was checked" ;;
esac

BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || BRANCH=""
case "$BRANCH" in
  ''|HEAD) die "no branch is checked out in $ROOT" ;;
esac

# Where this run's files live is lib.sh's answer, called as a subprocess. The
# stream sits beside `repos/` under the same home, so stripping the LAST
# `/repos/` segment off the task directory yields it without a second copy of
# the home expansion living here — the last, not the first: a home whose own
# path contains `/repos/` is an ordinary place to keep one.
DIR=$(bash "$HERE/lib.sh" hq_task_dir "$ROOT" "$BRANCH") || \
  die "this branch's run directory could not be derived, so there is nothing to read"
HOME_DIR=${DIR%/repos/*}
SINK="${HQ_SINK:-$HOME_DIR/stream.jsonl}"
REPO=$(repo_slug "$ROOT")

case "$MODE" in
  open)
    # One read of the stream. The list is derived from the rows alone:
    # nothing here has to look at any branch's findings file.
    out=$(join open "$SINK" "$REPO" "$BRANCH" "" "$SCHEMA") || \
      die "a file this face has to read could not be used in full (named above); nothing was listed" 2
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
    ;;

  check)
    FINDINGS="$DIR/findings.jsonl"
    # No findings file is not a failure: this branch's verifier wrote nothing
    # here. Whether it found nothing or was never told where to write is not
    # answerable from here — the launch gate is where those two part company
    # — so this says which file it looked for and stops.
    [ -f "$FINDINGS" ] || {
      printf 'triage-gate.sh: no findings file at %s, so there is nothing to dispose of\n' "$FINDINGS" >&2
      exit 0
    }
    out=$(join check "$SINK" "$REPO" "$BRANCH" "$FINDINGS" "$SCHEMA") || \
      die "a file this face has to read could not be used in full (named above); nothing was checked" 2
    [ -n "$out" ] || exit 0
    printf '%s\n' "$out"
    exit 1
    ;;
esac
