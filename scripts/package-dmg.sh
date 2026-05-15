#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacAllYouNeed"
PROJECT="$ROOT/MacAllYouNeed.xcodeproj"
SCHEME="MacAllYouNeed"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
STAGING_DIR="$ROOT/build/dmg-staging"
DMG_PATH="${DMG_PATH:-$DIST_DIR/$APP_NAME.dmg}"
VOLUME_NAME="${VOLUME_NAME:-Mac All You Need}"

YTDLP="$ROOT/Vendored/binaries/yt-dlp"
FFMPEG="$ROOT/Vendored/binaries/ffmpeg"
MANIFEST="$ROOT/Vendored/binaries/manifest.json"

if [[ ! -x "$YTDLP" || ! -x "$FFMPEG" || ! -f "$MANIFEST" ]]; then
  echo "error: missing downloader binaries. Run ./scripts/fetch-binaries.sh first." >&2
  exit 1
fi

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> Regenerating Xcode project"
  (cd "$ROOT" && xcodegen generate)
fi

echo "==> Building $APP_NAME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app not found at $APP_PATH" >&2
  exit 1
fi

echo "==> Preparing DMG staging"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating $DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "==> Signing DMG"
  codesign --force --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
fi

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  echo "==> Notarizing DMG with keychain profile"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait
  echo "==> Stapling DMG"
  xcrun stapler staple "$DMG_PATH"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  echo "==> Notarizing DMG with Apple ID credentials"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
  echo "==> Stapling DMG"
  xcrun stapler staple "$DMG_PATH"
else
  echo "==> Notarization skipped; set NOTARY_KEYCHAIN_PROFILE or APPLE_ID/APPLE_TEAM_ID/APPLE_APP_SPECIFIC_PASSWORD."
fi

echo "==> Verifying DMG"
hdiutil verify "$DMG_PATH"

echo "DMG ready: $DMG_PATH"
