#!/bin/bash
set -e

reset_permissions=false

for arg in "$@"; do
	if [[ "$arg" == "--reset-permissions" ]]; then
		reset_permissions=true
	fi
done

echo "Building Whisper..."
swift build

echo "Updating app bundle..."
cp .build/debug/Whisper Whisper.app/Contents/MacOS/

if [[ "$reset_permissions" == true ]]; then
	bash ./scripts/reset_permissions.sh
fi

echo "Done! Run with: open Whisper.app"
