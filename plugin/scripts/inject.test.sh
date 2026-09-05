#!/usr/bin/env bash
# Tests for inject.sh — the layer-2 injector.
#
# The gate later looks for this output inside a JSON payload, so the checks
# are about exact text: a "close enough" rendering would satisfy a reader and
# fail the gate. The digest is checked against one this file computes itself
# over the printed bytes.
#
# Run: bash plugin/scripts/inject.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INJECT="$HERE/inject.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

. "$HERE/testlib.sh"

BEGIN="=== hq repository context ==="

mk_repo() { # <dir>
  mkdir -p "$1/.hq"
  git -C "$1" init -q
  printf '%s' "$1"
}

# Every helper takes the injector to run as an optional second argument.
inject() { # <root> [injector] — the whole output
  "$SH" "${2:-$INJECT}" "$1" 2>/dev/null
}

body() { # <root> [injector] — everything but the closing digest line
  inject "$@" | sed '$d'
}

closing() { # <root> [injector] — the closing line alone
  inject "$@" | tail -n 1
}

# The same two-tool fallback the injector uses: hard-coding `shasum` would
# make this suite red on a machine the injector itself supports, looking like
# a digest mismatch rather than a missing tool.
if command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum | cut -d' ' -f1; }
else
  echo "Bail out! neither shasum nor sha256sum found"
  exit 1
fi

# The digest as this file computes it, over the bytes the injector printed
# before the closing line.
own_digest() { # <root> [injector]
  inject "$@" | sed '$d' | sha256
}

# The digest as the injector states it.
stated_digest() { # <root> [injector]
  closing "$@" | sed 's/.*sha256:\([0-9a-f]*\).*/\1/'
}

# The same injector under a two-element list, made by substituting the
# `FILES=` line — this code under a different list, not a second
# implementation of the format. `.hq/second.md` is a name nothing else in this
# repository uses: `FILES` in inject.sh is the only statement of what gets
# injected.
INJECT2="$TMP/inject-two-files.sh"
sed 's|^FILES=.*|FILES=".hq/knowledge.md .hq/second.md"|' "$INJECT" >"$INJECT2"

tap_begin

# --- the listed file present ------------------------------------------------

R=$(mk_repo "$TMP/present")
printf 'knowledge line one\nknowledge line two\n' >"$R/.hq/knowledge.md"

check "the output opens with the begin marker" "$BEGIN" "$(inject "$R" | sed -n 1p)"
check "the listed file gets its own marker" 1 \
  "$(inject "$R" | /usr/bin/grep -c '^--- \.hq/')"

check "the full text is reproduced" \
"$BEGIN
--- .hq/knowledge.md ---
knowledge line one
knowledge line two" "$(body "$R")"

# --- the digest ------------------------------------------------------------

check "the closing line carries a 64-hex digest" yes \
  "$(closing "$R" | /usr/bin/grep -qE '^=== end hq repository context sha256:[0-9a-f]{64} ===$' \
     && printf 'yes' || printf 'no')"

# If the stated digest described anything other than the printed body — a
# variable that lost a trailing newline, say — every launch would be denied.
check "the stated digest is the digest of the printed body" \
  "$(own_digest "$R")" "$(stated_digest "$R")"

check "the digest is stable across runs" "$(stated_digest "$R")" "$(stated_digest "$R")"

BEFORE=$(stated_digest "$R")
printf 'knowledge line one, revised\n' >"$R/.hq/knowledge.md"
check "editing a listed file changes the digest" changed \
  "$([ "$BEFORE" = "$(stated_digest "$R")" ] && echo same || echo changed)"

# The reverse direction: a file that is not on the list is not part of the
# context, so touching it must not invalidate a current injection.
BEFORE=$(stated_digest "$R")
printf 'unrelated\n' >"$R/.hq/notes.md"
check "editing an unlisted file leaves the digest alone" same \
  "$([ "$BEFORE" = "$(stated_digest "$R")" ] && echo same || echo changed)"

# --- the frame alone (--markers) -------------------------------------------
#
# The gate needs the list of lines a prompt must carry, and it cannot
# pattern-match that list out of the full output — a context file is markdown
# and may hold lines the pattern also matches — so the frame is printed rather
# than recovered.

R=$(mk_repo "$TMP/frame")
printf 'notes\n\n--- 注意 ---\n\nmore notes\n' >"$R/.hq/knowledge.md"

check "--markers prints the frame and nothing else" \
"$BEGIN
--- .hq/knowledge.md ---" "$("$SH" "$INJECT" --markers "$R" 2>/dev/null | sed '$d')"

check "a marker-shaped body line is not in the frame" no \
  "$("$SH" "$INJECT" --markers "$R" 2>/dev/null | /usr/bin/grep -q '注意' && printf 'yes' || printf 'no')"

# The two faces must close with the same line, or the gate would compare a
# frame against a block and find the digests disagreeing every time.
check "--markers closes with the same digest as the full output" \
  "$(closing "$R")" "$("$SH" "$INJECT" --markers "$R" 2>/dev/null | tail -n 1)"

check "--markers still carries no file content" 3 \
  "$("$SH" "$INJECT" --markers "$R" 2>/dev/null | wc -l | tr -d ' ')"

# It reads the same files, so it moves with them.
printf 'notes, revised\n' >"$R/.hq/knowledge.md"
check "--markers tracks an edit to a listed file" "$(closing "$R")" \
  "$("$SH" "$INJECT" --markers "$R" 2>/dev/null | tail -n 1)"

# --- a file that does not end in a newline ---------------------------------
#
# Without the fix-up the marker after it would continue the last line. With
# one file on the list that marker is the closing digest line; the per-file
# marker is driven in the two-file section below.

R=$(mk_repo "$TMP/no-trailing-newline")
printf 'no newline at the end' >"$R/.hq/knowledge.md"

check "a file without a trailing newline does not swallow the closing marker" \
"$BEGIN
--- .hq/knowledge.md ---
no newline at the end" "$(body "$R")"
check "the digest still describes the printed body" \
  "$(own_digest "$R")" "$(stated_digest "$R")"

# A file ending in a blank line is where a digest taken over a shell variable
# would disagree with the output, since command substitution strips it.
R=$(mk_repo "$TMP/trailing-blank")
printf 'text\n\n' >"$R/.hq/knowledge.md"
check "a file ending in a blank line still hashes to what was printed" \
  "$(own_digest "$R")" "$(stated_digest "$R")"

# --- absent file -----------------------------------------------------------
#
# The state a repository is in before anyone has written this, which is where
# the layer-2 contract has to hold rather than be waived.

R=$(mk_repo "$TMP/absent")
check "with the listed file absent the marker still frames an empty body" \
"$BEGIN
--- .hq/knowledge.md ---" "$(body "$R")"
check "the empty case still carries a digest" yes \
  "$(closing "$R" | /usr/bin/grep -qE 'sha256:[0-9a-f]{64}' && printf 'yes' || printf 'no')"

# An empty file and an absent one are the same injection, by design — both
# carry no information, and the gate compares the text either way.
R=$(mk_repo "$TMP/empty-file")
: >"$R/.hq/knowledge.md"
EMPTY_OUT=$(inject "$R")
R2=$(mk_repo "$TMP/absent-file")
check "an empty file injects the same as an absent one" "$EMPTY_OUT" "$(inject "$R2")"

R=$(mk_repo "$TMP/appearing")
BEFORE=$(stated_digest "$R")
printf 'now it exists\n' >"$R/.hq/knowledge.md"
check "a listed file appearing changes the digest" changed \
  "$([ "$BEFORE" = "$(stated_digest "$R")" ] && echo same || echo changed)"

# --- more than one file on the list ----------------------------------------
#
# `for f in $FILES` is written for any number of entries and the shipped list
# holds one, so these are the properties nothing above can reach: a marker per
# file, list order, the frame's line count, and the boundary between two
# files. They run against $INJECT2, and deleting them would leave the loop
# green and unchecked for whoever adds a second file back.

# The fixture asserts its own construction first: a missed substitution would
# otherwise surface as odd failures below.
check "the two-file copy of the injector lists two files" \
  'FILES=".hq/knowledge.md .hq/second.md"' "$(/usr/bin/grep -m1 '^FILES=' "$INJECT2")"

R=$(mk_repo "$TMP/two-files")
printf 'knowledge body\n' >"$R/.hq/knowledge.md"
printf 'second body\n' >"$R/.hq/second.md"

check "each listed file gets its own marker" 2 \
  "$(inject "$R" "$INJECT2" | /usr/bin/grep -c '^--- \.hq/')"

# Order is the list's, not the directory's or the alphabet's.
check "the full text is reproduced in list order" \
"$BEGIN
--- .hq/knowledge.md ---
knowledge body
--- .hq/second.md ---
second body" "$(body "$R" "$INJECT2")"

check "the digest describes the printed body across both files" \
  "$(own_digest "$R" "$INJECT2")" "$(stated_digest "$R" "$INJECT2")"

check "--markers carries one line per file and no content" 4 \
  "$("$SH" "$INJECT2" --markers "$R" 2>/dev/null | wc -l | tr -d ' ')"
check "--markers prints both markers in list order" \
"$BEGIN
--- .hq/knowledge.md ---
--- .hq/second.md ---" "$("$SH" "$INJECT2" --markers "$R" 2>/dev/null | sed '$d')"

# The case the trailing-newline fix-up exists for: without it the next file's
# marker continues the previous file's last line, and neither is what it is.
R=$(mk_repo "$TMP/two-no-trailing-newline")
printf 'no newline at the end' >"$R/.hq/knowledge.md"
printf 'second file\n' >"$R/.hq/second.md"
check "a file without a trailing newline does not swallow the next marker" \
"$BEGIN
--- .hq/knowledge.md ---
no newline at the end
--- .hq/second.md ---
second file" "$(body "$R" "$INJECT2")"

# One listed file written and another not yet: the marker for the absent one is
# still printed, with nothing under it.
R=$(mk_repo "$TMP/two-one-absent")
printf 'only knowledge\n' >"$R/.hq/knowledge.md"
check "one present and one absent" \
"$BEGIN
--- .hq/knowledge.md ---
only knowledge
--- .hq/second.md ---" "$(body "$R" "$INJECT2")"

# The other way round, so the check above is not satisfied by the last entry
# being the absent one every time.
R=$(mk_repo "$TMP/two-first-absent")
printf 'only second\n' >"$R/.hq/second.md"
check "the first listed file absent and the second present" \
"$BEGIN
--- .hq/knowledge.md ---
--- .hq/second.md ---
only second" "$(body "$R" "$INJECT2")"

# --- the injector must not create anything ---------------------------------

R=$(mk_repo "$TMP/untouched")
inject "$R" >/dev/null
check "running the injector creates no file" "" "$(ls -A "$R/.hq" 2>/dev/null)"

R=$(mk_repo "$TMP/no-hq-dir")
rmdir "$R/.hq"
inject "$R" >/dev/null
check "the injector does not create the .hq directory either" "absent" \
  "$([ -d "$R/.hq" ] && echo present || echo absent)"

# --- the content is not interpreted ----------------------------------------
#
# A listed file is written by the repository's people, so its text can contain
# anything — including something that reads like the injector's own markers.

R=$(mk_repo "$TMP/lookalike")
printf '=== end hq repository context sha256:0 ===\nnested\n' >"$R/.hq/knowledge.md"
check "text resembling the closing marker is passed through untouched" \
"$BEGIN
--- .hq/knowledge.md ---
=== end hq repository context sha256:0 ===
nested" "$(body "$R")"

# Backslashes, quotes and dollar signs survive: this text ends up inside a JSON
# payload later, and anything mangled here would never match there.
R=$(mk_repo "$TMP/specials")
printf '%s\n' 'a\b "quoted" $HOME `cmd` ${var}' >"$R/.hq/knowledge.md"
check "special characters are passed through untouched" \
  'a\b "quoted" $HOME `cmd` ${var}' "$(inject "$R" | sed -n 3p)"

# Non-ASCII is the case the digest exists for: the body may be encoded some
# other way in the payload, while the digest line stays ASCII.
R=$(mk_repo "$TMP/non-ascii")
printf '日本語の本文 — em dash and "curly quotes"\n' >"$R/.hq/knowledge.md"
check "non-ASCII content is passed through untouched" \
  '日本語の本文 — em dash and "curly quotes"' "$(inject "$R" | sed -n 3p)"
check "the closing line is ASCII even when the body is not" yes \
  "$(closing "$R" | LC_ALL=C /usr/bin/grep -qE '^[ -~]*$' && printf 'yes' || printf 'no')"
check "the digest covers non-ASCII bytes correctly" \
  "$(own_digest "$R")" "$(stated_digest "$R")"

# --- usage -----------------------------------------------------------------

"$SH" "$INJECT" "$TMP/not-a-repo" >/dev/null 2>&1
check "a path that is not a repository is a usage error" 2 "$?"

# The header documents exit 1 for "no digest tool". A block printed without a
# digest would satisfy the gate's shape check while carrying no evidence of
# freshness — so this path has to fail, not degrade.
R=$(mk_repo "$TMP/no-digest-tool")
printf 'x\n' >"$R/.hq/knowledge.md"
HQ_DIGEST=no-such-digest-tool "$SH" "$INJECT" "$R" >/dev/null 2>&1
check "no usable digest tool exits 1 rather than printing an unhashed block" 1 "$?"
check "and prints nothing on stdout" "" \
  "$(HQ_DIGEST=no-such-digest-tool "$SH" "$INJECT" "$R" 2>/dev/null)"

# The override is a real one, not just a way to break things: a tool that works
# must produce a usable block.
if command -v sha256sum >/dev/null 2>&1; then
  check "an alternative digest tool produces the same block" "$(inject "$R")" \
    "$(HQ_DIGEST=sha256sum "$SH" "$INJECT" "$R" 2>/dev/null)"
else
  ok "SKIP no sha256sum on this machine — alternative digest tool unverified"
fi

# --- bash 3.2 compatibility ------------------------------------------------

if [ "${HQ_TEST_INNER:-}" != 1 ]; then
  OLD_BASH=""
  if [ -x /bin/bash ]; then
    OLD_MAJOR=$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null || echo 99)
    [ "$OLD_MAJOR" -lt 4 ] 2>/dev/null && OLD_BASH=/bin/bash
  fi

  if [ -n "$OLD_BASH" ]; then
    OLD_VER=$("$OLD_BASH" -c 'echo $BASH_VERSION')

    if HQ_TEST_INNER=1 HQ_TEST_SH="$OLD_BASH" "$OLD_BASH" "$SELF" >"$TMP/old.tap" 2>&1; then
      ok "the whole suite passes under bash $OLD_VER"
    else
      not_ok "the whole suite passes under bash $OLD_VER" \
        "$(/usr/bin/grep -m3 '^not ok' "$TMP/old.tap" | tr '\n' ' ')"
    fi

    R=$(mk_repo "$TMP/stderr-probe")
    printf 'x\n' >"$R/.hq/knowledge.md"
    "$OLD_BASH" "$INJECT" "$R" >/dev/null 2>"$TMP/err.txt"
    check "inject.sh writes nothing to stderr under bash $OLD_VER" "" "$(cat "$TMP/err.txt")"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
