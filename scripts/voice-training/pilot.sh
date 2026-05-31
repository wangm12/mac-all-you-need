#!/usr/bin/env bash
# Full smoke pipeline: stats → export → prepare → whisper-tiny LoRA (12 steps).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Corpus stats"
"$DIR/stats.sh"

echo "==> Export"
"$DIR/export.sh"

echo "==> Prepare HF dataset"
"$DIR/venv.sh"
"$DIR/prepare.sh"

echo "==> Smoke train (whisper-tiny)"
"$DIR/train-whisper-smoke.sh"

echo ""
echo "Pilot complete. See docs/voice-training/README.md and docs/research/voice-training-pilot-o3b-2026-05-29.md"
