#!/bin/bash
set -euo pipefail

# build.sh — modern macOS build/run wrapper for Whisper
#
# This script keeps the existing convenience behavior around process shutdown,
# permission reset, and relaunch, but the actual app bundle is now produced by
# the Xcode `WhisperMac` target instead of a manual `swift build` packaging step.

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

reset_permissions=true
launch_app=true

for arg in "$@"; do
    case "$arg" in
        --no-reset-permissions)
            reset_permissions=false
            ;;
        --no-launch)
            launch_app=false
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: ./build.sh [--no-reset-permissions] [--no-launch]" >&2
            exit 1
            ;;
    esac
done

BUNDLE_ID="com.quincy.whisper"
APP_NAME="Whisper"
DERIVED_DATA_DIR="${ROOT_DIR}/.xcode-build"
APP_BUNDLE="${DERIVED_DATA_DIR}/Build/Products/Debug/${APP_NAME}.app"

# ── 1. Kill any running instance ────────────────────────────────────────────
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "Stopping running $APP_NAME instance..."
    pkill -TERM -x "$APP_NAME" 2>/dev/null || true
    for _ in $(seq 1 30); do
        pgrep -x "$APP_NAME" > /dev/null 2>&1 || break
        sleep 0.1
    done
    pkill -KILL -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    echo "  -> Stopped."
fi

# ── 2. Reset TCC permissions ────────────────────────────────────────────────
if [[ "$reset_permissions" == true ]]; then
    echo "Resetting TCC permissions for ${BUNDLE_ID}..."
    bash ./scripts/reset_permissions.sh "$BUNDLE_ID"
fi

# ── 3. Build via Xcode target ───────────────────────────────────────────────
echo "Building WhisperMac target..."
bash ./scripts/build_xcode_mac.sh

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "Expected app bundle not found at ${APP_BUNDLE}" >&2
    exit 1
fi

echo "Built app bundle:"
echo "  ${APP_BUNDLE}"

# ── 4. Launch ───────────────────────────────────────────────────────────────
if [[ "$launch_app" == true ]]; then
    echo "Launching Whisper..."
    open "${APP_BUNDLE}"
    echo ""
    echo "Done. Re-approve Accessibility and Microphone permissions when macOS prompts."
else
    echo "Launch skipped."
fi
