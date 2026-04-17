#!/usr/bin/env bash
# Push the branch-local plan cache to the hq:plan Issue on GitHub.
# Usage: plan-cache-push.sh <plan-number>
# Reads: .hq/tasks/<branch>/gh/plan.md
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

cache_file=".hq/tasks/${branch_dir}/gh/plan.md"
if [[ ! -f "$cache_file" ]]; then
  echo "error: cache file not found: $cache_file" >&2
  exit 1
fi

if ! gh issue edit "$plan" --body-file "$cache_file" > /dev/null 2> /tmp/plan-cache-push.err; then
  cat /tmp/plan-cache-push.err >&2
  rm -f /tmp/plan-cache-push.err
  exit 1
fi
rm -f /tmp/plan-cache-push.err

echo "pushed #${plan} from ${cache_file}"
