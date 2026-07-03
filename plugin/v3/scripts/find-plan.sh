#!/usr/bin/env bash
# Find the branch whose local plan matches the given query.
# Usage: find-plan.sh <branch-or-substring>
#   <query> is matched against the `branch:` field of .hq/tasks/*/context.md:
#   exact match wins; otherwise a unique substring match is accepted.
# Prints the branch name on stdout (from the `branch:` field in context.md).
# Exit codes:
#   0: found — branch printed on stdout
#   1: not found
#   2: missing/invalid arguments
#   5: ambiguous (multiple substring matches, no exact match)
set -euo pipefail
IFS=$'\n\t'

usage() {
  echo "Usage: $(basename "$0") <branch-or-substring>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
query="$1"
[[ -n "$query" ]] || usage

if [[ ! -d .hq/tasks ]]; then
  exit 1
fi

branches=()
while IFS= read -r -d '' ctx; do
  branch=$(awk '
    /^---[[:space:]]*$/ { in_fm = !in_fm; next }
    in_fm && /^branch:[[:space:]]*/ {
      b = $0; sub(/^branch:[[:space:]]*/, "", b); sub(/[[:space:]]*$/, "", b)
      print b; exit
    }
  ' "$ctx")
  if [[ -n "$branch" ]]; then
    branches+=("$branch")
  fi
done < <(find .hq/tasks -mindepth 2 -maxdepth 2 -name context.md -print0 2>/dev/null)

if [[ ${#branches[@]} -eq 0 ]]; then
  exit 1
fi

# Exact match wins outright.
for b in "${branches[@]}"; do
  if [[ "$b" == "$query" ]]; then
    echo "$b"
    exit 0
  fi
done

# Fall back to substring matching.
matches=()
for b in "${branches[@]}"; do
  if [[ "$b" == *"$query"* ]]; then
    matches+=("$b")
  fi
done

if [[ ${#matches[@]} -eq 0 ]]; then
  exit 1
fi

if [[ ${#matches[@]} -gt 1 ]]; then
  {
    echo "error: query '${query}' matches multiple branches:"
    printf '  %s\n' "${matches[@]}"
  } >&2
  exit 5
fi

echo "${matches[0]}"
