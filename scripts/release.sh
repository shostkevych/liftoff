#!/usr/bin/env bash
#
# Build a signed Liftoff.app, package it as a zip, and (re)generate the Sparkle
# appcast served from the marketing site. Run from the repo root:
#
#   scripts/release.sh 1.1 7        # <CFBundleShortVersionString> <CFBundleVersion>
#
# Prereqs (one-time):
#   - EdDSA signing key already in your login Keychain (Sparkle generate_keys).
#     The matching public key is in project.yml -> SUPublicEDKey.
#   - A "Developer ID Application" cert in the Keychain (project.yml signs with it).
#   - Notarization credentials stored as a keychain profile (one-time):
#       xcrun notarytool store-credentials liftoff-notary \
#         --apple-id <you@example.com> --team-id 696F3B97CX --password <app-specific-pw>
#     Then export NOTARY_PROFILE=liftoff-notary (default below). Without it the
#     script still builds + signs but SKIPS notarization, and Sparkle/Gatekeeper
#     will reject the update on other machines.
#
# After running, deploy the site (site/public/appcast.xml + site/public/releases/*).
set -euo pipefail

NOTARY_PROFILE="${NOTARY_PROFILE:-liftoff-notary}"

SHORT_VERSION="${1:?usage: release.sh <marketing-version> <build-number>}"
BUILD_NUMBER="${2:?usage: release.sh <marketing-version> <build-number>}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
RELEASES="$ROOT/site/public/releases"
TOOLS="$ROOT/.sparkle-tools"
SPARKLE_VERSION="2.6.4"
DOWNLOAD_PREFIX="https://liftoff.shostkevych.com/releases/"

mkdir -p "$RELEASES" "$TOOLS"

# Fetch Sparkle's signing/appcast tools once.
if [ ! -x "$TOOLS/bin/generate_appcast" ]; then
  echo "› Downloading Sparkle $SPARKLE_VERSION tools…"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    | tar -xJ -C "$TOOLS"
fi

# Archive, then export with Developer ID. The export step deep-signs every
# nested helper (incl. Sparkle's Updater.app / Autoupdate), applies a secure
# timestamp + hardened runtime, and strips the get-task-allow debug entitlement
# — all required for notarization. A plain `xcodebuild build` does none of that.
echo "› Archiving Release…"
ARCHIVE="$BUILD_DIR/Liftoff.xcarchive"
rm -rf "$ARCHIVE"
xcodebuild -project "$ROOT/Liftoff.xcodeproj" -scheme Liftoff -configuration Release \
  -archivePath "$ARCHIVE" -destination "generic/platform=macOS" \
  MARKETING_VERSION="$SHORT_VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  clean archive | tail -3

echo "› Exporting (Developer ID)…"
EXPORT_DIR="$BUILD_DIR/export"
rm -rf "$EXPORT_DIR"
cat > "$BUILD_DIR/exportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>696F3B97CX</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" | tail -3

APP="$EXPORT_DIR/Liftoff.app"
[ -d "$APP" ] || { echo "✗ Exported app not found at $APP"; exit 1; }

ZIP="$RELEASES/Liftoff-${SHORT_VERSION}.zip"

# Notarize the app, then staple the ticket into the .app so it launches without
# a network round-trip and passes Gatekeeper (required for Sparkle to install).
if security find-generic-password -s "com.apple.gke.notary.tool" -a "$NOTARY_PROFILE" >/dev/null 2>&1 \
   || xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "› Notarizing (profile: $NOTARY_PROFILE)…"
  NOTARIZE_ZIP="$BUILD_DIR/Liftoff-notarize.zip"
  rm -f "$NOTARIZE_ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARIZE_ZIP"
  xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "› Stapling ticket…"
  xcrun stapler staple "$APP"
  spctl -a -vv -t exec "$APP" || true
else
  echo "⚠️  No notarytool profile '$NOTARY_PROFILE' found — SKIPPING notarization."
  echo "    The update will be rejected by Gatekeeper/Sparkle on other machines."
  echo "    Set one up: xcrun notarytool store-credentials $NOTARY_PROFILE ..."
fi

echo "› Zipping (post-staple)…"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Release notes: pull this version's section out of CHANGELOG.md and drop a
# matching Liftoff-<version>.html next to the zip. generate_appcast embeds it
# as the item's <description>, so Sparkle's update prompt shows the same notes
# the app's post-update "What's New" popup does.
echo "› Extracting release notes for $SHORT_VERSION from CHANGELOG.md…"
/usr/bin/python3 - "$ROOT/CHANGELOG.md" "$SHORT_VERSION" "$RELEASES/Liftoff-${SHORT_VERSION}.html" <<'PYEOF'
import html, re, sys
src, version, dest = sys.argv[1:4]
lines, section, found = open(src).read().split("\n"), [], False
for line in lines:
    if line.startswith("## "):
        if found: break
        found = line[3:].strip() == version
        continue
    if found: section.append(line)
if not found or not any(s.strip() for s in section):
    sys.exit(f"CHANGELOG.md has no '## {version}' section — add one before releasing.")
out, in_list = [f"<h2>Version {html.escape(version)}</h2>"], False
def inline(s):
    s = html.escape(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", s)
for line in section:
    stripped = line.strip()
    if stripped.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append(f"<li>{inline(stripped[2:])}</li>")
    elif stripped:
        if in_list: out.append("</ul>"); in_list = False
        out.append(f"<p>{inline(stripped)}</p>")
if in_list: out.append("</ul>")
open(dest, "w").write("\n".join(out) + "\n")
PYEOF

echo "› Generating appcast (signs with your Keychain EdDSA key)…"
"$TOOLS/bin/generate_appcast" --embed-release-notes --download-url-prefix "$DOWNLOAD_PREFIX" "$RELEASES"

# generate_appcast writes releases/appcast.xml; the feed lives at site root.
cp "$RELEASES/appcast.xml" "$ROOT/site/public/appcast.xml"

echo "✓ Done. Review and deploy:"
echo "    site/public/appcast.xml"
echo "    $ZIP"
