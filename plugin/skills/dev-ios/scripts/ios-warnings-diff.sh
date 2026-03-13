#!/bin/bash
# ios-warnings-diff.sh - Compare warnings against baseline
#
# Usage: ios-warnings-diff.sh <baseline_file> [current_warnings_file]
#
# Exit codes:
#   0: Warnings same or decreased
#   1: Warnings increased
#   2: File not found

set -euo pipefail

BASELINE="${1:-}"
CURRENT="${2:-warnings.log}"

if [[ -z "$BASELINE" ]]; then
    echo "Usage: ios-warnings-diff.sh <baseline_file> [current_warnings_file]"
    exit 2
fi

if [[ ! -f "$BASELINE" ]]; then
    echo "Error: Baseline file not found: $BASELINE"
    exit 2
fi

if [[ ! -f "$CURRENT" ]]; then
    echo "Error: Current warnings file not found: $CURRENT"
    exit 2
fi

BASELINE_COUNT=$(wc -l < "$BASELINE" | tr -d ' ')
CURRENT_COUNT=$(wc -l < "$CURRENT" | tr -d ' ')

echo "Baseline warnings: $BASELINE_COUNT"
echo "Current warnings:  $CURRENT_COUNT"

if [[ $CURRENT_COUNT -gt $BASELINE_COUNT ]]; then
    echo ""
    echo "New warnings detected:"
    # Show lines in current but not in baseline
    comm -13 <(sort "$BASELINE") <(sort "$CURRENT") 2>/dev/null || \
        diff "$BASELINE" "$CURRENT" | grep "^>" | sed 's/^> //'
    exit 1
fi

if [[ $CURRENT_COUNT -lt $BASELINE_COUNT ]]; then
    echo ""
    echo "Warnings decreased!"
    echo "Removed warnings:"
    comm -23 <(sort "$BASELINE") <(sort "$CURRENT") 2>/dev/null || \
        diff "$BASELINE" "$CURRENT" | grep "^<" | sed 's/^< //'
fi

exit 0
