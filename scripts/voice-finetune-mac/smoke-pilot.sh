#!/usr/bin/env bash
# Pilot: extract MAYN export, prepare HF dataset, optional mlx-tune smoke (whisper-tiny).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXPORT_TAR="${1:-$ROOT/.build/voice-export/mayn-voice-training.tar.gz}"
WORKDIR="${WORKDIR:-$ROOT/.build/voice-finetune-pilot}"
PYTHON="${PYTHON:-python3}"

if [[ ! -f "$EXPORT_TAR" ]]; then
  echo "error: missing export at $EXPORT_TAR — run: make voice-training-export" >&2
  exit 1
fi

rm -rf "$WORKDIR/export" "$WORKDIR/hf-dataset"
mkdir -p "$WORKDIR/export"
tar -xzf "$EXPORT_TAR" -C "$WORKDIR/export"

"$PYTHON" "$ROOT/scripts/voice-finetune-mac/prepare-dataset.py" \
  --export-dir "$WORKDIR/export" \
  --output "$WORKDIR/hf-dataset"

LINES="$(wc -l < "$WORKDIR/export/data.jsonl" | tr -d ' ')"
TOTAL_MS=0
while IFS= read -r line; do
  ms="$(echo "$line" | "$PYTHON" -c 'import json,sys; print(json.load(sys.stdin).get("duration_ms",0))')"
  TOTAL_MS=$((TOTAL_MS + ms))
done < "$WORKDIR/export/data.jsonl"
TOTAL_MIN=$((TOTAL_MS / 60000))

echo ""
echo "=== Pilot corpus ==="
echo "  utterances: $LINES"
echo "  speech (approx): ${TOTAL_MIN} min (${TOTAL_MS} ms)"
echo "  hf dataset: $WORKDIR/hf-dataset"
if [[ "$LINES" -lt 50 ]]; then
  echo "  warning: below recommended 50 high utterances — expect limited LoRA gain"
fi
if [[ "$TOTAL_MIN" -lt 30 ]]; then
  echo "  warning: below recommended 30 min — smoke test only"
fi

if ! "$PYTHON" -c "import mlx" 2>/dev/null; then
  echo ""
  echo "=== mlx not installed — skipping training ==="
  echo "  pip install 'mlx-tune[audio]' mlx-lm"
  echo "  Then re-run this script or follow README.md for Qwen3 example 17."
  exit 0
fi

echo ""
echo "=== mlx available — for full Qwen3 LoRA see README (may take hours) ==="
echo "  Prepared data is ready at: $WORKDIR/hf-dataset"
echo "  O3b report template: $ROOT/.build/voice-finetune-pilot/O3b-report.md"

cat > "$WORKDIR/O3b-report.md" <<EOF
# O3b pilot report ($(date +%Y-%m-%d))

- Export: \`$EXPORT_TAR\`
- Utterances: $LINES
- Approx duration: ${TOTAL_MIN} min
- Train split: \`$WORKDIR/hf-dataset\`

## Phrase accuracy (fill in after mlx-tune inference)

| # | Reference (user_edited_text) | Base model | + adapter |
|---|------------------------------|------------|-----------|
| 1 | | | |
| 2 | | | |

## Notes

- Training not run automatically in smoke-pilot (install mlx-tune and run example 17 manually).
EOF

echo "  Wrote $WORKDIR/O3b-report.md"
