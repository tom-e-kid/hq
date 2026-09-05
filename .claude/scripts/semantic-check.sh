#!/usr/bin/env bash
# semantic-check.sh — asks a model whether a commit names something it should not.
#
#   semantic-check.sh staged    exit 0 clean, 1 refused, 2 could not ask.
#
# WHY A MODEL AND NOT A PATTERN. `secrets-check.sh` beside this one enforces a
# list of terms and a set of shapes. Neither can recognise a proper noun nobody
# wrote down — a company, a customer's project, another repository's name — and
# that is most of what must not be published from here. Recognising an unlisted
# name is not a property a regular expression has; it is a judgment, so it is
# asked of something that can make one.
#
# THE RULE IS NOT RESTATED HERE. What may and may not be named is written once,
# in `AGENTS.md` § Naming hygiene, and this script extracts that section and
# sends it as the standard to apply. A copy of the rule in this file would be
# a second definition that nothing compares.
#
# NOT HAVING BEEN ABLE TO ASK IS A REFUSAL, not a pass. A commit that went
# through because the model was unreachable is indistinguishable afterwards
# from one that was read and cleared. The deliberate way past is
# `HQ_SKIP_SEMANTIC=1 git commit …`, and THAT IS THE HOLE IN THIS GUARD: it is
# one environment variable, it leaves no record, and it is named here rather
# than hidden so that using it is a decision rather than a habit.
#
# WHAT IT DOES NOT GUARANTEE. A model reading a diff is a second opinion with
# false negatives. It lowers the chance that a name gets out; it does not
# remove it. Nothing downstream treats a clean answer here as proof.
#
# Overridable for tests: HQ_SEMANTIC_CMD is the command the diff is piped to
# (default: `claude -p --model haiku`). HQ_SEMANTIC_MAX_LINES caps how much
# diff is sent, and a capped run says so and refuses rather than reporting on
# the part it read.
#
# Portability: bash 3.2, BSD userland.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/../.." && pwd) || exit 2
MAX_LINES="${HQ_SEMANTIC_MAX_LINES:-1500}"

case "${1:-}" in
  staged) ;;
  *) echo "usage: semantic-check.sh staged" >&2; exit 2 ;;
esac

if [ "${HQ_SKIP_SEMANTIC:-}" = 1 ]; then
  echo "semantic-check: skipped by HQ_SKIP_SEMANTIC=1 — nothing read this commit" >&2
  exit 0
fi

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# Added lines and the paths, which is what a commit publishes. A removal
# carries the term too, and refusing the removal would make deleting a leak
# the one change that cannot be committed.
git -C "$ROOT" diff --cached --name-only >"$TMP/paths" 2>/dev/null || exit 2
git -C "$ROOT" diff --cached -U0 --no-color 2>/dev/null \
  | /usr/bin/grep '^+' | /usr/bin/grep -v '^+++' >"$TMP/added"

if [ ! -s "$TMP/paths" ] && [ ! -s "$TMP/added" ]; then
  exit 0
fi

n=$(/usr/bin/grep -c . "$TMP/added" 2>/dev/null || printf 0)
if [ "$n" -gt "$MAX_LINES" ]; then
  echo "semantic-check: $n added lines is over the $MAX_LINES the check sends, so it was NOT read. Commit in smaller pieces, or raise HQ_SEMANTIC_MAX_LINES having decided the cost is worth it." >&2
  exit 2
fi

# The standard, taken from where it is defined rather than copied.
RULE=$(awk '/^## Naming hygiene$/{f=1;next} f&&/^## /{exit} f' "$ROOT/AGENTS.md" 2>/dev/null)
if [ -z "$RULE" ]; then
  echo "semantic-check: the naming rule (AGENTS.md § Naming hygiene) could not be read, so there was no standard to apply" >&2
  exit 2
fi

{
  echo "You are checking one commit before it is published to a PUBLIC repository."
  echo
  echo "THE STANDARD, copied from this repository's own rules:"
  echo "---"
  echo "$RULE"
  echo "---"
  echo
  echo "Below are the file paths this commit touches and the lines it ADDS."
  echo "Find every proper noun that the standard above does not permit:"
  echo "the name of a company, a customer, a customer's project, a person,"
  echo "or another repository that is not this one. Names of tools and"
  echo "services this project genuinely uses are permitted, as the standard"
  echo "says. A fictional or placeholder identifier is permitted."
  echo
  echo "Answer in exactly this form and nothing else."
  echo "First line: 'VERDICT: CLEAN' or 'VERDICT: REFUSE'."
  echo "If REFUSE, one further line per finding: the term, then ' — ', then why."
  echo
  echo "PATHS:"
  cat "$TMP/paths"
  echo
  echo "ADDED LINES:"
  cat "$TMP/added"
} >"$TMP/prompt"

CMD="${HQ_SEMANTIC_CMD:-claude -p --model haiku}"
# shellcheck disable=SC2086
$CMD <"$TMP/prompt" >"$TMP/answer" 2>"$TMP/err" || {
  echo "semantic-check: the check could not be run ($CMD). $(head -2 "$TMP/err" | tr '\n' ' ')" >&2
  exit 2
}

verdict=$(/usr/bin/grep -m1 '^VERDICT:' "$TMP/answer" | sed 's/^VERDICT:[[:space:]]*//')
case "$verdict" in
  CLEAN) exit 0 ;;
  REFUSE)
    /usr/bin/grep -v '^VERDICT:' "$TMP/answer" | /usr/bin/grep -v '^[[:space:]]*$'
    echo "semantic-check: refused. Rename what it names, or use a placeholder." >&2
    exit 1
    ;;
  *)
    # AN ANSWER NOBODY CAN READ IS NOT A PASS. Reporting it as clean would make
    # every future change to the prompt or the model silently disable this.
    echo "semantic-check: the answer had no readable verdict, so nothing was checked:" >&2
    head -5 "$TMP/answer" >&2
    exit 2
    ;;
esac
