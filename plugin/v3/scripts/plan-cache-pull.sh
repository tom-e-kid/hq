#!/usr/bin/env bash
# Pull hq:plan Issue body from GitHub into the branch-local cache.
# Usage: plan-cache-pull.sh <plan-number>
# Writes: .hq/tasks/<branch>/gh/plan.md (atomic: temp + mv)
# Prints the absolute path of the written file on stdout.
set -euo pipefail
IFS=$'\n\t'

usage() {
  echo "Usage: $(basename "$0") <plan-number>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
plan="$1"
[[ "$plan" =~ ^[0-9]+$ ]] || usage

branch_raw=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ -z "$branch_raw" || "$branch_raw" == "HEAD" ]]; then
  echo "error: not on a named branch (detached HEAD)" >&2
  exit 1
fi
branch_dir=${branch_raw//\//-}

cache_dir=".hq/tasks/${branch_dir}/gh"
mkdir -p "$cache_dir"

cache_file="${cache_dir}/plan.md"
tmp_file="${cache_file}.tmp.$$"

if ! gh issue view "$plan" --json body --jq '.body' > "$tmp_file" 2>/tmp/plan-cache-pull.err; then
  cat /tmp/plan-cache-pull.err >&2
  rm -f "$tmp_file" /tmp/plan-cache-pull.err
  exit 1
fi
rm -f /tmp/plan-cache-pull.err

mv -f "$tmp_file" "$cache_file"

abs_path=$(cd "$(dirname "$cache_file")" && pwd)/$(basename "$cache_file")
echo "$abs_path"
