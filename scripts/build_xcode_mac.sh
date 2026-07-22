#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CLONE_DIR="${ROOT_DIR}/.xcode-sourcepackages"
DERIVED_DATA_DIR="${ROOT_DIR}/.xcode-build"

mkdir -p "$CLONE_DIR" "$DERIVED_DATA_DIR"

# Local debug only. This deliberately disables signing; use package_macos.sh for
# Developer ID archives and optional notarization.
xcodebuild \
  -project Whisper.xcodeproj \
  -scheme WhisperMac \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -clonedSourcePackagesDirPath "$CLONE_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build
