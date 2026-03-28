#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ClipSync.xcodeproj"
PBXPROJ_PATH="$PROJECT_PATH/project.pbxproj"
SCHEME="ClipSync"
APP_NAME="ClipSync"
INFO_PLIST="$ROOT_DIR/App/Info.plist"
BACKGROUND_SCRIPT="$ROOT_DIR/Scripts/generate_dmg_background.swift"
LAYOUT_CONFIG="$ROOT_DIR/Scripts/dmg_background_layout.json"
VERSION="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null \
    || echo "0.0.0"
)"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIGNING_MODE="${SIGNING_MODE:-auto}"
REBUILD_ARCHIVE="${REBUILD_ARCHIVE:-1}"
ARCHIVE_DIR="$ROOT_DIR/build/$APP_NAME.xcarchive"
DMG_PATH="$ROOT_DIR/build/${APP_NAME}-${VERSION}.dmg"
APP_PATH="$ARCHIVE_DIR/Products/Applications/${APP_NAME}.app"
TEMP_DMG_PATH="$ROOT_DIR/build/${APP_NAME}-${VERSION}-temp.dmg"
MOUNT_VOLUME_PATH=""
BACKGROUND_SOURCE_PATH="$ROOT_DIR/build/dmg-background.png"
BACKGROUND_FILE_NAME="background.png"
VOLUME_ICON_NAME=".VolumeIcon.icns"
APPLICATIONS_ALIAS_NAME="应用程序"
APPLICATIONS_FOLDER_ICON="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"
APPLICATIONS_ICON_WORK_COPY="$ROOT_DIR/build/ApplicationsFolderIcon.icns"
APPLICATIONS_ICON_RSRC="$ROOT_DIR/build/ApplicationsFolderIcon.rsrc"
WINDOW_BOUNDS="{160, 120, 1120, 680}"
ICON_SIZE="138"
TEXT_SIZE="16"
MOUNT_DEVICE=""

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "Xcode developer directory not found: $DEVELOPER_DIR" >&2
  echo "Try: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

cleanup() {
  if [[ -n "$MOUNT_DEVICE" ]]; then
    hdiutil detach "$MOUNT_DEVICE" -force >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

read_layout_value() {
  local key="$1"
  local fallback="$2"

  if [[ -f "$LAYOUT_CONFIG" ]]; then
    /usr/bin/plutil -extract "$key" raw -o - "$LAYOUT_CONFIG" 2>/dev/null || echo "$fallback"
  else
    echo "$fallback"
  fi
}

APP_ICON_POSITION="{\
$(read_layout_value appIconPositionX 248), \
$(read_layout_value appIconPositionY 300)\
}"
APPLICATIONS_ICON_POSITION="{\
$(read_layout_value applicationsIconPositionX 700), \
$(read_layout_value applicationsIconPositionY 300)\
}"

if [[ -d "/Volumes/$APP_NAME" ]]; then
  hdiutil detach "/Volumes/$APP_NAME" -force >/dev/null 2>&1 || true
fi

if [[ "$REBUILD_ARCHIVE" == "1" ]]; then
  rm -rf "$ARCHIVE_DIR"
fi
rm -rf "$DMG_PATH" "$TEMP_DMG_PATH"
mkdir -p "$ROOT_DIR/build"

typeset -a XCODE_EXTRA_ARGS
if [[ "$SIGNING_MODE" == "unsigned" ]]; then
  XCODE_EXTRA_ARGS+=(CODE_SIGNING_ALLOWED=NO)
elif [[ "$SIGNING_MODE" == "auto" ]] && grep -q 'DEVELOPMENT_TEAM = "";' "$PBXPROJ_PATH"; then
  echo "==> No Development Team configured, building unsigned archive for local testing"
  XCODE_EXTRA_ARGS+=(CODE_SIGNING_ALLOWED=NO)
fi

if [[ "$REBUILD_ARCHIVE" == "1" || ! -d "$APP_PATH" ]]; then
  echo "==> Archiving ${APP_NAME}.app"
  DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_DIR" \
    archive \
    "${XCODE_EXTRA_ARGS[@]}"
else
  echo "==> Reusing existing archive at $ARCHIVE_DIR"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive succeeded but app was not found at: $APP_PATH" >&2
  exit 1
fi

echo "==> Generating DMG background"
(
  cd "$ROOT_DIR"
  swift "$BACKGROUND_SCRIPT" "$BACKGROUND_SOURCE_PATH" "$APP_NAME"
)

APP_SIZE_MB="$(
  du -sm "$APP_PATH" | awk '{ print $1 }'
)"
DMG_SIZE_MB="$(( APP_SIZE_MB + 80 ))"
if (( DMG_SIZE_MB < 160 )); then
  DMG_SIZE_MB=160
fi

echo "==> Creating temporary writable DMG"
hdiutil create \
  -size "${DMG_SIZE_MB}m" \
  -fs HFS+ \
  -volname "$APP_NAME" \
  -ov \
  -type UDIF \
  "$TEMP_DMG_PATH" >/dev/null

echo "==> Mounting temporary DMG"
MOUNT_OUTPUT="$(
  hdiutil attach "$TEMP_DMG_PATH" \
    -readwrite \
    -noverify \
    -noautoopen
)"
MOUNT_DEVICE="$(echo "$MOUNT_OUTPUT" | awk '/Apple_HFS/ { print $1 }')"
MOUNT_VOLUME_PATH="$(echo "$MOUNT_OUTPUT" | awk '/Apple_HFS/ { print $NF }')"

if [[ -z "$MOUNT_DEVICE" || -z "$MOUNT_VOLUME_PATH" ]]; then
  echo "Failed to determine mounted DMG device." >&2
  exit 1
fi

echo "==> Copying app bundle and installer assets"
cp -R "$APP_PATH" "$MOUNT_VOLUME_PATH/"
mkdir -p "$MOUNT_VOLUME_PATH/.background"
cp "$BACKGROUND_SOURCE_PATH" "$MOUNT_VOLUME_PATH/.background/$BACKGROUND_FILE_NAME"
cp "$ROOT_DIR/App/AppIcon.icns" "$MOUNT_VOLUME_PATH/$VOLUME_ICON_NAME"
chflags hidden "$MOUNT_VOLUME_PATH/.background" "$MOUNT_VOLUME_PATH/$VOLUME_ICON_NAME"

osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to folder (POSIX file "$MOUNT_VOLUME_PATH" as alias)
  set applicationsTarget to POSIX file "/Applications" as alias
  make new alias file to applicationsTarget at dmgFolder with properties {name:"$APPLICATIONS_ALIAS_NAME"}
end tell
APPLESCRIPT

if [[ -f "$APPLICATIONS_FOLDER_ICON" ]] && xcrun --find DeRez >/dev/null 2>&1; then
  cp "$APPLICATIONS_FOLDER_ICON" "$APPLICATIONS_ICON_WORK_COPY"
  sips -i "$APPLICATIONS_ICON_WORK_COPY" >/dev/null
  xcrun DeRez -only icns "$APPLICATIONS_ICON_WORK_COPY" > "$APPLICATIONS_ICON_RSRC"
  xcrun Rez -append "$APPLICATIONS_ICON_RSRC" -o "$MOUNT_VOLUME_PATH/$APPLICATIONS_ALIAS_NAME"
  xcrun SetFile -a C "$MOUNT_VOLUME_PATH/$APPLICATIONS_ALIAS_NAME" || true
fi

if xcrun --find SetFile >/dev/null 2>&1; then
  xcrun SetFile -a C "$MOUNT_VOLUME_PATH" || true
fi

echo "==> Styling DMG Finder window"
osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to folder (POSIX file "$MOUNT_VOLUME_PATH" as alias)
  tell disk "$APP_NAME"
    open
    delay 1.5
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to $WINDOW_BOUNDS

    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $ICON_SIZE
    set text size of viewOptions to $TEXT_SIZE
    set background picture of viewOptions to file ".background:$BACKGROUND_FILE_NAME"

    update without registering applications
    delay 2
    close
    open
    delay 1
  end tell

  tell dmgFolder
    set position of item "$APP_NAME.app" to $APP_ICON_POSITION
    set position of item "$APPLICATIONS_ALIAS_NAME" to $APPLICATIONS_ICON_POSITION
  end tell
end tell
APPLESCRIPT

sync

echo "==> Finalizing DMG layout"
hdiutil detach "$MOUNT_DEVICE" >/dev/null
MOUNT_DEVICE=""

echo "==> Compressing DMG: $DMG_PATH"
hdiutil convert \
  "$TEMP_DMG_PATH" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

rm -f "$TEMP_DMG_PATH"

echo
echo "Done."
echo "Archive: $ARCHIVE_DIR"
echo "DMG:     $DMG_PATH"
echo
echo "If you plan to share this with other users:"
echo "1. Configure Developer ID signing in Xcode."
echo "2. Enable Hardened Runtime for Release."
echo "3. Notarize the final DMG with xcrun notarytool."
