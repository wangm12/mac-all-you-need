#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

voice_training_require_container

cd "$VOICE_TRAINING_ROOT/Shared"
PKG_CONFIG_PATH="$PKG_CONFIG_PATH" swift test --filter VoiceTrainingCorpusPilotTests/testProductionCorpusStats 2>&1 \
  | awk '/voice-training corpus:/{show=1} show{print} /medium\+audio:/{exit}'
