#!/usr/bin/env bash
# Preflight for signed Release builds (scheme-based; matches package-dmg.sh).
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT="${PROJECT:-$ROOT/MacAllYouNeed.xcodeproj}"
SCHEME="${SCHEME:-MacAllYouNeed}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM="${1:?team id required}"

if [[ "${CODE_SIGNING_ALLOWED:-}" == "NO" ]]; then
  exit 0
fi

settings_log="$(mktemp)"
trap 'rm -f "$settings_log"' EXIT

set +e
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=arm64" \
  -showBuildSettings \
  "DEVELOPMENT_TEAM=$TEAM" \
  >"$settings_log" 2>&1
status=$?
set -e

if grep -q "No Accounts" "$settings_log"; then
  cat >&2 <<EOF
error: Xcode cannot access any Apple ID accounts for automatic signing.

Do this once:
  1. Open Xcode.app → Settings → Accounts → add your Apple ID.
  2. Confirm the team for this repo (current setting: $TEAM).
     If your Team ID differs, run:
       cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
       # set DEVELOPMENT_TEAM to your Team ID, then: make release
  3. For Finder History, also run: make provision-extensions

EOF
  exit 1
fi

if [[ "$status" -ne 0 ]]; then
  echo "warning: xcodebuild -showBuildSettings exited $status (continuing anyway)" >&2
  tail -5 "$settings_log" >&2 || true
fi

if ! security find-identity -p codesigning -v 2>/dev/null | grep -qE "Apple Development|Developer ID Application"; then
  echo "note: no Apple Development certificate in keychain yet; Xcode may create one during the Release build." >&2
fi
