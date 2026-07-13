#!/usr/bin/env bash
#
# build-dmg.sh — build, Developer-ID sign, notarize, and package Liftoff
# into a distributable macOS DMG.
#
# One-time setup (notarization credentials):
#   xcrun notarytool store-credentials liftoff-notary \
#       --apple-id "you@example.com" \
#       --team-id 696F3B97CX \
#       --password "app-specific-password"   # https://appleid.apple.com → App-Specific Passwords
#
# Usage:
#   ./scripts/build-dmg.sh                 # full pipeline: build → sign → notarize → staple → dmg
#   SKIP_NOTARIZE=1 ./scripts/build-dmg.sh # build + sign + dmg only (no notarization — local testing)
#   VERSION=1.2.0 ./scripts/build-dmg.sh   # override the version baked into the dmg name
#
set -euo pipefail

# ---------------------------------------------------------------- config
SCHEME="Liftoff"
APP_NAME="Liftoff"
CONFIGURATION="Release"
TEAM_ID="${TEAM_ID:-696F3B97CX}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-liftoff-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SKIP_XCODEGEN="${SKIP_XCODEGEN:-0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/$APP_NAME.xcodeproj"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD/export"
APP="$EXPORT_DIR/$APP_NAME.app"

# ---------------------------------------------------------------- helpers
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\n\033[1;34m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- preflight
step "Preflight"
have xcodebuild || die "xcodebuild not found — install Xcode."
[ "$SKIP_XCODEGEN" = "1" ] || have xcodegen || die "xcodegen not found — 'brew install xcodegen' or set SKIP_XCODEGEN=1."
security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY" \
  || die "No '$SIGN_IDENTITY' identity in the keychain. Import your Developer ID cert first."
ok "Signing identity present: $SIGN_IDENTITY"

if [ "$SKIP_NOTARIZE" != "1" ]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "Notary profile '$NOTARY_PROFILE' not set up. Run the store-credentials command in this script's header, or set SKIP_NOTARIZE=1."
  ok "Notary profile present: $NOTARY_PROFILE"
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"

# ---------------------------------------------------------------- generate project
if [ "$SKIP_XCODEGEN" != "1" ]; then
  step "Generating Xcode project (xcodegen)"
  ( cd "$ROOT" && xcodegen generate >/dev/null )
  ok "Project generated"
fi

# ---------------------------------------------------------------- archive
step "Archiving ($CONFIGURATION, Developer ID)"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -quiet
ok "Archived → $ARCHIVE"

# ---------------------------------------------------------------- export
step "Exporting signed app"
cat > "$BUILD/exportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$SIGN_IDENTITY</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD/exportOptions.plist" \
  -exportPath "$EXPORT_DIR" \
  -quiet
[ -d "$APP" ] || die "Export did not produce $APP"
ok "Exported → $APP"

# Verify the signature & hardened runtime up front (cheaper than a failed notarization).
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -1
codesign -d --entitlements - --verbose=2 "$APP" >/dev/null 2>&1 || true
ok "Signature verified"

VERSION="${VERSION:-$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 1.0)}"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"

# ---------------------------------------------------------------- notarize
if [ "$SKIP_NOTARIZE" != "1" ]; then
  step "Notarizing (this can take a few minutes)"
  ZIP="$BUILD/$APP_NAME.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait \
    || die "Notarization failed. Inspect with: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
  rm -f "$ZIP"
  step "Stapling ticket"
  xcrun stapler staple "$APP"
  ok "Notarized & stapled"
else
  bold "⚠︎  SKIP_NOTARIZE=1 — the DMG will NOT be notarized (Gatekeeper will warn end users)."
fi

# ---------------------------------------------------------------- dmg
step "Building DMG"
if ! have create-dmg && have brew; then
  bold "create-dmg not found — installing via Homebrew for a polished installer…"
  brew install create-dmg >/dev/null 2>&1 || true
fi

rm -f "$DMG"
if have create-dmg; then
  create-dmg \
    --volname "$APP_NAME $VERSION" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 120 \
    --icon "$APP_NAME.app" 150 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 450 190 \
    --no-internet-enable \
    "$DMG" "$APP" \
    || die "create-dmg failed"
else
  # Fallback: functional drag-to-install DMG via hdiutil (no custom artwork).
  bold "create-dmg unavailable — building a plain hdiutil DMG."
  STAGE="$BUILD/dmg-stage"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
fi
ok "DMG → $DMG"

# Sign the DMG itself and (if notarizing) staple the disk image too.
codesign --sign "$SIGN_IDENTITY" "$DMG"
if [ "$SKIP_NOTARIZE" != "1" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
    && xcrun stapler staple "$DMG"
  ok "DMG notarized & stapled"
fi

step "Done"
bold "$DMG"
ls -lh "$DMG" | awk '{print $5, $9}'
