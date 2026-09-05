#!/usr/bin/env bash
# Suite for secrets-check.sh.
#
# EVERY SHAPE GETS A POSITIVE CONTROL, and the count of shapes is asserted
# beside them. A guard like this fails by matching nothing — a pattern edited
# into uselessness, a face that stopped reading its input — and a tree with no
# secrets in it looks exactly the same as a scanner that has stopped scanning.
# So each case here plants one thing and requires it to be refused.
#
# The fixture repository is a real one: this script's faces read `git` and the
# staged face reads a diff, so a directory of loose files would exercise
# neither.
#
# Output is TAP. Exit 0 when every check passes.
#
# Run: bash .claude/scripts/secrets-check.test.sh

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
SCAN="$HERE/secrets-check.sh"
TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

N=0
FAILED=0
ok() { N=$((N + 1)); printf 'ok %d - %s\n' "$N" "$1"; }
not_ok() { # <name> <detail>
  N=$((N + 1))
  FAILED=$((FAILED + 1))
  printf 'not ok %d - %s\n  ---\n  detail: %s\n  ...\n' "$N" "$1" "$2"
}
check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "expected [$2], got [$3]"; fi
}

# A repository shaped the way the scanner expects to be run inside: the script
# sits at .claude/scripts/ and derives the root two levels up.
REPO="$TMP/repo"
mkdir -p "$REPO/.claude/scripts"
cp "$SCAN" "$REPO/.claude/scripts/secrets-check.sh"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name t
printf 'seed\n' >"$REPO/seed.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m seed

BLOCK="$TMP/blocklist"
printf '# a comment\n\nacmecorp\nProject Nightingale\n' >"$BLOCK"

run() { # <face> [<blocklist path>] — prints the exit code, output kept in $TMP/out
  local face=$1 bl=${2-}
  ( cd "$REPO" && HQ_BLOCKLIST="$bl" bash .claude/scripts/secrets-check.sh "$face" ) \
    >"$TMP/out" 2>"$TMP/err"
  printf '%s' "$?"
}

says() { /usr/bin/grep -q -- "$1" "$TMP/out" && printf 'yes' || printf 'no'; }
says_err() { /usr/bin/grep -q -- "$1" "$TMP/err" && printf 'yes' || printf 'no'; }

plant() { # <content> — one tracked file holding it, staged
  printf '%s\n' "$1" >"$REPO/planted.txt"
  git -C "$REPO" add planted.txt
}
unplant() {
  rm -f "$REPO/planted.txt"
  git -C "$REPO" rm -q --cached planted.txt >/dev/null 2>&1 || true
}

printf 'TAP version 13\n'

# --- a clean tree ------------------------------------------------------------

check "a clean tree passes" 0 "$(run tree "$BLOCK")"
check "and says nothing" "" "$(cat "$TMP/out")"

# --- every shape, one at a time ----------------------------------------------
#
# The list is read out of the script rather than copied, so a shape added there
# without a case here is reported by the count below rather than going unseen.

SHAPE_N=$(/usr/bin/grep -c . <<EOF
$(sed -n "/^SHAPES='/,/'$/p" "$SCAN" | sed "s/^SHAPES='//; s/'$//")
EOF
)
check "the shape list was read out of the script" yes \
  "$([ "$SHAPE_N" -ge 7 ] && echo yes || echo "no ($SHAPE_N)")"

CASES=7

# EVERY PLANTED VALUE IS ASSEMBLED FROM PIECES. A literal here would be a
# tracked line carrying the very shape this script refuses, so the `tree` face
# would report its own suite — and the fix for that (exempting this path)
# would be a hole anything could hide in.
plant "-----BEGIN RSA PRIVATE"" KEY-----" 
check "a private key header is refused" 1 "$(run tree "$BLOCK")"

plant "AKIA""IOSFODNN7EXAMPLE"
check "an AWS access key id is refused" 1 "$(run tree "$BLOCK")"

plant "ghp""_0123456789abcdefghijklmnopqrstuvwxyz"
check "a GitHub token is refused" 1 "$(run tree "$BLOCK")"

plant "xox""b-1234567890-abcdefghij"
check "a Slack token is refused" 1 "$(run tree "$BLOCK")"

plant "API""_KEY = 's3cr3tvaluewithlength'"
check "a long value assigned to a secret-shaped name is refused" 1 "$(run tree "$BLOCK")"

plant "see /User""s/someone/dev/thing for the path"
check "an absolute home path is refused" 1 "$(run tree "$BLOCK")"

plant "write to someone""@realdomain.co.jp when it breaks"
check "an email address is refused" 1 "$(run tree "$BLOCK")"

check "every shape in the script has a case here" "$SHAPE_N" "$CASES"

# --- what must NOT be refused ------------------------------------------------

plant 'mail the team at someone@example.com'
check "a placeholder domain is allowed" 0 "$(run tree "$BLOCK")"

plant "AKIA""IOSFODNN7EXAMPLE  # secrets-allow: the shape itself, documented"
check "a line marked secrets-allow is allowed" 0 "$(run tree "$BLOCK")"

# --- the blocklist -----------------------------------------------------------

plant 'the work we did for acmecorp last spring'
check "a blocklisted term is refused" 1 "$(run tree "$BLOCK")"
check "and the term itself is not printed back" no "$(says 'acmecorp')"
check "but the file is named" yes "$(says 'planted.txt')"

plant 'PROJECT NIGHTINGALE ships in march'
check "a blocklisted term is matched whatever its case" 1 "$(run tree "$BLOCK")"

plant 'a comment line in the blocklist matches nothing'
check "a comment in the blocklist is not a term" 0 "$(run tree "$BLOCK")"

unplant

# A path can leak a name with no line of content doing it.
mkdir -p "$REPO/acmecorp"
printf 'nothing here\n' >"$REPO/acmecorp/notes.txt"
git -C "$REPO" add acmecorp
check "a blocklisted term in a path is refused" 1 "$(run tree "$BLOCK")"
git -C "$REPO" rm -q -r --cached acmecorp >/dev/null 2>&1
rm -rf "$REPO/acmecorp"

# --- a missing blocklist is reported, and is not a pass -----------------------

plant 'the work we did for acmecorp last spring'
check "with no blocklist the named term is not caught" 0 "$(run tree "$TMP/no-such-file")"
check "and the run says the list was not read" yes \
  "$(says_err 'no blocklist at')"
plant "-----BEGIN RSA PRIVATE"" KEY-----"
check "but the shapes still run without one" 1 "$(run tree "$TMP/no-such-file")"
unplant

# --- the staged face ---------------------------------------------------------

plant "ghp""_0123456789abcdefghijklmnopqrstuvwxyz"
check "staged refuses what the commit would add" 1 "$(run staged "$BLOCK")"

# THE DIFF'S `+` IS NOT CONTENT. Left on, it becomes the first character of
# every added line, and the address shape accepts it as a local part — so a
# line whose real content begins with `@` reads as an address nobody wrote.
# The `tree` face never sees a marker, so the two faces disagreed about the
# same file, which is how this was found.
plant "@SOMEFILE.md"
check "an added line beginning with @ is not read as an address" 0 \
  "$(run staged "$BLOCK")"
check "and the tree face agrees with it" 0 "$(run tree "$BLOCK")"

# REMOVING A LEAK MUST BE COMMITTABLE. A diff is scanned on its added lines
# only; taking the other reading makes the fix for a leak the one change that
# cannot be committed.
git -C "$REPO" commit -q -m 'planted' 2>/dev/null
git -C "$REPO" rm -q planted.txt
check "staged allows a commit that removes the leaked line" 0 "$(run staged "$BLOCK")"
git -C "$REPO" commit -q -m 'removed'

# --- usage -------------------------------------------------------------------

( cd "$REPO" && bash .claude/scripts/secrets-check.sh ) >/dev/null 2>&1
check "no face is a usage error" 2 "$?"
( cd "$REPO" && bash .claude/scripts/secrets-check.sh nonsense ) >/dev/null 2>&1
check "an unknown face is a usage error" 2 "$?"

printf '1..%d\n' "$N"
if [ "$FAILED" -eq 0 ]; then
  printf '# all %d checks passed\n' "$N"
else
  printf '# %d of %d checks failed\n' "$FAILED" "$N"
  exit 1
fi
