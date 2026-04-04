#!/bin/bash
# Read a file from Claude Code's auto memory directory.
# Usage: read-memory.sh <filename>
# Returns file contents, or "none" if not found.
MEMORY_DIR="$HOME/.claude/projects/$(pwd | sed 's|[/.]|-|g')/memory"
filename="$1"
if [[ -z "$filename" ]] || [[ "$filename" == */* ]] || [[ "$filename" == *..* ]]; then
  echo "ERROR: invalid filename" >&2
  exit 1
fi
cat "$MEMORY_DIR/$filename" 2>/dev/null || echo "none"
