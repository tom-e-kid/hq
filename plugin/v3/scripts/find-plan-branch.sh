#!/usr/bin/env bash
# Find the branch whose context.md references the given hq:plan issue number.
# Usage: find-plan-branch.sh <plan-number>
# Prints the branch name on stdout (from the `branch:` field in context.md).
# Exit codes:
#   0: found — branch printed on stdout
#   1: not found
#   2: missing/invalid arguments
#   5: ambiguous (multiple matches)
set -euo pipefail
IFS=$'\n\t'

usage() {
  echo "Usage: $(basename "$0") <plan-number>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
plan="$1"
[[ "$plan" =~ ^[0-9]+$ ]] || usage

if [[ ! -d .hq/tasks ]]; then
  exit 1
fi

matches=()
while IFS= read -r -d '' ctx; do
  # Match lines like "plan: 42" or "plan: #42" at column 1 of the frontmatter.
  if awk -v p="$plan" '
    /^---[[:space:]]*$/ { in_fm = !in_fm; next }
    in_fm && /^plan:[[:space:]]*#?[0-9]+[[:space:]]*$/ {
      n = $0; sub(/^plan:[[:space:]]*#?/, "", n); sub(/[[:space:]]*$/, "", n)
      if (n == p) { found = 1; exit }
    }
    END { exit (found ? 0 : 1) }
  ' "$ctx"; then
    branch=$(awk '
      /^---[[:space:]]*$/ { in_fm = !in_fm; next }
      in_fm && /^branch:[[:space:]]*/ {
        b = $0; sub(/^branch:[[:space:]]*/, "", b); sub(/[[:space:]]*$/, "", b)
        print b; exit
      }
    ' "$ctx")
    if [[ -n "$branch" ]]; then
      matches+=("$branch")
    fi
  fi
done < <(find .hq/tasks -mindepth 2 -maxdepth 2 -name context.md -print0 2>/dev/null)

if [[ ${#matches[@]} -eq 0 ]]; then
  exit 1
fi

if [[ ${#matches[@]} -gt 1 ]]; then
  {
    echo "error: plan #${plan} referenced by multiple contexts:"
    printf '  %s\n' "${matches[@]}"
  } >&2
  exit 5
fi

echo "${matches[0]}"
