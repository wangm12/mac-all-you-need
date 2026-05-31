#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

ANY_QUALITY="${MAYN_EXPORT_ANY_QUALITY:-1}"
voice_training_require_app_quit
voice_training_require_container

mkdir -p "$VOICE_EXPORT_DIR"

cd "$VOICE_TRAINING_ROOT/Shared"
export MAYN_PILOT_EXPORT_PATH="$VOICE_EXPORT_TAR"
export MAYN_EXPORT_ANY_QUALITY="$ANY_QUALITY"

PKG_CONFIG_PATH="$PKG_CONFIG_PATH" swift test --filter VoiceTrainingCorpusPilotTests/testProductionCorpusExport 2>&1 \
  | grep -E "voice-training export" || true

echo "Wrote $VOICE_EXPORT_TAR"
