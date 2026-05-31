#!/usr/bin/env bash
# Zero-shot TTS smoke test with Resemble Chatterbox (MIT) using MAYN reference audio.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REF="${VOICE_CLONE_REF_WAV:-$ROOT/docs/voice-cloning/reference-pack/instant-merged.wav}"
SCRIPT="$ROOT/docs/voice-cloning/test-script-en.txt"
OUT="${VOICE_CLONE_EVAL_DIR:-$ROOT/.build/voice-cloning-eval}"
VENV="${VOICE_CLONE_VENV:-$ROOT/.build/voice-cloning-eval/venv312}"
PYTHON="${VOICE_CLONE_PYTHON:-}"
# Long scripts OOM on long sampling runs; override with VOICE_CLONE_SMOKE_TEXT.
SMOKE_TEXT="${VOICE_CLONE_SMOKE_TEXT:-}"

if [[ ! -f "$REF" ]]; then
  echo "error: missing reference WAV — run ./scripts/voice-cloning/curate-reference-pack.sh" >&2
  exit 1
fi

if [[ -n "$SMOKE_TEXT" ]]; then
  TEXT="$SMOKE_TEXT"
else
  TEXT="Hi, this is a quick voice clone test for Mac All You Need."
fi
mkdir -p "$OUT"

_pick_python() {
  if [[ -n "$PYTHON" ]]; then
    echo "$PYTHON"
  elif [[ -x "$ROOT/.build/voice-finetune-pilot/venv312/bin/python" ]]; then
    echo "$ROOT/.build/voice-finetune-pilot/venv312/bin/python"
  else
    echo "python3.12"
  fi
}

PY="$(_pick_python)"

if [[ ! -d "$VENV" ]]; then
  "$PY" -m venv "$VENV"
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
  pip install -q --upgrade pip
  pip install -q --index-url https://pypi.org/simple chatterbox-tts torch torchaudio
else
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
fi

"$VENV/bin/python" - "$REF" "$TEXT" "$OUT/chatterbox-smoke-short.wav" <<'PY'
import sys
from pathlib import Path

ref, text, out = sys.argv[1:4]
try:
    from chatterbox.tts import ChatterboxTTS
except ImportError as e:
    raise SystemExit(f"chatterbox-tts not installed: {e}") from e

import torch

device = "mps" if torch.backends.mps.is_available() else "cpu"
model = ChatterboxTTS.from_pretrained(device=device)
if hasattr(model, "generate"):
    wav = model.generate(text, audio_prompt_path=ref, exaggeration=0.5, cfg_weight=0.5)
elif hasattr(model, "synthesize"):
    wav = model.synthesize(text, ref)
else:
    wav = model(text, ref)

out_path = Path(out)
out_path.parent.mkdir(parents=True, exist_ok=True)

import numpy as np
import torch
import torchaudio

sr = getattr(model, "sr", 24000)
if isinstance(wav, torch.Tensor):
    tensor = wav.detach().cpu()
    if tensor.dim() == 1:
        tensor = tensor.unsqueeze(0)
    torchaudio.save(str(out_path), tensor, sr)
elif isinstance(wav, np.ndarray):
    t = torch.from_numpy(wav).float()
    if t.dim() == 1:
        t = t.unsqueeze(0)
    torchaudio.save(str(out_path), t, sr)
else:
    raise SystemExit(f"unexpected output type: {type(wav)}")

print(f"wrote {out_path}")
PY

echo "Chatterbox output: $OUT/chatterbox-smoke-short.wav"
echo "Smoke text: $TEXT"
