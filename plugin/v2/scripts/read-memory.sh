#!/bin/bash
# Read a file from Claude Code's auto memory directory.
# Usage: read-memory.sh <filename>
# Returns file contents, or "none" if not found.
MEMORY_DIR="$HOME/.claude/projects/$(pwd | sed 's|[/.]|-|g')/memory"
cat "$MEMORY_DIR/$1" 2>/dev/null || echo "none"
