#!/usr/bin/env bash
# Tests for findings-gate.sh — the shape check on a verifier's findings.
#
# Each malformed shape gets its own check, and each one is a way the file
# could reach triage while looking fine — none of them announce themselves
# downstream. The valid cases matter as much: a gate that rejects good
# findings costs the verifier a rewrite for nothing, so the accepting side is
# checked too.
#
# `weight` is required and its three values are an enum, because triage reads
# it as an input to the verdict. The duplicate-id check is here under a second
# heading as well: a later review pass continues the numbering and appends, so
# reusing an id is how two findings end up under one identity.
#
# Run: bash plugin/scripts/findings-gate.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATE="$HERE/findings-gate.sh"
RECORD="$HERE/record.sh"
LIB="$HERE/lib.sh"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"

SH="${HQ_TEST_SH:-bash}"

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# The gate derives the findings path from the home; pointing the home at the
# fixture directory keeps this suite off the real one.
export HQ_HOME="$TMP/home"

. "$HERE/testlib.sh"

F="$TMP/findings.jsonl"

# A row with everything the gate requires, as one line.
GOOD='{"id":"F1","class":"logic","weight":"high","file":"a.sh","line":3,"claim":"c","evidence":"e","consequence":"q"}'

write() { printf '%s\n' "$@" >"$F"; }

# exit code of `check`
code() { "$SH" "$GATE" check "$F" >"$TMP/out" 2>&1; printf '%s' "$?"; }

# whether the reported problems mention <substring>
says() { /usr/bin/grep -q "$1" "$TMP/out" && printf 'yes' || printf 'no'; }

tap_begin

# --- shapes that must be accepted ------------------------------------------

write "$GOOD"
check "a complete row is accepted" 0 "$(code)"

write "$GOOD" '{"id":"F2","class":"drift","weight":"low","file":"b.md","against":"b.sh","claim":"c","evidence":"e","consequence":"q"}'
check "several rows are accepted" 0 "$(code)"

# class is optional by design — a defect outside the declared set is reported
# with no class rather than forced into one (reviewer.md).
write '{"id":"F1","weight":"medium","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}'
check "a row with no class is accepted" 0 "$(code)"

# line is optional: not every finding points at an exact line.
write '{"id":"F1","class":"security","weight":"high","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}'
check "a row with no line is accepted" 0 "$(code)"

# against names the definition a copy is supposed to agree with. It is optional
# because most findings are not one copy disagreeing with another; the verifier
# writes it when they are, and reads it back to tell whether a later pass is on
# a pair it has already reported (reviewer.md).
write '{"id":"F1","class":"drift","weight":"low","file":"a.md","against":"b.sh","claim":"c","evidence":"e","consequence":"q"}'
check "a row carrying against is accepted" 0 "$(code)"

# A drift finding always has a second definition to name, and the later pass
# needs it to tell whether it is on a pair already reported. So this one field
# is required for this one class, and optional everywhere else.
write '{"id":"F1","class":"drift","weight":"low","file":"a.md","claim":"c","evidence":"e","consequence":"q"}'
check "a drift row with no against is rejected" 1 "$(code)"
check "and the message says what is missing" yes "$(says "must carry against")"

write '{"id":"F1","class":"drift","weight":"low","file":"a.md","against":"   ","claim":"c","evidence":"e","consequence":"q"}'
check "a drift row whose against is blank is rejected" 1 "$(code)"

write '{"id":"F1","class":"logic","weight":"low","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}'
check "a row of another class with no against is accepted" 0 "$(code)"

write '{"id":"F1","weight":"low","file":"a.md","claim":"c","evidence":"e","consequence":"q"}'
check "a row with no class at all is still accepted" 0 "$(code)"

: >"$F"
check "an empty file is accepted — it means no findings" 0 "$(code)"

# Non-ASCII text is the normal case for this repository's findings.
write '{"id":"F1","class":"drift","weight":"low","file":"a.sh","against":"b.sh","claim":"主張","evidence":"根拠","consequence":"帰結"}'
check "a row written in Japanese is accepted" 0 "$(code)"

# Every weight the gate names is accepted, read off the gate's own enum
# rather than written here: a spelling added there and not here would
# otherwise go unexercised.
for w in $(/usr/bin/grep -m1 '^WEIGHTS=' "$GATE" | sed 's/^WEIGHTS="//; s/".*//'); do
  write "{\"id\":\"F1\",\"weight\":\"$w\",\"file\":\"a.sh\",\"claim\":\"c\",\"evidence\":\"e\",\"consequence\":\"q\"}"
  check "weight $w, as the gate's enum names it, is accepted" 0 "$(code)"
done

# --- shapes that must be rejected ------------------------------------------

for field in id weight file claim evidence consequence; do
  python3 -c '
import json, sys
row = json.loads(sys.argv[1])
del row[sys.argv[2]]
print(json.dumps(row))' "$GOOD" "$field" >"$F"
  check "a row missing $field is rejected" 1 "$(code)"
  check "and $field is named" yes "$(says "missing $field")"
done

# An empty string passes a presence test but carries nothing. `consequence` is
# the one that matters most: triage decides on consequence, so an empty one
# turns the decision into a guess.
write '{"id":"F1","weight":"high","file":"a.sh","claim":"c","evidence":"e","consequence":""}'
check "an empty consequence is rejected" 1 "$(code)"
check "and is named as empty rather than missing" yes "$(says "consequence is empty")"

write '{"id":"F1","weight":"high","file":"a.sh","claim":"c","evidence":"   ","consequence":"q"}'
check "whitespace-only evidence is rejected" 1 "$(code)"

# A required field that is present but is not text. Checking these through
# str() reads null as the word "None" and a number as its digits, so the row
# looks complete while carrying nothing usable.
write '{"id":"F1","weight":"high","file":"a.sh","claim":"c","evidence":"e","consequence":null}'
check "a null consequence is rejected" 1 "$(code)"
check "and is named as a type error, not as empty" yes "$(says "must be a string")"

write '{"id":1,"weight":"high","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}'
check "a numeric id is rejected" 1 "$(code)"

write '{"id":"F1","weight":"high","file":"a.sh","claim":123,"evidence":"e","consequence":"q"}'
check "a numeric claim is rejected" 1 "$(code)"

write '{"id":"F1","weight":"high","file":"a.sh","claim":"c","evidence":[],"consequence":"q"}'
check "an array evidence is rejected" 1 "$(code)"

write '{"id":"F1","weight":"high","file":{"path":"a.sh"},"claim":"c","evidence":"e","consequence":"q"}'
check "an object file is rejected" 1 "$(code)"

# A weight outside the enum. The row is otherwise complete, so nothing else can
# account for the refusal.
write '{"id":"F1","weight":"critical","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}'
check "an unknown weight is rejected" 1 "$(code)"
check "and the accepted weights are listed" yes "$(says "unknown weight critical (one of:")"

# Case matters: the enum is three lowercase spellings, and a row that only
# differs in case would otherwise reach triage as a weight nothing matches.
write '{"id":"F1","weight":"High","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}'
check "a weight differing only in case is rejected" 1 "$(code)"

# A null weight is a type error, reported once, in the vocabulary the other
# required fields use — not twice, and not as an unknown value.
write '{"id":"F1","weight":null,"file":"a.sh","claim":"c","evidence":"e","consequence":"q"}'
check "a null weight is rejected" 1 "$(code)"
check "and is named as a type error rather than an unknown value" yes \
  "$(says "weight must be a string")"
check "and is not also reported as an unknown weight" no \
  "$(says "unknown weight")"

# Two rows sharing a numeric id: a duplicate check that skipped non-strings
# would let their dispositions collide in the telemetry.
write '{"id":1,"weight":"high","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}' \
      '{"id":1,"weight":"high","file":"b.sh","claim":"c","evidence":"e","consequence":"q"}'
check "duplicate numeric ids are rejected" 1 "$(code)"

write '{"id":"F1","class":"performance","weight":"high","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}'
check "an unknown class is rejected" 1 "$(code)"
check "and the accepted classes are listed" yes "$(says "one of:")"

# `severity` is not a key here: the weight is a field of its own with three
# values, and a row carrying both would leave triage two answers to one
# question.
write '{"id":"F1","weight":"high","file":"a.sh","claim":"c","evidence":"e","consequence":"q","severity":"high"}'
check "an unknown key is rejected" 1 "$(code)"
check "and the key is named" yes "$(says "unknown key severity")"

write "$GOOD" '{"id":"F1","weight":"low","file":"b.sh","claim":"c","evidence":"e","consequence":"q"}'
check "a duplicate id is rejected" 1 "$(code)"
check "and both lines are named" yes "$(says "already used on line 1")"

# THE DUPLICATE CHECK IS WHAT MAKES AN ID NAME ONE DEFECT ACROSS REVIEW
# PASSES: reusing an id already in the file puts two findings under a single
# identity, and every disposition recorded against it afterwards answers both.
write "$GOOD" \
      '{"id":"F2","weight":"low","file":"b.sh","claim":"c","evidence":"e","consequence":"q"}' \
      '{"id":"F1","weight":"high","file":"c.sh","claim":"the second pass restarted the numbering","evidence":"e","consequence":"q"}'
check "a later pass reusing an earlier id is rejected" 1 "$(code)"
check "and the appended row is the one named" yes "$(says "line 3: id F1 already used on line 1")"

# The other direction: a gate that refused appended rows outright would pass
# the check above.
write "$GOOD" \
      '{"id":"F2","weight":"low","file":"b.sh","claim":"c","evidence":"e","consequence":"q"}' \
      '{"id":"F3","weight":"medium","file":"c.sh","claim":"c","evidence":"e","consequence":"q"}'
check "a later pass continuing the numbering is accepted" 0 "$(code)"

# A truncated write: the row reads as a fragment, and without a parser it would
# pass a grep for the keys it does contain.
write '{"id":"F1","weight":"high","file":"a.sh","claim":"c","evidence":"e","conseq'
check "a truncated line is rejected" 1 "$(code)"
check "and is reported as invalid JSON" yes "$(says "not valid JSON")"

# A JSON array on one line is valid JSON and the wrong shape.
write '[{"id":"F1","weight":"high","file":"a.sh","claim":"c","evidence":"e","consequence":"q"}]'
check "an array instead of an object is rejected" 1 "$(code)"

# The whole file as one pretty-printed object — the shape a model produces when
# it forgets the format is line-oriented.
printf '{\n  "id": "F1",\n  "file": "a.sh"\n}\n' >"$F"
check "a pretty-printed object spanning lines is rejected" 1 "$(code)"

write "$GOOD" '' "$GOOD"
check "a blank line between rows is rejected" 1 "$(code)"

# --- the class list is not a second copy -----------------------------------
#
# The gate reads record.sh's enum: with its own list, a class added to the
# telemetry would be rejected here while accepted there.

for c in $(/usr/bin/grep -m1 '^CLASSES=' "$RECORD" | sed 's/^CLASSES="//; s/".*//'); do
  write "{\"id\":\"F1\",\"class\":\"$c\",\"weight\":\"high\",\"file\":\"a.sh\",\"against\":\"b.sh\",\"claim\":\"c\",\"evidence\":\"e\",\"consequence\":\"q\"}"
  check "class $c, as recorded by record.sh, is accepted here" 0 "$(code)"
done

# --- the hook face ---------------------------------------------------------

payload() { # <file_path>
  python3 -c '
import json, sys
print(json.dumps({
    "hook_event_name": "PostToolUse",
    "tool_name": "Write",
    "tool_input": {"file_path": sys.argv[1], "content": "..."},
}))' "$1"
}

bash_payload() { # <command string>
  python3 -c '
import json, sys
print(json.dumps({
    "hook_event_name": "PostToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[1]},
}))' "$1"
}

run_hook() { # <payload>
  printf '%s' "$1" | "$SH" "$GATE" hook >"$TMP/hook.out" 2>"$TMP/hook.err"
  printf '%s' "$?"
}

write "$GOOD"
check "the hook exits 0 on a well-formed file" 0 "$(run_hook "$(payload "$F")")"
check "and says nothing" "" "$(cat "$TMP/hook.out")"

write '{"id":"F1","weight":"high","file":"a.sh","claim":"c","evidence":"e"}'
check "the hook exits 0 on a malformed file too" 0 "$(run_hook "$(payload "$F")")"
check "but emits a block decision" block \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["decision"])' "$TMP/hook.out" 2>/dev/null)"
check "the block reason names the problem" yes \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["reason"])' "$TMP/hook.out" 2>/dev/null \
    | /usr/bin/grep -q "missing consequence" && printf 'yes' || printf 'no')"
check "the block output is a single line" 1 "$(wc -l <"$TMP/hook.out" | tr -d ' ')"
check "the hook writes nothing to stderr" "" "$(cat "$TMP/hook.err")"

# --- the file written through Bash rather than Write ------------------------
#
# The verifier holds Bash as well as Write, so `cat > findings.jsonl <<EOF`
# is an ordinary thing for it to do, and a gate watching only Write would be
# bypassed without anyone choosing to. The command string is not parsed for a
# path; the gate asks lib.sh where this branch's run files live.

BR="$TMP/repo"
mkdir -p "$BR"
git -C "$BR" init -q
git -C "$BR" config user.email t@example.com
git -C "$BR" config user.name t
echo seed >"$BR/seed.txt"
git -C "$BR" add -A
git -C "$BR" commit -q -m seed
git -C "$BR" checkout -q -b feat/thing
BRANCH_DIR=$("$SH" "$LIB" hq_task_dir "$BR" 2>/dev/null)
check "the fixture's task directory was derived at all" yes \
  "$([ -n "$BRANCH_DIR" ] && printf 'yes' || printf 'no')"
mkdir -p "$BRANCH_DIR"
FINDINGS="$BRANCH_DIR/findings.jsonl"

run_hook_in() { # <dir> <payload>
  printf '%s' "$2" | ( cd "$1" && "$SH" "$GATE" hook ) >"$TMP/hook.out" 2>"$TMP/hook.err"
  printf '%s' "$?"
}

printf '%s\n' "$GOOD" >"$FINDINGS"
check "a Bash write of a well-formed file exits 0" 0 \
  "$(run_hook_in "$BR" "$(bash_payload "cat > $FINDINGS <<'EOF'
...
EOF")")"
check "and says nothing" "" "$(cat "$TMP/hook.out")"

printf '%s\n' '{"id":"F1","weight":"high","file":"a.sh","claim":"c","evidence":"e"}' >"$FINDINGS"
check "a Bash write of a malformed file exits 0" 0 \
  "$(run_hook_in "$BR" "$(bash_payload "cat > $FINDINGS <<'EOF'
...
EOF")")"
check "but emits a block decision" block \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["decision"])' "$TMP/hook.out" 2>/dev/null)"

# A redirection written some other way must reach the same place: the trigger
# is the file being named at all, not the shape of the command.
check "a redirection rather than a heredoc is also checked" block \
  "$(run_hook_in "$BR" "$(bash_payload "printf \"%s\" \"\$row\" >> $FINDINGS")" >/dev/null
     python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["decision"])' "$TMP/hook.out" 2>/dev/null)"

# A detached HEAD owns no run, so there is nothing for the gate to look at and
# nothing to say — asked with the malformed file still on disk, so silence can
# only come from the gate walking away.
git -C "$BR" checkout -q --detach
check "a detached HEAD: exits 0" 0 \
  "$(run_hook_in "$BR" "$(bash_payload "cat > $FINDINGS <<'EOF'
...
EOF")")"
check "a detached HEAD: says nothing" "" "$(cat "$TMP/hook.out")"
git -C "$BR" checkout -q feat/thing

# A Bash command that has nothing to do with the file leaves the gate silent,
# even while a malformed findings.jsonl sits on disk: this hook sees every
# Bash call in the session.
check "an unrelated Bash command: exits 0" 0 \
  "$(run_hook_in "$BR" "$(bash_payload 'ls -la')")"
check "an unrelated Bash command: says nothing" "" "$(cat "$TMP/hook.out")"

# Everything else the hook must ignore. A PostToolUse hook sees every write in
# the session; speaking about any of them would be noise at best.
OTHER="$TMP/notes.md"
printf 'not findings\n' >"$OTHER"
check "a write to another file: exits 0" 0 "$(run_hook "$(payload "$OTHER")")"
check "a write to another file: says nothing" "" "$(cat "$TMP/hook.out")"

check "a payload with no file_path: exits 0" 0 "$(run_hook '{"hook_event_name":"PostToolUse"}')"
check "a payload with no file_path: says nothing" "" "$(cat "$TMP/hook.out")"

check "an unparseable payload: exits 0" 0 "$(run_hook 'not json {{{')"
check "an unparseable payload: says nothing" "" "$(cat "$TMP/hook.out")"

check "an empty payload: exits 0" 0 "$(run_hook '')"

check "a findings.jsonl that no longer exists: exits 0" 0 \
  "$(run_hook "$(payload "$TMP/gone/findings.jsonl")")"
check "a findings.jsonl that no longer exists: says nothing" "" "$(cat "$TMP/hook.out")"

# --- when the gate cannot check at all --------------------------------------
#
# Both faces have to say so. The hook is the one that matters: it sits on the
# path a verifier's write actually takes, and staying quiet there would leave a
# findings.jsonl nobody validated — indistinguishable from one validated and
# found clean.
#
# HQ_PYTHON is what makes this reachable. PATH surgery is not usable on this
# machine — the interactive shell substitutes functions for several standard
# commands, so a stripped PATH built from `command -v` comes out broken rather
# than minimal.

write "$GOOD"
check "the hook exits 0 when the parser is missing" 0 \
  "$(printf '%s' "$(payload "$F")" | HQ_PYTHON=no-such-interpreter "$SH" "$GATE" hook \
     >"$TMP/hook.out" 2>"$TMP/hook.err"; printf '%s' "$?")"
check "but blocks rather than passing silently" block \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["decision"])' "$TMP/hook.out" 2>/dev/null)"
check "and says the file was not checked" yes \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["reason"])' "$TMP/hook.out" 2>/dev/null \
    | /usr/bin/grep -q 'NOT checked' && printf 'yes' || printf 'no')"
check "naming what it looked for" yes \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["reason"])' "$TMP/hook.out" 2>/dev/null \
    | /usr/bin/grep -q 'no-such-interpreter' && printf 'yes' || printf 'no')"
check "and telling the reader what to verify by hand" yes \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["reason"])' "$TMP/hook.out" 2>/dev/null \
    | /usr/bin/grep -q 'consequence' && printf 'yes' || printf 'no')"

HQ_PYTHON=no-such-interpreter "$SH" "$GATE" check "$F" >/dev/null 2>&1
check "check reports a missing parser as an error, not a pass" 2 "$?"

# The class list comes from record.sh. A copy of the gate with no record.sh
# beside it cannot validate anything either, and must say so for the same
# reason.
ORPHAN="$TMP/orphan"
mkdir -p "$ORPHAN"
cp "$GATE" "$ORPHAN/findings-gate.sh"
printf '%s' "$(payload "$F")" | "$SH" "$ORPHAN/findings-gate.sh" hook >"$TMP/hook.out" 2>&1
check "a gate that cannot read the class list blocks too" block \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["decision"])' "$TMP/hook.out" 2>/dev/null)"
check "and names that as the reason" yes \
  "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["reason"])' "$TMP/hook.out" 2>/dev/null \
    | /usr/bin/grep -q 'class list' && printf 'yes' || printf 'no')"

# --- usage -----------------------------------------------------------------

"$SH" "$GATE" check >/dev/null 2>&1
check "check with no file is a usage error" 2 "$?"
"$SH" "$GATE" check "$TMP/does-not-exist" >/dev/null 2>&1
check "check on a missing file is a usage error" 2 "$?"
"$SH" "$GATE" >/dev/null 2>&1
check "no mode is a usage error" 2 "$?"

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

    write "$GOOD"
    "$OLD_BASH" "$GATE" check "$F" >/dev/null 2>"$TMP/err.txt"
    printf '%s' "$(payload "$F")" | "$OLD_BASH" "$GATE" hook >/dev/null 2>>"$TMP/err.txt"
    check "findings-gate.sh writes nothing to stderr under bash $OLD_VER" "" "$(cat "$TMP/err.txt")"
  else
    ok "SKIP no bash older than 4 on this machine — replay unverified"
    ok "SKIP no bash older than 4 on this machine — stderr check unverified"
  fi
fi

tap_end
