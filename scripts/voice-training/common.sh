#!/usr/bin/env bash
# Shared paths for voice-training Make targets and scripts.
set -euo pipefail

VOICE_TRAINING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export VOICE_TRAINING_ROOT

export VOICE_EXPORT_DIR="${VOICE_EXPORT_DIR:-$VOICE_TRAINING_ROOT/.build/voice-export}"
export VOICE_EXPORT_TAR="${VOICE_EXPORT_TAR:-$VOICE_EXPORT_DIR/mayn-voice-training.tar.gz}"
export VOICE_EXPORT_EXTRACTED="${VOICE_EXPORT_EXTRACTED:-$VOICE_EXPORT_DIR/extracted}"

export VOICE_FINETUNE_DIR="${VOICE_FINETUNE_DIR:-$VOICE_TRAINING_ROOT/.build/voice-finetune-pilot}"
export VOICE_HF_DATASET="${VOICE_HF_DATASET:-$VOICE_FINETUNE_DIR/hf-dataset}"
export VOICE_ADAPTER_DIR="${VOICE_ADAPTER_DIR:-$VOICE_FINETUNE_DIR/whisper-tiny-lora/adapters}"
export VOICE_VENV="${VOICE_VENV:-$VOICE_FINETUNE_DIR/venv}"

export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-/opt/homebrew/opt/libarchive/lib/pkgconfig}"
export MAYN_CONTAINER="${MAYN_APP_GROUP_CONTAINER_OVERRIDE:-$HOME/Library/Group Containers/group.com.macallyouneed.shared}"

# Prefer Python 3.12 (HuggingFace datasets breaks on some 3.14 builds).
if [[ -z "${VOICE_PYTHON:-}" ]]; then
  if command -v python3.12 >/dev/null 2>&1; then
    export VOICE_PYTHON=python3.12
  else
    export VOICE_PYTHON=python3
  fi
fi

voice_training_require_app_quit() {
  if pgrep -x MacAllYouNeed >/dev/null 2>&1; then
    echo "error: Mac All You Need is running. Quit the app (Cmd+Q) before voice-training export." >&2
    exit 1
  fi
}

voice_training_require_container() {
  if [[ ! -d "$MAYN_CONTAINER/databases" ]]; then
    echo "error: App Group container not found at:" >&2
    echo "  $MAYN_CONTAINER" >&2
    echo "Launch Mac All You Need once, then quit and retry." >&2
    exit 1
  fi
}
