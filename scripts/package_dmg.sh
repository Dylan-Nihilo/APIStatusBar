#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="APIStatusBar"
PROJECT="$ROOT_DIR/APIStatusBar.xcodeproj"
SCHEME="APIStatusBar"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"
MOUNT_DIR="$ROOT_DIR/build/dmg-mount"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/APIStatusBar/Info.plist")"
OUTPUT_DMG="$DIST_DIR/${APP_NAME}-v${VERSION}.dmg"
TEMP_DMG="$DIST_DIR/${APP_NAME}-v${VERSION}.rw.dmg"
APP_PATH="$DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"
VOLUME_NAME="$APP_NAME Installer"

cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rm -f "$TEMP_DMG"
  rm -rf "$MOUNT_DIR"
}
trap cleanup EXIT

rm -rf "$STAGING_DIR" "$MOUNT_DIR" "$OUTPUT_DMG" "$TEMP_DMG"
mkdir -p "$STAGING_DIR/.background" "$DIST_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
swift "$ROOT_DIR/scripts/render_dmg_background.swift" "$STAGING_DIR/.background/background.png"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs APFS \
  -ov \
  -format UDRW \
  "$TEMP_DMG"

mkdir -p "$MOUNT_DIR"
hdiutil attach "$TEMP_DMG" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" >/dev/null

SetFile -a V "$MOUNT_DIR/.background" || true

osascript <<APPLESCRIPT
set targetFolder to POSIX file "$MOUNT_DIR" as alias
set backgroundFile to POSIX file "$MOUNT_DIR/.background/background.png" as alias
tell application "Finder"
  open targetFolder
  set targetWindow to container window of targetFolder
  set current view of targetWindow to icon view
  set toolbar visible of targetWindow to false
  set statusbar visible of targetWindow to false
  set bounds of targetWindow to {120, 120, 680, 460}
  set opts to icon view options of targetWindow
  set arrangement of opts to not arranged
  set icon size of opts to 92
  set text size of opts to 12
  set background picture of opts to backgroundFile
  set position of item "$APP_NAME.app" of targetFolder to {150, 188}
  set position of item "Applications" of targetFolder to {410, 188}
  update targetFolder without registering applications
  delay 1
  close targetWindow
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet
hdiutil convert "$TEMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUTPUT_DMG" >/dev/null

echo "$OUTPUT_DMG"
