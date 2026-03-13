#!/bin/bash
# ios-run.sh - Run app on iOS Simulator
#
# Usage: ios-run.sh [--restart|--reinstall|--stop|--shutdown]
#
# Subcommands:
#   (none)        boot → install → launch
#   --restart     terminate → launch
#   --reinstall   terminate → install → launch
#   --stop        terminate
#   --shutdown    terminate → shutdown simulator
#
# Exit codes:
#   0: Success
#   1: Run failed
#   2: Configuration error

set -euo pipefail

# Resolve git root for .hq directory (monorepo support)
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

CONFIG_FILE="$GIT_ROOT/.hq/build/config.sh"

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: $CONFIG_FILE not found. Run /hq:dev-ios first."
    exit 2
fi
source "$CONFIG_FILE"

if [[ -z "${BUNDLE_ID:-}" ]]; then
    echo "Error: BUNDLE_ID not set in config.sh. Reconfigure with /hq:dev-ios."
    exit 2
fi

# Parse arguments
MODE="run"
case "${1:-}" in
    --restart)    MODE="restart" ;;
    --reinstall)  MODE="reinstall" ;;
    --stop)       MODE="stop" ;;
    --shutdown)   MODE="shutdown" ;;
    "")           MODE="run" ;;
    *)
        echo "Error: Unknown option: $1"
        echo "Usage: ios-run.sh [--restart|--reinstall|--stop|--shutdown]"
        exit 2
        ;;
esac

# --- Internal functions ---

resolve_app_path() {
    local ws_flag="-workspace"
    if [[ "$WORKSPACE" == *.xcodeproj ]]; then
        ws_flag="-project"
    fi

    local build_settings
    build_settings=$(xcodebuild -showBuildSettings "$ws_flag" "$WORKSPACE" -scheme "$SCHEME" -destination "$LATEST_DEST" 2>/dev/null)

    local products_dir
    products_dir=$(echo "$build_settings" | grep '^\s*BUILT_PRODUCTS_DIR' | head -1 | awk '{print $3}')
    local product_name
    product_name=$(echo "$build_settings" | grep '^\s*FULL_PRODUCT_NAME' | head -1 | awk '{print $3}')

    if [[ -z "$products_dir" || -z "$product_name" ]]; then
        echo "Error: Could not resolve app path from build settings."
        exit 1
    fi

    APP_PATH="$products_dir/$product_name"

    if [[ ! -d "$APP_PATH" ]]; then
        echo "Error: App not found at $APP_PATH. Run build first."
        exit 1
    fi
}

resolve_device_udid() {
    UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
target_device = '${LATEST_DEVICE}'
target_os = '${LATEST_OS}'
runtime_suffix = 'iOS-' + target_os.replace('.', '-')
for runtime, devices in data.get('devices', {}).items():
    if runtime_suffix in runtime:
        for d in devices:
            if d['name'] == target_device:
                print(d['udid'])
                sys.exit(0)
sys.exit(1)
" 2>/dev/null)

    if [[ -z "${UDID:-}" ]]; then
        echo "Error: Could not find simulator for ${LATEST_DEVICE} (iOS ${LATEST_OS})."
        exit 1
    fi
}

boot_simulator() {
    echo "Booting simulator (${LATEST_DEVICE}, iOS ${LATEST_OS})..."
    xcrun simctl boot "$UDID" 2>/dev/null || true
    open -a Simulator
}

terminate_app() {
    echo "Terminating ${BUNDLE_ID}..."
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
}

install_app() {
    echo "Installing app..."
    xcrun simctl install "$UDID" "$APP_PATH"
}

launch_app() {
    echo "Launching ${BUNDLE_ID}..."
    xcrun simctl launch "$UDID" "$BUNDLE_ID"
}

shutdown_simulator() {
    echo "Shutting down simulator..."
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
}

# --- Main ---

resolve_device_udid

case "$MODE" in
    run)
        resolve_app_path
        boot_simulator
        install_app
        launch_app
        ;;
    restart)
        terminate_app
        launch_app
        ;;
    reinstall)
        resolve_app_path
        terminate_app
        install_app
        launch_app
        ;;
    stop)
        terminate_app
        ;;
    shutdown)
        terminate_app
        shutdown_simulator
        ;;
esac

echo "Done."
exit 0
