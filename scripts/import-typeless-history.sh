#!/usr/bin/env bash
# Import Typeless dictation history into Mac All You Need voice transcripts + training examples.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData}"
TOOL="$DERIVED_DATA/Build/Products/Debug/TypelessImport"
FFMPEG="$ROOT/Vendored/binaries/ffmpeg"
MAYN_CONTAINER="${MAYN_APP_GROUP_CONTAINER_OVERRIDE:-$HOME/Library/Group Containers/group.com.macallyouneed.shared}"

if pgrep -x MacAllYouNeed >/dev/null 2>&1; then
  echo "error: Mac All You Need is running. Quit the app (Cmd+Q) before importing." >&2
  exit 1
fi

if [[ ! -x "$FFMPEG" ]]; then
  echo "error: Missing $FFMPEG — run scripts/fetch-binaries.sh first." >&2
  exit 1
fi

if [[ ! -x "$TOOL" ]]; then
  echo "==> Building TypelessImport…" >&2
  xcodebuild -project "$ROOT/MacAllYouNeed.xcodeproj" \
    -scheme TypelessImport \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    build
fi

if [[ ! -d "$MAYN_CONTAINER/databases" ]]; then
  echo "error: Mac All You Need App Group container not found at:" >&2
  echo "  $MAYN_CONTAINER" >&2
  echo "Launch the app once, then quit and retry." >&2
  exit 1
fi

export SRCROOT="$ROOT"
exec "$TOOL" \
  --ffmpeg "$FFMPEG" \
  --mayn-container "$MAYN_CONTAINER" \
  "$@"
