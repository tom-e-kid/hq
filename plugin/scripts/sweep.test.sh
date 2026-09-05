#!/usr/bin/env bash
# Checks that span the whole plugin tree rather than any one script.
#
# In a suite of their own, not in the runner: the runner is itself driven over
# throwaway fixture directories by test.test.sh, and a check that reads
# agents/ would fail in every such fixture.
#
# Every check here has a positive control beside it: a list-comparing check
# goes quietly useless when the extraction breaks — both sides come back empty
# and agree. The count of checks is deliberately not stated: a number in a
# comment has nothing to compare itself against.
#
# Run: bash plugin/scripts/sweep.test.sh
# TAP output; exit 0 when every check passes, 1 otherwise.

set -u
LC_ALL=C
export LC_ALL

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

TMP=$(mktemp -d) || { echo "Bail out! mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# This suite RUNS every code block and context line the module definitions
# carry; without a home of its own it would grow directories in the
# developer's real ~/.hq.
export HQ_HOME="$TMP/home"

. "$HERE/testlib.sh"

tap_begin

# --- every script has a test beside it -------------------------------------
#
# The runner holds itself to the same rule; its own suite sitting in the glob
# is harmless — test.test.sh drives the runner over fixtures, never here.

missing_tests() { # <dir> — space-separated names of scripts with no adjacent test
  local dir=$1 f base out
  out=""
  for f in "$dir"/*.sh; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    case "$base" in
      *.test.sh) continue ;;
    esac
    [ -f "$dir/${base%.sh}.test.sh" ] || out="$out $base"
  done
  printf '%s' "${out# }"
}

check "every script has a test file beside it" "" "$(missing_tests "$HERE")"

# Positive control: a directory holding one covered and one uncovered script
# must come back naming exactly the uncovered one.
mkdir -p "$TMP/probe"
: >"$TMP/probe/covered.sh"
: >"$TMP/probe/covered.test.sh"
: >"$TMP/probe/uncovered.sh"
check "the missing-test check names an uncovered script" \
  "uncovered.sh" "$(missing_tests "$TMP/probe")"

# --- bash 4.0+ construct sweep ---------------------------------------------
#
# macOS ships bash 3.2 as /bin/bash while the PATH bash is usually 5.x, so a
# 4.0+ construct passes on the development machine and breaks on a stock one —
# silently: in a script file it writes to stderr and carries on with a wrong
# value. Replaying a suite under the old bash only covers the paths the tests
# reach; this reads the source itself.
#
# Comment-only lines are skipped, and so is any line carrying the marker
# `compat-allow` — without it the pattern below would match its own source.
#
# Each word-form pattern is bounded by a non-word character or line edge on
# both sides — narrower bounds missed a line-leading `mapfile` and `wait -n;`.

B='(^|[^a-zA-Z0-9_])' ; E='([^a-zA-Z0-9_-]|$)'
SWEEP_RE="${B}declare[[:space:]]+-[a-zA-Z]*[Ag]|${B}(mapfile|readarray)${E}|${B}(local|declare|typeset)[[:space:]]+-n${E}|${B}wait[[:space:]]+-n${E}|\\\$\\{[^}]*(\\^\\^|,,)[^}]*\\}|;;&|&>>|shopt[[:space:]]+-s[[:space:]]+globstar|\\\$\\{[A-Za-z_][A-Za-z0-9_]*\\[-" # compat-allow

# Positive control for the pattern above: every construct the list covers
# appears here, and the sweep must flag all of them.
FIXTURE="$TMP/compat-fixture.txt"
# Each line carries the marker so the sweep over *.sh skips this heredoc; a
# trailing comment does not affect what the pattern matches.
cat >"$FIXTURE" <<'EOF'
declare -A assoc # compat-allow
declare -g global=1 # compat-allow
mapfile -t arr <<< x # compat-allow
readarray -t arr <<< x # compat-allow
local -n ref=target # compat-allow
wait -n # compat-allow
upper=${name^^} # compat-allow
lower=${name,,} # compat-allow
case a in a) :;;& *) :;; esac # compat-allow
echo x &>> /dev/null # compat-allow
shopt -s globstar # compat-allow
echo ${arr[-1]} # compat-allow
EOF
FIX_TOTAL=$(wc -l <"$FIXTURE" | tr -d ' ')
FIX_HIT=$(/usr/bin/grep -cE "$SWEEP_RE" "$FIXTURE")
if [ "$FIX_TOTAL" = "$FIX_HIT" ]; then
  ok "the sweep pattern matches every construct it claims to cover ($FIX_HIT)"
else
  not_ok "the sweep pattern matches every construct it claims to cover" \
    "missed: $(/usr/bin/grep -vE "$SWEEP_RE" "$FIXTURE" | tr '\n' '; ')"
fi

# No counterpart to the suite counter above is needed here: this glob always
# matches at least this file.
SWEEP_HITS=""
for f in "$HERE"/*.sh; do
  [ -e "$f" ] || continue
  hits=$(/usr/bin/grep -nE "$SWEEP_RE" "$f" 2>/dev/null \
    | /usr/bin/grep -v 'compat-allow' \
    | /usr/bin/grep -v '^[0-9][0-9]*:[[:space:]]*#')
  [ -n "$hits" ] && SWEEP_HITS="$SWEEP_HITS$(basename "$f"): $hits
"
done
check "no bash 4.0+ construct in plugin/scripts/*.sh" "" "$SWEEP_HITS"

# --- one definition of the shared vocabularies ------------------------------
#
# The class list is written in two places by design — the recorder enforces
# it, the verifier's definition tells the agent which spellings to use — and
# they have to be the same list.

PLUGIN=$(cd "$HERE/.." && pwd)
RECORD="$HERE/record.sh"
REVIEWER="$PLUGIN/agents/reviewer.md"

script_values() { # <variable name> — the enum record.sh enforces
  /usr/bin/grep -m1 "^$1=" "$RECORD" | sed 's/^[A-Z]*="//; s/".*//' | tr ' ' '\n' | sort -u | tr '\n' ' '
}
reviewer_classes() { # the table under the verifier's class heading, and only it
  sed -n '/^## The six declared classes/,/^## /p' "$REVIEWER" \
    | /usr/bin/grep -o '^| `[a-z-]*`' | tr -d '|` ' | sort -u | tr '\n' ' '
}

RECORD_CLASSES=$(script_values CLASSES)
# Without this, an extraction that broke everywhere at once would compare empty
# against empty and pass — the failure mode these three checks exist to catch.
check "the class vocabulary was extracted at all" yes \
  "$([ -n "$RECORD_CLASSES" ] && echo yes || echo no)"
check "the verifier's definition and record.sh agree on the class vocabulary" \
  "$RECORD_CLASSES" "$(reviewer_classes)"

# --- the findings contract has one definition -------------------------------
#
# The verifier's definition tells the agent which fields to write; the gate
# decides which ones a row must carry. Two statements of one contract, held to
# agreement here.

GATE="$HERE/findings-gate.sh"

md_fields() { # <yes|no> — field names marked that way in the verifier's table
  sed -n '/^| field | required/,/^$/p' "$REVIEWER" \
    | /usr/bin/grep "| $1 |" | /usr/bin/grep -o '^| `[a-z]*`' | tr -d '|` ' | sort | tr '\n' ' '
}
sh_fields() { # <variable name> — the list the gate enforces
  /usr/bin/grep -m1 "^$1=" "$GATE" | sed 's/^[A-Z]*="//; s/".*//' | tr ' ' '\n' | sort | tr '\n' ' '
}

REQUIRED_FIELDS=$(sh_fields REQUIRED)
check "the required-field list was extracted at all" yes \
  "$([ -n "$REQUIRED_FIELDS" ] && echo yes || echo no)"
check "the verifier's table and the gate agree on the required fields" \
  "$REQUIRED_FIELDS" "$(md_fields yes)"
check "the verifier's table and the gate agree on the optional fields" \
  "$(sh_fields OPTIONAL)" "$(md_fields no)"

# The weight vocabulary is the same shape. The gate is the enforcing side, so
# it is the source; this compares the definition's table against it.

reviewer_weights() { # the table under the verifier's weight heading, and only it
  sed -n '/^## The three weights/,/^## /p' "$REVIEWER" \
    | /usr/bin/grep -o '^| `[a-z]*`' | tr -d '|` ' | sort | tr '\n' ' '
}

WEIGHT_VALUES=$(sh_fields WEIGHTS)
check "the weight vocabulary was extracted at all" yes \
  "$([ -n "$WEIGHT_VALUES" ] && echo yes || echo no)"
check "the verifier's definition and findings-gate.sh agree on the weight vocabulary" \
  "$WEIGHT_VALUES" "$(reviewer_weights)"

# --- every registered hook command actually runs -----------------------------
#
# A hook is registered as a command string that executes the script directly —
# the one path no unit test goes down, since each gate's suite calls `bash
# gate.sh hook`, which works whatever the file's mode is. A missing executable
# bit exits 126 on every event while every suite stays green.
#
# Each registered command runs the way the harness would run it, with an empty
# payload: every gate here is fail-open, so exit 0 with no output is the
# correct outcome — and a permission error, a moved script or a syntax error
# all fail it.

ROOT=$(cd "$PLUGIN/.." && pwd)
HOOKS="$PLUGIN/hooks/hooks.json"

# The value is a JSON string containing escaped quotes, so it is read to the
# end of the line — a `[^"]*` capture stops at the first `\"` and yields a
# prefix.
hook_commands() { # <file>
  sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$1" \
    | sed 's/\\"/"/g'
}

# Runs one registered command as the harness would. Prints nothing when it is
# fine; prints why when it is not.
try_hook_command() { # <command string>
  local cmd out code
  cmd=$(printf '%s' "$1" | sed "s|\${CLAUDE_PLUGIN_ROOT}|$ROOT|g")
  out=$(eval "$cmd" </dev/null 2>&1)
  code=$?
  if [ "$code" -ne 0 ]; then
    printf 'exit %s: %s (%s)\n' "$code" "$cmd" "$out"
  elif [ -n "$out" ]; then
    printf 'spoke on an empty payload: %s (%s)\n' "$cmd" "$out"
  fi
}

HOOK_CMDS=$(hook_commands "$HOOKS")
HOOK_N=$(printf '%s\n' "$HOOK_CMDS" | /usr/bin/grep -c 'plugin' || true)
check "the registered hook commands were extracted at all" yes \
  "$([ "$HOOK_N" -ge 1 ] && echo yes || echo "no ($HOOK_N)")"

HOOK_BAD=""
while IFS= read -r c; do
  [ -n "$c" ] || continue
  HOOK_BAD="$HOOK_BAD$(try_hook_command "$c")"
done <<EOF
$HOOK_CMDS
EOF
check "every command hooks.json registers runs as registered" "" "$HOOK_BAD"

# Positive control: a registered command pointing at a script without the
# executable bit must come back named.
printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/not-executable.sh"
chmod 644 "$TMP/not-executable.sh"
check "a registered command that cannot execute is reported" yes \
  "$([ -n "$(try_hook_command "\"$TMP\"/not-executable.sh hook")" ] && echo yes || echo no)"

# --- every command a module definition prints actually runs ------------------
#
# The fenced bash blocks are copied out and executed, and the `!` lines are
# executed by the harness with their output pasted in; without this section a
# definition can point at a moved script, a renamed function or a dropped
# executable bit while the whole suite stays green.
#
# TWO OUTCOMES, not one — a placeholder that runs silently produces a wrong
# value, so a block is judged against what its own text asks for:
#
#   no placeholder -> it runs, exit 0
#   a placeholder  -> it fails, exit non-zero
#
# The `!` lines are judged on their exit code alone; emptiness is NOT a
# failure (the review module's target line correctly returns nothing when the
# branch has no changes). A moved script fails a placeholder block the same
# way the placeholder does, so the path check below asks the question no exit
# code can blur: does every plugin path a definition names exist.
#
# WHAT THIS STILL DOES NOT REACH:
#
#   a `!` line whose command name is wrong     -> NOT caught: a context line
#     ending in `|| echo "(unresolved)"` exits 0 whatever happens to its left
#   a command that produces a wrong value      -> NOT caught: THIS ASKS
#     WHETHER A COMMAND RUNS AS ITS OWN TEXT ASKS, NOT WHETHER WHAT IT
#     PRODUCES IS RIGHT
#
# Side effects are contained by substituting the environment: the recorder
# takes HQ_SINK, and the only destructive block carries a placeholder and
# fails before doing anything. A block that hangs would hang this suite —
# there is no portable timeout here, and none of the blocks present can
# block.

CMDS_DIR="$PLUGIN/commands"
CMD_SINK="$TMP/command-sweep-sink.jsonl"

# Each fenced bash block of one file, written out as NNN.sh in <dir>; the
# printed count is how the caller learns how many there were. A fence may be
# indented — inside a list item, markdown asks for it — and bash ignores
# leading whitespace, so the body is copied as it stands.
extract_blocks() { # <file> <dir>
  awk -v dir="$2" '
    /^[[:space:]]*```bash[[:space:]]*$/ { inblk = 1; n++; f = sprintf("%s/%03d.sh", dir, n); next }
    inblk && /^[[:space:]]*```[[:space:]]*$/ { inblk = 0; close(f); next }
    inblk { print > f }
    END { print n + 0 }
  ' "$1"
}

# The same count taken a second way, by a pattern that shares no anchor with
# the one above. The two have to agree.
#
# What this guards is the extractor going quiet: an extractor that stopped
# matching one file would drop that file's blocks and still leave a
# population well above any floor.
crude_block_count() { # <file>
  /usr/bin/grep -c '```bash' "$1" || true
}

# The `!` lines: a context bullet whose value is a command in backticks, read
# to the last backtick on the line — a `[^`]*` capture would stop inside a
# command that quotes.
context_lines() { # <file>
  sed -n 's/^-[[:space:]].*:[[:space:]]*!`\(.*\)`[[:space:]]*$/\1/p' "$1"
}

carries_placeholder() { # <file>
  /usr/bin/grep -qE '<[A-Za-z][^>]*>' "$1"
}

# Runs every block and every context line of every .md in <dir>, and prints one
# line per outcome that disagrees with what the text asks for.
command_problems() { # <dir>
  local f blkdir n i b code line out
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    blkdir="$TMP/blocks-$(basename "$f" .md)"
    rm -rf "$blkdir"; mkdir -p "$blkdir"
    n=$(extract_blocks "$f" "$blkdir")
    i=1
    while [ "$i" -le "$n" ]; do
      b=$(printf '%s/%03d.sh' "$blkdir" "$i")
      ( cd "$ROOT" && CLAUDE_PLUGIN_ROOT="$ROOT" HQ_SINK="$CMD_SINK" bash "$b" ) \
        </dev/null >/dev/null 2>&1
      code=$?
      if carries_placeholder "$b"; then
        [ "$code" -eq 0 ] && printf '%s block %s: carries a placeholder and still ran (exit 0) — it has to fail until the placeholder is replaced\n' \
          "$(basename "$f")" "$i"
      else
        [ "$code" -ne 0 ] && printf '%s block %s: exit %s\n' "$(basename "$f")" "$i" "$code"
      fi
      i=$((i + 1))
    done
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      out=$( ( cd "$ROOT" && CLAUDE_PLUGIN_ROOT="$ROOT" HQ_SINK="$CMD_SINK" \
               bash -c "$line" ) </dev/null 2>&1 )
      code=$?
      [ "$code" -ne 0 ] && printf '%s context line: exit %s: %s (%s)\n' \
        "$(basename "$f")" "$code" "$line" "$out"
    done <<EOF
$(context_lines "$f")
EOF
  done
  return 0
}

# How many of each there are, so that an empty population cannot pass as a
# clean one — the glob spans a directory that had one file in it a week ago.
command_population() { # <dir>
  local f total=0 blkdir
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    blkdir="$TMP/count-$(basename "$f" .md)"
    rm -rf "$blkdir"; mkdir -p "$blkdir"
    total=$((total + $(extract_blocks "$f" "$blkdir") + $(context_lines "$f" | /usr/bin/grep -c . || true)))
  done
  printf '%s' "$total"
}

# Two independent counts of the same fact, per file. A disagreement means the
# extractor is no longer seeing what is there.
extraction_disagreements() { # <dir>
  local f blkdir n crude
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    blkdir="$TMP/xcount-$(basename "$f" .md)"
    rm -rf "$blkdir"; mkdir -p "$blkdir"
    n=$(extract_blocks "$f" "$blkdir")
    crude=$(crude_block_count "$f")
    [ "$n" = "$crude" ] || printf '%s: extracted %s block(s), the file opens %s\n' \
      "$(basename "$f")" "$n" "$crude"
  done
  return 0
}

CMD_POP=$(command_population "$CMDS_DIR")
check "the module definitions' commands were found at all" yes \
  "$([ "$CMD_POP" -ge 2 ] && echo yes || echo "no ($CMD_POP)")"
check "the block extraction sees every block the files open" "" \
  "$(extraction_disagreements "$CMDS_DIR")"

# --- every plugin path a module definition names exists ----------------------
#
# Asked separately from running the blocks, because an exit code cannot
# answer it. This also covers the paths a definition names in prose, which no
# block would ever run.

named_plugin_paths() { # <dir>
  /usr/bin/grep -oh 'plugin/[A-Za-z0-9._/-]*[A-Za-z0-9]' "$1"/*.md 2>/dev/null | sort -u
}

missing_named_paths() { # <dir>
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -e "$ROOT/$p" ] || printf 'names %s, which does not exist\n' "$p"
  done <<EOF
$(named_plugin_paths "$1")
EOF
  return 0
}

NAMED_N=$(named_plugin_paths "$CMDS_DIR" | /usr/bin/grep -c . || true)
check "the paths the definitions name were extracted at all" yes \
  "$([ "$NAMED_N" -ge 1 ] && echo yes || echo "no ($NAMED_N)")"
check "every plugin path a module definition names exists" "" \
  "$(missing_named_paths "$CMDS_DIR")"
# --- no runnable block names a destructive command ---------------------------
#
# THIS SECTION RUNS BEFORE THE ONE THAT EXECUTES, AND THE ORDER IS THE WHOLE
# GUARANTEE: placed after the executor, this check would be a report on damage
# already done — `gh pr create` opens a real pull request, `git push` reaches
# the remote, `rm -r` deletes, and none of it is undone by the next run.
#
# The order is pinned by DESTRUCTIVE_GUARD_RAN, asserted immediately before
# the executor: moving this section back below it leaves the variable unset
# and turns that check red. A comment asking for the order would not.
#
# THE DEFINITIONS THAT NEED THOSE COMMANDS PRINT THEM OUTSIDE A `bash` FENCE
# AND OUTSIDE A CONTEXT LINE, and that is the rule this check enforces rather
# than a note asking for it: a reader copies them out of a plain fence, and
# the runner below never opens one.
#
# TWO LISTS, POINTING OPPOSITE WAYS, BECAUSE ONE OF THEM CANNOT BE COMPLETE.
# A denylist of dangerous commands is unbounded — commands past its edge run
# with the suite green. The set of commands a definition is ALLOWED to have
# this suite execute is small, closed, and countable, so the load-bearing list
# is the allowlist below, and anything else is reported without having to be
# foreseen. `gh` is not on it, which is what makes every `gh` subcommand a
# violation without naming one of them.
#
# THE DENYLIST DOES NOT GO AWAY, because two of the allowed programs can still
# leave the tree: `git push` reaches a remote, `rm -r` deletes. It covers only
# subcommands of programs on the allowlist, which IS a bounded surface.
#
# `git checkout -b` and `git add` are on neither footing — local, reversible,
# and ordinary things for a definition to print — so they are not denied.

# Programs, plus the shell builtins that cannot leave this tree. A builtin is
# listed rather than skipped so that adding one is a decision someone takes.
EXECUTABLE_HEADS="bash cat date echo exit git mkdir printf [ test true false :"

DESTRUCTIVE_RE='git[[:space:]]+push|git[[:space:]]+tag|git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+branch[[:space:]]+-[dD]|git[[:space:]]+clean[[:space:]]+-|rm[[:space:]]+-[[:alpha:]]*r'

# The program each fragment of a shell line runs: fragments are split on the
# operators that start a new command, leading `VAR=value` assignments are
# dropped, and a path is reduced to its basename.
#
# Deliberately loose in the reporting direction: a fragment this cannot parse
# yields a token that is not on the allowlist and gets reported.
# Over-reporting is a line someone reads; under-reporting is the silence this
# whole section exists to remove.
command_heads() { # <line>
  printf '%s\n' "$1" | awk '
    {
      s = $0
      gsub(/\$\(/, "\n", s); gsub(/`/, "\n", s)
      gsub(/&&/, "\n", s);   gsub(/\|\|/, "\n", s)
      gsub(/\|/, "\n", s);   gsub(/;/, "\n", s)
      n = split(s, part, "\n")
      for (i = 1; i <= n; i++) {
        p = part[i]
        sub(/^[[:space:]]+/, "", p)
        while (p ~ /^[A-Za-z_][A-Za-z0-9_]*=/) sub(/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]*/, "", p)
        sub(/[[:space:]].*$/, "", p)
        gsub(/["'"'"'()]/, "", p)
        sub(/^.*\//, "", p)
        # Shell syntax, not a program. Dropping these is not an exemption:
        # whatever they introduce is a fragment of its own and is read on its
        # own turn.
        if (p ~ /^([{}()]|then|else|elif|fi|do|done|while|until|for|case|esac|if|!)$/) continue
        if (p != "") print p
      }
    }'
}

# The heads of one line that the allowlist does not name.
unlisted_heads() { # <line>
  local h
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    case " $EXECUTABLE_HEADS " in *" $h "*) ;; *) printf '%s\n' "$h" ;; esac
  done <<EOF
$(command_heads "$1")
EOF
  return 0
}

# Positive control for the denylist. It proves the pattern still matches its
# own contents and nothing more — a list written from itself cannot show what
# it is missing, which is why the allowlist carries the weight.
DESTRUCTIVE_FIXTURE="$TMP/destructive-fixture.txt"
cat >"$DESTRUCTIVE_FIXTURE" <<'EOF'
git push -u origin HEAD
git tag v1.2.3
git reset --hard origin/main
git branch -D feat/gone
git clean -fd
rm -rf build
EOF
DESTRUCTIVE_TOTAL=$(wc -l <"$DESTRUCTIVE_FIXTURE" | tr -d ' ')
DESTRUCTIVE_HIT=$(/usr/bin/grep -cE "$DESTRUCTIVE_RE" "$DESTRUCTIVE_FIXTURE")
if [ "$DESTRUCTIVE_TOTAL" = "$DESTRUCTIVE_HIT" ]; then
  ok "the destructive-command pattern matches every command it claims to cover ($DESTRUCTIVE_HIT)"
else
  not_ok "the destructive-command pattern matches every command it claims to cover" \
    "missed: $(/usr/bin/grep -vE "$DESTRUCTIVE_RE" "$DESTRUCTIVE_FIXTURE" | tr '\n' '; ')"
fi

# EVERYTHING THIS SUITE EXECUTES IS READ: command_problems runs the bash
# blocks AND every `!` context line, so both populations are read here.
# Prose naming a command and a plain fence are neither read nor executed — a
# person copies those out by hand. Both lists are applied to every executed
# line: the denylist names a dangerous use of an allowed program, the
# allowlist names a program nobody sanctioned.
line_problems() { # <line> — empty when the line is fine
  local unlisted
  printf '%s\n' "$1" | /usr/bin/grep -qE "$DESTRUCTIVE_RE" \
    && { printf 'destructive: %s\n' "$1"; return 0; }
  unlisted=$(unlisted_heads "$1" | sort -u | tr '\n' ' ')
  [ -n "${unlisted% }" ] && printf 'runs a program the allowlist does not name (%s): %s\n' \
    "${unlisted% }" "$1"
  return 0
}

destructive_blocks() { # <dir> — one line per executed thing naming one
  local f blkdir n i b line hit
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    blkdir="$TMP/destructive-$(basename "$f" .md)"
    rm -rf "$blkdir"; mkdir -p "$blkdir"
    n=$(extract_blocks "$f" "$blkdir")
    i=1
    while [ "$i" -le "$n" ]; do
      b=$(printf '%s/%03d.sh' "$blkdir" "$i")
      while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        hit=$(line_problems "$line")
        [ -n "$hit" ] && printf '%s block %s: %s\n' "$(basename "$f")" "$i" "$hit"
      done <"$b"
      i=$((i + 1))
    done
    # The same extraction command_problems uses, so a line it would run is a
    # line this reads — asked per line, so the report names the one at fault.
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      hit=$(line_problems "$line")
      [ -n "$hit" ] && printf '%s context line: %s\n' "$(basename "$f")" "$hit"
    done <<EOF
$(context_lines "$f")
EOF
  done
  return 0
}

# Kept in a variable rather than consumed by the check, because the executor
# below reads it too. Reporting a violation does not stop a suite — `check`
# records the failure and the file runs on — so the guard has to be something
# the executor consults, not something it follows.
DESTRUCTIVE_HITS=$(destructive_blocks "$CMDS_DIR")
check "nothing a module definition has this suite execute names a destructive command" "" \
  "$DESTRUCTIVE_HITS"

# Positive controls, both directions: the check above would pass just as
# quietly if the extraction stopped seeing blocks, and a check that flagged
# the prose too would make the rule unfollowable — a definition that opens
# pull requests has to name the command somewhere.
DESTRUCTIVE_DIR="$TMP/destructive-defs"
mkdir -p "$DESTRUCTIVE_DIR"
printf 'text\n\n```bash\ngit push -u origin HEAD\n```\n' >"$DESTRUCTIVE_DIR/bad.md"
check "a bash block naming one is reported" yes \
  "$(destructive_blocks "$DESTRUCTIVE_DIR" | /usr/bin/grep -q 'bad.md block 1' \
     && printf 'yes' || printf 'no')"

rm -f "$DESTRUCTIVE_DIR/bad.md"

# THE CONTROL FOR THE ALLOWLIST IS WRITTEN FROM NEITHER LIST: `curl` is on
# neither, so the check has to report a program it was never told about — a
# fixture drawn from either list could only show the lists matching
# themselves.
printf -- '- Fetch: !`curl -sS https://example.com/x`\n' >"$DESTRUCTIVE_DIR/unknown.md"
check "a program on neither list is reported" yes \
  "$(destructive_blocks "$DESTRUCTIVE_DIR" | /usr/bin/grep -q 'allowlist does not name' \
     && printf 'yes' || printf 'no')"

# Commands past the old denylist's edge, none named anywhere in this file:
# they are caught for running `gh`, which nobody put on the allowlist.
# Initialised, and that is load-bearing: left unset, `set -u` aborts the
# assignment on the FIRST miss and the check below reads "" — a clean answer
# produced by the failure it was meant to report.
GH_MISSED=""
rm -f "$DESTRUCTIVE_DIR/unknown.md"
for GH_CASE in 'gh pr comment 1 --body x' 'gh pr edit 1 --add-label y' \
               'gh api -X POST /repos/o/r/issues' 'gh release delete v1' \
               'gh repo delete o/r --yes'; do
  printf -- '- Do: !`%s`\n' "$GH_CASE" >"$DESTRUCTIVE_DIR/gh.md"
  GH_SEEN=$(destructive_blocks "$DESTRUCTIVE_DIR" | /usr/bin/grep -c . || true)
  [ "$GH_SEEN" -ge 1 ] || GH_MISSED="$GH_MISSED$GH_CASE; "
done
check "every gh subcommand is caught without being enumerated" "" "${GH_MISSED:-}"
rm -f "$DESTRUCTIVE_DIR/gh.md"

printf -- '- Publish: !`git push -u origin HEAD`\n' >"$DESTRUCTIVE_DIR/ctx.md"
check "a context line naming one is reported too" yes \
  "$(destructive_blocks "$DESTRUCTIVE_DIR" | /usr/bin/grep -q 'ctx.md context line' \
     && printf 'yes' || printf 'no')"

# The two halves are reported apart: a guard covering only one of them could
# otherwise pass by reporting the block for a violation that is in the line.
rm -f "$DESTRUCTIVE_DIR/ctx.md"
printf -- 'x\n\n```bash\nrm -rf build\n```\n\n- Publish: !`gh pr create --base develop`\n' \
  >"$DESTRUCTIVE_DIR/both.md"
check "a definition violating in both places is reported twice" 2 \
  "$(destructive_blocks "$DESTRUCTIVE_DIR" | /usr/bin/grep -c . || true)"

rm -f "$DESTRUCTIVE_DIR/both.md"
printf 'Run `gh pr create` yourself:\n\n```\ngh pr create --base develop\n```\n\n```bash\ntrue\n```\n' \
  >"$DESTRUCTIVE_DIR/fine.md"
check "the same command in prose and a plain fence is not" "" \
  "$(destructive_blocks "$DESTRUCTIVE_DIR")"

# Set last, so it means "the guard above finished" rather than "the file
# reached this line". Read immediately before the executor.
DESTRUCTIVE_GUARD_RAN=yes

# The next line executes every block and context line in commands/; that the
# guard has run already is asserted here rather than assumed.
check "the destructive-command guard ran before anything was executed" yes \
  "${DESTRUCTIVE_GUARD_RAN:-no}"

# AND THE EXECUTION IS SKIPPED WHEN IT FOUND SOMETHING: a red check stops
# nothing, and running these anyway would carry out the very command the
# guard just named. Reported as a failure rather than passed over — a suite
# that went quiet here would look exactly like one where everything ran.
if [ -n "$DESTRUCTIVE_HITS" ]; then
  not_ok "every command a module definition prints does what its own text asks" \
    "NOT RUN — the guard above named a destructive command in a definition, and executing these would carry it out. Move it out of the fence or the context line, then run again."
else
  check "every command a module definition prints does what its own text asks" "" \
    "$(command_problems "$CMDS_DIR")"
fi

# Positive controls: each failure mode is put in front of the runner once —
# a block that fails, a block whose placeholder does not stop it, and a
# context line that fails.
FIX="$TMP/command-fixture"
mkdir -p "$FIX"
cat >"$FIX/broken.md" <<'EOF'
- Branch: !`false && echo unreachable`

It names plugin/scripts/no-such-script.sh in prose.

```bash
exit 3
```

```bash
echo "<PLACEHOLDER> in a block that runs anyway"
```
EOF
FIX_OUT=$(command_problems "$FIX")
check "a plugin path that does not exist is reported" yes \
  "$(missing_named_paths "$FIX" | /usr/bin/grep -q 'no-such-script.sh' && printf 'yes' || printf 'no')"

# The extraction cross-check needs its own broken case: a fence the extractor
# cannot see but the crude count still counts.
mkdir -p "$FIX/hidden"
printf 'text\n\n```bash extra\nexit 0\n```\n' >"$FIX/hidden/odd.md"
check "an extraction that stops seeing a block is reported" yes \
  "$(extraction_disagreements "$FIX/hidden" | /usr/bin/grep -q 'the file opens' && printf 'yes' || printf 'no')"
check "a bash block that would run wrong is reported" yes \
  "$(printf '%s' "$FIX_OUT" | /usr/bin/grep -q 'block 1: exit 3' && printf 'yes' || printf 'no')"
check "a placeholder that fails to stop its block is reported" yes \
  "$(printf '%s' "$FIX_OUT" | /usr/bin/grep -q 'carries a placeholder and still ran' && printf 'yes' || printf 'no')"
check "a context line that fails is reported" yes \
  "$(printf '%s' "$FIX_OUT" | /usr/bin/grep -q 'context line: exit' && printf 'yes' || printf 'no')"

# The recorder writes where it was told to. A block that records telemetry must
# not have reached the real sink while this ran.
check "the sweep's telemetry went to its own sink" yes \
  "$([ -f "$CMD_SINK" ] && echo yes || echo "no — nothing recorded, so the block that records was not run")"

# --- every subcommand a definition invokes still exists ----------------------
#
# A third question, and neither check above answers it: a script keeps
# existing after the mode a definition calls it with is renamed away, and a
# block carrying a placeholder fails identically whether the mode is there or
# not.
#
# HOW A MODE IS DECIDED TO EXIST, without a second copy of any script's list
# of them living here: the script is asked twice, once with the mode the
# definition names and once with a word no script has ever had, and the two
# answers are compared — every dispatcher funnels an unrecognised word into
# one usage branch, so a mode that is gone answers EXACTLY as a nonsense word
# does.
#
# BOTH TOKENS ARE ERASED FROM BOTH ANSWERS BEFORE COMPARING, and each erasure
# closes a way this goes quiet: a dispatcher that quotes the word back would
# make every rejection look different, and a usage TEXT still listing a
# removed mode would print that name on one side only.
#
# ONLY A QUOTED PATH FOLLOWED BY A WORD IS READ AS A CALL — the quote is what
# keeps prose that merely names a script from being read as one. The
# population check below is what would notice the extraction going quiet.
#
# The probes run in this repository's tree with the sweep's own sink and home;
# none of the modes named here writes.

SENTINEL_MODE=hq-no-such-subcommand

named_subcommands() { # <dir> — `<script path> <mode>` per line, deduplicated
  /usr/bin/grep -ohE 'plugin/scripts/[A-Za-z0-9._-]+\.sh" +[a-z_][A-Za-z0-9_-]*' \
    "$1"/*.md 2>/dev/null | sed 's/" */ /' | sort -u
}

# One script's whole answer to one word: both streams and the exit status.
answer_to() { # <script path> <word>
  ( cd "$ROOT" && CLAUDE_PLUGIN_ROOT="$ROOT" HQ_SINK="$CMD_SINK" \
      bash "$ROOT/$1" "$2" </dev/null 2>&1; printf '[exit %s]\n' "$?" )
}

unknown_subcommands() { # <dir> — one line per mode the script no longer knows
  local pair script mode a b
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    script=${pair%% *}
    mode=${pair##* }
    # A path that does not exist at all is the path check's to report; saying it
    # twice in two vocabularies sends the reader looking for two defects.
    [ -f "$ROOT/$script" ] || continue
    a=$(answer_to "$script" "$mode" \
        | sed -e "s/$mode/<MODE>/g" -e "s/$SENTINEL_MODE/<MODE>/g")
    b=$(answer_to "$script" "$SENTINEL_MODE" \
        | sed -e "s/$mode/<MODE>/g" -e "s/$SENTINEL_MODE/<MODE>/g")
    [ "$a" = "$b" ] && printf 'names `%s %s`, and that script answers `%s` exactly as it answers a word it has never had\n' \
      "$script" "$mode" "$mode"
  done <<EOF
$(named_subcommands "$1")
EOF
  return 0
}

SUB_N=$(named_subcommands "$CMDS_DIR" | /usr/bin/grep -c . || true)
check "the modes the definitions invoke were extracted at all" yes \
  "$([ "$SUB_N" -ge 2 ] && echo yes || echo "no ($SUB_N)")"
check "every subcommand a module definition invokes exists" "" \
  "$(unknown_subcommands "$CMDS_DIR")"

# Positive control, both directions in one fixture: a call on a mode that is
# there and a call on one that never was. Reporting neither is what a probe
# that stopped probing looks like, and reporting both is what a probe that
# cannot tell them apart looks like.
SUBFIX="$TMP/subcommand-defs"
mkdir -p "$SUBFIX"
cat >"$SUBFIX/calls.md" <<'EOF'
This definition asks the fence both ways:

    bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/plan-gate.sh" surface <PLAN> <BASE>

and then a face that was renamed out from under it:

    bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/plan-gate.sh" summary <PLAN>
EOF
SUB_OUT=$(unknown_subcommands "$SUBFIX")
check "a subcommand the script does not have is reported" yes \
  "$(printf '%s' "$SUB_OUT" | /usr/bin/grep -q 'summary' && printf 'yes' || printf 'no')"
# THE NEEDLE HAS TO BE THE MODE THE FIXTURE ACTUALLY CALLS. Grepping for a
# word the fixture does not contain answers `no` whatever the probe did, and
# the control stops being one — which is what happened here when the valid
# mode in the fixture above was renamed and this line was not.
check "and the one beside it that does is not" no \
  "$(printf '%s' "$SUB_OUT" | /usr/bin/grep -q 'surface' && printf 'yes' || printf 'no')"

# --- no definition throws away what a gate said -----------------------------
#
# A gate has two channels: stdout is the answer, stderr is whether the answer
# is whole. Sent to /dev/null, "found nothing" and "skipped rows it could not
# read and found nothing in the rest" arrive as the same empty output.
#
# This asks about `*-gate.sh` and nothing else. Other commands on those lines
# are muted on purpose: lib.sh derivations print a message the definition
# replaces with a sentinel word its own prose then reads.

muted_gate_calls() { # <dir>
  /usr/bin/grep -n -- '-gate\.sh' "$1"/*.md 2>/dev/null \
    | /usr/bin/grep '2>/dev/null' || true
}

check "no module definition throws away what a gate said" "" \
  "$(muted_gate_calls "$CMDS_DIR")"

# Positive control: the check above is an empty-output assertion, and an empty
# output is also what a pattern that stopped matching produces.
MUTED="$TMP/muted-gate"
mkdir -p "$MUTED"
printf -- '- Open: !`bash "$X/plugin/scripts/triage-gate.sh" open 2>/dev/null || echo none`\n' \
  >"$MUTED/quiet.md"
check "a definition that muted a gate would be reported" yes \
  "$([ -n "$(muted_gate_calls "$MUTED")" ] && echo yes || echo no)"

# --- the plan contract has one definition -----------------------------------
#
# Same shape a third time. The plan module's definition tells the model which
# sections and tags to write; the plan gate decides which ones a file must
# carry. A section one side requires and the other does not is a rule with no
# reader, or a block naming something the writer was never told about.

PLAN_GATE="$HERE/plan-gate.sh"
PLAN_MD="$PLUGIN/commands/plan.md"

# Two forms, because a section name can hold a space: splitting the sorted
# list on spaces would cut `Editable surface` in half, so the lists are
# joined while the `|` is still there.
gate_sections_raw() { # <variable name>
  /usr/bin/grep -m1 "^$1=" "$PLAN_GATE" | sed 's/^[A-Z_]*="//; s/".*//'
}
gate_sections() { # <variable name> — the `|`-separated list the gate enforces
  gate_sections_raw "$1" | tr '|' '\n' | sort | tr '\n' ' '
}
md_sections() { # <yes|no> — sections marked that way in the contract table
  sed -n '/^| section | required/,/^$/p' "$PLAN_MD" \
    | /usr/bin/grep "| $1 |" | /usr/bin/grep -o '^| `## [A-Za-z ]*`' \
    | sed 's/^| `## //; s/`$//' | sort | tr '\n' ' '
}
md_tags() { # <heading> — the backticked tags in the table under it
  sed -n "/^### $1/,/^#/p" "$PLAN_MD" \
    | /usr/bin/grep -o '^| `\[[a-z]*\]`' | tr -d '|` []' | sort | tr '\n' ' '
}

PLAN_REQUIRED=$(gate_sections REQUIRED_SECTIONS)
check "the required-section list was extracted at all" yes \
  "$([ -n "$PLAN_REQUIRED" ] && echo yes || echo no)"
check "the plan contract and the gate agree on the required sections" \
  "$PLAN_REQUIRED" "$(md_sections yes)"
# There are no optional sections to compare: `## Plan` is written later, by the
# builder, so the contract marks nothing `no` and the gate holds no second
# list. A comparison of two empty lists would pass whatever either side did.
check "the contract marks no section optional" "" "$(md_sections no)"

check "the plan contract and the gate agree on the fence tags" \
  "$(/usr/bin/grep -m1 '^SURFACE_TAGS=' "$PLAN_GATE" | sed 's/^SURFACE_TAGS="//; s/".*//' \
     | tr ' ' '\n' | sort | tr '\n' ' ')" \
  "$(md_tags 'The fence tags')"

check "the plan contract and the gate agree on the confirmation tags" \
  "$(/usr/bin/grep -m1 '^CONFIRM_TAGS=' "$PLAN_GATE" | sed 's/^CONFIRM_TAGS="//; s/".*//' \
     | tr ' ' '\n' | sort | tr '\n' ' ')" \
  "$(md_tags 'The confirmation tags')"

# `[auto]` is the one tag the gate names literally on a list item; every other
# tag it enforces comes out of one of the sets above. Extracting from the call
# sites keeps the enforcing code as the single source, and the contract has to
# name the same one — a second literal appearing here is a rule the writer was
# never told about.
gate_item_tags() {
  /usr/bin/grep -o 'has_tag "[$]item" [a-z][a-z]*' "$PLAN_GATE" \
    | sed 's/.* //' | sort -u | tr '\n' ' '
}
GATE_ITEM_TAGS=$(gate_item_tags)
check "the item-tag extraction found the gate's call sites" yes \
  "$([ -n "$GATE_ITEM_TAGS" ] && echo yes || echo no)"
check "the only tag the gate names on a list item is the floor's" \
  "auto " "$GATE_ITEM_TAGS"
check "and the contract's floor section names it" yes \
  "$(sed -n '/^### The floor/,/^### /p' "$PLAN_MD" \
     | /usr/bin/grep -qF '`[auto]`' && echo yes || echo no)"


# --- one JSON escaper, copied rather than shared -----------------------------
#
# Several scripts here emit JSON and each carries its own `json_escape` —
# deliberately: some are hooks with a fail-open trap, and a syntax error in a
# sourced file would be swallowed by that trap. What copying costs is drift,
# and every difference is a way for that script's output to stop being
# readable JSON.
#
# So the copies are held byte-identical and compared here, comment included.
# The comment is inside the compared span on purpose: a false comment beside
# correct code is what the next reader believes.
#
# The report names no culprit: a text comparison cannot know which copy is
# the right one, so it prints the partition — each distinct text with the
# files carrying it.
#
# The comparison is on the text itself, not on a digest of it: this suite runs
# where `shasum` may be absent, and there every hash would come back empty and
# every copy would agree.

escaper_block() { # <file> — the compared span, empty when the file has none
  sed -n '/^# JSON string escaping, kept/,/^}/p' "$1"
}

# The two below take the copy they are comparing as arguments, because this is
# not the only function in the tree that is deliberately copied — see the
# repo_slug section further down. One comparison, told where to look.
copy_files() { # <dir> <definition pattern> — the scripts carrying it
  local f
  for f in "$1"/*.sh; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in *.test.sh) continue ;; esac
    /usr/bin/grep -q "$2" "$f" && printf '%s\n' "$f"
  done
  return 0
}

# Empty when every copy is the same text. Otherwise one line per distinct text,
# naming the files that carry it.
copy_disagreements() { # <dir> <block function> <definition pattern>
  local f g txt other seen="" group out="" block=$2 pat=$3
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    txt=$("$block" "$f")
    case "$seen" in *"|$(basename "$f")|"*) continue ;; esac
    group=""
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      other=$("$block" "$g")
      if [ "$other" = "$txt" ]; then
        group="$group $(basename "$g")"
        seen="$seen|$(basename "$g")|"
      fi
    done <<EOF
$(copy_files "$1" "$pat")
EOF
    out="$out
one text is carried by:$group"
  done <<EOF
$(copy_files "$1" "$pat")
EOF
  # One group means they all agree, which is the whole point — say nothing.
  case "$out" in
    *"one text"*"one text"*) printf '%s\n' "${out#
}" ;;
  esac
  return 0
}

ESCAPERS=$(copy_files "$HERE" '^json_escape()' | /usr/bin/grep -c . || true)
check "more than one script carries the escaper" yes \
  "$([ "$ESCAPERS" -ge 2 ] && echo yes || echo "no ($ESCAPERS)")"
check "every json_escape in the tree is the same text" "" \
  "$(copy_disagreements "$HERE" escaper_block '^json_escape()')"

# The span has to be found in every file, or the ones it is missing from
# compare as empty and agree with each other — asserted per file, or an
# anchor still matching in one script would satisfy a spot check.
ESC_EMPTY=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -n "$(escaper_block "$f")" ] || ESC_EMPTY="$ESC_EMPTY $(basename "$f")"
done <<EOF
$(copy_files "$HERE" '^json_escape()')
EOF
check "the compared span is found in every file that carries one" "" "$ESC_EMPTY"

# Positive control. The drifted copy is made by ADDING a line inside the block
# rather than by deleting a specific one: a control built by removing an exact
# line stops working the day that line is refactored away. Adding is a
# difference whatever the canonical text happens to be.
ESC_FIX="$TMP/escapers"
mkdir -p "$ESC_FIX"
escaper_block "$HERE/plan-gate.sh" >"$ESC_FIX/a.sh"
escaper_block "$HERE/plan-gate.sh" | sed 's/^}/  : # drifted\n}/' >"$ESC_FIX/b.sh"
check "the drifted fixture really differs" no \
  "$(cmp -s "$ESC_FIX/a.sh" "$ESC_FIX/b.sh" && echo yes || echo no)"
ESC_OUT=$(copy_disagreements "$ESC_FIX" escaper_block '^json_escape()')
check "a json_escape that drifted is reported" yes \
  "$([ -n "$ESC_OUT" ] && echo yes || echo no)"
check "and the report names both sides rather than one culprit" yes \
  "$(printf '%s' "$ESC_OUT" | /usr/bin/grep -q 'a.sh' \
     && printf '%s' "$ESC_OUT" | /usr/bin/grep -q 'b.sh' && printf 'yes' || printf 'no')"

# --- one repository slug, copied for the same reason -------------------------
#
# `repo_slug` turns a worktree into the `owner/name` a row carries. record.sh
# WRITES that value; the other scripts carrying the function derive it again
# to scope what they read. Drift between the copies does not produce a broken
# row — it produces an empty answer, which looks exactly like success.
#
# WHY IT IS NOT EXTRACTED: record.sh sources nothing, so lib.sh cannot hold
# the shared copy for it. The copies stay and the machine compares them;
# which files carry one is discovered by the glob below, not stated here.
#
# ONLY THE FUNCTION BODIES ARE COMPARED, unlike json_escape, whose comment is
# inside the span: each copy carries a comment about its own role, and those
# are not the same sentence.

slug_block() { # <file> — the compared span, empty when the file has none
  sed -n '/^repo_slug() {/,/^}/p' "$1"
}

SLUGS=$(copy_files "$HERE" '^repo_slug()' | /usr/bin/grep -c . || true)
check "more than one script derives the repository slug" yes \
  "$([ "$SLUGS" -ge 2 ] && echo yes || echo "no ($SLUGS)")"
check "every repo_slug in the tree is the same text" "" \
  "$(copy_disagreements "$HERE" slug_block '^repo_slug()')"

SLUG_EMPTY=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -n "$(slug_block "$f")" ] || SLUG_EMPTY="$SLUG_EMPTY $(basename "$f")"
done <<EOF
$(copy_files "$HERE" '^repo_slug()')
EOF
check "the slug span is found in every file that carries one" "" "$SLUG_EMPTY"

# Positive control, built by adding a line inside the block for the reason the
# escaper's control gives.
SLUG_FIX="$TMP/slugs"
mkdir -p "$SLUG_FIX"
slug_block "$HERE/record.sh" >"$SLUG_FIX/a.sh"
slug_block "$HERE/record.sh" | sed 's/^}/  : # drifted\n}/' >"$SLUG_FIX/b.sh"
check "the drifted slug fixture really differs" no \
  "$(cmp -s "$SLUG_FIX/a.sh" "$SLUG_FIX/b.sh" && echo yes || echo no)"
SLUG_OUT=$(copy_disagreements "$SLUG_FIX" slug_block '^repo_slug()')
check "a repo_slug that drifted is reported" yes \
  "$([ -n "$SLUG_OUT" ] && echo yes || echo no)"
check "and that report names both sides too" yes \
  "$(printf '%s' "$SLUG_OUT" | /usr/bin/grep -q 'a.sh' \
     && printf '%s' "$SLUG_OUT" | /usr/bin/grep -q 'b.sh' && printf 'yes' || printf 'no')"

# --- jq is not a dependency -------------------------------------------------
#
# lib.sh states it, and reads one JSON key by hand rather than take the
# dependency. A script that started calling jq would work on this machine and
# fail on one without it — the same shape as the bash 3.2 problem. Comment
# lines are skipped: naming the tool is not using it.

# Bounded to where a command can start — line beginning, after a pipe or
# separator, or inside a substitution: a looser bound matches the word `jq` in
# this file's own check descriptions.
JQ_RE='(^|[|;&]|\$\()[[:space:]]*jq([[:space:]]|$)'

# Each fixture line carries the marker so this file's own heredoc is skipped
# by the sweep below: the fixture has to contain what the pattern looks for.
JQ_FIXTURE="$TMP/jq-fixture.txt"
cat >"$JQ_FIXTURE" <<'EOF'
val=$(jq -r '.base_branch' settings.json) # jq-allow
cat x | jq # jq-allow
jq # jq-allow
EOF
JQ_TOTAL=$(wc -l <"$JQ_FIXTURE" | tr -d ' ')
JQ_HIT=$(/usr/bin/grep -cE "$JQ_RE" "$JQ_FIXTURE")
check "the jq pattern matches every call form it claims to cover" "$JQ_TOTAL" "$JQ_HIT"

JQ_HITS=""
for f in "$HERE"/*.sh "$PLUGIN"/commands/*.md "$PLUGIN"/agents/*.md; do
  [ -e "$f" ] || continue
  hits=$(/usr/bin/grep -nE "$JQ_RE" "$f" 2>/dev/null \
    | /usr/bin/grep -v 'jq-allow' \
    | /usr/bin/grep -v '^[0-9][0-9]*:[[:space:]]*#')
  [ -n "$hits" ] && JQ_HITS="$JQ_HITS$(basename "$f"): $hits
"
done
check "no script or module definition calls jq" "" "$JQ_HITS"

# --- nothing here launches an external reviewer -----------------------------
#
# Pillar B measures this plugin from outside, and that only holds while the
# reviewer is one the plugin cannot start: the moment a module calls one, that
# reviewer is inside the loop and stops being a measurement.

EXTERNAL_RE='codex[[:space:]]+(review|exec)|codex-companion|/codex:|/code-review|gh[[:space:]]+copilot|copilot[[:space:]]+review' # external-allow

# Positive control, same reason as the construct sweep: a pattern list is only
# worth having if something proves it still matches what it names.
EXT_FIXTURE="$TMP/external-fixture.txt"
cat >"$EXT_FIXTURE" <<'EOF'
codex review --base develop # external-allow
codex exec "do the thing" # external-allow
node scripts/codex-companion.mjs review # external-allow
/codex:review # external-allow
/code-review ultra # external-allow
gh copilot suggest # external-allow
copilot review this pull request # external-allow
EOF
EXT_TOTAL=$(wc -l <"$EXT_FIXTURE" | tr -d ' ')
EXT_HIT=$(/usr/bin/grep -cE "$EXTERNAL_RE" "$EXT_FIXTURE")
if [ "$EXT_TOTAL" = "$EXT_HIT" ]; then
  ok "the external-reviewer pattern matches every form it claims to cover ($EXT_HIT)"
else
  not_ok "the external-reviewer pattern matches every form it claims to cover" \
    "missed: $(/usr/bin/grep -vE "$EXTERNAL_RE" "$EXT_FIXTURE" | tr '\n' '; ')"
fi

EXT_HITS=""
EXT_SWEPT=0
for f in "$HERE"/*.sh "$PLUGIN"/commands/*.md "$PLUGIN"/agents/*.md "$PLUGIN"/hooks/*.json; do
  [ -e "$f" ] || continue
  EXT_SWEPT=$((EXT_SWEPT + 1))
  hits=$(/usr/bin/grep -nE "$EXTERNAL_RE" "$f" 2>/dev/null | /usr/bin/grep -v 'external-allow')
  [ -n "$hits" ] && EXT_HITS="$EXT_HITS$(basename "$f"): $hits
"
done
check "no module or script starts an external reviewer" "" "$EXT_HITS"
# The glob spans four directories, three of which did not exist when this was
# written; an empty sweep here would be silent.
check "the external-reviewer sweep read the module files" yes \
  "$([ "$EXT_SWEPT" -ge 4 ] && echo yes || echo "no ($EXT_SWEPT files)")"

# The manifest, for the checks further down that read what it registers. There
# is one plugin directory and no versioned ones, so nothing here asks which
# version is registered — that question, and the checks that asked it, went
# with the frozen trees.
MANIFEST="$(cd "$PLUGIN/.." && pwd)/.claude-plugin/plugin.json"

# --- what a definition runs is what its own frontmatter declares -------------
#
# `allowed-tools` is what decides whether a Bash call in a module definition
# runs without asking. A head it does not cover falls through to the user's own
# permission settings: interactively that is a prompt, and under `/hq:loop` it
# is a stopped run, or a refusal, or nothing at all — the step's guarantee
# quietly reverting to whatever it was borrowing before.
#
# NOT A NAMED PAIR AND NOT A COUNT: every definition is compared against its
# own declaration, and the failures are named. Counted by hand this comes out
# wrong — the same tally taken by hand and by this check disagreed, and the
# hand was low.
#
# BUILTINS ARE NOT EXEMPT, and the fixture below says so mechanically rather
# than in this comment. The permission check resolves a prefix per subcommand
# of the command line and matches it as a string against the rules; nothing in
# that path asks whether the program is a builtin, so `printf` is covered by
# `Bash(printf:*)` and by nothing else. An exemption list would be a second
# list nobody can check.
#
# FENCED BLOCKS ONLY, and that boundary is real. A `!` context line is one
# command to the permission check — whatever sits inside a quoted `bash -c`
# argument is not a subcommand of it — so reading the heads out of a context
# line the way a block is read would report programs that are never separately
# permitted.
#
# THE HEADS ARE TAKEN WITH `command_heads`, the extractor the allowlist check
# above already uses. A second extractor written here would be a second answer
# to one question.

declared_bash_heads() { # <file> — the heads its allowed-tools grants
  sed -n 's/^allowed-tools:[[:space:]]*//p' "$1" \
    | /usr/bin/grep -o 'Bash([^)]*)' \
    | sed -e 's/^Bash(//' -e 's/)$//' -e 's/:\*$//' \
    | sort -u
}

run_bash_heads() { # <file> — the heads its fenced bash blocks actually run
  local blkdir n i b line
  blkdir="$TMP/heads-$(basename "$1" .md)"
  rm -rf "$blkdir"; mkdir -p "$blkdir"
  n=$(extract_blocks "$1" "$blkdir")
  i=1
  while [ "$i" -le "$n" ]; do
    b=$(printf '%s/%03d.sh' "$blkdir" "$i")
    while IFS= read -r line; do
      case "$line" in ''|'#'*) continue ;; esac
      command_heads "$line"
    done <"$b"
    i=$((i + 1))
  done | sort -u
}

undeclared_heads() { # <dir> — one line per head a definition runs and does not declare
  local f granted h
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    granted=" $(declared_bash_heads "$f" | tr '\n' ' ')"
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      case "$granted" in
        *" $h "*) ;;
        *) printf '%s: runs %s, which no Bash(%s:*) declares\n' "$(basename "$f")" "$h" "$h" ;;
      esac
    done <<EOF
$(run_bash_heads "$f")
EOF
  done
  return 0
}

# Both sides counted, because the assertion below is an empty string and two
# broken extractions agree on one. The floor is one per definition on each
# side: every module declares at least `Bash(bash:*)` and every one of them
# runs at least one command.
DECLARED_HEAD_N=0
RUN_HEAD_N=0
for f in "$CMDS_DIR"/*.md; do
  [ -e "$f" ] || continue
  DECLARED_HEAD_N=$((DECLARED_HEAD_N + $(declared_bash_heads "$f" | /usr/bin/grep -c . || true)))
  RUN_HEAD_N=$((RUN_HEAD_N + $(run_bash_heads "$f" | /usr/bin/grep -c . || true)))
done
CMD_DEF_N=$(ls "$CMDS_DIR"/*.md 2>/dev/null | /usr/bin/grep -c . || true)
check "the declarations were read at all" yes \
  "$([ "$DECLARED_HEAD_N" -ge "$CMD_DEF_N" ] && echo yes || echo "no ($DECLARED_HEAD_N)")"
check "the commands the blocks run were read at all" yes \
  "$([ "$RUN_HEAD_N" -ge "$CMD_DEF_N" ] && echo yes || echo "no ($RUN_HEAD_N)")"
check "every command a module definition runs is covered by its own allowed-tools" "" \
  "$(undeclared_heads "$CMDS_DIR")"

# Positive controls, on fixtures: one definition that declares what it runs,
# one that does not, and one whose undeclared head is a shell builtin.
HEADFIX="$TMP/head-defs"
rm -rf "$HEADFIX"; mkdir -p "$HEADFIX"
printf -- '---\nallowed-tools: Bash(bash:*), Read\n---\n\n```bash\nbash x.sh\n```\n' \
  >"$HEADFIX/covered.md"
check "a definition declaring what it runs is not reported" "" \
  "$(undeclared_heads "$HEADFIX")"

printf -- '---\nallowed-tools: Bash(bash:*), Read\n---\n\n```bash\nmkdir -p /tmp/x\n```\n' \
  >"$HEADFIX/uncovered.md"
check "a definition running a head it does not declare is reported" \
  "uncovered.md: runs mkdir, which no Bash(mkdir:*) declares" \
  "$(undeclared_heads "$HEADFIX")"

rm -f "$HEADFIX/uncovered.md"
printf -- '---\nallowed-tools: Bash(bash:*), Read\n---\n\n```bash\nprintf hi\n```\n' \
  >"$HEADFIX/builtin.md"
check "an undeclared head that is a shell builtin is reported the same way" \
  "builtin.md: runs printf, which no Bash(printf:*) declares" \
  "$(undeclared_heads "$HEADFIX")"

rm -f "$HEADFIX/builtin.md"
printf -- '---\nallowed-tools: Bash(bash:*), Bash(printf:*)\n---\n\n```bash\nprintf hi\n```\n' \
  >"$HEADFIX/builtin-declared.md"
check "and declaring it is what stops the report" "" \
  "$(undeclared_heads "$HEADFIX")"

# --- the modules derive the plan's path the same way ------------------------
#
# Where a branch's plan lives is stated in more places than one: each module
# prints it in its § Context. Drifted, one of them reports `none` for a plan
# another is writing, and each looks right on its own page.
#
# Compared as text rather than unified into a helper: the line is a context
# command run by the harness before any definition is read, and there is no way
# to call a shell function from there.
#
# EVERY DEFINITION THAT CARRIES ONE IS COMPARED, not a named pair: a pair has
# to be extended by hand the day another module derives the same path, and the
# forgotten extension is precisely the copy that then drifts.

plan_path_line() { # <file> — the context command that derives this branch's plan
  context_lines "$1" | /usr/bin/grep 'hq_task_dir' | /usr/bin/grep 'plan\.md'
}

PLAN_PATH_LINE=$(plan_path_line "$CMDS_DIR/plan.md")
check "the plan-path context line was extracted at all" yes \
  "$([ -n "$PLAN_PATH_LINE" ] && echo yes || echo no)"

PLAN_PATH_DRIFT=""
PLAN_PATH_N=0
for f in "$CMDS_DIR"/*.md; do
  [ -e "$f" ] || continue
  line=$(plan_path_line "$f")
  [ -n "$line" ] || continue
  PLAN_PATH_N=$((PLAN_PATH_N + 1))
  [ "$line" = "$PLAN_PATH_LINE" ] || \
    PLAN_PATH_DRIFT="$PLAN_PATH_DRIFT$(basename "$f") "
done
# Without this, a `plan_path_line` that stopped matching would leave every
# definition contributing nothing and the comparison below would report clean.
check "more than one definition derives the plan's path" yes \
  "$([ "$PLAN_PATH_N" -ge 2 ] && echo yes || echo "no ($PLAN_PATH_N)")"
check "every module that derives the plan's path derives it identically" "" \
  "$PLAN_PATH_DRIFT"

# --- and the same for where a triage pass leaves its directives --------------
#
# The fix directives of a triage pass are written to a file under the run's own
# directory, and two definitions derive that location: the one that writes the
# file and the one that is handed its path. Drifted, one writes where the other
# does not look — triage reports a path it wrote, implement's line says `none`,
# and each page reads correctly on its own.
#
# EVERY DEFINITION CARRYING ONE IS COMPARED rather than a named pair, for the
# reason the plan-path check above gives: a pair has to be extended by hand the
# day a third module derives the same path.

directive_path_line() { # <file> — the context command that derives this branch's directives
  context_lines "$1" | /usr/bin/grep 'hq_task_dir' | /usr/bin/grep 'directives'
}

# The definitions whose line differs from the first one seen, by name.
directive_path_drift() { # <dir>
  local f line ref="" out=""
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    line=$(directive_path_line "$f")
    [ -n "$line" ] || continue
    if [ -z "$ref" ]; then ref=$line; continue; fi
    [ "$line" = "$ref" ] || out="$out$(basename "$f") "
  done
  printf '%s' "$out"
}

directive_path_count() { # <dir> — how many definitions carry such a line
  local f n=0
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    [ -n "$(directive_path_line "$f")" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

DIRECTIVE_PATH_N=$(directive_path_count "$CMDS_DIR")
# Without this, an extraction that stopped matching would leave every
# definition contributing nothing and the comparison below reporting clean.
check "more than one definition derives where the directives live" yes \
  "$([ "$DIRECTIVE_PATH_N" -ge 2 ] && echo yes || echo "no ($DIRECTIVE_PATH_N)")"
check "every module that derives the directives' location derives it identically" "" \
  "$(directive_path_drift "$CMDS_DIR")"

# Positive control, on a fixture rather than on the tree: the assertion above
# is an empty string, which is also what a broken extraction produces. The
# drifted line is a REAL drift of the same derivation — the glob widened by one
# character — not a line written to be obviously different, and the
# substitution is asserted to have taken so that the control cannot degenerate
# into comparing a string with itself.
DIRFIX="$TMP/directive-defs"
rm -rf "$DIRFIX"; mkdir -p "$DIRFIX"
DIR_REF=$(directive_path_line "$CMDS_DIR/triage.md")
DIR_DRIFTED=$(printf '%s' "$DIR_REF" | sed 's/triage-\*/*/')
check "the reference line was extracted from the definition that writes them" yes \
  "$([ -n "$DIR_REF" ] && echo yes || echo no)"
check "the fixture's drifted line really differs from it" yes \
  "$([ -n "$DIR_DRIFTED" ] && [ "$DIR_DRIFTED" != "$DIR_REF" ] && echo yes || echo no)"

printf -- '- Directives for this branch: !`%s`\n' "$DIR_REF" >"$DIRFIX/a-same.md"
printf -- '- Directives for this branch: !`%s`\n' "$DIR_REF" >"$DIRFIX/b-same.md"
check "two definitions deriving it identically are not reported" "" \
  "$(directive_path_drift "$DIRFIX")"

printf -- '- Directives for this branch: !`%s`\n' "$DIR_DRIFTED" >"$DIRFIX/c-drifted.md"
check "a definition deriving it another way is reported" "c-drifted.md " \
  "$(directive_path_drift "$DIRFIX")"
check "and all three fixture lines were seen" 3 "$(directive_path_count "$DIRFIX")"

# --- and the directory they name is the one that gets created ----------------
#
# § Context is not the only place this location is derived. The triage module
# makes the directory before it writes into it, and that line sits in a fenced
# block — which the comparison above cannot see, because `context_lines` reads
# only `- <label>: !`…`` bullets. A rename in one of the two and not the other
# passes every check above.
#
# THE THIRD DERIVATION CANNOT BE DROPPED INSTEAD. A fenced block is copied out
# and run as a shell script; nothing in it can read a value § Context printed,
# so the line that creates the directory has to derive the location itself.
#
# COMPARED BY RUNNING BOTH, not as text. The three sites have three shapes — a
# bullet that globs for the latest file, a bullet that resolves one path, and a
# `mkdir -p` — so there is no verbatim comparison to be made. What they have to
# agree on is the directory itself, so the block is run in a throwaway home and
# the context line is then asked where it looks. That ties the third site to
# triage's own bullet, and the check above ties that bullet to every other
# definition's.

# The blocks of a definition that create a directory, by path. Taken out of the
# file rather than written here: a copy written here would be a fourth
# derivation of the same location, which is what this section exists to stop.
mkdir_blocks() { # <file>
  local d
  d="$TMP/mkdirblk-$(basename "$1" .md)"
  rm -rf "$d"; mkdir -p "$d"
  extract_blocks "$1" "$d" >/dev/null
  /usr/bin/grep -l 'mkdir' "$d"/*.sh 2>/dev/null || true
}

# Runs <creation script> in an empty home, then asks <context line> in that same
# home where it looks, and prints a line when the two do not meet.
creation_gap() { # <creation-script> <context-line> <home>
  local out dir
  rm -rf "$3"
  ( cd "$ROOT" && CLAUDE_PLUGIN_ROOT="$ROOT" HQ_HOME="$3" bash "$1" ) \
    </dev/null >/dev/null 2>&1
  out=$( ( cd "$ROOT" && CLAUDE_PLUGIN_ROOT="$ROOT" HQ_HOME="$3" bash -c "$2" ) \
           </dev/null 2>/dev/null )
  dir=${out%% (latest:*}
  if [ -z "$dir" ] || [ "$dir" = "$out" ]; then
    printf 'the context line did not answer with a path: [%s]\n' "$out"
    return 0
  fi
  [ -d "$dir" ] || printf '%s: the context line looks here, and nothing created it\n' "$dir"
  return 0
}

MKDIR_BLOCKS=$(mkdir_blocks "$CMDS_DIR/triage.md")
check "the definition that writes the directives carries one directory-creating block" 1 \
  "$(printf '%s\n' "$MKDIR_BLOCKS" | /usr/bin/grep -c . || true)"
MKDIR_BLOCK=$(printf '%s\n' "$MKDIR_BLOCKS" | head -1)
check "the directory that block creates is the one § Context looks in" "" \
  "$(creation_gap "$MKDIR_BLOCK" "$DIR_REF" "$TMP/creation-home")"

# Positive control: the assertion above is an empty string, which is also what a
# creation script that silently did nothing would produce. The drift is a REAL
# one — the directory renamed in the block and nowhere else — and the
# substitution is asserted to have taken.
MKDIR_DRIFTED="$TMP/mkdir-drifted.sh"
sed 's|/directives|/directives-elsewhere|' "$MKDIR_BLOCK" >"$MKDIR_DRIFTED"
check "the drifted creation block really differs from it" yes \
  "$(cmp -s "$MKDIR_BLOCK" "$MKDIR_DRIFTED" && echo no || echo yes)"
check "a block that creates some other directory is reported" yes \
  "$([ -n "$(creation_gap "$MKDIR_DRIFTED" "$DIR_REF" "$TMP/creation-home-drifted")" ] && echo yes || echo no)"

# --- the loop's entry is derived where the table lives -----------------------
#
# Which module a cycle enters at is a pure function of what is on this machine,
# and the function is `loop-state.sh`. Before it existed the orchestrator held
# the table in prose and called the triage gate itself, and the table drifted
# from the modules it names while every suite stayed green — a table nothing
# compares itself against is a table that is right until it is not.
#
# TWO HALVES, and neither implies the other: the call has to be there, and the
# call it replaced has to be gone. A definition that gained the script and kept
# the gate would have two answers to one question, and would go on picking
# whichever one it read last.
#
# THE TWO HALVES ARE ASKED WITH DIFFERENT PATTERNS, on purpose. What has to be
# THERE is a CALL, so it is looked for as a quoted script path — the same thing
# that parts a call from prose in the subcommand check above, and without it a
# page that merely mentions the script in a sentence would satisfy this. What
# has to be GONE is asked as a bare mention, which is the stricter side: a
# definition has no business naming that gate at all now.
#
# WHAT THIS DOES NOT SEE: whether the prose alongside the call still carries a
# copy of the table. That is not a decidable predicate — a paraphrase is still
# a copy — so it is not claimed here, and it is claimed nowhere else either.
# What this check gives is exactly two things: the call is present, and the
# gate it replaced is not named. A definition that satisfies both and still
# spells the table out in prose passes, and nothing catches that.

entry_derivation_problems() { # <dir>
  local f="$1/loop.md"
  [ -f "$f" ] || { printf 'no loop.md in %s to check\n' "$1"; return 0; }
  /usr/bin/grep -q 'plugin/scripts/loop-state\.sh"' "$f" || \
    printf 'loop.md never calls loop-state.sh, so nothing derives which module this run enters at\n'
  /usr/bin/grep -q 'triage-gate\.sh' "$f" && \
    printf 'loop.md names triage-gate.sh itself, and that observation belongs to loop-state.sh now\n'
  return 0
}

check "the loop derives its entry with loop-state.sh and not by hand" "" \
  "$(entry_derivation_problems "$CMDS_DIR")"

# Positive control, both halves. An empty-output assertion passes just as well
# when the greps have stopped matching anything at all.
ENTRYFIX="$TMP/entry-defs"
mkdir -p "$ENTRYFIX/neither" "$ENTRYFIX/both"
# The first fixture names the script in prose without calling it: that is the
# shape a whole-file grep would wave through.
printf 'This page decides the entry from a table it carries, the way `loop-state.sh` would.\n' \
  >"$ENTRYFIX/neither/loop.md"
printf -- '- Entry: !`bash "$X/plugin/scripts/loop-state.sh"`\n- Gate: !`bash "$X/plugin/scripts/triage-gate.sh" check`\n' \
  >"$ENTRYFIX/both/loop.md"
check "a definition that derives no entry at all is reported" yes \
  "$(entry_derivation_problems "$ENTRYFIX/neither" | /usr/bin/grep -q 'never calls' && echo yes || echo no)"
check "a definition that kept the gate call beside it is reported" yes \
  "$(entry_derivation_problems "$ENTRYFIX/both" | /usr/bin/grep -q 'names triage-gate' && echo yes || echo no)"
check "and the one that kept the gate is not also reported for the other half" no \
  "$(entry_derivation_problems "$ENTRYFIX/both" | /usr/bin/grep -q 'never calls' && echo yes || echo no)"
check "a directory with no loop.md at all is reported rather than passing" yes \
  "$(entry_derivation_problems "$TMP/probe" | /usr/bin/grep -q 'no loop.md' && echo yes || echo no)"

# --- nothing live still names the old workspace location --------------------
#
# A run's working files live under the home, and the derivation is
# `hq_task_dir` in lib.sh alone. A definition still naming the old in-tree
# location would go on writing there, everything else would keep working, and
# nobody would find out until a plan was invisible to the module that had to
# read it.
#
# THE PATTERN IS ASSEMBLED FROM A VARIABLE rather than written out. This file is
# inside the set it sweeps, and a literal would make the check report itself —
# a check that can only ever fail is not a check.

LEGACY_SEG=tasks
LEGACY="\.hq/$LEGACY_SEG"

legacy_mentions() { # <dir>… — the files naming the old location, by name
  local f out=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    out="$out$(basename "$f") "
  done <<EOF
$(/usr/bin/grep -rl -- "$LEGACY" "$@" 2>/dev/null | sort)
EOF
  printf '%s' "$out"
}

check "no live definition names the old workspace location" "" \
  "$(legacy_mentions "$HERE" "$CMDS_DIR" "$PLUGIN/agents" "$PLUGIN/hooks")"

# Positive control. The sweep above passes trivially over a tree that is already
# clean, and would keep passing if the extraction broke — `grep -rl` over a
# directory that does not exist is silent and exits non-zero, and both halves of
# a comparison would then be empty and agree.
mkdir -p "$TMP/legacy-probe"
printf 'path="%s/%s/x/plan.md"\n' ".hq" "$LEGACY_SEG" >"$TMP/legacy-probe/names-it.sh"
printf 'path="$(lib hq_task_dir)/plan.md"\n' >"$TMP/legacy-probe/does-not.sh"
check "the sweep for the old location really finds one" "names-it.sh " \
  "$(legacy_mentions "$TMP/legacy-probe")"

# --- every agent is registered, and every gated type is an agent ------------
#
# Two wirings, each invisible from inside the file that gets it wrong: an
# agent file nobody registered never loads, and a type in the OWNED list
# matching no agent leaves that launch ungated while the gate's own suite
# stays green — the suite supplies the type it tests.
#
# The prefix is checked too: OWNED entries are `<plugin name>:<agent>`, and a
# rename in the manifest turns every entry into a string that matches nothing
# — the same silence as a typo.

AGENTS_DIR="$PLUGIN/agents"
LAUNCH_GATE="$HERE/launch-gate.sh"

agent_files() { # <dir> — the agent definitions present, by name
  local f out=""
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    out="$out$(basename "$f" .md)
"
  done
  printf '%s' "$out" | sort | tr '\n' ' '
}

registered_agents() { # <manifest> — the agent names the manifest registers
  /usr/bin/grep -o '"\./plugin/agents/[A-Za-z0-9._-]*\.md"' "$1" \
    | sed 's|.*/||; s|\.md"$||' | sort | tr '\n' ' '
}

owned_types() { # <gate file> — the OWNED list, one per line
  /usr/bin/grep -m1 '^OWNED=' "$1" | sed 's/^OWNED="//; s/".*//' | tr ' ' '\n'
}

# Empty when the gate's OWNED list and the agents on disk are the same set —
# BOTH DIRECTIONS: an owned type with no agent behind it is a gate guarding
# nothing, and an agent with no owned type is a launch nobody gates. The rule
# is equality rather than containment, so that an agent deliberately left
# ungated has to be made visible: the check goes red and a person decides.
wiring_problems() { # <gate file> <dir> <plugin name>
  local t f owned out=""
  owned=$(owned_types "$1")
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    case "$t" in
      "$3":*) ;;
      *) out="$out $t (not prefixed $3:)"; continue ;;
    esac
    [ -f "$2/${t#*:}.md" ] || out="$out $t (no ${t#*:}.md)"
  done <<EOF
$owned
EOF
  for f in "$2"/*.md; do
    [ -e "$f" ] || continue
    t="$3:$(basename "$f" .md)"
    case "
$owned
" in
      *"
$t
"*) ;;
      *) out="$out $t (an agent the launch gate does not own)" ;;
    esac
  done
  printf '%s' "${out# }"
}

PLUGIN_NAME=$(/usr/bin/grep -m1 '"name"' "$MANIFEST" | sed 's/.*: *"//; s/".*//')
AGENTS_PRESENT=$(agent_files "$AGENTS_DIR")

check "the agent definitions were found at all" yes \
  "$([ -n "$AGENTS_PRESENT" ] && echo yes || echo no)"
check "the plugin name was read from the manifest" yes \
  "$([ -n "$PLUGIN_NAME" ] && echo yes || echo no)"
check "every agent definition is registered in the manifest, and no other" \
  "$AGENTS_PRESENT" "$(registered_agents "$MANIFEST")"
check "the launch gate owns exactly the agents that exist" "" \
  "$(wiring_problems "$LAUNCH_GATE" "$AGENTS_DIR" "$PLUGIN_NAME")"

# Positive controls. Both checks above pass on a wired tree and would keep
# passing if either extraction went quiet, so each is shown a broken pair once.
WIRE="$TMP/wiring"
mkdir -p "$WIRE/agents"
: >"$WIRE/agents/present.md"
: >"$WIRE/agents/unregistered.md"
printf '{"name":"hq","agents":["./plugin/agents/present.md"]}\n' >"$WIRE/manifest.json"
check "an agent nobody registered is reported" no \
  "$([ "$(agent_files "$WIRE/agents")" = "$(registered_agents "$WIRE/manifest.json")" ] \
     && echo yes || echo no)"

printf 'OWNED="hq:present hq:missing other:present"\n' >"$WIRE/gate.sh"
WIRE_OUT=$(wiring_problems "$WIRE/gate.sh" "$WIRE/agents" hq)
check "a gated type with no agent behind it is reported" yes \
  "$(printf '%s' "$WIRE_OUT" | /usr/bin/grep -q 'hq:missing' && printf 'yes' || printf 'no')"
check "and so is one carrying another plugin's prefix" yes \
  "$(printf '%s' "$WIRE_OUT" | /usr/bin/grep -q 'other:present' && printf 'yes' || printf 'no')"
# The other direction, which is the one that was missing: unregistered.md sits
# in the fixture's agents directory and appears in no OWNED entry.
check "an agent the gate does not own is reported" yes \
  "$(printf '%s' "$WIRE_OUT" | /usr/bin/grep -q 'hq:unregistered' && printf 'yes' || printf 'no')"


tap_end
