#!/usr/bin/env bash
# secrets-check.sh — refuses content this repository must not publish.
#
#   secrets-check.sh staged     what a commit is about to add. exit 0 clean,
#                               1 hits, 2 could not look.
#   secrets-check.sh tree       every tracked file, contents and paths. Same
#                               exit codes. This is the face `check.sh` runs.
#
# TWO SOURCES, AND THEY FAIL DIFFERENTLY.
#
#   1. THE BLOCKLIST — terms this machine's owner must never publish: client
#      names, project code names, people. It lives OUTSIDE the repository, at
#      <HQ_HOME>/blocklist (HQ_HOME defaults to ~/.hq), one term per line,
#      `#` starts a comment.
#
#      IT IS OUTSIDE THE REPOSITORY ON PURPOSE. A tracked file listing the
#      names that must not be published would publish them — the guard would
#      leak exactly what it guards. Nothing here ever prints a blocklist term
#      either: a hit names the file and the line number and stops.
#
#      A missing blocklist is REPORTED AND NOT FATAL. Someone who clones this
#      repository has no reason to hold the owner's list, and blocking them
#      would make the guard something to switch off. The shapes below still
#      run for everyone.
#
#   2. THE SHAPES — secrets that look like secrets whoever wrote them: private
#      keys, provider tokens, an assignment of something long to a name like
#      SECRET. These need no list and run everywhere.
#
# WHAT IT CANNOT DO. It cannot recognise a proper noun it was never told
# about. "No client name reaches the tree" is not a property any regular
# expression holds, and reading this script as though it did is the mistake
# worth naming here: it enforces a list plus a set of shapes, and the list is
# only as good as the last time somebody added to it.
#
# An intentional line — a fixture, an example, documentation of the pattern
# itself — carries `secrets-allow` in a comment on that same line.
#
# Portability: bash 3.2, BSD userland.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd) || exit 2
BLOCKLIST="${HQ_BLOCKLIST:-${HQ_HOME:-$HOME/.hq}/blocklist}"

# The shapes, one per line of the alternation. Kept as one variable so the
# test can count them and drive each one.
#
# `secrets-allow` elsewhere on the line exempts it; the exemption is per line
# rather than per file, so a file holding one example is still swept.
SHAPES='-----BEGIN [A-Z ]*PRIVATE KEY-----
AKIA[0-9A-Z]{16}
gh[pousr]_[A-Za-z0-9]{30,}
xox[abpsr]-[0-9A-Za-z-]{10,}
(SECRET|TOKEN|PASSWORD|PASSWD|API_KEY|ACCESS_KEY|PRIVATE_KEY)[A-Z_]*[[:space:]]*[:=][[:space:]]*.?[A-Za-z0-9/+_-]{16,}
(^|[^A-Za-z0-9_.])/(Users|home)/[a-z][a-z0-9_-]+/
[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

# `example.com` and the placeholder domains are what the repository's own rule
# tells writers to use, so the address shape has to let them through or the
# rule and the guard contradict each other.
# An SSH remote is an address shape that is not an address, and it appears in
# any fixture that builds a repository. `git@<forge>` is the whole of it.
ALLOWED_DOMAINS='@example\.(com|org|net)|@localhost|git@(github|gitlab|bitbucket)\.'

shapes_re() {
  printf '%s' "$SHAPES" | tr '\n' '|' | sed 's/|$//'
}

# What every hit passes through before it is reported: a line that says it is
# deliberate is not a hit, and the placeholder domains the naming rule tells
# writers to use are not addresses.
drop_allowed() {
  /usr/bin/grep -v 'secrets-allow' | /usr/bin/grep -v -E "$ALLOWED_DOMAINS"
}

# The blocklist's terms, comments and blank lines removed, prepared once.
# Returns non-zero when there is no list to apply.
blocklist_terms() {
  [ -f "$BLOCKLIST" ] || return 1
  /usr/bin/grep -v -E '^[[:space:]]*(#|$)' "$BLOCKLIST" >"$TMPPAT" 2>/dev/null
  [ -s "$TMPPAT" ]
}

# A blocklist hit NEVER carries the term. Everything after `<file>:<line>:` is
# replaced, because the term is the thing being protected; the shapes print
# what they matched, since a token already in the tree is not revealed by
# saying so.
hide_terms() {
  sed -E 's|^(.*):([0-9]+):.*$|\1:\2: a blocklisted term (the term is not printed)|'
}

# One file, labelled by the caller — the staged face reads a diff, which has no
# filename worth printing.
scan_text() { # <label> <file to read>
  local label=$1 src=$2 re
  re=$(shapes_re)
  /usr/bin/grep -n -E -e "$re" "$src" 2>/dev/null | drop_allowed | sed "s|^|$label:|"
}

scan_blocklist() { # <label> <file to read>
  local label=$1 src=$2
  blocklist_terms || return 0
  /usr/bin/grep -n -i -F -f "$TMPPAT" "$src" 2>/dev/null \
    | /usr/bin/grep -v 'secrets-allow' \
    | sed "s|:.*|: a blocklisted term (the term is not printed)|" \
    | sed "s|^|$label:|"
}

# THE WHOLE TREE IN ONE PASS. Called once per file, `grep -f` rebuilds its
# matcher over every pattern each time, and with a blocklist of a few hundred
# terms that was the slowest thing in the repository's gate. `-H` forces the
# filename prefix even when a batch happens to hold one file, so the output
# shape does not depend on how xargs split the list.
scan_tree() { # <NUL-separated paths on stdin> — shapes, then the blocklist
  local re; re=$(shapes_re)
  ( cd "$ROOT" && xargs -0 /usr/bin/grep -H -n -E -e "$re" -- 2>/dev/null ) \
    | drop_allowed
}

scan_tree_blocklist() { # <NUL-separated paths on stdin>
  blocklist_terms || return 0
  ( cd "$ROOT" && xargs -0 /usr/bin/grep -H -n -i -F -f "$TMPPAT" -- 2>/dev/null ) \
    | /usr/bin/grep -v 'secrets-allow' \
    | hide_terms
}

TMPPAT=$(mktemp) || exit 2
TMPBUF=$(mktemp) || exit 2
TMPLIST=$(mktemp) || exit 2
trap 'rm -f "$TMPPAT" "$TMPBUF" "$TMPLIST"' EXIT

HITS=""
add() { [ -n "$1" ] && HITS="$HITS$1
"; }

case "${1:-}" in
  staged)
    # Added lines only: a diff that removes a leaked line must not be refused
    # for containing it, or the fix for a leak becomes uncommittable.
    git -C "$ROOT" diff --cached -U0 --no-color >"$TMPBUF" 2>/dev/null || exit 2
    # THE MARKER COMES OFF. The leading plus is the diff's, not the content's,
    # and leaving it on makes it the first character of every added line — the
    # address shape accepts it as a local part, so a line whose real content
    # begins with an at-sign and names a file reads as an address that nobody
    # wrote. Scanning the marker is scanning something that is not in the file.
    # (The literal is not written out here: this file is swept too.)
    /usr/bin/grep '^+' "$TMPBUF" | /usr/bin/grep -v '^+++' | sed 's/^+//' \
      >"$TMPBUF.added" 2>/dev/null
    mv "$TMPBUF.added" "$TMPBUF"
    add "$(scan_text 'staged' "$TMPBUF")"
    add "$(scan_blocklist 'staged' "$TMPBUF")"
    # The paths themselves: a file named after a client leaks without a single
    # line of content doing so.
    git -C "$ROOT" diff --cached --name-only >"$TMPBUF" 2>/dev/null
    add "$(scan_blocklist 'staged path' "$TMPBUF")"
    ;;
  tree)
    ( cd "$ROOT" && git ls-files ) >"$TMPBUF" 2>/dev/null || exit 2
    add "$(scan_blocklist 'tracked path' "$TMPBUF")"
    ( cd "$ROOT" && git ls-files -z ) >"$TMPLIST" 2>/dev/null || exit 2
    add "$(scan_tree <"$TMPLIST")"
    add "$(scan_tree_blocklist <"$TMPLIST")"
    ;;
  *)
    echo "usage: secrets-check.sh {staged|tree}" >&2
    exit 2
    ;;
esac

# NOT HAVING LOOKED IS SAID OUT LOUD. A run with no blocklist checks strictly
# less than one with it, and a reader who cannot tell the two apart reads a
# partial pass as a full one.
[ -f "$BLOCKLIST" ] || \
  echo "secrets-check: no blocklist at $BLOCKLIST — the shapes were checked, the named terms were not" >&2

if [ -n "$HITS" ]; then
  printf '%s' "$HITS"
  echo "secrets-check: refused. Remove it, or mark the line 'secrets-allow' if it is deliberate." >&2
  exit 1
fi
exit 0
