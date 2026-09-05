#!/usr/bin/env bash
# hq shared functions.
#
# Functions:
#   hq_branch_dir     <branch>                   branch name -> directory name
#   hq_repo_key       [<repo-root>]              this clone's key under the home
#   hq_task_dir       [<repo-root>] [<branch>]   where a branch's run files live
#   hq_run_id         [<repo-root>] [<branch>]   the identifier of this cycle
#   hq_resolve_base   [<repo-root>]              base-branch resolution chain
#   hq_changed_files  <base> [<head>] [<root>]   the changed paths, one per line
#   hq_classify_file  <path>                     code | prose
#   hq_verifier_for   <path>                     which verifier reviews it
#   hq_review_targets <base> [<head>] [<root>]   verifier + path, one per line
#   hq_diff_profile   <base> [<head>] [<root>]   code | prose | mixed | none
#
# Also invocable as a command: `bash lib.sh <function> [args...]`.
#
# Portability: bash 3.2 (stock macOS /bin/bash) and BSD userland. No jq.

set -u
LC_ALL=C
export LC_ALL

# Branch name -> the directory name a run's working files take.
hq_branch_dir() { # <branch>
  [ $# -eq 1 ] || { echo "usage: hq_branch_dir <branch>" >&2; return 2; }
  printf '%s\n' "$1" | tr '/' '-'
}

# --- where a run's working files live ---------------------------------------
#
# THE WORKING FILES ARE NOT IN THE REPOSITORY BEING WORKED ON, and the
# derivation is here and nowhere else.

# The home. One knob, HQ_HOME, defaulting to ~/.hq; record.sh reads the same
# variable for the telemetry sink.
#
# A RELATIVE VALUE IS REFUSED, not resolved: everything below composes a path
# from this one, and for a hook the current directory is the repository being
# worked on — the one place this layout exists to keep these files out of.
#
# A MISSING `HOME` IS REFUSED BY NAME rather than left to `set -u`, so the
# error says which variable to set. Not defaulted to `/.hq` in that case: that
# is an absolute path, so it would pass the check below and put a whole home
# at the filesystem root.
hq_home() {
  local h="${HQ_HOME:-}"
  if [ -z "$h" ]; then
    [ -n "${HOME:-}" ] || {
      echo "hq_home: neither HQ_HOME nor HOME is set, so there is no home to derive from. Set HQ_HOME to an absolute path." >&2
      return 2
    }
    h="$HOME/.hq"
  fi
  case "$h" in
    /*) ;;
    *) echo "hq_home: HQ_HOME must be an absolute path, got '$h'" >&2; return 2 ;;
  esac
  while :; do
    case "$h" in
      /|*[!/]) break ;;
      */) h=${h%/} ;;
    esac
  done
  printf '%s' "$h"
}

# The key this clone has under the home: the COMMON git dir's absolute path,
# with the leading `/` dropped and every character outside [A-Za-z0-9._-] folded
# to `-`.
#
# COMMON GIT DIR, NOT THE TOP LEVEL: `--show-toplevel` differs per worktree of
# one clone; the common git dir is the same for all of them and differs between
# clones, so the working files follow the branch rather than the directory it
# is checked out in.
#
# THE KEY IS NOT INJECTIVE. `/a/b/c` and `/a-b/c` fold to the same key, so two
# clones whose paths differ only in a character outside the set would share a
# directory. Nothing guards it; stated as a property instead.
hq_repo_key() { # [<repo-root>]
  local root d
  root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  [ -n "$root" ] || { echo "hq_repo_key: not in a git repository" >&2; return 2; }
  d=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null) || d=""
  [ -n "$d" ] || { echo "hq_repo_key: not a git repository: $root" >&2; return 2; }
  # `--git-common-dir` answers relative to the directory git ran in, which `-C`
  # made $root. Resolved with `pwd -P` so that two spellings of one directory —
  # /var and /private/var on macOS — cannot become two keys for one clone.
  case "$d" in /*) ;; *) d="$root/$d" ;; esac
  d=$(cd "$d" 2>/dev/null && pwd -P) || d=""
  [ -n "$d" ] || { echo "hq_repo_key: cannot resolve the git directory of $root" >&2; return 2; }
  printf '%s\n' "$(printf '%s' "${d#/}" | tr -c 'A-Za-z0-9._-' '-')"
}

# <HQ_HOME>/repos/<repo-key>/tasks/<branch-dir> — the directory holding one
# branch's run: `plan.md`, `findings.jsonl`, `reports/`, `directives/`,
# `checks.md` and `run_id`. No trailing slash; callers append the file name.
#
# A DETACHED HEAD IS REFUSED RATHER THAN ANSWERED: answering would file the
# run under `HEAD/`, where the next detached run would read it as its own.
hq_task_dir() { # [<repo-root>] [<branch>]
  local root branch key home
  root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  [ -n "$root" ] || { echo "hq_task_dir: not in a git repository" >&2; return 2; }
  # The repository is settled first, so that a root that is not one says so
  # rather than being reported as a checkout with no branch.
  key=$(hq_repo_key "$root") || return 2
  branch="${2:-$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
  case "$branch" in
    ''|HEAD) echo "hq_task_dir: no branch is checked out in $root" >&2; return 2 ;;
  esac
  # Taken into a variable first: inside a command substitution the non-zero
  # return of hq_home is swallowed, and printf would compose `/repos/…` at the
  # filesystem root.
  home=$(hq_home) || return 2
  printf '%s/repos/%s/tasks/%s\n' "$home" "$key" "$(hq_branch_dir "$branch")"
}

# The identifier every telemetry row is scoped by, ONE PER CYCLE — the run of
# work a branch carries, plan through ship and beyond.
#
# IT IS A FILE BECAUSE IT HAS TO OUTLIVE THE PROCESS: composed inline, every
# call would mint a new id and the field would name a call rather than a cycle.
#
# THE BOUNDARY IS THE BRANCH'S LIFETIME, and this function does not end it:
# the id ends when the run's directory does, which is the archiving module's
# to do.
#
# THE FIRST WRITER WINS: `set -C` in a subshell makes the second writer's
# redirect fail, and both then read what the first wrote. An empty file is a
# torn write rather than an identifier, so it is removed before the attempt.
#
# THE COMPOSITION IS NOT INJECTIVE: the same clone directory name, branch name
# and UTC second compose the same string. Nothing guards it; the envelope's
# `repo` still tells the rows apart.
hq_run_id() { # [<repo-root>] [<branch>]
  local root dir file id
  root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  [ -n "$root" ] || { echo "hq_run_id: not in a git repository" >&2; return 2; }
  dir=$(hq_task_dir "$root" "${2:-}") || return 2

  file="$dir/run_id"
  id=$(head -1 "$file" 2>/dev/null)
  if [ -z "$id" ]; then
    [ ! -e "$file" ] || rm -f "$file" 2>/dev/null
    mkdir -p "$dir" 2>/dev/null || {
      echo "hq_run_id: cannot create $dir" >&2; return 2; }
    ( set -C; printf '%s-%s-%s\n' \
        "$(basename "$root")" "$(basename "$dir")" "$(date -u +%Y%m%dT%H%M%S)" \
        >"$file" ) 2>/dev/null
    id=$(head -1 "$file" 2>/dev/null)
  fi
  [ -n "$id" ] || {
    echo "hq_run_id: cannot read or write $file" >&2; return 2; }
  printf '%s\n' "$id"
}

# Base-branch resolution chain, in this order for every caller:
#   .hq/settings.json `base_branch`            project default
#   -> git symbolic-ref refs/remotes/origin/HEAD  remote HEAD, `origin/` stripped
#   -> main
#
# The JSON is read without jq, deliberately narrow: `"base_branch"` as a key
# followed by a string value, first match, nothing else. A nested object
# carrying the same key would be picked up — .hq/settings.json is flat, and
# this is not a JSON parser.
#
# A root that is not a repository is refused rather than answered: the last
# step returns `main` for any input, so answering would hand the caller a
# plausible branch name it would then take a diff against.
hq_resolve_base() { # [<repo-root>]
  local root val
  root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  [ -n "$root" ] || { echo "hq_resolve_base: not in a git repository" >&2; return 2; }
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || {
    echo "hq_resolve_base: not a git repository: $root" >&2; return 2; }

  if [ -f "$root/.hq/settings.json" ]; then
    val=$(/usr/bin/grep -o '"base_branch"[[:space:]]*:[[:space:]]*"[^"]*"' \
          "$root/.hq/settings.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    if [ -n "$val" ]; then printf '%s\n' "$val"; return 0; fi
  fi

  # --short still leaves the `origin/` prefix; every consumer wants it gone.
  val=$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -n "$val" ]; then printf '%s\n' "${val#origin/}"; return 0; fi

  printf 'main\n'
}

# code | prose, per file — what selects a verifier, chosen per changed file
# rather than per pull request. `prose` is the closed list: what a person
# reads. Everything else is `code`, including structured configuration and
# files with no extension — for an extension nobody anticipated, the
# conservative direction is more scrutiny, not less.
#
# The extension is taken from the basename; its equivalence with the
# whole-path form is a property of this particular prose list, not of the code.
hq_classify_file() { # <path>
  [ $# -eq 1 ] || { echo "usage: hq_classify_file <path>" >&2; return 2; }
  local base ext
  base=${1##*/}
  case "$base" in
    ?*.*) ext=$(printf '%s' "${base##*.}" | tr 'A-Z' 'a-z') ;;
    *)    ext="" ;;
  esac
  case "$ext" in
    md|markdown|txt|rst|csv|svg|html|htm|css) printf 'prose\n' ;;
    *) printf 'code\n' ;;
  esac
}

# Which verifier reviews a given file, per file and not per pull request.
# Every class maps to the same verifier, deliberately. The branch below is
# the only place a second verifier gets wired in: callers ask this function,
# they do not classify and decide themselves.
hq_verifier_for() { # <path>
  [ $# -eq 1 ] || { echo "usage: hq_verifier_for <path>" >&2; return 2; }
  case "$(hq_classify_file "$1")" in
    code)  printf 'reviewer\n' ;;
    prose) printf 'reviewer\n' ;;
  esac
}

# The changed file list, or a non-zero exit with the reason on stderr.
#
# An empty diff and a diff that could not be taken produce the same empty
# output, and the caller reads empty as "nothing changed": exit 3 says the
# diff is unavailable, exit 0 with no output says there is nothing in it.
#
# Everything printed on stdout is read by callers as a path, so stderr is not
# folded in: git says things while exiting 0 (`GIT_TRACE` alone adds three
# lines), and each such line would become a path nobody wrote.
hq_changed_files() { # <base> [<head>] [<repo-root>]
  [ $# -ge 1 ] || { echo "usage: hq_changed_files <base> [<head>] [<repo-root>]" >&2; return 2; }
  local out err status head="${2:-HEAD}" root="${3:-.}"
  err=$(mktemp) || { echo "hq_changed_files: mktemp failed" >&2; return 3; }
  out=$(git -C "$root" diff --name-only "$1...$head" 2>"$err")
  status=$?
  # Whatever git said still reaches a person, on the stream it was written to.
  [ -s "$err" ] && cat "$err" >&2
  rm -f "$err"
  [ "$status" -eq 0 ] || return 3
  [ -n "$out" ] || return 0
  printf '%s\n' "$out"
}

# The changed files paired with the verifier that takes each one, as
# `<verifier><TAB><path>`, one per line. Empty output means no file changed;
# exit 3 means the diff could not be taken at all.
hq_review_targets() { # <base> [<head>] [<repo-root>]
  [ $# -ge 1 ] || { echo "usage: hq_review_targets <base> [<head>] [<repo-root>]" >&2; return 2; }
  local base="$1" head="${2:-HEAD}" root="${3:-.}" f v files
  files=$(hq_changed_files "$base" "$head" "$root") || return 3
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    v=$(hq_verifier_for "$f")
    [ -n "$v" ] && printf '%s\t%s\n' "$v" "$f"
  done <<EOF
$files
EOF
  return 0
}

# The pull request's profile, from the same per-file classification. Used to
# label a record and to group yield by kind of change — never to decide whether
# a verifier runs, which is a per-file question.
hq_diff_profile() { # <base> [<head>] [<repo-root>]
  [ $# -ge 1 ] || { echo "usage: hq_diff_profile <base> [<head>] [<repo-root>]" >&2; return 2; }
  local base="$1" head="${2:-HEAD}" root="${3:-.}" f have_prose have_code files
  files=$(hq_changed_files "$base" "$head" "$root") || return 3
  have_prose=0; have_code=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$(hq_classify_file "$f")" = code ]; then have_code=1; else have_prose=1; fi
  done <<EOF
$files
EOF
  if [ "$have_prose" -eq 1 ] && [ "$have_code" -eq 1 ]; then printf 'mixed\n'
  elif [ "$have_prose" -eq 1 ]; then printf 'prose\n'
  elif [ "$have_code" -eq 1 ]; then printf 'code\n'
  else printf 'none\n'
  fi
}

# Command dispatch: `bash lib.sh <function> [args...]`
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  fn="${1:-}"
  case "$fn" in
    hq_branch_dir|hq_repo_key|hq_task_dir|hq_run_id|hq_resolve_base|hq_changed_files|hq_classify_file|hq_verifier_for|hq_review_targets|hq_diff_profile)
      shift
      "$fn" "$@"
      ;;
    *)
      echo "usage: bash lib.sh {hq_branch_dir|hq_repo_key|hq_task_dir|hq_run_id|hq_resolve_base|hq_changed_files|hq_classify_file|hq_verifier_for|hq_review_targets|hq_diff_profile} [args...]" >&2
      exit 2
      ;;
  esac
fi
