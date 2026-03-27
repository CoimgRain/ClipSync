#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MediaImporterMenuBar.xcodeproj"
PBXPROJ_PATH="$PROJECT_PATH/project.pbxproj"
SCHEME="MediaImporterMenuBar"
APP_NAME="MediaImporterMenuBar"
INFO_PLIST="$ROOT_DIR/App/Info.plist"
VERSION="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null \
    || echo "0.0.0"
)"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIGNING_MODE="${SIGNING_MODE:-auto}"
ARCHIVE_DIR="$ROOT_DIR/build/$APP_NAME.xcarchive"
DMG_ROOT_DIR="$ROOT_DIR/build/dmg-root"
DMG_PATH="$ROOT_DIR/build/${APP_NAME}-${VERSION}.dmg"
APP_PATH="$ARCHIVE_DIR/Products/Applications/${APP_NAME}.app"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "Xcode developer directory not found: $DEVELOPER_DIR" >&2
  echo "Try: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

rm -rf "$ARCHIVE_DIR" "$DMG_ROOT_DIR" "$DMG_PATH"
mkdir -p "$ROOT_DIR/build" "$DMG_ROOT_DIR"

typeset -a XCODE_EXTRA_ARGS
if [[ "$SIGNING_MODE" == "unsigned" ]]; then
  XCODE_EXTRA_ARGS+=(CODE_SIGNING_ALLOWED=NO)
elif [[ "$SIGNING_MODE" == "auto" ]] && grep -q 'DEVELOPMENT_TEAM = "";' "$PBXPROJ_PATH"; then
  echo "==> No Development Team configured, building unsigned archive for local testing"
  XCODE_EXTRA_ARGS+=(CODE_SIGNING_ALLOWED=NO)
fi

echo "==> Archiving ${APP_NAME}.app"
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_DIR" \
  archive \
  "${XCODE_EXTRA_ARGS[@]}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive succeeded but app was not found at: $APP_PATH" >&2
  exit 1
fi

echo "==> Preparing DMG staging directory"
cp -R "$APP_PATH" "$DMG_ROOT_DIR/"
ln -s /Applications "$DMG_ROOT_DIR/Applications"

echo "==> Creating DMG: $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo
echo "Done."
echo "Archive: $ARCHIVE_DIR"
echo "DMG:     $DMG_PATH"
echo
echo "If you plan to share this with other users:"
echo "1. Configure Developer ID signing in Xcode."
echo "2. Enable Hardened Runtime for Release."
echo "3. Notarize the final DMG with xcrun notarytool."
