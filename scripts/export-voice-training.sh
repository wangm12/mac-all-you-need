#!/usr/bin/env bash
# Export voice training examples from the Mac All You Need App Group DB.
# Prefer: make voice-training-export  (see docs/voice-training/README.md)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == "--make" ]]; then
  exec make -C "$ROOT" voice-training-export
fi
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData}"
TOOL="$DERIVED_DATA/Build/Products/Debug/VoiceTrainingExport"
MAYN_CONTAINER="${MAYN_APP_GROUP_CONTAINER_OVERRIDE:-$HOME/Library/Group Containers/group.com.macallyouneed.shared}"
OUTPUT="${1:-$ROOT/.build/voice-export/mayn-voice-training.tar.gz}"

if pgrep -x MacAllYouNeed >/dev/null 2>&1; then
  echo "error: Mac All You Need is running. Quit the app (Cmd+Q) before exporting." >&2
  exit 1
fi

if [[ ! -x "$TOOL" ]]; then
  echo "==> Building VoiceTrainingExport…" >&2
  xcodebuild -project "$ROOT/MacAllYouNeed.xcodeproj" \
    -scheme VoiceTrainingExport \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    build
fi

mkdir -p "$(dirname "$OUTPUT")"
exec "$TOOL" --mayn-container "$MAYN_CONTAINER" --output "$OUTPUT" "${@:2}"
