#!/bin/bash
set -euo pipefail

bundle_id="${1:-com.quincy.whisper}"

if ! command -v tccutil >/dev/null 2>&1; then
  echo "tccutil not found. This script must run on macOS."
  exit 1
fi

echo "Resetting TCC permissions for ${bundle_id}..."

# sudo is required to clear the system-level TCC database entries;
# without it the Accessibility grant may silently persist or become
# un-toggleable in System Settings → Privacy & Security → Accessibility.
sudo tccutil reset Microphone "${bundle_id}" || true
sudo tccutil reset Accessibility "${bundle_id}" || true
sudo tccutil reset AppleEvents "${bundle_id}" || true

echo "Done. Relaunch the app and re-approve permissions when prompted."
