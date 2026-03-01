#!/bin/bash
# ios-build.sh - Run iOS build and extract warnings
#
# Usage: ios-build.sh [latest|minimum] [--incremental] [--save-baseline <path>]
#
# Options:
#   --incremental    Skip clean step (faster, use during development)
#   --save-baseline  Save warnings to specified file
#
# Exit codes:
#   0: Build succeeded
#   1: Build failed
#   2: Configuration error

set -euo pipefail

# Resolve git root for .hq directory (monorepo support)
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

CONFIG_FILE="$GIT_ROOT/.hq/build/config.sh"

# Determine feature directory from current branch
BRANCH_NAME=$(git branch --show-current 2>/dev/null || echo "")
SESSION_NAME="${BRANCH_NAME//\//-}"
if [[ -n "$SESSION_NAME" && -d "$GIT_ROOT/.hq/tasks/$SESSION_NAME" ]]; then
    FEATURE_DIR="$GIT_ROOT/.hq/tasks/$SESSION_NAME"
else
    FEATURE_DIR="$GIT_ROOT/.hq/build"
fi

BUILD_LOG="$FEATURE_DIR/build_output.log"
WARNINGS_LOG="$FEATURE_DIR/warnings.log"

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: $CONFIG_FILE not found. Run /hq:ios-dev first."
    exit 2
fi
source "$CONFIG_FILE"

# Parse arguments
BUILD_TYPE="${1:-latest}"
SAVE_BASELINE=""
INCREMENTAL=false

shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --save-baseline)
            SAVE_BASELINE="$2"
            shift 2
            ;;
        --incremental)
            INCREMENTAL=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Select build command
case "$BUILD_TYPE" in
    latest)
        BUILD_CMD="$BUILD_CMD_LATEST"
        echo "Building with latest configuration (OS: ${LATEST_OS:-unknown})..."
        ;;
    minimum)
        if [[ -z "${BUILD_CMD_MINIMUM:-}" ]]; then
            echo "Error: Minimum build not configured"
            exit 2
        fi
        BUILD_CMD="$BUILD_CMD_MINIMUM"
        echo "Building with minimum configuration (OS: ${MIN_OS:-unknown})..."
        ;;
    *)
        echo "Error: Unknown build type: $BUILD_TYPE (use 'latest' or 'minimum')"
        exit 2
        ;;
esac

# Remove clean step for incremental builds
if [[ "$INCREMENTAL" == true ]]; then
    BUILD_CMD="${BUILD_CMD/ clean / }"
    echo "(incremental build - skipping clean)"
fi

# Run build
set +e
eval "$BUILD_CMD" 2>&1 | tee "$BUILD_LOG"
BUILD_RESULT=${PIPESTATUS[0]}
set -e

# Extract warnings (apply filter)
if [[ -n "${WARNINGS_FILTER:-}" ]]; then
    eval "$WARNINGS_FILTER" < "$BUILD_LOG" > "$WARNINGS_LOG" 2>/dev/null || true
else
    grep -i "warning:" "$BUILD_LOG" 2>/dev/null | sort -u > "$WARNINGS_LOG" || true
fi

WARNING_COUNT=$(wc -l < "$WARNINGS_LOG" | tr -d ' ')

# Report results
echo ""
if [[ $BUILD_RESULT -ne 0 ]]; then
    echo "BUILD FAILED"
    rm -f "$BUILD_LOG"
    exit 1
fi

echo "Build succeeded"
echo "Warnings: $WARNING_COUNT"

# Save baseline if requested
if [[ -n "$SAVE_BASELINE" ]]; then
    mkdir -p "$(dirname "$SAVE_BASELINE")"
    mv "$WARNINGS_LOG" "$SAVE_BASELINE"
    echo "Baseline saved to $SAVE_BASELINE"
else
    if [[ $WARNING_COUNT -gt 0 ]]; then
        echo ""
        echo "Warnings:"
        cat "$WARNINGS_LOG"
    fi
    rm -f "$WARNINGS_LOG"
fi

rm -f "$BUILD_LOG"
exit 0
