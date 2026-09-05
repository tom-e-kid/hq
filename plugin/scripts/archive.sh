#!/usr/bin/env bash
# hq archive script — the deterministic faces of the after-merge module.
#
#   archive.sh missing [<count>]
#       Walks the merge commits of the base branch, newest first, derives a
#       pull request number from each `Merge pull request #N from owner/branch`
#       subject, and prints one line per pull request the telemetry holds NO
#       residual row for: <number><TAB><branch>. THE COUNT (default 20) CAPS
#       THE OUTPUT, NOT THE LOOK-BACK: a window of the newest merge commits
#       would stop moving the moment its commits were recorded — here,
#       recording a pull request frees its line, so the next run surfaces the
#       next batch until the backlog is drained. The branch is a derivation
#       for the cleanup step, not a guarantee; empty when the subject names
#       none. exit 0 whether or not the list is empty, 2 when it could not
#       look. A line of the stream that cannot be parsed is counted on stderr
#       and the rest is still processed — refusing outright would take this
#       list away for good over one torn append.
#
#   archive.sh cleanup <branch>
#       Removes what a finished run leaves on this machine, as TWO
#       INDEPENDENT REMOVALS, each reporting what it found:
#         - the run directory, <HQ_HOME>/repos/<repo-key>/tasks/<branch-dir>
#         - the LOCAL branch of that name. The remote one is never touched.
#       Either can be there without the other, so neither absence ends the
#       call. BOTH REMOVALS ARE IRREVERSIBLE, and the directory's ENDS THE RUN
#       IDENTIFIER'S LIFE: the next work on a branch of that name mints a new
#       one. It refuses — exit 1 — when:
#         - the branch is the base itself, per hq_resolve_base: the merged
#           test below cannot catch it (the base's tip is its own ancestor),
#           and its run directory is live state. One typo must not end it.
#         - the branch cannot be shown MERGED into the base. TWO PROOFS, IN
#           ORDER: the branch resolves (refs/heads, then refs/remotes/origin)
#           and its tip is an ancestor of the base; or, where nothing resolves
#           because the forge deleted the head on merge, a merge commit on the
#           base names it. The second is weaker and that is why it is second —
#           it says a branch of that name was merged, not that this directory
#           holds that incarnation's work. Neither one available is a refusal:
#           the doubt is somebody's live work.
#         - the run directory is THERE AND CANNOT BE ENTERED — this process
#           has no access to it, or it is a symlink whose target is gone:
#           where it resolves cannot be checked, so it is not touched.
#         - the directory RESOLVES OUTSIDE the home: the derived path is
#           re-resolved physically before anything is removed, so a planted
#           symlink cannot walk the deletion out of <HQ_HOME>/repos/.
#         - the branch named IS THE ONE CHECKED OUT and the base cannot be
#           checked out in its place — it is not a local branch, or the
#           checkout failed. Nothing is removed in that case: the checkout is
#           taken before either removal for exactly that reason.
#         - GIT ITSELF WILL NOT DELETE the local branch — another worktree of
#           this repository has it checked out, most often. THIS ONE IS THE
#           EXCEPTION TO "nothing was removed": the removals are independent
#           and the directory's has already happened by then, so what went is
#           on stdout above the refusal, and a second call retries the branch
#           on its own.
#       THAT LIST IS THE ONLY COPY OF ITSELF. Every refusal names its own
#       condition on stderr when it fires, so nothing downstream needs the
#       list to report one: `--help` and the module definition say that the
#       face refuses and point here. A second enumeration in prose cannot be
#       compared against this one by any machine — the two that existed both
#       went stale against it, one of them by a whole condition.
#       exit 0 done, whatever was or was not there; 2 when the question could
#       not be answered at all. THIS FACE IS THE ONLY DELETION PATH the
#       module has: the test suite refuses destructive commands in a
#       definition's fenced blocks, so both the `rm` and the branch deletion
#       live here, behind the refusals.
#
# NO gh AND NO NETWORK. The merge commit subject already carries the number,
# so the list is derived from the repository alone.
#
# WHAT IS NOT GUARANTEED: that this ever runs. A merge happens on the forge,
# outside any tool call, so no hook can fire on it; the only callers are the
# module definition's prose and a person. A run that never happened leaves the
# denominator short, and the `missing` face is how the NEXT run finds what the
# last one skipped — the gap is closable, not detectable.
#
# ROWS ARE SCOPED the way triage-gate.sh scopes dispositions: to the schema
# record.sh writes (read from that file, not copied here) and to this
# repository's slug. An unscoped answer would let another project's #12 record
# this one's.
#
# Portability: bash 3.2, BSD userland.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || HERE=""
RECORD="$HERE/record.sh"

# The interpreter, overridable so the tests can drive the branch where there
# is none.
PY="${HQ_PYTHON:-python3}"

have_python() { command -v "$PY" >/dev/null 2>&1; }

# The schema this reader accepts, taken from the script that writes the rows:
# a copy of the number left behind at a schema bump would read only rows
# nobody writes any more.
schema() {
  [ -f "$RECORD" ] || return 1
  /usr/bin/grep -m1 '^SCHEMA=' "$RECORD" | sed 's/^SCHEMA=//'
}

die() { printf 'archive.sh: %s\n' "$1" >&2; exit "${2:-2}"; }

# A refusal is an answer — "no, and here is why" — where die is "the question
# could not be answered": a refusal is reported and left alone, a failure is
# fixed and asked again.
refuse() { printf 'archive.sh: %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  archive.sh missing [<count>]   merged pull requests with no residual record
  archive.sh cleanup <branch>    remove a merged branch's run directory and
                                 its local branch

missing: walks the merge commits of the base branch, newest first, and
         prints one line — <number><TAB><branch> — per pull request that has
         no residual row in the telemetry stream, stopping after <count>
         (default 20) lines or when the history runs out. The count caps the
         output, not how far back it looks. exit 0 whether or not the list
         is empty (an empty list means nothing is owed), 2 when it could not
         look.
cleanup: removes two things independently — the run directory
         <HQ_HOME>/repos/<repo-key>/tasks/<branch-dir>, and the local branch
         of that name. The remote branch is never touched. Irreversible, and
         the directory's removal ends the run identifier's life. Refuses —
         exit 1 — whatever it cannot decide is finished, and names on stderr
         which condition it hit, so a run never has to look the list up. The
         conditions are stated once, in the cleanup section of this script's
         header comment; a second list here is what went stale last time.
         Every refusal but one comes before anything is removed; the
         exception is a local branch git will not delete (another worktree
         has it checked out), refused once the run directory has already
         gone, so read what stdout says was removed rather than assume
         nothing was. exit 0 done, 2 when the question could not be answered.
EOF
}

# The repository slug an envelope carries: `owner/name` from the origin
# remote, falling back to the directory name. KEPT BYTE-IDENTICAL to
# record.sh's copy, which writes the value this reads — a test compares the
# bodies as text, and editing one fails until the others match
# (sweep.test.sh). Not shared through a sourced file: record.sh states in its
# own header why it sources nothing.
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

# --- reading the stream -------------------------------------------------------
#
# The pull request numbers the telemetry already holds a residual row for, one
# per line, normalised: whitespace trimmed and a leading `#` dropped, so that
# `pr=272` and `pr=#272` are one record rather than two spellings that leave a
# recorded pull request on the missing list.
#
# Three states per line, and the middle one is the one that gets lost: a line
# that parses joins; a residual row that parses and names no pull request is
# said out loud on stderr; a line that is not JSON at all is counted on
# stderr. A file that is absent is an answer — no rows yet — while a file
# that is there and cannot be opened is exit 2: the two read identically as
# an empty set, and only one of them is one.
recorded_prs() { # <sink> <repo> <schema>
  "$PY" -c '
import json, sys

sink, repo, schema = sys.argv[1:4]
SCHEMA = int(schema)

bad = 0
broken = []
out = []
try:
    fh = open(sink, encoding="utf-8")
except FileNotFoundError:
    fh = None
except OSError as exc:
    sys.stderr.write("archive.sh: cannot read %s: %s\n"
                     % (sink, exc.strerror or exc))
    raise SystemExit(2)
if fh is not None:
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
            if not isinstance(row, dict):
                bad += 1
                continue
            # Schema first: it decides which vocabulary the row is written
            # in, and a row of another one is not a row of this format that
            # went wrong.
            if row.get("schema") != SCHEMA:
                continue
            if row.get("kind") != "residual":
                continue
            if row.get("repo") != repo:
                continue
            payload = row.get("payload")
            pr = payload.get("pr") if isinstance(payload, dict) else None
            if not isinstance(pr, str) or not pr.strip():
                broken.append(n)
                continue
            out.append(pr.strip().lstrip("#"))
if bad:
    sys.stderr.write(
        "archive.sh: %d line(s) of %s could not be parsed and were "
        "skipped\n" % (bad, sink))
if broken:
    sys.stderr.write(
        "archive.sh: %d residual row(s) of %s name no pull request and were "
        "not counted (line %s)\n"
        % (len(broken), sink, ", ".join(str(n) for n in broken)))
for pr in out:
    print(pr)
' "$1" "$2" "$3"
}

# The base as a ref that resolves to a commit here: the resolved name itself,
# or `origin/` in front of it — settings naming `develop` where only
# `origin/develop` was fetched is the everyday case. Prints the usable ref;
# non-zero when neither resolves, which the callers refuse rather than read as
# an empty history.
base_ref() { # <root> <base>
  if git -C "$1" rev-parse --verify --quiet "$2^{commit}" >/dev/null; then
    printf '%s' "$2"
  elif git -C "$1" rev-parse --verify --quiet "origin/$2^{commit}" >/dev/null; then
    printf 'origin/%s' "$2"
  else
    return 1
  fi
}

# The branch a merge commit's subject names, in the shape the forge writes it:
# `Merge pull request #<n> from <owner>/<branch>`. Sets MERGE_BRANCH to the
# branch, or to the empty string when the subject is not that shape.
#
# ONE DEFINITION OF THAT SHAPE, READ BY BOTH FACES — `missing` takes the branch
# beside the number, `cleanup` asks whether any subject names the branch it was
# handed. A second copy would drift the day the forge changed its wording, and
# the two faces would then disagree about what counts as merged.
#
# IT SETS A VARIABLE RATHER THAN PRINTING: `missing` calls it once per merge
# commit on the base, over the whole history, and a command substitution there
# would fork per commit.
MERGE_BRANCH=""
set_merge_branch() { # <subject>
  MERGE_BRANCH=""
  case "$1" in 'Merge pull request #'*) ;; *) return 0 ;; esac
  _ms_rest=${1#"Merge pull request #"}
  case "$_ms_rest" in *' from '*) ;; *) return 0 ;; esac
  _ms_br=${_ms_rest#* from }
  # The owner is stripped, not the branch's own slashes: `acme/feat/new-plan`
  # is the owner `acme` and the branch `feat/new-plan`.
  case "$_ms_br" in */*) _ms_br=${_ms_br#*/} ;; esac
  MERGE_BRANCH=$_ms_br
}

# --- main ---------------------------------------------------------------------

MODE="${1:-}"
case "$MODE" in
  missing|cleanup) ;;
  -h|--help|help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
shift

# Each face's arguments are settled before anything is derived: a call that
# is wrong as written is answered about its own text.
BR=""
COUNT=20
if [ "$MODE" = missing ]; then
  if [ $# -ge 1 ]; then
    case "$1" in
      *[!0-9]*|'') die "missing takes a cap on how many pull requests to list, got '$1'" ;;
      0) die "a cap of zero would answer an empty list for any repository" ;;
      *) COUNT=$1 ;;
    esac
    shift
  fi
  [ $# -eq 0 ] || die "usage: archive.sh missing [<count>]"
else
  [ $# -eq 1 ] || \
    die "cleanup takes exactly one argument, the branch whose run directory is to be removed: archive.sh cleanup <branch>"
  BR=$1
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] || die "not in a git repository"
[ -n "$HERE" ] && [ -f "$HERE/lib.sh" ] || \
  die "lib.sh is not beside this script; there is no way to find this run's files"

BASE=$(bash "$HERE/lib.sh" hq_resolve_base "$ROOT" 2>/dev/null)
[ -n "$BASE" ] || die "the base branch did not resolve"
# Refused rather than read as an empty history: folding a failed `git log`
# into "no merges" would report a misconfigured base as a repository that
# owes nothing, and `cleanup` would have nothing to prove a branch merged
# into.
BASEREF=$(base_ref "$ROOT" "$BASE") || \
  die "the base branch '$BASE' does not resolve to a commit here; nothing was done"

# --- cleanup ------------------------------------------------------------------

if [ "$MODE" = cleanup ]; then
  # THE BASE ITSELF IS REFUSED IN FRONT OF THE MERGED PROOF, which cannot
  # catch it: the base's tip is trivially an ancestor of itself, and the
  # base's run directory is live state. The comparison is against what
  # hq_resolve_base answered, so it holds wherever the base is configured.
  [ "$BR" != "$BASE" ] || \
    refuse "the branch '$BR' is the base branch itself; its run directory is live state (the after-merge records' run identifier lives there), and nothing was removed"

  # MERGED IS PROVEN, NOT ASSUMED: the branch has to resolve — locally first,
  # then as origin's, what is left after a merge deleted the local one — and
  # its tip has to be an ancestor of the base. "Cannot decide" is a refusal:
  # the doubt is somebody's live work.
  SHA=$(git -C "$ROOT" rev-parse --verify --quiet "refs/heads/$BR^{commit}") || SHA=""
  [ -n "$SHA" ] || \
    SHA=$(git -C "$ROOT" rev-parse --verify --quiet "refs/remotes/origin/$BR^{commit}") || SHA=""
  if [ -n "$SHA" ]; then
    git -C "$ROOT" merge-base --is-ancestor "$SHA" "$BASEREF" || \
      refuse "the branch '$BR' is not merged into $BASEREF; its run directory is live state, and nothing was removed"
  else
    # NOTHING LEFT TO ASK. Deleting the head branch on merge is a forge setting
    # many repositories have on, and where it is on, the test above can never
    # be taken: by the time anything gets here there is no ref to resolve, and
    # the directory stays for good. The merge commit on the base is what is
    # left of that branch, and it answers the same question.
    SUBJ=$(git -C "$ROOT" log --merges --first-parent --format='%s' "$BASEREF" --) || \
      refuse "the branch '$BR' does not resolve here and the merges on $BASEREF could not be read, so whether it is merged cannot be decided; nothing was removed"
    PROVEN=no
    while IFS= read -r s; do
      set_merge_branch "$s"
      if [ "$MERGE_BRANCH" = "$BR" ]; then PROVEN=yes; break; fi
    done <<EOF
$SUBJ
EOF
    [ "$PROVEN" = yes ] || \
      refuse "the branch '$BR' does not resolve here (neither refs/heads nor refs/remotes/origin) and no merge commit on $BASEREF names it, so whether it is merged cannot be decided; nothing was removed"
  fi

  # TWO REMOVALS, NOT ONE, AND NEITHER STANDS IN FOR THE OTHER: a run leaves
  # a directory under the home and a branch in the repository, and either can
  # be there without the other — the branch survives a directory already
  # cleaned up, and the directory survives a branch deleted on the forge. So
  # each is decided on its own and each reports what it found.
  DIR=$(bash "$HERE/lib.sh" hq_task_dir "$ROOT" "$BR") || \
    die "the branch's run directory could not be derived; nothing was removed"

  # WHERE IT RESOLVES IS CHECKED BEFORE ANYTHING MOVES: the physical
  # resolution (`pwd -P`) is what a symlink cannot lie to. Asked here, with
  # the other refusals, so that every answer this face can give without
  # touching the tree is given before it touches the tree.
  #
  # `-e` OR `-L`, because `-e` FOLLOWS THE LINK: a symlink whose target is
  # gone answers no to `-e` while sitting right there on disk, and reading
  # that as "no directory" sent the run past this whole block — the branch
  # deleted, the link left, and "nothing to remove" printed over it. The link
  # also outlives its own removal path that way: `mkdir -p` on a dangling
  # link fails, so the next run of that branch name cannot mint a run
  # identifier. Entered here, `cd` fails on it and the refusal below fires
  # BEFORE anything is removed, which is where an undecidable answer belongs.
  HOMEP=""
  DIRP=""
  if [ -e "$DIR" ] || [ -L "$DIR" ]; then
    HOME_DIR=${DIR%/repos/*}
    DIRP=$(cd "$DIR" 2>/dev/null && pwd -P) || \
      refuse "$DIR is there and cannot be entered — no access to it, or a symlink whose target is gone — so where it resolves cannot be checked; nothing was removed"
    HOMEP=$(cd "$HOME_DIR" 2>/dev/null && pwd -P) || \
      die "the home at $HOME_DIR cannot be entered; nothing was removed"
    case "$DIRP" in
      "$HOMEP"/repos/*/tasks/?*) ;;
      *) refuse "$DIR resolves to $DIRP, which is not under $HOMEP/repos/; nothing was removed" ;;
    esac
  fi

  # A BRANCH CANNOT BE DELETED WHILE IT IS THE ONE CHECKED OUT, so the base is
  # checked out first. THE CHECKOUT COMES BEFORE EITHER REMOVAL: it is the one
  # step here that an ordinary working tree can refuse — uncommitted changes —
  # and a run that stopped there has removed nothing at all.
  #
  # THE ORDER IS NOT ARBITRARY. A design that keeps a run's folder INSIDE the
  # repository has to move that folder before checking out, because the
  # checkout would take it; this run's directory is under the home, outside
  # every working tree, so that constraint does not apply and the checkout can
  # come first — where the only refusable step belongs.
  CURRENT=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || CURRENT=""
  if [ "$CURRENT" = "$BR" ]; then
    # THE BASE AS A LOCAL BRANCH, never `origin/<base>`: checking out the
    # remote ref leaves a detached HEAD, and hq_task_dir refuses one — this
    # face would be handing the next run a repository it cannot derive
    # anything in.
    git -C "$ROOT" rev-parse --verify --quiet "refs/heads/$BASE^{commit}" >/dev/null || \
      refuse "'$BR' is the branch checked out here and the base '$BASE' is not a local branch, so there is nowhere to move to that is not a detached HEAD; nothing was removed"
    git -C "$ROOT" checkout -q "$BASE" || \
      refuse "'$BR' is the branch checked out here and moving to '$BASE' failed (git said why above); nothing was removed"
    printf 'checked out %s\n' "$BASE"
  fi

  # WHAT WAS DERIVED IS REMOVED, not what it resolved to: for a real directory
  # the same place, and for a symlink that passed the check above, removing
  # the link ends this branch's entry without reaching through it.
  if [ -n "$DIRP" ]; then
    rm -rf -- "$DIR"
    [ ! -e "$DIR" ] || die "could not remove $DIR"
    printf 'removed %s\n' "$DIR"
  else
    printf 'nothing to remove: no run directory at %s\n' "$DIR"
  fi

  # THE BRANCH GOES LAST. If it went first and the directory removal then
  # failed, a second run would have nothing left to prove merged with — the
  # local ref gone and the remote one gone with the merge — and this face
  # could never finish the job. In this order every failure leaves a state a
  # second run can walk through.
  #
  # THE REMOTE BRANCH IS NOT TOUCHED. Deleting it is the forge's to do on
  # merge, and a local tool that reaches for it destroys a ref it cannot put
  # back.
  #
  # `-D`, not `-d`: `-d` takes the merge proof again against the current HEAD
  # or an upstream, and answers no for a branch merged into a base this clone
  # only holds as `origin/<base>`. The proof this face needs was taken above,
  # against the ref that does resolve. git's own line goes nowhere — this face
  # prints its own — while anything it says on stderr is left alone.
  if git -C "$ROOT" rev-parse --verify --quiet "refs/heads/$BR^{commit}" >/dev/null; then
    git -C "$ROOT" branch -D "$BR" >/dev/null || \
      refuse "the local branch '$BR' could not be deleted (git said why above); whatever was removed above is reported above, and running this again retries the branch alone"
    printf 'deleted local branch %s\n' "$BR"
  else
    printf 'nothing to delete: no local branch %s\n' "$BR"
  fi
  exit 0
fi

# --- missing ------------------------------------------------------------------

have_python || die "$PY is not on PATH, so the stream cannot be read; nothing was listed"
SCHEMA=$(schema) || SCHEMA=""
case "$SCHEMA" in
  ''|*[!0-9]*)
    die "the schema number could not be read from $RECORD, so there is no way to tell this format's rows from an older version's; nothing was listed" ;;
esac

# Where the stream is, derived the way triage-gate.sh derives it: lib.sh owns
# where a run's files live, and the stream sits beside `repos/` under the same
# home — stripping the LAST `/repos/` segment off the task directory yields it
# without a second copy of the home expansion living here.
BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || BRANCH=""
case "$BRANCH" in
  ''|HEAD) die "no branch is checked out in $ROOT" ;;
esac
DIR=$(bash "$HERE/lib.sh" hq_task_dir "$ROOT" "$BRANCH") || \
  die "this branch's run directory could not be derived, so the stream cannot be found"
HOME_DIR=${DIR%/repos/*}
SINK="${HQ_SINK:-$HOME_DIR/stream.jsonl}"
REPO=$(repo_slug "$ROOT")

# First-parent, because the question is what was merged INTO the base. The
# whole history, because the count caps what is printed below, not what is
# looked at — a `-n` here would be the fixed window this face must not have.
SUBJECTS=$(git -C "$ROOT" log --merges --first-parent --format='%s' "$BASEREF" --) || \
  die "git log on $BASEREF failed, so the merges could not be read; nothing was listed"
[ -n "$SUBJECTS" ] || exit 0

RECORDED=$(recorded_prs "$SINK" "$REPO" "$SCHEMA") || \
  die "the stream at $SINK could not be read (named above); nothing was listed"

# Membership is probed with a case pattern over one space-delimited string,
# not a pipeline per number: in the steady state every merged pull request
# takes this test, so a fork here grows linearly with the history.
RECSET=" ${RECORDED//$'\n'/ } "

SEEN=" "
PRINTED=0
while IFS= read -r s; do
  case "$s" in
    'Merge pull request #'*) ;;
    *) continue ;;
  esac
  rest=${s#"Merge pull request #"}
  num=${rest%% *}
  case "$num" in
    ''|*[!0-9]*) continue ;;
  esac
  # A number merged twice — a revert re-merged — is one pull request, and the
  # newer merge already spoke for it.
  case "$SEEN" in
    *" $num "*) continue ;;
  esac
  SEEN="$SEEN$num "
  set_merge_branch "$s"
  br=$MERGE_BRANCH
  case "$RECSET" in
    *" $num "*) continue ;;
  esac
  printf '%s\t%s\n' "$num" "$br"
  PRINTED=$((PRINTED + 1))
  [ "$PRINTED" -lt "$COUNT" ] || break
done <<EOF
$SUBJECTS
EOF

exit 0
