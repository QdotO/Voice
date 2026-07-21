#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SVG="${1:-$ROOT_DIR/Design/WhisperV2-AppIcon.svg}"
IOS_ICONSET="${2:-$ROOT_DIR/iOS/App/Assets.xcassets/AppIcon.appiconset}"
MAC_ICONSET="${3:-$ROOT_DIR/Design/Generated/WhisperV2.iconset}"
MAC_ICNS="${4:-$ROOT_DIR/Design/Generated/WhisperV2.icns}"

if [[ ! -f "$SOURCE_SVG" ]]; then
  echo "Missing source SVG: $SOURCE_SVG" >&2
  exit 1
fi

if [[ ! -d "$IOS_ICONSET" ]]; then
  echo "Missing iOS app icon set: $IOS_ICONSET" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

qlmanage -t -s 1024 -o "$TMP_DIR" "$SOURCE_SVG" >/dev/null 2>&1
RENDERED_PNG="$TMP_DIR/$(basename "$SOURCE_SVG").png"

if [[ ! -f "$RENDERED_PNG" ]]; then
  echo "Quick Look failed to render $SOURCE_SVG" >&2
  exit 1
fi

function resize_png() {
  local size="$1"
  local output="$2"
  sips -s format png -z "$size" "$size" "$RENDERED_PNG" --out "$output" >/dev/null
}

mkdir -p "$MAC_ICONSET"
mkdir -p "$(dirname "$MAC_ICNS")"

cp "$RENDERED_PNG" "$IOS_ICONSET/AppIcon-1024.png"
resize_png 40 "$IOS_ICONSET/AppIcon-20@2x.png"
resize_png 60 "$IOS_ICONSET/AppIcon-20@3x.png"
resize_png 58 "$IOS_ICONSET/AppIcon-29@2x.png"
resize_png 87 "$IOS_ICONSET/AppIcon-29@3x.png"
resize_png 80 "$IOS_ICONSET/AppIcon-40@2x.png"
resize_png 120 "$IOS_ICONSET/AppIcon-40@3x.png"
resize_png 120 "$IOS_ICONSET/AppIcon-60@2x.png"
resize_png 180 "$IOS_ICONSET/AppIcon-60@3x.png"

resize_png 16 "$MAC_ICONSET/icon_16x16.png"
resize_png 32 "$MAC_ICONSET/icon_16x16@2x.png"
resize_png 32 "$MAC_ICONSET/icon_32x32.png"
resize_png 64 "$MAC_ICONSET/icon_32x32@2x.png"
resize_png 128 "$MAC_ICONSET/icon_128x128.png"
resize_png 256 "$MAC_ICONSET/icon_128x128@2x.png"
resize_png 256 "$MAC_ICONSET/icon_256x256.png"
resize_png 512 "$MAC_ICONSET/icon_256x256@2x.png"
resize_png 512 "$MAC_ICONSET/icon_512x512.png"
resize_png 1024 "$MAC_ICONSET/icon_512x512@2x.png"

if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$MAC_ICONSET" -o "$MAC_ICNS"
else
  echo "warning: iconutil not found, skipping .icns generation" >&2
fi

echo "Updated iOS icon set: $IOS_ICONSET"
echo "Generated macOS iconset source: $MAC_ICONSET"
[[ -f "$MAC_ICNS" ]] && echo "Generated macOS icns: $MAC_ICNS"
