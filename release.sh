#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS="$REPO/macos"
SITE="$REPO/site"
PROJECT="$MACOS/project.yml"
CHANGELOG="$MACOS/CHANGELOG.md"
NOTARY_PROFILE="${NOTARY_PROFILE:-liftoff-notary}"
SIGN_ID="Developer ID Application: Oleh Shostkevych (696F3B97CX)"
EXPECTED_NAME="Oleh Shostkevych"
EXPECTED_EMAIL="personal@shostkevych.com"
RELEASE_BASE_URL="https://liftoff.shostkevych.com"
DNC="${DNC_PATH:-$REPO/../docker-node-commander/src/index.ts}"

usage() {
  cat <<'EOF'
Usage:
  ./release.sh
  ./release.sh <version> <build>

With no arguments, version and build are read from macos/project.yml.
Before running:
  1. Add the release section to macos/CHANGELOG.md.
  2. Sync site/changelog.md.
  3. Set MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml and Xcode.
  4. Commit everything on a clean feature branch.

Optional environment:
  NOTARY_PROFILE=liftoff-notary
  DNC_PATH=/path/to/docker-node-commander/src/index.ts
EOF
}

fail() {
  echo "✗ $*" >&2
  exit 1
}

step() {
  echo
  echo "› $*"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -eq 0 || $# -eq 2 ]] || {
  usage
  exit 1
}

command -v git >/dev/null || fail "git is required"
command -v gh >/dev/null || fail "GitHub CLI is required"
command -v xcodebuild >/dev/null || fail "Xcode command-line tools are required"
command -v create-dmg >/dev/null || fail "create-dmg is required"
command -v bun >/dev/null || fail "Bun is required for Docker Node Commander"
[[ -f "$DNC" ]] || fail "Docker Node Commander not found at $DNC"
[[ -f "$SITE/.hawkfile" ]] || fail "Missing site/.hawkfile"

if [[ $# -eq 2 ]]; then
  VERSION="$1"
  BUILD_NUMBER="$2"
else
  VERSION="$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' "$PROJECT")"
  BUILD_NUMBER="$(awk '/CURRENT_PROJECT_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' "$PROJECT")"
fi

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "Invalid version: $VERSION"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "Invalid build number: $BUILD_NUMBER"

PROJECT_VERSION="$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' "$PROJECT")"
PROJECT_BUILD="$(awk '/CURRENT_PROJECT_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' "$PROJECT")"
[[ "$VERSION" == "$PROJECT_VERSION" ]] \
  || fail "Requested version $VERSION does not match project.yml ($PROJECT_VERSION)"
[[ "$BUILD_NUMBER" == "$PROJECT_BUILD" ]] \
  || fail "Requested build $BUILD_NUMBER does not match project.yml ($PROJECT_BUILD)"

cd "$REPO"

BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || fail "Detached HEAD is not releasable"
[[ "$BRANCH" != "main" && "$BRANCH" != "staging" ]] \
  || fail "Release from a feature branch, never $BRANCH"

[[ "$(git config user.name)" == "$EXPECTED_NAME" ]] \
  || fail "git user.name must be $EXPECTED_NAME"
[[ "$(git config user.email)" == "$EXPECTED_EMAIL" ]] \
  || fail "git user.email must be $EXPECTED_EMAIL"
[[ -z "$(git status --porcelain)" ]] \
  || fail "Working tree must be clean before publishing"

grep -q "^## $VERSION$" "$CHANGELOG" \
  || fail "CHANGELOG.md has no '## $VERSION' section"
cmp -s "$CHANGELOG" "$SITE/changelog.md" \
  || fail "site/changelog.md must match macos/CHANGELOG.md"
grep -q "MARKETING_VERSION = $VERSION;" "$MACOS/Liftoff.xcodeproj/project.pbxproj" \
  || fail "Xcode project marketing version is not $VERSION"
grep -q "CURRENT_PROJECT_VERSION = $BUILD_NUMBER;" "$MACOS/Liftoff.xcodeproj/project.pbxproj" \
  || fail "Xcode project build number is not $BUILD_NUMBER"

gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated"
security find-identity -v -p codesigning | grep -Fq "$SIGN_ID" \
  || fail "Developer ID certificate is unavailable"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "Notary profile '$NOTARY_PROFILE' is unavailable"

TAG="v$VERSION"
HEAD_SHA="$(git rev-parse HEAD)"
if git show-ref --verify --quiet "refs/tags/$TAG"; then
  [[ "$(git rev-list -n 1 "$TAG")" == "$HEAD_SHA" ]] \
    || fail "Local tag $TAG points to another commit"
fi

REMOTE_TAG_SHA="$(git ls-remote --tags origin "refs/tags/$TAG" | awk '{print $1}')"
if [[ -n "$REMOTE_TAG_SHA" && "$REMOTE_TAG_SHA" != "$HEAD_SHA" ]]; then
  fail "Remote tag $TAG points to another commit"
fi

DEPLOY_HOST="$(awk '$1 == "host:" {print $2; exit}' "$SITE/.hawkfile")"
HOST_PORT="$(sed -nE 's/^[[:space:]]*-[[:space:]]*"([0-9]+):[0-9]+".*/\1/p' "$SITE/.hawkfile" | head -1)"
[[ -n "$DEPLOY_HOST" && -n "$HOST_PORT" ]] || fail "Invalid site/.hawkfile host or port"

step "Checking deployment host and port $DEPLOY_HOST:$HOST_PORT"
ssh "ubuntu@$DEPLOY_HOST" \
  "docker ps --filter name=liftoff-site --format '{{.Names}} {{.Ports}} {{.Status}}'; ss -ltn '( sport = :$HOST_PORT )'"

step "Building, signing, notarizing, and generating Sparkle update"
"$MACOS/scripts/release.sh" "$VERSION" "$BUILD_NUMBER"

step "Building, signing, and notarizing DMG"
"$MACOS/scripts/make-dmg.sh" "$VERSION"

APP="$MACOS/build/export/Liftoff.app"
ZIP="$SITE/public/releases/Liftoff-$VERSION.zip"
DMG="$SITE/public/dmg/Liftoff-$VERSION.dmg"
APPCAST="$SITE/public/appcast.xml"

[[ -d "$APP" && -f "$ZIP" && -f "$DMG" && -f "$APPCAST" ]] \
  || fail "One or more release artifacts are missing"

step "Validating release artifacts"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]] \
  || fail "Built app version mismatch"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD_NUMBER" ]] \
  || fail "Built app number mismatch"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
grep -q "<title>$VERSION</title>" "$APPCAST" \
  || fail "Generated appcast does not contain $VERSION"
shasum -a 256 "$ZIP" "$DMG"

step "Pushing source branch and tag"
git push -u origin "$BRANCH"
if ! git show-ref --verify --quiet "refs/tags/$TAG"; then
  git tag "$TAG" "$HEAD_SHA"
fi
if [[ -z "$REMOTE_TAG_SHA" ]]; then
  git push origin "refs/tags/$TAG"
fi

NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT
awk -v version="$VERSION" '
  $0 == "## " version { found = 1; next }
  /^## / && found { exit }
  found && /^- / { print }
' "$CHANGELOG" > "$NOTES_FILE"
[[ -s "$NOTES_FILE" ]] || fail "Release $VERSION has no changelog bullets"

step "Publishing GitHub release"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" "$ZIP" --clobber
  gh release edit "$TAG" --title "Liftoff $VERSION" --notes-file "$NOTES_FILE"
else
  gh release create "$TAG" "$DMG" "$ZIP" \
    --title "Liftoff $VERSION" \
    --notes-file "$NOTES_FILE"
fi

step "Deploying Sparkle feed, changelog, and release files"
(
  cd "$SITE"
  bun run "$DNC" --update
)

step "Verifying live update"
curl --fail --silent --show-error --retry 5 \
  "$RELEASE_BASE_URL/appcast.xml?v=$VERSION" \
  | grep -F "<title>$VERSION</title>" >/dev/null
curl --fail --silent --show-error --retry 5 --head \
  "$RELEASE_BASE_URL/releases/Liftoff-$VERSION.zip" >/dev/null
curl --fail --silent --show-error --retry 5 \
  "$RELEASE_BASE_URL/changelog" \
  | grep -F "$VERSION" >/dev/null

echo
echo "✓ Liftoff $VERSION (build $BUILD_NUMBER) published"
echo "  https://github.com/shostkevych/liftoff/releases/tag/$TAG"
