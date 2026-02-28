#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# build.sh — Build, permission-reset, and relaunch Whisper
#
# Defaults: always kill the running instance and reset TCC permissions so that
# each fresh binary gets a clean Accessibility/Microphone prompt.
# Pass --no-reset-permissions to skip the TCC reset (e.g. CI / fast iteration).
# ─────────────────────────────────────────────────────────────────────────────

reset_permissions=true

for arg in "$@"; do
    if [[ "$arg" == "--no-reset-permissions" ]]; then
        reset_permissions=false
    fi
done

BUNDLE_ID="com.quincy.whisper"
APP_NAME="Whisper"

# ── 1. Kill any running instance ────────────────────────────────────────────
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "Stopping running $APP_NAME instance..."
    pkill -TERM -x "$APP_NAME" 2>/dev/null || true
    # Wait up to 3 s for graceful exit
    for i in $(seq 1 30); do
        pgrep -x "$APP_NAME" > /dev/null 2>&1 || break
        sleep 0.1
    done
    # Force-kill if still alive
    pkill -KILL -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    echo "  → Stopped."
fi

# ── 2. Reset TCC permissions ─────────────────────────────────────────────────
if [[ "$reset_permissions" == true ]]; then
    echo "Resetting TCC permissions for ${BUNDLE_ID}..."
    bash ./scripts/reset_permissions.sh "$BUNDLE_ID"
fi

# ── 3. Build ──────────────────────────────────────────────────────────────────
echo "Building Whisper..."
swift build

# ── 4. Update app bundle ──────────────────────────────────────────────────────
echo "Updating app bundle..."
cp .build/debug/Whisper Whisper.app/Contents/MacOS/

# ── 5. Launch ─────────────────────────────────────────────────────────────────
echo "Launching Whisper..."
open Whisper.app

echo ""
echo "Done! Re-approve Accessibility & Microphone permissions when macOS prompts."
