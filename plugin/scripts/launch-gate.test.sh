#!/usr/bin/env bash
# Tests for launch-gate.sh — the layer-2 gate.
#
# Two properties carry the weight here, and they pull in opposite directions:
# it must deny a launch that is missing or stale (nothing else reads what the
# root pasted), and it must stay silent on everything else (a false deny stops
# all work). Every check ending in "says nothing" guards the second direction.
#
# The payloads are built with python's json.dumps, which escapes non-ASCII as
# \uXXXX by default — a Japanese context file appears in these payloads in a
# form that shares no bytes with the file itself, which is what makes the
# encoding check real rather than assumed.
#
# Run: bash plugin/scripts/launch-gate.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATE="$HERE/launch-gate.sh"
INJECT="$HERE/inject.sh"
LIB="$HERE/lib.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# The home is pinned here rather than inherited: a machine with HQ_HOME
# already set would otherwise decide whether half of this file is exercised.
# Nothing writes there; both faces only print.
export HQ_HOME="$TMP/home"

. "$HERE/testlib.sh"

# --- fixtures --------------------------------------------------------------

mk_repo() { # <dir> [knowledge.md content]
  mkdir -p "$1/.hq"
  git -C "$1" init -q
  [ $# -ge 2 ] && printf '%s\n' "$2" >"$1/.hq/knowledge.md"
  printf '%s' "$1"
}

# A repository with a commit on a branch, so that the run's directory
# derives; `mk_repo` above deliberately stops short of one.
mk_repo_committed() { # <dir> [knowledge.md content]
  mkdir -p "$1/.hq"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name t
  [ $# -ge 2 ] && printf '%s\n' "$2" >"$1/.hq/knowledge.md"
  : >"$1/seed.txt"
  git -C "$1" add -A
  git -C "$1" commit -q -m seed
  printf '%s' "$1"
}

context_for() { # <root> — what the injector prints right now
  "$SH" "$INJECT" "$1" 2>/dev/null
}

# Asked of lib.sh, which is where the gate asks: lib.test.sh owns whether the
# derivation is right, and what is under test here is that the gate requires
# whatever it answers.
task_dir_for() { # <root>
  "$SH" "$LIB" hq_task_dir "$1" 2>/dev/null
}

# A launch payload as the harness would encode one.
payload() { # <subagent_type> <prompt>
  python3 -c '
import json, sys
print(json.dumps({
    "session_id": "s1",
    "hook_event_name": "PreToolUse",
    "tool_name": "Agent",
    "tool_input": {"subagent_type": sys.argv[1], "prompt": sys.argv[2]},
}))' "$1" "$2"
}

# Runs the hook face inside <root>. Output goes to $TMP/hook.out, exit code is
# echoed.
run_hook() { # <root> <payload> [<gate path>]
  local gate="${3:-$GATE}"
  printf '%s' "$2" | ( cd "$1" && "$SH" "$gate" hook ) >"$TMP/hook.out" 2>"$TMP/hook.err"
  printf '%s' "$?"
}

said_nothing() { # yes when the hook produced no stdout
  if [ -s "$TMP/hook.out" ]; then printf 'no'; else printf 'yes'; fi
}

denied() { # yes when the hook emitted a deny decision
  python3 -c '
import json, sys
try:
    o = json.load(open(sys.argv[1]))
except Exception:
    print("no"); raise SystemExit
print("yes" if o.get("hookSpecificOutput", {}).get("permissionDecision") == "deny" else "no")
' "$TMP/hook.out" 2>/dev/null || printf 'no'
}

reason() {
  python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["hookSpecificOutput"]["permissionDecisionReason"])
' "$TMP/hook.out" 2>/dev/null
}

tap_begin

# --- a correct launch passes -----------------------------------------------

R=$(mk_repo "$TMP/plain" "project notes")
CTX=$(context_for "$R")

check "a prompt carrying the current context exits 0" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "review the branch

$CTX

go")")"
check "and says nothing" yes "$(said_nothing)"

# --- the encoding case the digest exists for -------------------------------
#
# json.dumps escapes non-ASCII to \uXXXX, so the Japanese body in this payload
# shares no bytes with the file on disk. A gate comparing body text would deny
# here, on every launch, forever.

R=$(mk_repo "$TMP/japanese" "この repository では日本語で書く —— em dash も入る"
)
CTX=$(context_for "$R")
PAY=$(payload hq:reviewer "prompt

$CTX")

check "the payload really did escape the non-ASCII body" yes \
  "$(printf '%s' "$PAY" | /usr/bin/grep -q '\\u' && printf 'yes' || printf 'no')"
check "the payload does not contain the raw bytes of the file" yes \
  "$(printf '%s' "$PAY" | LC_ALL=C /usr/bin/grep -qE '^[ -~]*$' && printf 'yes' || printf 'no')"
check "a non-ASCII context still passes the gate" 0 "$(run_hook "$R" "$PAY")"
check "and says nothing" yes "$(said_nothing)"

# --- context whose body looks like the frame -------------------------------
#
# A context file is markdown. `--- 注意 ---` is an ordinary thing to write in
# one, and a gate that recovered its required lines by pattern-matching the
# injector's full output would read that body line as a required line — being
# non-ASCII it could never match inside the payload, and the launch would be
# denied for context that was exactly current.

R=$(mk_repo "$TMP/marker-shaped-body" "notes

--- 注意 ---

more notes")
CTX=$(context_for "$R")
check "a body line shaped like a marker does not deny a current context" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "prompt

$CTX")")"
check "and says nothing" yes "$(said_nothing)"

# The same in ASCII, so the property is not read as being about non-ASCII
# alone.
R=$(mk_repo "$TMP/ascii-marker-body" "notes

--- caution ---

more notes")
CTX=$(context_for "$R")
check "an ASCII body line shaped like a marker also passes" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "prompt

$CTX")")"

# Glob metacharacters in the body: the comparison is a quoted case pattern, so
# they are literal. This pins that.
R=$(mk_repo "$TMP/glob-body" 'notes with * and ? and [abc] in them')
CTX=$(context_for "$R")
check "glob metacharacters in the body do not disturb the comparison" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "prompt

$CTX")")"

# --- a missing context is denied -------------------------------------------

R=$(mk_repo "$TMP/missing" "notes")
check "a prompt with no context at all still exits 0" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "review the branch, go")")"
check "but emits a deny decision" yes "$(denied)"
check "naming the injector to run" yes \
  "$(reason | /usr/bin/grep -q 'inject.sh' && printf 'yes' || printf 'no')"

# --- every owned agent is gated, and the reason names the launched one -------
#
# A suite that only ever launches one owned agent cannot tell a list from a
# constant, and a reason text naming one agent inside itself would be false
# for any other launch while still reading as a correct sentence.

R=$(mk_repo "$TMP/implementer" "notes")
CTX=$(context_for "$R")

check "the implementer with a current context exits 0" 0 \
  "$(run_hook "$R" "$(payload hq:implementer "work the plan

$CTX")")"
check "and says nothing" yes "$(said_nothing)"

run_hook "$R" "$(payload hq:implementer "work the plan, go")" >/dev/null
check "the implementer without the context is denied" yes "$(denied)"
check "and the reason names the agent that was launched" yes \
  "$(reason | /usr/bin/grep -q '^hq:implementer:' && printf 'yes' || printf 'no')"

run_hook "$R" "$(payload hq:reviewer "review the branch, go")" >/dev/null
check "a reviewer denial names the reviewer" yes \
  "$(reason | /usr/bin/grep -q '^hq:reviewer:' && printf 'yes' || printf 'no')"

# --- a receipt without the block is denied ----------------------------------
#
# A prompt carrying only the digest line must not pass while the verifier
# gets none of the context: each way a block can arrive incomplete must be
# refused, not waved through on the strength of the part that did arrive.

R=$(mk_repo "$TMP/receipt-only" "notes")
DIGEST_LINE=$(context_for "$R" | tail -n 1)

check "a prompt carrying only the digest line exits 0" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "prompt

$DIGEST_LINE")")"
check "but is denied" yes "$(denied)"

# The opening marker and the digest, with the per-file markers dropped. The
# gate requires every line `inject.sh --markers` prints, so this covers a list
# of any length.
check "a prompt missing the per-file markers is denied" yes \
  "$(run_hook "$R" "$(payload hq:reviewer "prompt

=== hq repository context ===
$DIGEST_LINE")" >/dev/null; denied)"

# The block opened and never closed: the digest is what says which version it
# was, so its absence cannot be a pass.
check "a prompt missing the digest line is denied" yes \
  "$(run_hook "$R" "$(payload hq:reviewer "prompt

$(context_for "$R" | sed '$d')")" >/dev/null; denied)"

# --- a stale context is denied, and told apart ------------------------------
#
# A block was pasted, then a file it covers changed. The prompt still looks
# injected, and the old text must not be reused.

R=$(mk_repo "$TMP/stale" "first version")
CTX=$(context_for "$R")
printf 'second version\n' >"$R/.hq/knowledge.md"

check "a stale context exits 0" 0 "$(run_hook "$R" "$(payload hq:reviewer "prompt

$CTX")")"
check "but emits a deny decision" yes "$(denied)"
check "and says the context is out of date rather than missing" yes \
  "$(reason | /usr/bin/grep -q 'out of date' && printf 'yes' || printf 'no')"
check "telling the reader to paste the whole block rather than patch it" yes \
  "$(reason | /usr/bin/grep -q 'paste the whole block' && printf 'yes' || printf 'no')"

# A file appearing is the same event as a file changing: the injection over a
# fresh repository is a marker over an empty body, and the gate has to move
# when someone writes the file.
R=$(mk_repo "$TMP/appeared")
CTX=$(context_for "$R")
printf 'knowledge now exists\n' >"$R/.hq/knowledge.md"
run_hook "$R" "$(payload hq:reviewer "prompt

$CTX")" >/dev/null
check "a listed file appearing after injection is denied" yes "$(denied)"

# --- the destination the caller is the only party able to pass --------------
#
# The caller's prompt is the only place the destination can come from, and
# nothing downstream can check it: the findings gate exits 0 on a file that
# is not there, because a review that found nothing writes no file. One
# string covers both agents — the reviewer's output directory and the
# implementer's plan's parent — so both are driven below.

R=$(mk_repo_committed "$TMP/destination" "notes")
CTX=$(context_for "$R")
DEST=$(task_dir_for "$R")

# Without this the whole section would pass by never having an expectation.
check "the fixture derives a run directory at all" yes \
  "$([ -n "$DEST" ] && printf 'yes' || printf 'no')"

check "a reviewer launch carrying the context and the output directory exits 0" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "review the branch

Output directory: $DEST

$CTX")")"
check "and says nothing" yes "$(said_nothing)"

run_hook "$R" "$(payload hq:reviewer "review the branch

$CTX")" >/dev/null
check "a current context without the output directory is denied" yes "$(denied)"
check "and the reason carries the path that was missing" yes \
  "$(reason | /usr/bin/grep -qF "$DEST" && printf 'yes' || printf 'no')"
# The context was current, so blaming the injection would send the reader to
# re-paste a block that was already right.
check "and does not report the context as the problem" no \
  "$(reason | /usr/bin/grep -q 'inject.sh' && printf 'yes' || printf 'no')"

# The implementer is handed `<dir>/plan.md`, which contains the directory —
# the same mistake must be caught on the other launch too.
check "an implementer launch carrying only the plan's path exits 0" 0 \
  "$(run_hook "$R" "$(payload hq:implementer "work the plan at $DEST/plan.md

$CTX")")"
check "and says nothing" yes "$(said_nothing)"

run_hook "$R" "$(payload hq:implementer "work the plan, route fresh

$CTX")" >/dev/null
check "an implementer launch with no plan path is denied" yes "$(denied)"

# Both problems in one launch. They are independent, and a caller told about
# one at a time re-launches twice for one mistake.
run_hook "$R" "$(payload hq:reviewer "review the branch, go")" >/dev/null
check "a prompt missing the context and the directory is denied" yes "$(denied)"
check "and the reason carries both problems" yes \
  "$(reason | /usr/bin/grep -q 'inject.sh' \
     && reason | /usr/bin/grep -qF "$DEST" && printf 'yes' || printf 'no')"
check "and it is still one decision object on one line" 1 \
  "$(wc -l <"$TMP/hook.out" | tr -d ' ')"

# --- when the gate cannot hold that expectation, it says nothing ------------
#
# Each of these is a state a person is entitled to be in. The control for all
# of them is the deny above: same shape of prompt, path available, denied.

DET=$(mk_repo_committed "$TMP/detached" "notes")
DET_CTX=$(context_for "$DET")
git -C "$DET" checkout -q --detach
check "a detached HEAD really has no run directory" "" "$(task_dir_for "$DET")"
check "a detached HEAD: exits 0" 0 \
  "$(run_hook "$DET" "$(payload hq:reviewer "prompt

$DET_CTX")")"
check "a detached HEAD: says nothing" yes "$(said_nothing)"

# A gate installed without lib.sh beside it: the subprocess's absence is a
# non-zero exit the gate reads as "no opinion" rather than an abort under the
# fail-open trap.
NOLIB="$TMP/no-lib"
mkdir -p "$NOLIB"
cp "$GATE" "$NOLIB/launch-gate.sh"
cp "$INJECT" "$NOLIB/inject.sh"
check "a gate with no lib.sh beside it: exits 0" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "prompt

$CTX")" "$NOLIB/launch-gate.sh")"
check "a gate with no lib.sh beside it: says nothing" yes "$(said_nothing)"

# A PATH THE PAYLOAD'S ENCODER WOULD REWRITE. json.dumps escapes non-ASCII to
# \uXXXX, so a Japanese branch name cannot be found in the payload however
# carefully the caller pasted it — and `"` has to be escaped by any encoder;
# both are legal in a git ref. Comparing anyway would deny a launch that was
# right.

JP=$(mk_repo_committed "$TMP/nonascii-branch" "notes")
git -C "$JP" checkout -q -b 'feat/日本語'
JP_CTX=$(context_for "$JP")
check "the fixture really derives a non-ASCII path" yes \
  "$(task_dir_for "$JP" | LC_ALL=C /usr/bin/grep -q '[^ -~]' && printf 'yes' || printf 'no')"
check "a non-ASCII run directory: exits 0" 0 \
  "$(run_hook "$JP" "$(payload hq:reviewer "prompt

$JP_CTX")")"
check "a non-ASCII run directory: says nothing" yes "$(said_nothing)"

QT=$(mk_repo_committed "$TMP/quoted-branch" "notes")
git -C "$QT" checkout -q -b 'feat/q"uote'
QT_CTX=$(context_for "$QT")
check "the fixture really derives a path holding a quote" yes \
  "$(task_dir_for "$QT" | /usr/bin/grep -q '"' && printf 'yes' || printf 'no')"
check "a run directory the encoder must escape: exits 0" 0 \
  "$(run_hook "$QT" "$(payload hq:reviewer "prompt

$QT_CTX")")"
check "a run directory the encoder must escape: says nothing" yes "$(said_nothing)"

# --- the two checks do not switch each other off ----------------------------
#
# They are recovered from different scripts, so one being unavailable says
# nothing about the other.

BOTH="$TMP/broken-injector-with-lib"
mkdir -p "$BOTH"
cp "$GATE" "$BOTH/launch-gate.sh"
cp "$LIB" "$BOTH/lib.sh"
printf '#!/usr/bin/env bash\nexit 1\n' >"$BOTH/inject.sh"
run_hook "$R" "$(payload hq:reviewer "review the branch, go")" "$BOTH/launch-gate.sh" >/dev/null
check "a broken injector does not switch the destination check off" yes "$(denied)"
check "and the reason is the destination alone" no \
  "$(reason | /usr/bin/grep -q 'inject.sh' && printf 'yes' || printf 'no')"

# --- the deny object is well formed ----------------------------------------

R=$(mk_repo "$TMP/shape" "notes")
run_hook "$R" "$(payload hq:reviewer "no context here")" >/dev/null
check "the deny output is a single line" 1 "$(wc -l <"$TMP/hook.out" | tr -d ' ')"
check "it names the hook event" PreToolUse \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["hookSpecificOutput"]["hookEventName"])' "$TMP/hook.out" 2>/dev/null)"
check "it never emits allow" yes \
  "$(/usr/bin/grep -q '"permissionDecision":"allow"' "$TMP/hook.out" && printf 'no' || printf 'yes')"
check "the hook writes nothing to stderr" "" "$(cat "$TMP/hook.err")"

# --- everything the gate must stay silent about ----------------------------
#
# Each of these is a distinct way the gate could fail to recognise what it is
# looking at. All of them must reach the same place: exit 0, no output.

R=$(mk_repo "$TMP/silent" "notes")

check "another plugin's agent: exits 0" 0 \
  "$(run_hook "$R" "$(payload some-other:agent "no context here")")"
check "another plugin's agent: says nothing" yes "$(said_nothing)"

check "an agent type that merely contains ours: exits 0" 0 \
  "$(run_hook "$R" "$(payload not-hq:reviewer-either "no context")")"
check "an agent type that merely contains ours: says nothing" yes "$(said_nothing)"

check "a payload with no subagent_type: exits 0" 0 \
  "$(run_hook "$R" '{"hook_event_name":"PreToolUse","tool_name":"Bash"}')"
check "a payload with no subagent_type: says nothing" yes "$(said_nothing)"

check "an unparseable payload: exits 0" 0 "$(run_hook "$R" 'not json at all {{{')"
check "an unparseable payload: says nothing" yes "$(said_nothing)"

check "an empty payload: exits 0" 0 "$(run_hook "$R" '')"
check "an empty payload: says nothing" yes "$(said_nothing)"

# Outside a repository there is no context to compare against.
mkdir -p "$TMP/not-a-repo"
check "outside a git repository: exits 0" 0 \
  "$(run_hook "$TMP/not-a-repo" "$(payload hq:reviewer "no context")")"
check "outside a git repository: says nothing" yes "$(said_nothing)"

# --- fail-open when the gate's own machinery is broken ----------------------
#
# The gate cannot deny on the strength of an expectation it failed to compute.
# A broken injector must read as "no opinion", not as "nothing was injected".

BROKEN="$TMP/broken-injector"
mkdir -p "$BROKEN"
cp "$GATE" "$BROKEN/launch-gate.sh"
printf '#!/usr/bin/env bash\nexit 1\n' >"$BROKEN/inject.sh"
R=$(mk_repo "$TMP/with-broken" "notes")
check "an injector that fails: exits 0" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "no context here")" "$BROKEN/launch-gate.sh")"
check "an injector that fails: says nothing" yes "$(said_nothing)"

MISSING="$TMP/absent-injector"
mkdir -p "$MISSING"
cp "$GATE" "$MISSING/launch-gate.sh"
check "an injector that is not there: exits 0" 0 \
  "$(run_hook "$R" "$(payload hq:reviewer "no context here")" "$MISSING/launch-gate.sh")"
check "an injector that is not there: says nothing" yes "$(said_nothing)"

# --- lint predicts the hook -------------------------------------------------

R=$(mk_repo "$TMP/lint" "notes")
CTX=$(context_for "$R")
printf 'prompt\n\n%s\n' "$CTX" >"$TMP/good-prompt.txt"
printf 'prompt with nothing injected\n' >"$TMP/bare-prompt.txt"

# This fixture has no commit, so it has no branch and the destination cannot
# be derived. The context is current, so the only honest answer is "that half
# is fine, the other was not checked".
( cd "$R" && "$SH" "$GATE" lint "$TMP/good-prompt.txt" >"$TMP/lint-nobranch.out" 2>&1 )
check "a current context in a repo with no branch is not reported as clean" 2 "$?"
check "and the context half is credited" yes \
  "$(/usr/bin/grep -q '^ok so far: .*repository context' "$TMP/lint-nobranch.out" && printf 'yes' || printf 'no')"
( cd "$R" && "$SH" "$GATE" lint "$TMP/bare-prompt.txt" >/dev/null 2>&1 )
check "lint rejects a prompt with no context" 1 "$?"

printf 'changed\n' >"$R/.hq/knowledge.md"
( cd "$R" && "$SH" "$GATE" lint "$TMP/good-prompt.txt" >"$TMP/lint.out" 2>&1 )
check "lint rejects a prompt that has gone stale" 1 "$?"
check "lint names the verdict it reached" yes \
  "$(/usr/bin/grep -q '^stale:' "$TMP/lint.out" && printf 'yes' || printf 'no')"

# lint has to predict the hook on the second requirement too, and it is the
# face a person runs before launching anything.
LR=$(mk_repo_committed "$TMP/lint-destination" "notes")
LR_CTX=$(context_for "$LR")
LR_DEST=$(task_dir_for "$LR")
printf 'prompt\n\n%s\n' "$LR_CTX" >"$TMP/no-dest-prompt.txt"
printf 'prompt\n\nOutput directory: %s\n\n%s\n' "$LR_DEST" "$LR_CTX" >"$TMP/full-prompt.txt"

( cd "$LR" && "$SH" "$GATE" lint "$TMP/full-prompt.txt" >/dev/null 2>&1 )
check "lint accepts a prompt carrying the context and the directory" 0 "$?"
( cd "$LR" && "$SH" "$GATE" lint "$TMP/no-dest-prompt.txt" >"$TMP/lint-dest.out" 2>&1 )
check "lint rejects a prompt with a current context and no directory" 1 "$?"
check "lint names that verdict rather than blaming the context" yes \
  "$(/usr/bin/grep -q '^no-destination:' "$TMP/lint-dest.out" && printf 'yes' || printf 'no')"
check "and prints the path on the same line" yes \
  "$(/usr/bin/grep -qF "$LR_DEST" "$TMP/lint-dest.out" && printf 'yes' || printf 'no')"
check "lint reports one line per problem" 2 \
  "$( ( cd "$LR" && "$SH" "$GATE" lint "$TMP/bare-prompt.txt" 2>&1 ) | wc -l | tr -d ' ')"

# NOT-CHECKED IS NEVER REPORTED AS CLEAN. `lint` is the face a person runs
# before launching, so it is the last place that may confuse an expectation it
# could not form with one it formed and met.

# 1. The destination cannot be derived. Nothing in HOME or HQ_HOME to build it
#    from, so the check never runs — which must not read as `ok`.
( cd "$LR" && env -u HOME -u HQ_HOME "$SH" "$GATE" lint "$TMP/full-prompt.txt" >"$TMP/lint-und.out" 2>&1 )
check "an underivable destination is not reported as clean" 2 "$?"
check "and it says which half went unchecked" yes \
  "$(/usr/bin/grep -q "^unchecked: the run's directory" "$TMP/lint-und.out" && printf 'yes' || printf 'no')"
check "while still crediting the half it did check" yes \
  "$(/usr/bin/grep -q '^ok so far: .*repository context' "$TMP/lint-und.out" && printf 'yes' || printf 'no')"
check "and it never says the bare ok" yes \
  "$(/usr/bin/grep -q '^ok: ' "$TMP/lint-und.out" && printf 'no' || printf 'yes')"

# 2. The injector is broken. lint must still look at the destination — the
#    hook in the same situation reports it, and a failure in one mechanism
#    must not silently switch off an unrelated one.
BROKEN_LINT="$TMP/broken-lint"
mkdir -p "$BROKEN_LINT"
cp "$GATE" "$BROKEN_LINT/launch-gate.sh"
cp "$HERE/lib.sh" "$BROKEN_LINT/lib.sh"
printf '#!/usr/bin/env bash\nexit 1\n' >"$BROKEN_LINT/inject.sh"
( cd "$LR" && "$SH" "$BROKEN_LINT/launch-gate.sh" lint "$TMP/no-dest-prompt.txt" >"$TMP/lint-broken.out" 2>&1 )
check "a broken injector does not switch the destination check off in lint" 1 "$?"
check "and the context it could not form is named" yes \
  "$(/usr/bin/grep -q '^unchecked: the repository context' "$TMP/lint-broken.out" && printf 'yes' || printf 'no')"
check "and the destination problem is still reported" yes \
  "$(/usr/bin/grep -q '^no-destination:' "$TMP/lint-broken.out" && printf 'yes' || printf 'no')"

"$SH" "$GATE" lint >/dev/null 2>&1
check "lint with no argument is a usage error" 2 "$?"
"$SH" "$GATE" lint "$TMP/does-not-exist.txt" >/dev/null 2>&1
check "lint with an unreadable file is a usage error" 2 "$?"
"$SH" "$GATE" >/dev/null 2>&1
check "no mode is a usage error" 2 "$?"

# --- bash 3.2 compatibility ------------------------------------------------
#
# The stakes are higher here: under the fail-open trap an unsupported
# construct's abort is silence — the gate would stop existing.

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

    R=$(mk_repo "$TMP/old-stderr" "notes")
    CTX=$(context_for "$R")
    printf '%s' "$(payload hq:reviewer "prompt

$CTX")" | ( cd "$R" && "$OLD_BASH" "$GATE" hook ) >/dev/null 2>"$TMP/old-err.txt"
    check "launch-gate.sh writes nothing to stderr under bash $OLD_VER" "" \
      "$(cat "$TMP/old-err.txt")"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
