#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

MAX_STEPS="${VOICE_TRAIN_MAX_STEPS:-12}"

if [[ ! -d "$VOICE_HF_DATASET" ]]; then
  echo "error: missing $VOICE_HF_DATASET — run: make voice-training-prepare" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$VOICE_VENV/bin/activate" 2>/dev/null || {
  "$(dirname "$0")/venv.sh"
  source "$VOICE_VENV/bin/activate"
}

OUT="$VOICE_FINETUNE_DIR/whisper-tiny-lora"
rm -rf "$OUT"
mkdir -p "$OUT"

"$VOICE_PYTHON" "$VOICE_TRAINING_ROOT/scripts/voice-finetune-mac/pilot-train-whisper-tiny.py" \
  --dataset "$VOICE_HF_DATASET" \
  --output "$OUT" \
  --max-steps "$MAX_STEPS"

echo "Adapters: $VOICE_ADAPTER_DIR"
