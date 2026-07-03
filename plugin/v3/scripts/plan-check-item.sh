#!/usr/bin/env bash
# Toggle a single "[ ]" checkbox to "[x]" in the branch-local plan cache.
# Usage: plan-check-item.sh <pattern>
#   <pattern> is a fixed substring that uniquely identifies the checklist line.
# Exit codes:
#   0: toggled successfully (or already checked — idempotent, stdout notes this)
#   2: missing/invalid arguments
#   3: no matching line
#   4: ambiguous (multiple matches)
set -euo pipefail
IFS=$'\n\t'

usage() {
  echo "Usage: $(basename "$0") <pattern>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
pattern="$1"
[[ -n "$pattern" ]] || usage

branch_raw=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ -z "$branch_raw" || "$branch_raw" == "HEAD" ]]; then
  echo "error: not on a named branch (detached HEAD)" >&2
  exit 1
fi
branch_dir=${branch_raw//\//-}

cache_file=".hq/tasks/${branch_dir}/gh/plan.md"
if [[ ! -f "$cache_file" ]]; then
  echo "error: cache file not found: $cache_file" >&2
  exit 1
fi

# Find unchecked matches: lines starting with "- [ ] " (allowing leading spaces) containing the pattern.
mapfile -t unchecked_lines < <(grep -nF -- "$pattern" "$cache_file" | awk -F: '{line=$0; sub(/^[0-9]+:/, "", line); if (line ~ /^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]/) print $0}')
# Find already-checked matches for idempotency check.
mapfile -t checked_lines < <(grep -nF -- "$pattern" "$cache_file" | awk -F: '{line=$0; sub(/^[0-9]+:/, "", line); if (line ~ /^[[:space:]]*-[[:space:]]*\[[xX]\][[:space:]]/) print $0}')

if [[ ${#unchecked_lines[@]} -eq 0 ]]; then
  if [[ ${#checked_lines[@]} -ge 1 ]]; then
    echo "already checked: ${checked_lines[0]}"
    exit 0
  fi
  echo "error: no unchecked checklist item matching pattern: $pattern" >&2
  exit 3
fi

if [[ ${#unchecked_lines[@]} -gt 1 ]]; then
  {
    echo "error: pattern matches multiple unchecked items:"
    printf '  %s\n' "${unchecked_lines[@]}"
  } >&2
  exit 4
fi

line_no=${unchecked_lines[0]%%:*}

tmp_file="${cache_file}.tmp.$$"
awk -v ln="$line_no" '
  NR==ln {
    sub(/-[[:space:]]*\[[[:space:]]\]/, "- [x]")
  }
  { print }
' "$cache_file" > "$tmp_file"
mv -f "$tmp_file" "$cache_file"

modified=$(sed -n "${line_no}p" "$cache_file")
echo "$modified"
