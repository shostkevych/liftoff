#!/usr/bin/env bash
#
# Package the already-built, notarized & stapled Liftoff.app (from release.sh's
# export step) into a signed + notarized + stapled .dmg for the website download
# button. Sparkle auto-updates keep using the .zip; this DMG is download-only.
#
#   scripts/make-dmg.sh 1.3
#
set -euo pipefail

SHORT_VERSION="${1:?usage: make-dmg.sh <marketing-version>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-liftoff-notary}"
SIGN_ID="Developer ID Application: Oleh Shostkevych (696F3B97CX)"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/export/Liftoff.app"
# DMGs live in their own dir (NOT site/public/releases) so Sparkle's
# generate_appcast — which scans releases/ — never sees a .dmg + .zip for the
# same bundle version and aborts on the duplicate.
DMG_DIR="$ROOT/site/public/dmg"
mkdir -p "$DMG_DIR"
DMG="$DMG_DIR/Liftoff-${SHORT_VERSION}.dmg"

[ -d "$APP" ] || { echo "✗ App not found at $APP — run release.sh first"; exit 1; }

echo "› Building DMG…"
rm -f "$DMG"
create-dmg \
  --volname "Liftoff $SHORT_VERSION" \
  --window-pos 200 120 --window-size 600 360 --icon-size 110 \
  --icon "Liftoff.app" 150 180 \
  --app-drop-link 450 180 \
  --no-internet-enable \
  "$DMG" "$APP"

echo "› Signing DMG…"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG"

echo "› Notarizing DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "› Stapling DMG…"
xcrun stapler staple "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG" || true

echo "✓ DMG ready: $DMG"
