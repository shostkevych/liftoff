#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build-dev"
APP="$DERIVED/Build/Products/Debug/Liftoff.app"
INSTALL_APP="/Applications/Liftoff Dev.app"

cd "$ROOT"

xcodebuild \
  -project Liftoff.xcodeproj \
  -scheme Liftoff \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  PRODUCT_BUNDLE_IDENTIFIER=com.shostkevych.liftoff.dev \
  ASSETCATALOG_COMPILER_APPICON_NAME=dev-icon \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LIFTOFF_DEV' \
  CODE_SIGNING_ALLOWED=NO \
  build

/usr/libexec/PlistBuddy -c "Delete :CFBundleDisplayName" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string 'Liftoff Dev'" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Liftoff Dev" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconName dev-icon" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile dev-icon" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

if [ -e "$INSTALL_APP" ]; then
  osascript -e 'tell application id "com.shostkevych.liftoff.dev" to quit' 2>/dev/null || true
  for _ in {1..30}; do
    pgrep -f "$INSTALL_APP/Contents/MacOS/Liftoff" >/dev/null || break
    sleep 0.1
  done
  backup="$HOME/.Trash/Liftoff Dev-$(date +%Y%m%d-%H%M%S).app"
  mv "$INSTALL_APP" "$backup"
fi
ditto "$APP" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"
open "$INSTALL_APP"

printf 'Installed %s\n' "$INSTALL_APP"
