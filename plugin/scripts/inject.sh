#!/usr/bin/env bash
# hq layer-2 injector — prints the repository context that gets pasted into
# a subagent's launch prompt verbatim.
#
#   usage: bash inject.sh [--markers] [<repo-root>]
#
# `--markers` prints the frame alone — the opening marker, one line per listed
# file, and the closing digest — with no file content between them. The gate
# uses it to know which lines a prompt must carry: it cannot recover that list
# from the full output, because a context file is markdown and may contain a
# line any marker pattern loose enough to match also matches.
#
# Two properties this script is built around, both from the layer-2 contract:
#
#   Whole files, never sections: the launch gate compares what was pasted
#   against what the file says now, and a rule that extracts cannot be
#   compared against anything.
#
#   A missing file is empty, not an error: its marker is printed with nothing
#   under it. THIS SCRIPT NEVER CREATES A FILE.
#
# The markers are part of what gets compared, so they are fixed text. A file
# whose content does not end in a newline gets one added, and only there: a
# marker that started mid-line would break the comparison.
#
# WHY THE DIGEST IS IN THE CLOSING MARKER. The gate reads the prompt out of a
# JSON payload whose encoder is not ours, and a listed file holds non-ASCII;
# comparing body text directly would fail on encoding rather than content. The
# digest line is ASCII whatever the body holds, so it survives any encoding,
# and it changes the moment a listed file does.
#
# Exit codes: 0 printed, 2 usage (no repository), 1 no digest tool.
#
# Portability: bash 3.2, BSD userland.

set -u
LC_ALL=C
export LC_ALL

# The list. Adding an element here is what "inject one more thing" means, and
# THIS LINE IS THE ONLY STATEMENT OF THE LIST. The code below works for any
# number of elements; inject.test.sh drives the multi-element properties
# against a copy with the line below substituted — a coupling to its shape.
FILES=".hq/knowledge.md"

BEGIN_MARKER="=== hq repository context ==="

MARKERS_ONLY=""
case "${1:-}" in
  --markers) MARKERS_ONLY=1; shift ;;
esac

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$root" ] || { echo "inject.sh: not in a git repository" >&2; exit 2; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "inject.sh: not a git repository: $root" >&2; exit 2; }

# Missing both tools is an error rather than a fallback to an unhashed block:
# a block with no digest would pass the gate's shape check while carrying no
# evidence of freshness.
#
# HQ_DIGEST names a different tool — one that reads stdin and prints a sha256
# hex digest first on the line. It exists so the tests can reach the branch
# where no tool is found.
if [ -n "${HQ_DIGEST:-}" ]; then
  command -v "$HQ_DIGEST" >/dev/null 2>&1 || {
    echo "inject.sh: HQ_DIGEST names a command that is not on PATH: $HQ_DIGEST" >&2
    exit 1
  }
  digest() { "$HQ_DIGEST" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  digest() { shasum -a 256 | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null 2>&1; then
  digest() { sha256sum | cut -d' ' -f1; }
else
  echo "inject.sh: neither shasum nor sha256sum found" >&2
  exit 1
fi

# The body is assembled into a file so the digest is taken over the exact
# bytes that get printed: command substitution strips trailing newlines,
# which would make the digest disagree for any file ending in a blank line.
BODY=$(mktemp) || { echo "inject.sh: mktemp failed" >&2; exit 1; }
trap 'rm -f "$BODY"' EXIT

{
  printf '%s\n' "$BEGIN_MARKER"
  for f in $FILES; do
    printf -- '--- %s ---\n' "$f"
    [ -f "$root/$f" ] || continue
    cat "$root/$f"
    # Add the newline only when the file lacks one. `tail -c1 | wc -l` is 0
    # when the last byte is not a newline, and also 0 for an empty file — which
    # needs nothing added, hence the -s test first.
    if [ -s "$root/$f" ] && [ "$(tail -c1 "$root/$f" | wc -l | tr -d ' ')" -eq 0 ]; then
      printf '\n'
    fi
  done
} >"$BODY"

# The digest is taken over the body either way, so the closing line is the
# same in both faces — the gate can compare a frame against a full block.
if [ -n "$MARKERS_ONLY" ]; then
  printf '%s\n' "$BEGIN_MARKER"
  for f in $FILES; do
    printf -- '--- %s ---\n' "$f"
  done
else
  cat "$BODY"
fi
printf '=== end hq repository context sha256:%s ===\n' "$(digest <"$BODY")"
