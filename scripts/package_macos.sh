#!/bin/bash
set -euo pipefail

# Creates a direct-distribution ZIP. Default path requires Developer ID signing.
# Never submits to Apple unless --notarize is explicitly passed.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Whisper.xcodeproj"
SCHEME="WhisperMac"
DIST_DIR="$ROOT_DIR/dist"
CLONE_DIR="$ROOT_DIR/.xcode-sourcepackages"
DERIVED_DATA_DIR="$ROOT_DIR/.xcode-build-distribution"
ARCHIVE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/whisper-macos-archive.XXXXXX")"
ARCHIVE_PATH="$ARCHIVE_ROOT/Whisper.xcarchive"

MODE="signed"
NOTARIZE=0

usage() {
  cat <<'EOF'
Usage:
  scripts/package_macos.sh [--unsigned-validation] [--notarize]

Default: archive Release with Developer ID signing, verify, then create
         dist/Whisper-<version>-macOS.zip.

Required for signed distribution:
  DEVELOPER_ID_APP='Developer ID Application: Your Name (TEAMID)'

Optional build-time input:
  DEVELOPMENT_TEAM=TEAMID

Explicit notarization step only:
  scripts/package_macos.sh --notarize
  requires NOTARY_KEYCHAIN_PROFILE=<existing notarytool keychain profile>.

Unsigned validation only:
  scripts/package_macos.sh --unsigned-validation
  creates dist/Whisper-<version>-macOS-unsigned-validation.zip. It is not
  distributable and is never submitted or stapled.
EOF
}

while (($#)); do
  case "$1" in
    --unsigned-validation)
      MODE="unsigned-validation"
      ;;
    --notarize)
      NOTARIZE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$MODE" == "unsigned-validation" && "$NOTARIZE" -eq 1 ]]; then
  echo "error: --notarize requires a signed Developer ID archive" >&2
  exit 2
fi

if [[ "$MODE" == "signed" ]]; then
  : "${DEVELOPER_ID_APP:?set DEVELOPER_ID_APP to a Developer ID Application identity}"
  if ! security find-identity -p codesigning -v | grep -Fq "$DEVELOPER_ID_APP"; then
    echo "error: Developer ID identity not available: $DEVELOPER_ID_APP" >&2
    exit 1
  fi
  if [[ "$NOTARIZE" -eq 1 ]]; then
    : "${NOTARY_KEYCHAIN_PROFILE:?set NOTARY_KEYCHAIN_PROFILE for explicit notarization}"
  fi
fi

mkdir -p "$CLONE_DIR" "$DERIVED_DATA_DIR" "$DIST_DIR"
cd "$ROOT_DIR"

BUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration Release
  -destination 'generic/platform=macOS'
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$DERIVED_DATA_DIR"
  -clonedSourcePackagesDirPath "$CLONE_DIR"
  archive
)

if [[ "$MODE" == "unsigned-validation" ]]; then
  BUILD_ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
else
  BUILD_ARGS+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_APP" OTHER_CODE_SIGN_FLAGS=--timestamp)
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    BUILD_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
  fi
fi

xcodebuild "${BUILD_ARGS[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/Whisper.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: archive did not contain Whisper.app" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [[ "$MODE" == "unsigned-validation" ]]; then
  ZIP_PATH="$DIST_DIR/Whisper-${VERSION}-macOS-unsigned-validation.zip"
else
  ZIP_PATH="$DIST_DIR/Whisper-${VERSION}-macOS.zip"
fi

if [[ -e "$ZIP_PATH" ]]; then
  echo "error: output already exists: $ZIP_PATH" >&2
  exit 1
fi

if [[ "$MODE" == "signed" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  codesign -dvvv --entitlements :- "$APP_PATH"
  find "$APP_PATH/Contents" -type d \( -name '*.app' -o -name '*.appex' -o -name '*.framework' -o -name '*.xpc' \) -print0 |
    while IFS= read -r -d '' nested; do
      codesign --verify --strict --verbose=2 "$nested"
    done
fi

/usr/bin/ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ "$NOTARIZE" -eq 1 ]]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  rm "$ZIP_PATH"
  /usr/bin/ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"
fi

echo "artifact: $ZIP_PATH"
if [[ "$MODE" == "unsigned-validation" ]]; then
  echo "signing: unsigned validation only; not distributable"
elif [[ "$NOTARIZE" -eq 1 ]]; then
  echo "signing: Developer ID signed, notarized, and stapled"
else
  echo "signing: Developer ID signed; not notarized or stapled"
fi
