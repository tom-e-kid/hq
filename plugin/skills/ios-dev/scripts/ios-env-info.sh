#!/bin/bash
# ios-env-info.sh - Gather iOS development environment information
#
# Usage: ios-env-info.sh [workspace]
#
# Outputs environment information for configuring iOS builds.

set -euo pipefail

echo "=== iOS Environment Information ==="
echo ""

# Find workspace/project
WORKSPACE="${1:-}"
if [[ -z "$WORKSPACE" ]]; then
    WORKSPACE=$(ls -d *.xcworkspace 2>/dev/null | head -1 || true)
    if [[ -z "$WORKSPACE" ]]; then
        WORKSPACE=$(ls -d *.xcodeproj 2>/dev/null | head -1 || true)
    fi
fi

if [[ -z "$WORKSPACE" ]]; then
    echo "Error: No workspace or project found"
    exit 1
fi

echo "## Project"
echo "Workspace/Project: $WORKSPACE"
echo ""

# Get schemes
echo "## Schemes"
if [[ "$WORKSPACE" == *.xcworkspace ]]; then
    xcodebuild -workspace "$WORKSPACE" -list 2>/dev/null | grep -A 100 "Schemes:" | tail -n +2 | grep -v "^$" | head -10 || echo "(none found)"
else
    xcodebuild -project "$WORKSPACE" -list 2>/dev/null | grep -A 100 "Schemes:" | tail -n +2 | grep -v "^$" | head -10 || echo "(none found)"
fi
echo ""

# Get deployment target
echo "## Deployment Target"
PROJECT_FILE=$(echo "$WORKSPACE" | sed 's/\.xcworkspace/.xcodeproj/' || echo "$WORKSPACE")
if [[ -d "$PROJECT_FILE" ]]; then
    grep -r "IPHONEOS_DEPLOYMENT_TARGET" "$PROJECT_FILE/project.pbxproj" 2>/dev/null | \
        sed 's/.*= //' | tr -d ';' | sort -u | head -5 || echo "(not found)"
else
    echo "(project file not found)"
fi
echo ""

# Get installed runtimes
echo "## Installed iOS Runtimes"
xcrun simctl runtime list 2>/dev/null | grep -i "iOS" || echo "(none found)"
echo ""

# Get available devices for each runtime
echo "## Available Simulators"
xcrun simctl list devices available 2>/dev/null | grep -E "(-- iOS|iPhone|iPad)" | head -30 || echo "(none found)"
echo ""

# Code formatting
echo "## Code Formatting"
if command -v swift-format &> /dev/null; then
    echo "swift-format: $(swift-format --version 2>/dev/null || echo 'installed')"
else
    echo "swift-format: NOT FOUND"
    echo "  Install: brew install swift-format"
fi
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if [ -f "$GIT_ROOT/.swift-format" ]; then
    echo "Config: $GIT_ROOT/.swift-format (exists)"
else
    echo "Config: No .swift-format found (will use defaults)"
fi
echo ""

echo "=== End of Environment Information ==="
