#!/usr/bin/env bash
# Suite for semantic-check.sh.
#
# THE MODEL IS STUBBED. What this suite can decide is whether the script asks
# the right thing and reads the answer correctly — whether the model's judgment
# is any good is not decidable here, and a suite that called the real one would
# be slow, costly, and would pass or fail for reasons that have nothing to do
# with this file.
#
# So `HQ_SEMANTIC_CMD` is pointed at a stub that answers as told, and every
# branch the script claims is driven: clean, refused, an unreadable answer, a
# command that fails, a diff over the cap, an empty diff, the skip switch. The
# branch that matters most is the one where nothing could be asked — a guard
# that reports a pass when it did not run is the failure this whole file is
# guarding against elsewhere.
#
# The prompt is asserted too: it has to carry the repository's own rule, the
# paths and the added lines. A prompt that lost one of those still gets an
# answer back, and the answer still parses.
#
# Output is TAP. Exit 0 when every check passes.
#
# Run: bash .claude/scripts/semantic-check.test.sh

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/semantic-check.sh"
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

# A repository shaped the way the script expects: it derives its root two
# levels up from itself, and it reads AGENTS.md for the rule.
REPO="$TMP/repo"
mkdir -p "$REPO/.claude/scripts"
cp "$SCRIPT" "$REPO/.claude/scripts/semantic-check.sh"
cat >"$REPO/AGENTS.md" <<'EOF'
# fixture

## Naming hygiene

THE FIXTURE RULE: placeholder identifiers only.

## The next one

not part of the rule.
EOF
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name t
git -C "$REPO" add -A
git -C "$REPO" commit -q -m seed

# The stub: prints whatever STUB_OUT holds, and exits with STUB_CODE. It also
# keeps the prompt it was handed, so the prompt can be asserted.
STUB="$TMP/stub.sh"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
cat >"$STUB_PROMPT"
printf '%s\n' "$STUB_OUT"
exit "${STUB_CODE:-0}"
EOF
chmod +x "$STUB"

run() { # <stub stdout> <stub exit> — prints the script's exit code
  ( cd "$REPO" \
    && STUB_PROMPT="$TMP/prompt" STUB_OUT="$1" STUB_CODE="$2" \
       HQ_SEMANTIC_CMD="$STUB" \
       bash .claude/scripts/semantic-check.sh staged ) >"$TMP/out" 2>"$TMP/err"
  printf '%s' "$?"
}

stage() { # <content>
  printf '%s\n' "$1" >"$REPO/work.txt"
  git -C "$REPO" add work.txt
}

says_err() { /usr/bin/grep -q -- "$1" "$TMP/err" && printf 'yes' || printf 'no'; }
in_prompt() { /usr/bin/grep -q -- "$1" "$TMP/prompt" && printf 'yes' || printf 'no'; }

printf 'TAP version 13\n'

# --- nothing staged ----------------------------------------------------------

check "an empty commit is not asked about" 0 "$(run 'VERDICT: CLEAN' 0)"
check "and the stub was never called" no \
  "$([ -f "$TMP/prompt" ] && printf 'yes' || printf 'no')"

# --- the two verdicts --------------------------------------------------------

stage 'an ordinary line'
check "CLEAN passes" 0 "$(run 'VERDICT: CLEAN' 0)"

check "REFUSE fails" 1 "$(run 'VERDICT: REFUSE
Northwind Traders — a customer name' 0)"
check "and the reason reaches the user" yes \
  "$(/usr/bin/grep -q 'a customer name' "$TMP/out" && printf 'yes' || printf 'no')"

# --- what the model was actually asked ---------------------------------------
#
# Each of these can go missing without the answer changing shape, so the answer
# alone cannot tell you the question was complete.

check "the prompt carries the repository's own rule" yes "$(in_prompt 'THE FIXTURE RULE')"
check "and stops at the next section" no "$(in_prompt 'not part of the rule')"
check "the prompt carries the changed paths" yes "$(in_prompt 'work.txt')"
check "the prompt carries the added lines" yes "$(in_prompt 'an ordinary line')"

# --- every way it can fail to have looked ------------------------------------

check "an unreadable answer is not a pass" 2 "$(run 'I think it looks fine!' 0)"
check "and says nothing was checked" yes "$(says_err 'no readable verdict')"

check "a command that fails is not a pass" 2 "$(run 'VERDICT: CLEAN' 3)"
check "and says the check could not be run" yes "$(says_err 'could not be run')"

check "an empty answer is not a pass" 2 "$(run '' 0)"

# The rule is the standard being applied; with no rule there is nothing to
# apply, and answering anyway would be answering a different question.
mv "$REPO/AGENTS.md" "$REPO/AGENTS.md.away"
check "a missing rule is not a pass" 2 "$(run 'VERDICT: CLEAN' 0)"
check "and says the rule could not be read" yes "$(says_err 'naming rule')"
mv "$REPO/AGENTS.md.away" "$REPO/AGENTS.md"

# --- the cap -----------------------------------------------------------------
#
# Sending part of a diff and reporting on that part is the shape of a check
# that reads as complete and is not.
BIG=""
i=0
while [ "$i" -lt 12 ]; do BIG="$BIG
line $i"; i=$((i + 1)); done
stage "$BIG"
check "a diff over the cap is refused rather than partly read" 2 \
  "$(HQ_SEMANTIC_MAX_LINES=5 run 'VERDICT: CLEAN' 0)"
check "and says it was not read" yes "$(says_err 'NOT read')"
check "under the cap it is asked about" 0 \
  "$(HQ_SEMANTIC_MAX_LINES=500 run 'VERDICT: CLEAN' 0)"

# --- the deliberate way past --------------------------------------------------

check "the skip switch passes without asking" 0 \
  "$(HQ_SKIP_SEMANTIC=1 run 'VERDICT: REFUSE
would have been refused' 0)"
check "and says nothing was read" yes "$(says_err 'nothing read this commit')"

# --- usage --------------------------------------------------------------------

( cd "$REPO" && bash .claude/scripts/semantic-check.sh ) >/dev/null 2>&1
check "no face is a usage error" 2 "$?"

printf '1..%d\n' "$N"
if [ "$FAILED" -eq 0 ]; then
  printf '# all %d checks passed\n' "$N"
else
  printf '# %d of %d checks failed\n' "$FAILED" "$N"
  exit 1
fi
