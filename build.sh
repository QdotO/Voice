#!/bin/bash
set -e

echo "Building Whisper..."
swift build

echo "Updating app bundle..."
cp .build/debug/Whisper Whisper.app/Contents/MacOS/

echo "Done! Run with: open Whisper.app"
