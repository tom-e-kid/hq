#!/bin/bash
# Read the branch-local context.md from .hq/tasks/<branch>/.
# Usage: read-context.sh
# Returns file contents, or "none" if not found.
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's|/|-|g')
if [[ -z "$branch" ]]; then
  echo "none"
  exit 0
fi
cat ".hq/tasks/$branch/context.md" 2>/dev/null || echo "none"
