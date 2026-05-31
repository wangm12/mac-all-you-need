#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

if [[ ! -f "$VOICE_EXPORT_EXTRACTED/data.jsonl" ]]; then
  echo "==> Extracting export…" >&2
  "$(dirname "$0")/extract.sh"
fi

# shellcheck source=/dev/null
source "$VOICE_VENV/bin/activate" 2>/dev/null || {
  "$(dirname "$0")/venv.sh"
  source "$VOICE_VENV/bin/activate"
}

rm -rf "$VOICE_HF_DATASET"
"$VOICE_PYTHON" "$VOICE_TRAINING_ROOT/scripts/voice-finetune-mac/prepare-dataset.py" \
  --export-dir "$VOICE_EXPORT_EXTRACTED" \
  --output "$VOICE_HF_DATASET"

echo "HF dataset: $VOICE_HF_DATASET"
